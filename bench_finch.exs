Mix.install([
  {:finch, path: "./"},
  {:benchee, "~> 1.1.0"},
  {:bandit, "~> 1.0.0-pre.5"},
  {:plug, "~> 1.14.2"}
])

defmodule PlugServer do
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, "OK")
  end
end

Supervisor.start_link([
  {DynamicSupervisor, name: BenchFinch.Supervisor}
], strategy: :one_for_one)

start_child = fn spec ->
  DynamicSupervisor.start_child(BenchFinch.Supervisor, spec)
end

stop_child = fn pid ->
  DynamicSupervisor.terminate_child(BenchFinch.Supervisor, pid)
end

## Benchmarks

save_file = Path.expand("_finch.benchee", __DIR__)
save? = !File.exists?(save_file) || System.get_env("SAVE")

save_opts =
  if save? do
    [save: [path: save_file, tag: "saved"]]
  else
    [load: save_file]
  end

bandit_opts = [
  plug: PlugServer,
  port: 4000,
  ip: :loopback
]

opts =
  save_opts ++ [
    warmup: 2,
    time: 5,
    inputs: %{
      "http1" => :http1,
      "http2" => :http2
    },
    before_scenario: fn
      :http1 ->
        {:ok, pid1} = start_child.({Finch, name: BenchFinch.HTTP1})
        {:ok, pid2} = start_child.({Bandit, bandit_opts ++ [scheme: :http, http_2_options: [enabled: false]]})

        request = Finch.build(:get, "http://localhost:#{bandit_opts[:port]}")

        %{pids: [pid1, pid2], request: request, finch_name: BenchFinch.HTTP1}

      :http2 ->
        bandit_http2 = [
          scheme: :https,
          keyfile: Path.expand("./test/fixtures/selfsigned_key.pem", __DIR__),
          certfile: Path.expand("./test/fixtures/selfsigned.pem", __DIR__),
          cipher_suite: :strong,
          otp_app: :finch,
          http_1_options: [enabled: false]
        ]

        finch_opts = [
          name: BenchFinch.HTTP2,
          pools: %{
            default: [
              protocol: :http2,
              conn_opts: [
                transport_opts: [verify: :verify_none]
              ]
            ]
          }
        ]

        {:ok, pid1} = start_child.({Finch, finch_opts})
        {:ok, pid2} = start_child.({Bandit, bandit_opts ++ bandit_http2})

        request = Finch.build(:get, "https://localhost:#{bandit_opts[:port]}")

        %{pids: [pid1, pid2], request: request, finch_name: BenchFinch.HTTP2}
    end,
    after_scenario: fn %{pids: pids} ->
      for pid <- pids do
        :ok = stop_child.(pid)
      end
    end
  ]

benchmarks = %{
  "Finch.request!/3" =>
    fn %{request: request, finch_name: finch_name} ->
      Finch.request!(request, finch_name)
    end
}

Benchee.run(benchmarks, opts)
