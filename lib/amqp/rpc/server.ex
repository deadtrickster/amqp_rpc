defmodule AMQP.RPC.Server do
  # TODO: add connect timing
  # TODO: add acks switch
  # TODO: add content-type matching
  # TODO: pluggable reconnect intervals generators
  # TODO: custom prefetch_count
  # TODO: pluggable command fun runners i.e. sync, pooled, one-for-one, etc
  require Logger
  use AMQP

  defp default_name_prefix(target_module) do
    target_module
    |> Atom.to_string
    |> String.split(".")
    |> List.last
    |> Macro.underscore
  end

  defp normalize_commands(commands) do
    commands
    |> Enum.map(fn (command) ->
      case command do
        {str, fun} ->
          {str, fun}
        fun ->
          {Atom.to_string(fun), fun}
      end
    end)
    |> Enum.into(%{})
  end

  defmacro __using__(opts) do
    target_module = __CALLER__.module

    name = Access.get(opts, :name, target_module)
    reconnects = Access.get(opts, :reconnects, 6)
    reconnect_interval = Access.get(opts, :reconnect_interval, 60000)
    connection_string = Access.get(opts, :connection_string, "amqp://localhost")
    {:ok, commands} = Access.fetch(opts, :commands)
    {:ok, exchange} = Access.fetch(opts, :exchange)
    {:ok, queue} = Access.fetch(opts, :queue)
    commands = normalize_commands(commands)

    quote do
      require Logger
      use GenServer
      use AMQP

      @exchange unquote(exchange)
      @queue unquote(queue)

      defp connection_string() do
        unquote(case connection_string do
                  {:system, name} ->
                    System.get_env(name)
                  {app, key} ->
                    quote do
                      {:ok, connection_string} = :application.get_env(unquote(app), unquote(key))
                      connection_string
                    end
                  _ ->
                    connection_string
                end)
      end

      def start_link(_) do
        start_link
      end
      def start_link() do
        GenServer.start_link(__MODULE__, [], name: unquote(name))
      end

      def init(_opts) do
        Logger.info("#{unquote(name)}: starting RabbitMQ RPC client.")
        Logger.debug("#{unquote(name)}: connecting to RabbitMQ using '#{connection_string}'")
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

      def handle_info({:basic_deliver, scommand, meta}, state) do
        %{channel: channel} = state
        {:ok, command} = deserialize(scommand)
        command_name = Access.get(command, :command_name, :false)
        # TODO: check if command is string
        if command_name do
          command_fun = Access.get(unquote(Macro.escape(commands)), command_name, :false)
          if command_fun do
            {:ok, args} = Access.fetch(command, :args)
            response = apply(unquote(target_module), command_fun, [args])
            {:ok, sresponse} = serialize(response)
            AMQP.Basic.publish(channel, @exchange, meta.reply_to, sresponse , correlation_id: meta.correlation_id)
          else
            Logger.warn("#{unquote(name)}: unknown command '#{command_name}'. Ignoring request.")
          end
        else
          Logger.warn("#{unquote(name)}: missing command field. Ignoring request.")
        end
        {:noreply, state}
      end

      def handle_info({:try_to_connect, attempt}, state) do
        new_state = connect(attempt, state)
        {:noreply, new_state}
      end

      def handle_info({:DOWN, _, :process, _pid, _reason}, state) do
        Logger.warn("#{unquote(name)}: connection to RabbitMQ lost, reconnecting.")
        new_state = connect(1, :not_connected)
        {:noreply, new_state}
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
        case Connection.open(connection_string) do
          {:ok, conn} ->

            Process.monitor(conn.pid)
            {:ok, chan} = Channel.open(conn)
            {:ok, reply_queue} = Queue.declare(chan, @queue)
            unquote(
              unless exchange == "" do
                quote do
                  Queue.bind(chan, @queue, @exchange)
                end
              end
            )
            {:ok, _consumer_tag} = Basic.consume(chan, @queue, self(), no_ack: true)
            %{channel: chan}
          {:error, _} ->
            false
        end
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
