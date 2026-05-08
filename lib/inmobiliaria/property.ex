defmodule Inmobiliaria.Property do
  @moduledoc """
  GenServer individual para cada propiedad publicada.

  Cada propiedad se ejecuta como un proceso independiente, lo que permite
  manejar operaciones concurrentes (compra/arriendo) de forma segura.
  Al ser un proceso aislado, solo una operación puede modificar el estado
  de una propiedad a la vez, garantizando consistencia.

  Estado interno (mapa):
    - `id`: identificador único de la propiedad (ej: "prop001")
    - `type`: tipo de propiedad (casa, apartamento, oficina, lote)
    - `modality`: modalidad (venta, arriendo)
    - `location`: ubicación/ciudad
    - `price`: precio
    - `rooms`: número de habitaciones
    - `area`: área en metros cuadrados
    - `status`: estado actual (disponible, reservada, vendida, arrendada)
    - `owner`: usuario que publicó la propiedad

  Al completar una operación (compra/arriendo), el proceso:
  1. Cambia el estado de la propiedad
  2. Persiste el cambio
  3. Retorna los datos de la operación para registrar en el historial
  """

  use GenServer
  require Logger

  # --- API Pública ---

  @doc """
  Inicia un GenServer para una propiedad específica.

  El proceso se registra en el Registry global bajo el id de la propiedad
  para poder localizarlo fácilmente.

  ## Parámetros
    - `property_data`: mapa con todos los datos de la propiedad
  """
  @spec start_link(map()) :: GenServer.on_start()
  def start_link(property_data) do
    id = property_data["id"]
    GenServer.start_link(__MODULE__, property_data, name: via_tuple(id))
  end

  @doc """
  Consulta el estado actual de una propiedad por su ID.

  ## Parámetros
    - `property_id`: identificador de la propiedad

  ## Retorno
    - `{:ok, property_data}` con el mapa completo de la propiedad
    - `{:error, "Property process not found"}` si el proceso no existe
  """
  @spec get_info(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_info(property_id) do
    case GenServer.whereis(via_tuple(property_id)) do
      nil -> {:error, "Property process not found"}
      pid -> {:ok, GenServer.call(pid, :get_info)}
    end
  end

  @doc """
  Intenta comprar una propiedad.

  Solo se permite si la propiedad está en modalidad "venta" y con
  estado "disponible". Si dos clientes intentan comprar simultáneamente,
  solo el primero que llegue al GenServer tendrá éxito (serialización
  de mensajes propia de GenServer).

  ## Parámetros
    - `property_id`: identificador de la propiedad
    - `buyer`: nombre del usuario comprador

  ## Retorno
    - `{:ok, transaction_data}` con los datos de la transacción
    - `{:error, reason}` si la operación no es posible
  """
  @spec buy(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def buy(property_id, buyer) do
    case GenServer.whereis(via_tuple(property_id)) do
      nil -> {:error, "Property not found"}
      pid -> GenServer.call(pid, {:buy, buyer})
    end
  end

  @doc """
  Intenta arrendar una propiedad.

  Solo se permite si la propiedad está en modalidad "arriendo" y con
  estado "disponible". La concurrencia se maneja igual que en `buy/2`.

  ## Parámetros
    - `property_id`: identificador de la propiedad
    - `tenant`: nombre del usuario arrendatario

  ## Retorno
    - `{:ok, transaction_data}` con los datos de la transacción
    - `{:error, reason}` si la operación no es posible
  """
  @spec rent(String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def rent(property_id, tenant) do
    case GenServer.whereis(via_tuple(property_id)) do
      nil -> {:error, "Property not found"}
      pid -> GenServer.call(pid, {:rent, tenant})
    end
  end

  # --- Callbacks del GenServer ---

  @impl true
  def init(property_data) do
    Logger.info("[Property] Proceso iniciado para propiedad: #{property_data["id"]}")
    {:ok, property_data}
  end

  @impl true
  def handle_call(:get_info, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_call({:buy, buyer}, _from, state) do
    cond do
      state["modality"] != "venta" ->
        {:reply, {:error, "This property is not for sale"}, state}

      state["status"] != "disponible" ->
        {:reply, {:error, "This property is no longer available (status: #{state["status"]})"}, state}

      state["owner"] == buyer ->
        {:reply, {:error, "You cannot buy your own property"}, state}

      true ->
        updated_state = Map.put(state, "status", "vendida")

        transaction = %{
          "client" => buyer,
          "responsible" => state["owner"],
          "property_id" => state["id"],
          "operation" => "compra",
          "location" => state["location"],
          "price" => state["price"],
          "final_status" => "Completada"
        }

        Logger.info("[Property] Propiedad #{state["id"]} vendida a #{buyer}")
        {:reply, {:ok, transaction}, updated_state}
    end
  end

  @impl true
  def handle_call({:rent, tenant}, _from, state) do
    cond do
      state["modality"] != "arriendo" ->
        {:reply, {:error, "This property is not for rent"}, state}

      state["status"] != "disponible" ->
        {:reply, {:error, "This property is no longer available (status: #{state["status"]})"}, state}

      state["owner"] == tenant ->
        {:reply, {:error, "You cannot rent your own property"}, state}

      true ->
        updated_state = Map.put(state, "status", "arrendada")

        transaction = %{
          "client" => tenant,
          "responsible" => state["owner"],
          "property_id" => state["id"],
          "operation" => "arriendo",
          "location" => state["location"],
          "price" => state["price"],
          "final_status" => "Completada"
        }

        Logger.info("[Property] Propiedad #{state["id"]} arrendada a #{tenant}")
        {:reply, {:ok, transaction}, updated_state}
    end
  end

  # --- Funciones Privadas ---

  # Genera la tupla `via` para registrar/localizar el proceso en el Registry.
  # Usamos :global para simplicidad sin necesidad de un Registry adicional.
  @spec via_tuple(String.t()) :: {:global, term()}
  defp via_tuple(property_id) do
    {:global, {:property, property_id}}
  end
end
