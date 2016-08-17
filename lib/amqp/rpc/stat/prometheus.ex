defmodule AMQP.RPC.Stat.Prometheus do
  @behaviour AMQP.RPC.Stat.Plugin

  def init(name, opts) do
    :prometheus_histogram.declare([name: name,
                                   help: "#{name} requests histogram",
                                   labels: [:command, :response],
                                   buckets: [1_000, 10_000, 100_000, 300_000, 500_000, 750_000, 1_000_000, 1_500_000, 2_000_000, 3_000_000, 30_000_000]])
  end

  def instrument_request(name, command, result, ms) do
    :prometheus_histogram.observe(name, [command, normalize_result(result)], ms)
  end

  defp normalize_result(:blown), do: :blown
  defp normalize_result(:timeout), do: :timeout
  defp normalize_result(:not_connected), do: :not_connected
  defp normalize_result(:connection_lost), do: :connection_lost
  defp normalize_result(_), do: :ok

end
