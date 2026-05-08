defmodule Inmobiliaria.Location do
  @moduledoc """
  Módulo para gestión y validación de ubicaciones.

  Carga la lista de ubicaciones válidas desde el archivo `locations.dat`
  y proporciona funciones para verificar si una ubicación es válida.

  Cada línea del archivo `locations.dat` contiene el nombre de una ciudad
  o ubicación válida para publicar propiedades.
  """

  @locations_file "locations.dat"

  # --- Funciones Públicas ---

  @doc """
  Retorna la lista completa de ubicaciones válidas.

  Lee el archivo `locations.dat` y retorna cada ubicación como string
  en minúsculas para facilitar comparaciones.

  ## Retorno
    - Lista de strings con los nombres de las ubicaciones válidas
  """
  @spec list() :: [String.t()]
  def list do
    Inmobiliaria.Persistence.read_lines(@locations_file)
  end

  @doc """
  Verifica si una ubicación es válida.

  La comparación se realiza en minúsculas para ser case-insensitive.

  ## Parámetros
    - `location`: string con la ubicación a validar

  ## Retorno
    - `true` si la ubicación existe en `locations.dat`
    - `false` si no existe

  ## Ejemplo
      iex> Inmobiliaria.Location.valid?("Armenia")
      true
      iex> Inmobiliaria.Location.valid?("Atlantis")
      false
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(location) do
    normalized = String.downcase(String.trim(location))

    list()
    |> Enum.any?(fn loc -> String.downcase(loc) == normalized end)
  end
end
