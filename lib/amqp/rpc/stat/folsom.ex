defmodule AMQP.RPC.Stat.Folsom do
  @behaviour AMQP.RPC.Stat.Plugin

  def init(name, opts) do
    for result <- [:ok, :blown, :timeout], do: :folsom_metric.new_histogram(metric(name, result))
  end

  def instrument_request(name, _command_name, result, ms) do
    :folsom_metrics.notify({metric(name, result), ms})
  end

  defp metric(name, :blown), do: name <> "$.blown"
  defp metric(name, :timeout), do: name <> "$.timeout"
  defp metric(name, :not_connected), do: name <> "$.not_connected"
  defp metric(name, :connection_lost), do: name <> "$.connection_lost"
  defp metric(name, _), do: name <> "$.ok"
end
