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
