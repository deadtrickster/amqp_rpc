defmodule AMQP.RPC.Stat.Plugin do
  @callback init(Atom.t, any) :: any
  @callback instrument_request(Atom.t, String.t, any, integer()) :: any

  def current_time, do: :erlang.monotonic_time
  def time_from(start), do: (:erlang.monotonic_time - start) |> :erlang.convert_time_unit(:native, :micro_seconds)
end
