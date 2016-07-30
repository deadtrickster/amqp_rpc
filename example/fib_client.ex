defmodule Fibonacci do
  use AMQP.RPC.Client, [exchange: "",
                        queue: "rpc_queue"]

  def fib(n, timeout \\ @timeout) do
    rpc(%{command_name: "fib",
          args: n}, timeout)
  end
end
