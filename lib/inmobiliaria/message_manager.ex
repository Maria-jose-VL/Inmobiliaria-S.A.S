defmodule Inmobiliaria.MessageManager do
  @moduledoc """
  GenServer para el sistema de mensajería entre usuarios.

  Permite la comunicación entre clientes y responsables de propiedades.
  Los mensajes se asocian a una propiedad específica, facilitando la
  consulta del historial por propiedad.

  Estado interno:
  Lista de mensajes, cada uno es un mapa con:
    - `from`: remitente del mensaje
    - `to`: destinatario del mensaje
    - `property_id`: propiedad asociada
    - `message`: contenido del mensaje
    - `timestamp`: marca de tiempo

  Persistencia: `messages.log`
  Formato: from=ana; to=carlos; property_id=prop001; message=Hola; timestamp=2026-03-17T10:00:00
  """

  use GenServer
  require Logger

  @messages_file "messages.log"

  # --- API Pública ---

  @doc """
  Inicia el GenServer de mensajería.

  Carga los mensajes existentes desde `messages.log`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Envía un mensaje de un usuario al propietario de una propiedad.

  El destinatario se resuelve automáticamente consultando el proceso
  de la propiedad para obtener el owner.

  ## Parámetros
    - `from`: nombre del remitente
    - `property_id`: ID de la propiedad asociada
    - `content`: contenido del mensaje

  ## Retorno
    - `{:ok, message_data}` si el mensaje se envió correctamente
    - `{:error, reason}` si la propiedad no existe
  """
  @spec send_message(String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, String.t()}
  def send_message(from, property_id, content) do
    GenServer.call(__MODULE__, {:send_message, from, property_id, content})
  end

  @doc """
  Consulta los mensajes recibidos por un usuario.

  ## Parámetros
    - `username`: nombre del usuario

  ## Retorno
    - Lista de mapas con los mensajes donde `to` es el usuario
  """
  @spec get_messages_for(String.t()) :: [map()]
  def get_messages_for(username) do
    GenServer.call(__MODULE__, {:get_messages_for, username})
  end

  @doc """
  Consulta los mensajes asociados a una propiedad.

  ## Parámetros
    - `property_id`: ID de la propiedad

  ## Retorno
    - Lista de mapas con los mensajes de esa propiedad
  """
  @spec get_messages_for_property(String.t()) :: [map()]
  def get_messages_for_property(property_id) do
    GenServer.call(__MODULE__, {:get_messages_for_property, property_id})
  end

  # --- Callbacks del GenServer ---

  @impl true
  def init(:ok) do
    Logger.info("[MessageManager] Iniciando gestor de mensajes...")
    messages = load_messages()
    Logger.info("[MessageManager] #{length(messages)} mensajes cargados")
    {:ok, messages}
  end

  @impl true
  def handle_call({:send_message, from, property_id, content}, _from_pid, messages) do
    # Resolver el destinatario a partir de la propiedad
    case Inmobiliaria.Property.get_info(property_id) do
      {:ok, property_data} ->
        to = property_data["owner"]

        message = %{
          "from" => from,
          "to" => to,
          "property_id" => property_id,
          "message" => content,
          "timestamp" => current_timestamp()
        }

        # Persistir el mensaje inmediatamente
        Inmobiliaria.Persistence.append_record(@messages_file, message)
        updated_messages = messages ++ [message]

        Logger.info("[MessageManager] Mensaje de #{from} a #{to} sobre #{property_id}")
        {:reply, {:ok, message}, updated_messages}

      {:error, _} ->
        {:reply, {:error, "Property #{property_id} not found"}, messages}
    end
  end

  @impl true
  def handle_call({:get_messages_for, username}, _from, messages) do
    user_messages =
      Enum.filter(messages, fn msg -> msg["to"] == username end)

    {:reply, user_messages, messages}
  end

  @impl true
  def handle_call({:get_messages_for_property, property_id}, _from, messages) do
    property_messages =
      Enum.filter(messages, fn msg -> msg["property_id"] == property_id end)

    {:reply, property_messages, messages}
  end

  # --- Funciones Privadas ---

  # Carga los mensajes desde el archivo de persistencia.
  @spec load_messages() :: [map()]
  defp load_messages do
    Inmobiliaria.Persistence.read_records(@messages_file)
  end

  # Retorna la marca de tiempo actual en formato ISO 8601.
  @spec current_timestamp() :: String.t()
  defp current_timestamp do
    NaiveDateTime.utc_now() |> NaiveDateTime.to_iso8601()
  end
end
