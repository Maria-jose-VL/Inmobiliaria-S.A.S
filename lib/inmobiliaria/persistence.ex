defmodule Inmobiliaria.Persistence do
  @moduledoc """
  Módulo utilitario para lectura y escritura de archivos de texto plano.

  Proporciona funciones helper para:
  - Leer archivos línea por línea y parsearlos con delimitador ";"
  - Escribir registros con formato delimitado por ";"
  - Agregar líneas al final de un archivo (append)
  - Sobreescribir un archivo completo con nuevos datos
  - Asegurar que el directorio `data/` exista antes de cualquier operación

  Todos los archivos de datos se almacenan en el directorio `data/` relativo
  a la raíz del proyecto.
  """

  @data_dir "data"

  # --- Funciones Públicas ---

  @doc """
  Retorna la ruta completa a un archivo dentro del directorio de datos.

  ## Parámetros
    - `filename`: nombre del archivo (ej: "users.dat")

  ## Ejemplo
      iex> Inmobiliaria.Persistence.data_path("users.dat")
      "data/users.dat"
  """
  @spec data_path(String.t()) :: String.t()
  def data_path(filename) do
    Path.join(@data_dir, filename)
  end

  @doc """
  Lee un archivo de datos y retorna una lista de mapas.

  Cada línea del archivo se parsea usando ";" como delimitador de campos.
  Cada campo tiene formato "clave=valor". Las líneas vacías se ignoran.

  ## Parámetros
    - `filename`: nombre del archivo a leer
    - `opts`: opciones adicionales (no usadas actualmente, reservadas para futuro)

  ## Retorno
    - Lista de mapas donde cada mapa es un registro del archivo

  ## Ejemplo
      iex> Inmobiliaria.Persistence.read_records("users.dat")
      [%{"username" => "ana", "role" => "cliente", "password" => "1234", "score" => "0"}]
  """
  @spec read_records(String.t(), keyword()) :: [map()]
  def read_records(filename, _opts \\ []) do
    path = data_path(filename)

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&parse_line/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  @doc """
  Escribe una lista de mapas como registros en un archivo, sobreescribiendo el contenido.

  Cada mapa se serializa como una línea con formato "clave=valor; clave=valor; ..."

  ## Parámetros
    - `filename`: nombre del archivo destino
    - `records`: lista de mapas a escribir

  ## Retorno
    - `:ok` si la escritura fue exitosa
  """
  @spec write_records(String.t(), [map()]) :: :ok
  def write_records(filename, records) do
    ensure_data_dir()
    path = data_path(filename)

    content =
      records
      |> Enum.map(&serialize_record/1)
      |> Enum.join("\n")

    # Agregar salto de línea final solo si hay contenido
    final_content = if content == "", do: "", else: content <> "\n"
    File.write!(path, final_content)
    :ok
  end

  @doc """
  Agrega un registro al final de un archivo existente (append).

  Si el archivo no existe, lo crea. Útil para logs de operaciones y mensajes.

  ## Parámetros
    - `filename`: nombre del archivo
    - `record`: mapa con los datos a agregar

  ## Retorno
    - `:ok` si la escritura fue exitosa
  """
  @spec append_record(String.t(), map()) :: :ok
  def append_record(filename, record) do
    ensure_data_dir()
    path = data_path(filename)
    line = serialize_record(record) <> "\n"
    File.write!(path, line, [:append])
    :ok
  end

  @doc """
  Lee todas las líneas de un archivo sin parsearlas.

  Útil para archivos como `locations.dat` que contienen solo valores simples.

  ## Parámetros
    - `filename`: nombre del archivo a leer

  ## Retorno
    - Lista de strings, cada uno representando una línea del archivo
  """
  @spec read_lines(String.t()) :: [String.t()]
  def read_lines(filename) do
    path = data_path(filename)

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.map(&String.trim/1)
    else
      []
    end
  end

  # --- Funciones Privadas ---

  # Parsea una línea con formato "clave=valor; clave=valor" en un mapa.
  # Retorna nil si la línea está vacía o es inválida.
  @spec parse_line(String.t()) :: map() | nil
  defp parse_line(line) do
    trimmed = String.trim(line)

    if trimmed == "" do
      nil
    else
      trimmed
      |> String.split(";")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))
      |> Enum.reduce(%{}, fn pair, acc ->
        case String.split(pair, "=", parts: 2) do
          [key, value] ->
            Map.put(acc, String.trim(key), String.trim(value))

          _ ->
            acc
        end
      end)
    end
  end

  # Serializa un mapa a formato "clave=valor; clave=valor".
  # Las claves se ordenan alfabéticamente para consistencia.
  @spec serialize_record(map()) :: String.t()
  defp serialize_record(record) do
    record
    |> Enum.sort_by(fn {key, _} -> key end)
    |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
    |> Enum.join("; ")
  end

  # Crea el directorio de datos si no existe.
  @spec ensure_data_dir() :: :ok
  defp ensure_data_dir do
    File.mkdir_p!(@data_dir)
    :ok
  end
end
