defmodule Inmobiliaria.PropertyManager do
  @moduledoc """
  Módulo orquestador para la gestión de propiedades.

  No es un GenServer en sí mismo, sino un módulo funcional que coordina
  las operaciones entre:
  - `PropertySupervisor` (creación de procesos)
  - `Property` (consultas y operaciones sobre procesos)
  - `Persistence` (almacenamiento en `properties.dat`)
  - `UserManager` (actualización de puntajes)

  Responsabilidades:
  - Publicar nuevas propiedades (crear proceso + persistir)
  - Listar propiedades con filtros (tipo, modalidad, ubicación, precio, estado)
  - Ejecutar operaciones de compra/arriendo y registrar en historial
  - Cargar propiedades existentes desde el archivo al iniciar
  - Generar IDs únicos para propiedades
  """

  require Logger

  @properties_file "properties.dat"
  @results_file "results.log"

  # --- Funciones Públicas ---

  @doc """
  Carga todas las propiedades desde `properties.dat` e inicia un proceso
  GenServer para cada una a través del PropertySupervisor.

  Debe llamarse después de que el supervision tree esté activo.

  ## Retorno
    - `:ok` siempre
  """
  @spec load_properties() :: :ok
  def load_properties do
    records = Inmobiliaria.Persistence.read_records(@properties_file)

    Enum.each(records, fn record ->
      # Normalizar los datos numéricos
      property_data = normalize_property(record)

      case Inmobiliaria.PropertySupervisor.add_property(property_data) do
        {:ok, _pid} ->
          Logger.info("[PropertyManager] Propiedad cargada: #{property_data["id"]}")

        {:error, reason} ->
          Logger.warning("[PropertyManager] Error cargando propiedad #{record["id"]}: #{inspect(reason)}")
      end
    end)

    count = Inmobiliaria.PropertySupervisor.count_children()
    Logger.info("[PropertyManager] #{count} propiedades activas como procesos")
    :ok
  end

  @doc """
  Publica una nueva propiedad en el sistema.

  Genera un ID único, crea un proceso GenServer para la propiedad
  y la persiste en `properties.dat`.

  ## Parámetros
    - `owner`: nombre del usuario que publica
    - `attrs`: mapa con los atributos de la propiedad:
      - `"type"`: tipo (casa, apartamento, oficina, lote)
      - `"modality"`: modalidad (venta, arriendo)
      - `"location"`: ubicación/ciudad
      - `"price"`: precio (string numérico)
      - `"rooms"`: habitaciones (string numérico)
      - `"area"`: área en m² (string numérico)

  ## Retorno
    - `{:ok, property_id}` si la publicación fue exitosa
    - `{:error, reason}` si hubo un error de validación
  """
  @spec publish(String.t(), map()) :: {:ok, String.t()} | {:error, String.t()}
  def publish(owner, attrs) do
    with :ok <- validate_property_type(attrs["type"]),
         :ok <- validate_modality(attrs["modality"]),
         :ok <- validate_location(attrs["location"]),
         :ok <- validate_numeric(attrs["price"], "price"),
         :ok <- validate_non_negative(attrs["rooms"], "rooms"),
         :ok <- validate_numeric(attrs["area"], "area") do
      property_id = generate_id()

      property_data = %{
        "id" => property_id,
        "type" => attrs["type"],
        "modality" => attrs["modality"],
        "location" => attrs["location"],
        "price" => attrs["price"],
        "rooms" => attrs["rooms"],
        "area" => attrs["area"],
        "status" => "disponible",
        "owner" => owner
      }

      case Inmobiliaria.PropertySupervisor.add_property(property_data) do
        {:ok, _pid} ->
          persist_all_properties()
          Logger.info("[PropertyManager] Propiedad #{property_id} publicada por #{owner}")
          {:ok, property_id}

        {:error, reason} ->
          {:error, "Failed to create property process: #{inspect(reason)}"}
      end
    end
  end

  @doc """
  Lista todas las propiedades disponibles, opcionalmente filtradas.

  ## Parámetros
    - `filters`: mapa con filtros opcionales:
      - `"type"`: tipo de propiedad
      - `"modality"`: modalidad
      - `"location"`: ubicación
      - `"min_price"`: precio mínimo
      - `"max_price"`: precio máximo
      - `"status"`: estado específico (por defecto solo "disponible")

  ## Retorno
    - Lista de mapas con los datos de las propiedades que cumplen los filtros
  """
  @spec list_properties(map()) :: [map()]
  def list_properties(filters \\ %{}) do
    all_records = Inmobiliaria.Persistence.read_records(@properties_file)

    all_records
    |> Enum.map(&normalize_property/1)
    |> apply_filters(filters)
  end

  @doc """
  Ejecuta una operación de compra sobre una propiedad.

  Delega al GenServer de la propiedad, actualiza puntajes de ambas partes,
  persiste el estado actualizado y registra la transacción en `results.log`.

  ## Parámetros
    - `property_id`: ID de la propiedad
    - `buyer`: nombre del comprador

  ## Retorno
    - `{:ok, transaction}` si la compra fue exitosa
    - `{:error, reason}` si no se pudo completar
  """
  @spec buy_property(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def buy_property(property_id, buyer) do
    case Inmobiliaria.Property.buy(property_id, buyer) do
      {:ok, transaction} ->
        finalize_transaction(transaction)
        {:ok, transaction}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Ejecuta una operación de arriendo sobre una propiedad.

  Funciona de manera análoga a `buy_property/2` pero para arriendos.

  ## Parámetros
    - `property_id`: ID de la propiedad
    - `tenant`: nombre del arrendatario

  ## Retorno
    - `{:ok, transaction}` si el arriendo fue exitoso
    - `{:error, reason}` si no se pudo completar
  """
  @spec rent_property(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def rent_property(property_id, tenant) do
    case Inmobiliaria.Property.rent(property_id, tenant) do
      {:ok, transaction} ->
        finalize_transaction(transaction)
        {:ok, transaction}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # --- Funciones Privadas ---

  # Finaliza una transacción: actualiza puntajes, persiste propiedades y registra en historial.
  @spec finalize_transaction(map()) :: :ok
  defp finalize_transaction(transaction) do
    # Otorgar puntos al cliente y al responsable
    Inmobiliaria.UserManager.add_points(transaction["client"])
    Inmobiliaria.UserManager.add_points(transaction["responsible"])

    # Persistir estado actualizado de todas las propiedades
    persist_all_properties()

    # Registrar operación en el historial
    log_entry = Map.put(transaction, "date", current_date())
    Inmobiliaria.Persistence.append_record(@results_file, log_entry)

    Logger.info(
      "[PropertyManager] Transacción registrada: #{transaction["operation"]} " <>
        "de #{transaction["property_id"]} por #{transaction["client"]}"
    )

    :ok
  end

  # Lee los datos actualizados de cada proceso activo y los persiste en el archivo.
  @spec persist_all_properties() :: :ok
  defp persist_all_properties do
    records = Inmobiliaria.Persistence.read_records(@properties_file)

    # Actualizar los registros con el estado actual de los procesos vivos
    updated_records =
      Enum.map(records, fn record ->
        case Inmobiliaria.Property.get_info(record["id"]) do
          {:ok, live_data} -> live_data
          {:error, _} -> record
        end
      end)

    # Agregar propiedades que son nuevas (no estaban en el archivo)
    existing_ids = Enum.map(records, & &1["id"]) |> MapSet.new()

    # Recolectar todas las propiedades vivas de los procesos globalmente registrados
    new_from_processes =
      :global.registered_names()
      |> Enum.filter(fn
        {:property, _id} -> true
        _ -> false
      end)
      |> Enum.map(fn {:property, id} -> id end)
      |> Enum.reject(&MapSet.member?(existing_ids, &1))
      |> Enum.map(fn id ->
        case Inmobiliaria.Property.get_info(id) do
          {:ok, data} -> data
          {:error, _} -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    all_records = updated_records ++ new_from_processes
    Inmobiliaria.Persistence.write_records(@properties_file, all_records)
    :ok
  end

  # Aplica filtros a la lista de propiedades.
  @spec apply_filters([map()], map()) :: [map()]
  defp apply_filters(properties, filters) do
    properties
    |> maybe_filter("type", filters["type"])
    |> maybe_filter("modality", filters["modality"])
    |> maybe_filter("location", filters["location"])
    |> maybe_filter("status", filters["status"] || "disponible")
    |> maybe_filter_price_range(filters["min_price"], filters["max_price"])
  end

  # Filtro genérico por igualdad de un campo (case-insensitive).
  @spec maybe_filter([map()], String.t(), String.t() | nil) :: [map()]
  defp maybe_filter(properties, _field, nil), do: properties

  defp maybe_filter(properties, field, value) do
    normalized_value = String.downcase(String.trim(value))

    Enum.filter(properties, fn prop ->
      prop_value = prop[field]
      prop_value != nil and String.downcase(String.trim(prop_value)) == normalized_value
    end)
  end

  # Filtro por rango de precio.
  @spec maybe_filter_price_range([map()], String.t() | nil, String.t() | nil) :: [map()]
  defp maybe_filter_price_range(properties, nil, nil), do: properties

  defp maybe_filter_price_range(properties, min_str, max_str) do
    min_price = parse_price(min_str)
    max_price = parse_price(max_str)

    Enum.filter(properties, fn prop ->
      price = parse_price(prop["price"])

      (is_nil(min_price) or price >= min_price) and
        (is_nil(max_price) or price <= max_price)
    end)
  end

  # Parsea un string de precio a número, retorna nil si es inválido.
  @spec parse_price(String.t() | nil) :: number() | nil
  defp parse_price(nil), do: nil

  defp parse_price(str) do
    case Integer.parse(String.trim(str)) do
      {num, _} -> num
      :error -> nil
    end
  end

  # Normaliza una propiedad cargada del archivo asegurando valores consistentes.
  @spec normalize_property(map()) :: map()
  defp normalize_property(record) do
    %{
      "id" => record["id"],
      "type" => record["type"] || "casa",
      "modality" => record["modality"] || "venta",
      "location" => record["location"] || "N/A",
      "price" => record["price"] || "0",
      "rooms" => record["rooms"] || "0",
      "area" => record["area"] || "0",
      "status" => record["status"] || "disponible",
      "owner" => record["owner"] || "unknown"
    }
  end

  # Valida el tipo de propiedad.
  @spec validate_property_type(String.t() | nil) :: :ok | {:error, String.t()}
  defp validate_property_type(nil), do: {:error, "Property type is required"}

  defp validate_property_type(type) do
    valid_types = ["casa", "apartamento", "oficina", "lote"]

    if String.downcase(type) in valid_types do
      :ok
    else
      {:error, "Invalid property type. Must be one of: #{Enum.join(valid_types, ", ")}"}
    end
  end

  # Valida la modalidad de la propiedad.
  @spec validate_modality(String.t() | nil) :: :ok | {:error, String.t()}
  defp validate_modality(nil), do: {:error, "Modality is required"}

  defp validate_modality(modality) do
    if String.downcase(modality) in ["venta", "arriendo"] do
      :ok
    else
      {:error, "Invalid modality. Must be: venta or arriendo"}
    end
  end

  # Valida que la ubicación sea válida según locations.dat.
  @spec validate_location(String.t() | nil) :: :ok | {:error, String.t()}
  defp validate_location(nil), do: {:error, "Location is required"}

  defp validate_location(location) do
    if Inmobiliaria.Location.valid?(location) do
      :ok
    else
      available = Inmobiliaria.Location.list() |> Enum.join(", ")
      {:error, "Invalid location '#{location}'. Available: #{available}"}
    end
  end

  # Valida que un campo sea un número válido.
  @spec validate_numeric(String.t() | nil, String.t()) :: :ok | {:error, String.t()}
  defp validate_numeric(nil, field), do: {:error, "#{field} is required"}

  defp validate_numeric(value, field) do
    case Integer.parse(value) do
      {n, _} when n > 0 -> :ok
      _ -> {:error, "#{field} must be a positive number"}
    end
  end

  # Valida que un campo sea un número no negativo (permite 0).
  # Se usa para campos como habitaciones donde un lote puede tener 0.
  @spec validate_non_negative(String.t() | nil, String.t()) :: :ok | {:error, String.t()}
  defp validate_non_negative(nil, field), do: {:error, "#{field} is required"}

  defp validate_non_negative(value, field) do
    case Integer.parse(value) do
      {n, _} when n >= 0 -> :ok
      _ -> {:error, "#{field} must be a non-negative number"}
    end
  end

  # Genera un ID único para una propiedad con formato "propXXX".
  @spec generate_id() :: String.t()
  defp generate_id do
    timestamp = System.unique_integer([:positive]) |> rem(100_000)
    "prop#{String.pad_leading(to_string(timestamp), 5, "0")}"
  end

  # Retorna la fecha actual en formato ISO 8601.
  @spec current_date() :: String.t()
  defp current_date do
    Date.utc_today() |> Date.to_iso8601()
  end
end
