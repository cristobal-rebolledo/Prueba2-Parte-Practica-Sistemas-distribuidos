# Regenerate gRPC code with proper namespaces
# Run with: mix run regenerate_grpc_code.exs

Logger.configure(level: :debug)

defmodule GRPCCodeGen do
  @proto_path "../../proto_server/log.proto"
  @out_path "./lib/game_project"

  def run do
    IO.puts("Regenerating gRPC code with proper namespaces...")

    # Ensure protoc-gen-elixir is installed
    ensure_plugin_installed()

    # Find protoc executable
    protoc = find_protoc()
    IO.puts("Using protoc: #{protoc}")

    # Prepare the protoc command
    plugin_path = Path.join(["#{:code.priv_dir(:protobuf)}", "protoc-gen-elixir"])
    IO.puts("Plugin path: #{plugin_path}")

    # Command to execute
    cmd = "#{protoc} --proto_path=#{Path.dirname(@proto_path)} " <>
          "--elixir_out=plugins=grpc:#{@out_path} " <>
          "--plugin=protoc-gen-elixir=#{plugin_path} " <>
          "#{Path.basename(@proto_path)}"

    IO.puts("Executing: #{cmd}")

    # Execute command
    case System.cmd("sh", ["-c", cmd], stderr_to_stdout: true) do
      {output, 0} ->
        IO.puts("Command executed successfully!")
        IO.puts(output)
        postprocess_files()

      {output, _} ->
        IO.puts("Error executing command:")
        IO.puts(output)
    end
  end

  defp ensure_plugin_installed do
    case System.find_executable("protoc-gen-elixir") do
      nil ->
        IO.puts("Installing protoc-gen-elixir...")
        System.cmd("mix", ["escript.install", "hex", "protobuf"])
      _ ->
        IO.puts("protoc-gen-elixir is already installed.")
    end
  end

  defp find_protoc do
    case System.find_executable("protoc") do
      nil ->
        # Check for local protoc.exe in Windows
        local_protoc = Path.join(["bin", "protoc.exe"])
        if File.exists?(local_protoc) do
          IO.puts("Found local protoc.exe")
          local_protoc
        else
          raise "protoc executable not found. Please install protoc."
        end
      path ->
        path
    end
  end

  defp postprocess_files do
    IO.puts("Post-processing generated files...")

    # Add GameProject namespace to all modules
    file_path = Path.join(@out_path, "log.pb.ex")
    if File.exists?(file_path) do
      content = File.read!(file_path)

      # Add GameProject namespace to all defmodule declarations
      updated_content = String.replace(content,
        ~r/defmodule\s+(\w+)/,
        "defmodule GameProject.Log.\\1"
      )

      # Fix references to other modules
      updated_content = String.replace(updated_content,
        ~r/(\w+)\.Service/,
        "GameProject.Log.\\1.Service"
      )

      updated_content = String.replace(updated_content,
        ~r/stream\((\w+)\)/,
        "stream(GameProject.Log.\\1)"
      )

      updated_content = String.replace(updated_content,
        ~r/service:\s+(\w+)\.Service/,
        "service: GameProject.Log.\\1.Service"
      )

      # Write back the updated content
      File.write!(file_path, updated_content)
      IO.puts("Updated #{file_path} with proper namespaces")
    else
      IO.puts("Warning: Generated file not found at #{file_path}")
    end
  end
end

# Run the code generation
GRPCCodeGen.run()
