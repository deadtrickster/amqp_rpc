defmodule AmqpRpc.Mixfile do
  use Mix.Project

  def project do
    [app: :amqp_rpc,
     version: "0.0.8",
     elixir: "~> 1.3",
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps(),
     description: description,
     package: package()]
  end

  def package do
    [
      external_dependencies: [],
      license_file: "LICENSE",
      files: [ "lib", "mix.exs", "README*", "LICENSE"],
      maintainers: ["Ilya Khaprov"],
      licenses: ["MIT"],
      links:  %{
        "GitHub" => "https://github.com/deadtrickster/amqp_rpc"
      }
    ]
  end

  defp description do
    """
    AMQP RPC Client/Server templates
    """
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    [applications: [:logger,
                    :amqp,
                    :fuse]]
  end

  # Dependencies can be Hex packages:
  #
  #   {:mydep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:mydep, git: "https://github.com/elixir-lang/mydep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [{:amqp, "~> 1.3.1"},
     {:poison, "~> 4.0.1"},
     {:fuse, "~> 2.4.2"},
     #{:amqp_client, "~> 3.7.11"},
     {:ex_doc, ">= 0.21.2", only: :dev}]
  end
end
