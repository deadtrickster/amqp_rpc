defmodule AMQP.RPC.Client do
  # TODO: add connect timing
  # TODO: add rpc timing
  # TODO: add concerns (i.e. fire and forget, fuse, connected, wait for reply)
  # TODO: add acks switch
  # TODO: add pluggable continuations backend support
  # TODO: add content-type matching
  # TODO: pluggable reconnect intervals generators
  require Logger
  use GenServer
  use AMQP

  defp default_name_prefix(target_module) do
    target_module
    |> Atom.to_string
    |> String.split(".")
    |> List.last
    |> Macro.underscore
  end

  defp default_fuse_name(target_module) do
    default_name_prefix(target_module) <> "_fuse"
  end

  defmacro __using__(opts) do
    target_module = __CALLER__.module
    timeout = Access.get(opts, :timeout, 5000)
    fuse_name = Access.get(opts, :fuse_name, default_fuse_name(target_module))
    fuse_opts = Access.get(opts, :fuse_opts, {{:standard, 2, 10000}, {:reset, 60000}})
    {:ok, exchange} = Access.fetch(opts, :exchange)
    {:ok, queue} = Access.fetch(opts, :queue)
    name = Access.get(opts, :name, target_module)
    reconnects = Access.get(opts, :reconnects, 6)
    reconnect_interval = Access.get(opts, :reconnect_interval, 60000)
    connection_string = Access.get(opts, :connetion_string, "amqp://localhost")
    cleanup_interval = Access.get(opts, :cleanup_interval, 60000)

    quote do
      require Logger
      use GenServer
      use AMQP

      @timeout unquote(timeout)
      @exchange unquote(exchange)
      @queue unquote(queue)

      def start_link do
        GenServer.start_link(__MODULE__, [], name: unquote(name))
      end

      def init(_opts) do
        Logger.info("#{unquote(name)}: starting RabbitMQ RPC client.")
        unquote(if fuse_opts do
          quote do
            Logger.debug("#{unquote(name)}: initializing fuse #{unquote(fuse_name)}")
            :fuse.install(unquote(fuse_name), unquote(Macro.escape(fuse_opts)))
          end
        end)
        Logger.debug("#{unquote(name)}: connecting to RabbitMQ using '#{unquote(connection_string)}'")
        resp = try_to_connect()
        if resp do
          Logger.debug("#{unquote(name)}: connected to RabbitMQ")
          {:ok, resp}
        else
          unquote(if reconnects == 0 do
            quote do
              Logger.warn("#{unquote(name)}: failed to connect to RabbitMQ during init. Exiting.")
              {:exit, :not_connected}
            end
          else
            quote do
              Logger.warn("#{unquote(name)}: failed to connect to RabbitMQ during init. Scheduling reconnect.")
              :erlang.send_after(next_reconnect_interval(1), :erlang.self(), {:try_to_connect, 2})
              {:ok, :not_connected}
            end
          end)
        end
      end

      # Confirmation sent by the broker after registering this process as a consumer
      def handle_info({:basic_consume_ok, %{consumer_tag: _consumer_tag}}, state) do
        {:noreply, state}
      end

      # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
      def handle_info({:basic_cancel, %{consumer_tag: _consumer_tag}}, state) do
        {:stop, :normal, state}
      end

      # Confirmation sent by the broker to the consumer process after a Basic.cancel
      def handle_info({:basic_cancel_ok, %{consumer_tag: _consumer_tag}}, state) do
        {:noreply, state}
      end

      def handle_info({:basic_deliver, sdata, %{correlation_id: deliver_correlation_id}}, %{channel: channel,
                                                                                            continuations: continuations,
                                                                                            correlation_id: correlation_id,
                                                                                            reply_queue: reply_queue}) do
        cont = Map.get(continuations, deliver_correlation_id, false)
        if cont do
          {from, timeout} = cont
          if not continuation_timed_out(timeout) do
            {:ok, data} = deserialize(sdata)
            GenServer.reply(from, data)
            {:noreply, %{channel: channel,
                         reply_queue: reply_queue,
                         correlation_id: correlation_id,
                         continuations: Map.delete(continuations, deliver_correlation_id)}}
          end
        end
      end

      def handle_info({:try_to_connect, attempt}, state) do
        new_state = connect(attempt, state)
        {:noreply, new_state}
      end

      def handle_info(:cleanup_trigger, state) do
        :erlang.send_after(unquote(cleanup_interval), :erlang.self(), :cleanup_trigger)
        {:noreply, cleanup_timedout_continuations(state)}
      end

      def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
        Logger.warn("#{unquote(name)}: connection to RabbitMQ lost, cleaning continuations.")
        fail_all_continuations(state, :not_connected)
        Logger.warn("#{unquote(name)}: connection to RabbitMQ lost, reconnecting.")
        new_state = connect(1, :not_connected)
        {:noreply, new_state}
      end

      def handle_call({{:call, command}, timeout}, from, state) do
        {command, headers} = normalize_command(command)
        if state == :not_connected do
          {:reply, :not_connected}
        else
          {:ok, scommand} = serialize(command)
          %{channel: channel,
            continuations: continuations,
            correlation_id: correlation_id,
            reply_queue: reply_queue} = state

          encoded_correlation_id = Integer.to_string(correlation_id)

          :ok = Basic.publish(channel,
            @exchange,
            @queue,
            scommand,
            reply_to: reply_queue,
            correlation_id: encoded_correlation_id,
            content_type: content_type,
            headers: headers)

          {:noreply, %{channel: channel,
                       reply_queue: reply_queue,
                       correlation_id: correlation_id + 1,
                       continuations: Map.put(continuations, encoded_correlation_id, {from, timeout})}}
        end
      end

      defp connect(attempt, state) do
        Logger.warn("#{unquote(name)}: RabbitMQ connect attempt ##{attempt}.")
        if state == :not_connected do
          resp = try_to_connect()
          if resp do
            Logger.warn("#{unquote(name)}: RabbitMQ connect attempt ##{attempt} succeeded.")
            resp
          else
            if (attempt + 1) <= unquote(reconnects) do
              Logger.warn("#{unquote(name)}: RabbitMQ connect attempt ##{attempt} failed. Scheduling reconnect.")
              :erlang.send_after(next_reconnect_interval(attempt), :erlang.self(), {:try_to_connect, attempt + 1})
              :not_connected
            else
              Logger.warn("#{unquote(name)}: RabbitMQ connect attempt ##{attempt} failed. Reconnects limit reached. Exiting.")
              exit(:not_connected)
            end
          end
        else
          :io.format("~p", [state])
          Logger.debug("#{unquote(name)}: trying to connect while aready connected.")
          state
        end
      end

      defp try_to_connect do
        case Connection.open(unquote(connection_string)) do
          {:ok, conn} ->

            Process.monitor(conn.pid)
            {:ok, chan} = Channel.open(conn)
            {:ok, reply_queue} = Queue.declare(chan, "", exclusive: true, auto_delete: true)
            %{queue: reply_queue} = reply_queue
            unquote(
              unless exchange == "" do
                quote do
                  Queue.bind(chan, @queue, @exchange)
                end
              end
            )
            {:ok, _consumer_tag} = Basic.consume(chan, reply_queue, self(), no_ack: true)
            :erlang.send_after(unquote(cleanup_interval), :erlang.self(), :cleanup_trigger)
            %{channel: chan,
              reply_queue: reply_queue,
              correlation_id: 0,
              continuations: %{}}
          {:error, _} ->
            false
        end
      end

      defp rpc(command, timeout) do
        unquote(if fuse_opts do
          quote do
            case :fuse.ask(unquote(fuse_name), :sync) do
              :ok ->
                real_rpc(command, timeout)
              :blown ->
                :timeout
            end
          end
        else
          quote do
            real_rpc(command, timeout)
          end
        end)
      end

      defp real_rpc(command, timeout) do
        try do
          GenServer.call(unquote(name), {{:call, command}, :erlang.monotonic_time(:milli_seconds) + timeout}, timeout)
        catch
          :exit, {:timeout, _} ->
            unquote(if fuse_opts do
                quote do
                  :fuse.melt(unquote(fuse_name))
                end
              end)
          :timeout
        end
      end

      defp normalize_command(command) do
        case command do
          %{command: ncommand} ->
            {ncommand, Access.get(command, :headers, [])}
          _ ->
            {command, []}
        end
      end

      defp fail_all_continuations(state, reply) do
        %{continuations: continuations} = state
        Map.to_list(continuations)
        |> Enum.each(fn({_, {from, timeout}}) ->
          if not continuation_timed_out(timeout) do
            GenServer.reply(from, reply)
          end
        end)
      end

      defp cleanup_timedout_continuations(state) do
        if state != :not_connected do
          %{continuations: old_continuations} = state
          clist = Map.to_list(old_continuations)
          new_continuations = clist |> Enum.reject(fn({_, {_, timeout}}) -> continuation_timed_out timeout end)
          Logger.debug("#{unquote(name)}: timed out continuations cleaned: before #{length(clist)}, after #{length(new_continuations)}")
          %{state | :continuations => Enum.into(new_continuations, %{})}
        end
      end

      defp continuation_timed_out (timeout) do
        :erlang.monotonic_time(:milli_seconds) >= timeout
      end

      defp content_type, do: "application/json"

      defp serialize(data), do: Poison.encode(data)

      defp deserialize(sdata), do: Poison.decode(sdata, keys: :atoms)

      defp next_reconnect_interval(_attempt), do: unquote(reconnect_interval)

      defoverridable [content_type: 0,
                      serialize: 1,
                      deserialize: 1]
    end
  end
end
