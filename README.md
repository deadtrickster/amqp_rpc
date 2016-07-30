# AMQP RPC Client/Server templates

**Warning!** POC quality!

## Goals
 - Reduce boilerplate
 - Reconnects
 - Messages housekeeping 
 - Logging
 - Monitoring
 - Use [fuse](https://github.com/jlouis/fuse)
 - Content negotiation

## Example

Below is 'classic' RPC example from (RabbitMQ tutorials)[http://www.rabbitmq.com/tutorials/tutorial-six-elixir.html]
rewritten using amqp_rpc:

Client:

```elixir
defmodule Fibonacci do
  use AMQP.RPC.Client, [exchange: "",
                        queue: "rpc_queue"]

  def fib(n, timeout \\ @timeout) do
    rpc(%{command_name: "fib",
          args: n}, timeout)
  end
end
```

Server:

```elixir
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
```

## Installation

[Available in Hex](https://hex.pm/packages/amqp_rpc), the package can be installed as:

  1. Add `amqp_rpc` to your list of dependencies in `mix.exs`:

    ```elixir
    def deps do
      [{:amqp_rpc, "~> 0.0.1"}]
    end
    ```

  2. Ensure `amqp_rpc` is started before your application:

    ```elixir
    def application do
      [applications: [:amqp_rpc]]
    end
    ```

