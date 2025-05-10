defmodule Prueba2.PasswordManager do
  import IO.ANSI

  @input_color bright() <> cyan()
  @reset reset()

  def hash_password(""), do: nil
  def hash_password(password), do: :crypto.hash(:sha256, password) |> Base.encode16(case: :lower)

  def verify_password(stored_hash, input_hash) do
    stored_hash == nil || input_hash == stored_hash
  end

  def get_room_password do
    IO.write(@input_color <> "Ingrese contraseña (vacía para sala sin contraseña): " <> @reset)
    IO.gets("") |> String.trim()
  end

  def get_join_password do
    IO.write(@input_color <> "Ingrese la contraseña: " <> @reset)
    password = IO.gets("") |> String.trim()
    hash_password(password)
  end
end
