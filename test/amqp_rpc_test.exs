defmodule AmqpRpcTest do
  use ExUnit.Case

  test "the truth" do
    assert 1 + 1 == 2
  end

  @tag timeout: 120000
  test "Basic all-in-one test" do
    {:ok, client_pid} = Fibonacci.start_link
    assert Fibonacci.fib(5) == :timeout

    # melt fuse
    spawn fn -> Fibonacci.fib(5) end
    spawn fn -> Fibonacci.fib(5) end
    spawn fn -> Fibonacci.fib(5) end

    :timer.sleep(6000)
    assert Fibonacci.fib(5) == :blown
    :timer.sleep(61000)

    {:ok, server_pid} = FibonacciServer.start_link
    :timer.sleep(1000)

    # we didn't receive expired continuations
    assert :erlang.process_info(self, :messages) == {:messages, []}

    # rpc calls should still work
    assert Fibonacci.fib(5) == 5

    :erlang.exit(client_pid, :ok)
    :erlang.exit(server_pid, :ok)
  end
end

defmodule Fibonacci do
  use AMQP.RPC.Client, [exchange: "",
                        queue: "rpc_queue"]

  def fib(n, timeout \\ @timeout) do
    rpc(%{command_name: "fib",
          args: n}, timeout)
  end
end

defmodule FibonacciServer do
  use AMQP.RPC.Server, [exchange: "",
                        queue: "rpc_queue",
                        commands: [:fib]]

  ## adapted from https://gist.github.com/stevedowney/2f910bd3d72678b4cf99

  def fib(0), do: 0

  def fib(n)
  when is_number(n) and n > 0,
    do: fib(n, 1, 0, 1)

  def fib(_), do: [error: "positive integers only"]

  def fib(n, m, _prev_fib, current_fib)
  when n == m,
    do: current_fib

  def fib(n, m, prev_fib, current_fib),
    do: fib(n, m+1, current_fib, prev_fib + current_fib)

end
