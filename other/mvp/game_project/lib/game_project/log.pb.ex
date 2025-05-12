defmodule LogEntry do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field :timestamp, 1, type: :int64
  field :id_instancia, 2, type: :int32, json_name: "idInstancia"
  field :marcador, 3, type: :string
  field :ip, 4, type: :string
  field :alias, 5, type: :string
  field :accion, 6, type: :string
  field :args, 7, type: :string
end

defmodule Ack do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field :ok, 1, type: :bool
end

defmodule DumpRequest do
  @moduledoc false

  use Protobuf, protoc_gen_elixir_version: "0.14.1", syntax: :proto3

  field :id_instancia, 1, type: :int32, json_name: "idInstancia"
end

defmodule LogService.Service do
  @moduledoc false

  use GRPC.Service, name: "LogService", protoc_gen_elixir_version: "0.14.1"

  rpc(:SendLog, LogEntry, Ack)

  rpc(:DumpLogs, DumpRequest, stream(LogEntry))
end

defmodule LogService.Stub do
  @moduledoc false

  use GRPC.Stub, service: LogService.Service
end
