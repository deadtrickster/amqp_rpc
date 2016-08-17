defmodule AMQP.RPC.Stat.Ets do
  @behaviour AMQP.RPC.Stat.Plugin

  def init(name, _opts) do
    case :ets.info(__MODULE__) do
      :undefined -> :ets.new(__MODULE__, [:named_table, :public, :set,
                                         write_concurrency: true])
      _ ->
        :ok
    end

    :ets.insert(__MODULE__, [{metric(name, :ok), 0},
                             {metric(name, :blown), 0},
                             {metric(name, :timeout), 0}])

  end

  def instrument_request(name, _command_name, result, _ms) do
    :ets.update_counter(__MODULE__, metric(name, result), 1)
  end

  def counters(name) do
    for result <- [:ok, :blown, :timeout], do: {result, :ets.lookup_element(__MODULE__, metric(name, result), 2)}
  end

  defp metric(name, :blown), do: {name, :blown}
  defp metric(name, :timeout), do: {name, :timeout}
  defp metric(name, :not_connected), do: {:name, :not_connected}
  defp metric(name, :connection_lost), do: {:name, :connection_lost}
  defp metric(name, _), do: {name, :ok}
end
