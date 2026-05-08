defmodule Inmobiliaria.UserManager do
  @moduledoc """
  GenServer para la gestión de usuarios del sistema inmobiliario.

  Responsabilidades:
  - Registro y autenticación de usuarios (login automático si no existe)
  - Gestión de roles: cliente, vendedor, arrendador
  - Puntajes acumulados por usuario
  - Ranking global de usuarios más activos
  - Persistencia en `users.dat`

  Estado interno:
  Un mapa donde cada clave es el nombre de usuario y el valor es un mapa con:
    - `role`: rol del usuario (cliente | vendedor | arrendador)
    - `password`: contraseña del usuario
    - `score`: puntaje acumulado

  Formato de `users.dat`:
    username=ana; role=cliente; password=1234; score=0
  """

  use GenServer
  require Logger

  @users_file "users.dat"

  # Puntos otorgados por operación según rol
  @client_points 10
  @seller_points 15

  # --- API Pública ---

  @doc """
  Inicia el GenServer de usuarios.

  Carga los datos existentes desde `users.dat` al estado inicial.
  Se registra con nombre `Inmobiliaria.UserManager` para acceso global.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @doc """
  Conecta un usuario al sistema.

  Si el usuario no existe, se registra automáticamente con el rol indicado.
  Si ya existe, valida la contraseña.

  ## Parámetros
    - `username`: nombre de usuario
    - `password`: contraseña
    - `role`: rol deseado ("cliente", "vendedor", "arrendador")

  ## Retorno
    - `{:ok, user_data}` si la conexión fue exitosa
    - `{:error, reason}` si la contraseña es incorrecta o el rol es inválido
  """
  @spec connect(String.t(), String.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def connect(username, password, role) do
    GenServer.call(__MODULE__, {:connect, username, password, role})
  end

  @doc """
  Obtiene los datos de un usuario.

  ## Parámetros
    - `username`: nombre del usuario a consultar

  ## Retorno
    - `{:ok, user_data}` con la info del usuario
    - `{:error, "User not found"}` si no existe
  """
  @spec get_user(String.t()) :: {:ok, map()} | {:error, String.t()}
  def get_user(username) do
    GenServer.call(__MODULE__, {:get_user, username})
  end

  @doc """
  Consulta el puntaje actual de un usuario.

  ## Parámetros
    - `username`: nombre del usuario

  ## Retorno
    - `{:ok, score}` con el puntaje numérico
    - `{:error, "User not found"}` si no existe
  """
  @spec get_score(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t()}
  def get_score(username) do
    GenServer.call(__MODULE__, {:get_score, username})
  end

  @doc """
  Agrega puntos a un usuario tras completar una operación.

  Se otorgan puntos según el rol:
  - Cliente: #{@client_points} puntos
  - Vendedor/Arrendador: #{@seller_points} puntos

  ## Parámetros
    - `username`: nombre del usuario

  ## Retorno
    - `:ok` si los puntos se agregaron correctamente
    - `{:error, "User not found"}` si el usuario no existe
  """
  @spec add_points(String.t()) :: :ok | {:error, String.t()}
  def add_points(username) do
    GenServer.call(__MODULE__, {:add_points, username})
  end

  @doc """
  Retorna el ranking global de usuarios ordenado por puntaje descendente.

  ## Retorno
    - Lista de mapas con `username`, `role` y `score`
  """
  @spec ranking() :: [map()]
  def ranking do
    GenServer.call(__MODULE__, :ranking)
  end

  @doc """
  Retorna el ranking filtrado por un rol específico.

  ## Parámetros
    - `role`: rol a filtrar ("cliente", "vendedor", "arrendador")

  ## Retorno
    - Lista de mapas con `username`, `role` y `score` del rol indicado
  """
  @spec ranking_by_role(String.t()) :: [map()]
  def ranking_by_role(role) do
    GenServer.call(__MODULE__, {:ranking_by_role, role})
  end

  @doc """
  Verifica si un usuario existe en el sistema.

  ## Parámetros
    - `username`: nombre del usuario a verificar

  ## Retorno
    - `true` si existe, `false` si no
  """
  @spec exists?(String.t()) :: boolean()
  def exists?(username) do
    GenServer.call(__MODULE__, {:exists?, username})
  end

  # --- Callbacks del GenServer ---

  @impl true
  def init(:ok) do
    Logger.info("[UserManager] Iniciando gestor de usuarios...")
    users = load_users()
    Logger.info("[UserManager] #{map_size(users)} usuarios cargados desde #{@users_file}")
    {:ok, users}
  end

  @impl true
  def handle_call({:connect, username, password, role}, _from, users) do
    case validate_role(role) do
      :ok ->
        case Map.get(users, username) do
          nil ->
            # Registro automático: el usuario no existe, se crea
            new_user = %{"role" => role, "password" => password, "score" => 0}
            updated_users = Map.put(users, username, new_user)
            persist_users(updated_users)
            Logger.info("[UserManager] Nuevo usuario registrado: #{username} (#{role})")
            {:reply, {:ok, Map.put(new_user, "username", username)}, updated_users}

          existing_user ->
            # El usuario existe, validar contraseña
            if existing_user["password"] == password do
              Logger.info("[UserManager] Usuario conectado: #{username}")
              {:reply, {:ok, Map.put(existing_user, "username", username)}, users}
            else
              Logger.warning("[UserManager] Contraseña incorrecta para: #{username}")
              {:reply, {:error, "Incorrect password"}, users}
            end
        end

      {:error, reason} ->
        {:reply, {:error, reason}, users}
    end
  end

  @impl true
  def handle_call({:get_user, username}, _from, users) do
    case Map.get(users, username) do
      nil -> {:reply, {:error, "User not found"}, users}
      user -> {:reply, {:ok, Map.put(user, "username", username)}, users}
    end
  end

  @impl true
  def handle_call({:get_score, username}, _from, users) do
    case Map.get(users, username) do
      nil -> {:reply, {:error, "User not found"}, users}
      user -> {:reply, {:ok, user["score"]}, users}
    end
  end

  @impl true
  def handle_call({:add_points, username}, _from, users) do
    case Map.get(users, username) do
      nil ->
        {:reply, {:error, "User not found"}, users}

      user ->
        points = if user["role"] == "cliente", do: @client_points, else: @seller_points
        updated_user = Map.update!(user, "score", &(&1 + points))
        updated_users = Map.put(users, username, updated_user)
        persist_users(updated_users)
        Logger.info("[UserManager] +#{points} puntos para #{username} (total: #{updated_user["score"]})")
        {:reply, :ok, updated_users}
    end
  end

  @impl true
  def handle_call(:ranking, _from, users) do
    ranked = build_ranking(users)
    {:reply, ranked, users}
  end

  @impl true
  def handle_call({:ranking_by_role, role}, _from, users) do
    ranked =
      users
      |> Enum.filter(fn {_username, data} -> data["role"] == role end)
      |> build_ranking_from_list()

    {:reply, ranked, users}
  end

  @impl true
  def handle_call({:exists?, username}, _from, users) do
    {:reply, Map.has_key?(users, username), users}
  end

  # --- Funciones Privadas ---

  # Carga los usuarios desde el archivo de persistencia.
  # Retorna un mapa %{username => %{role, password, score}}.
  @spec load_users() :: map()
  defp load_users do
    Inmobiliaria.Persistence.read_records(@users_file)
    |> Enum.reduce(%{}, fn record, acc ->
      username = record["username"]

      if username do
        user_data = %{
          "role" => record["role"] || "cliente",
          "password" => record["password"] || "",
          "score" => parse_integer(record["score"], 0)
        }

        Map.put(acc, username, user_data)
      else
        acc
      end
    end)
  end

  # Persiste el estado completo de usuarios al archivo.
  @spec persist_users(map()) :: :ok
  defp persist_users(users) do
    records =
      Enum.map(users, fn {username, data} ->
        %{
          "username" => username,
          "role" => data["role"],
          "password" => data["password"],
          "score" => to_string(data["score"])
        }
      end)

    Inmobiliaria.Persistence.write_records(@users_file, records)
  end

  # Construye el ranking desde el mapa completo de usuarios.
  @spec build_ranking(map()) :: [map()]
  defp build_ranking(users) do
    users
    |> Enum.map(fn {username, data} ->
      %{"username" => username, "role" => data["role"], "score" => data["score"]}
    end)
    |> Enum.sort_by(fn u -> u["score"] end, :desc)
  end

  # Construye el ranking desde una lista filtrada de {username, data}.
  @spec build_ranking_from_list([{String.t(), map()}]) :: [map()]
  defp build_ranking_from_list(user_list) do
    user_list
    |> Enum.map(fn {username, data} ->
      %{"username" => username, "role" => data["role"], "score" => data["score"]}
    end)
    |> Enum.sort_by(fn u -> u["score"] end, :desc)
  end

  # Valida que el rol sea uno de los permitidos.
  @spec validate_role(String.t()) :: :ok | {:error, String.t()}
  defp validate_role(role) when role in ["cliente", "vendedor", "arrendador"], do: :ok
  defp validate_role(_role), do: {:error, "Invalid role. Must be: cliente, vendedor, or arrendador"}

  # Parsea un string a entero con valor por defecto.
  @spec parse_integer(String.t() | nil, integer()) :: integer()
  defp parse_integer(nil, default), do: default

  defp parse_integer(str, default) do
    case Integer.parse(str) do
      {num, _} -> num
      :error -> default
    end
  end
end
