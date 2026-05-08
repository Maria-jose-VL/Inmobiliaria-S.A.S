defmodule Inmobiliaria.PropertySupervisor do
  @moduledoc """
  DynamicSupervisor para los procesos de propiedades.

  Supervisa cada propiedad como un GenServer hijo. Si un proceso de propiedad
  falla, el supervisor lo reinicia automáticamente, garantizando la
  disponibilidad del sistema.

  Este supervisor se inicia vacío y las propiedades se agregan dinámicamente
  cuando se publican o cuando se cargan desde el archivo de persistencia
  al iniciar el sistema.
  """

  use DynamicSupervisor
  require Logger

  # --- API Pública ---

  @doc """
  Inicia el DynamicSupervisor de propiedades.

  Se registra con nombre global `Inmobiliaria.PropertySupervisor`.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(_opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Agrega una nueva propiedad como proceso hijo del supervisor.

  Crea un nuevo GenServer `Inmobiliaria.Property` con los datos proporcionados.

  ## Parámetros
    - `property_data`: mapa con los datos completos de la propiedad

  ## Retorno
    - `{:ok, pid}` si el proceso se creó exitosamente
    - `{:error, reason}` si hubo un error (ej: propiedad ya existe)
  """
  @spec add_property(map()) :: DynamicSupervisor.on_start_child()
  def add_property(property_data) do
    child_spec = {Inmobiliaria.Property, property_data}
    DynamicSupervisor.start_child(__MODULE__, child_spec)
  end

  @doc """
  Retorna la cantidad de procesos de propiedades activos bajo el supervisor.

  ## Retorno
    - Número entero de procesos activos
  """
  @spec count_children() :: non_neg_integer()
  def count_children do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  # --- Callbacks del DynamicSupervisor ---

  @impl true
  def init(:ok) do
    Logger.info("[PropertySupervisor] DynamicSupervisor iniciado")
    DynamicSupervisor.init(strategy: :one_for_one)
  end
end
