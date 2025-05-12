import Config

config :game_project, :http_port, 4000
config :game_project, :grpc_server, %{ip: "127.0.0.1", port: 50051}
