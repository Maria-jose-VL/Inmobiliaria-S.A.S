defmodule Inmobiliaria.Server do
  @moduledoc """
  Servidor principal interactivo (CLI) del sistema inmobiliario.

  Implementa un loop de lectura-evaluación-impresión (REPL) que recibe
  comandos del usuario y los ejecuta según su sesión actual.

  Flujo:
  1. El usuario se conecta con `connect <user> <password> <role>`
  2. Una vez autenticado, puede ejecutar comandos según su rol
  3. Se desconecta con `disconnect` o sale con `exit`

  Comandos disponibles:
  - `connect <user> <pass> <role>` → Login/registro
  - `disconnect` → Cerrar sesión
  - `publish_property tipo=X modalidad=X ubicacion=X precio=X habitaciones=X area=X`
  - `list_properties` → Listar propiedades disponibles
  - `search_properties <filtro>=<valor> ...` → Búsqueda con filtros
  - `buy_property <id>` → Comprar propiedad
  - `rent_property <id>` → Arrendar propiedad
  - `send_message <property_id> <mensaje>` → Enviar mensaje
  - `read_messages` → Ver mensajes recibidos
  - `my_score` → Ver puntaje
  - `ranking` → Ranking global
  - `ranking <role>` → Ranking por rol
  - `help` → Mostrar ayuda
  - `exit` → Salir del sistema
  """

  require Logger

  # Mapa que representa la sesión activa: nil si no hay usuario conectado
  @type session :: %{username: String.t(), role: String.t()} | nil

  # --- Función de Entrada ---

  @doc """
  Inicia el servidor interactivo.

  Carga las propiedades existentes desde el archivo de persistencia
  y luego entra en el loop principal de comandos.
  """
  @spec start() :: :ok
  def start do
    print_banner()
    Inmobiliaria.PropertyManager.load_properties()
    IO.puts("\n✅ System ready. Type 'help' to see available commands.\n")
    loop(nil)
  end

  # --- Loop Principal ---

  # El loop principal lee comandos, los parsea y los ejecuta.
  # El estado de sesión se pasa como parámetro para mantener
  # el tracking del usuario conectado.
  @spec loop(session()) :: :ok
  defp loop(session) do
    prompt = build_prompt(session)
    input = IO.gets(prompt)

    case input do
      :eof ->
        IO.puts("\n👋 Goodbye!")
        :ok

      raw_input ->
        trimmed = String.trim(raw_input)

        if trimmed == "" do
          loop(session)
        else
          new_session = execute_command(trimmed, session)
          loop(new_session)
        end
    end
  end

  # --- Parseo y Ejecución de Comandos ---

  # Ejecuta un comando y retorna la nueva sesión (puede cambiar tras connect/disconnect).
  @spec execute_command(String.t(), session()) :: session()
  defp execute_command(input, session) do
    parts = String.split(input, " ", trim: true)
    command = hd(parts) |> String.downcase()
    args = tl(parts)

    case command do
      "connect" -> cmd_connect(args, session)
      "disconnect" -> cmd_disconnect(session)
      "publish_property" -> cmd_publish_property(args, session)
      "list_properties" -> cmd_list_properties(session)
      "search_properties" -> cmd_search_properties(args, session)
      "buy_property" -> cmd_buy_property(args, session)
      "rent_property" -> cmd_rent_property(args, session)
      "send_message" -> cmd_send_message(args, session)
      "read_messages" -> cmd_read_messages(session)
      "my_score" -> cmd_my_score(session)
      "ranking" -> cmd_ranking(args, session)
      "help" -> cmd_help(session)
      "exit" -> cmd_exit()
      _ ->
        IO.puts("❌ Unknown command: '#{command}'. Type 'help' for available commands.")
        session
    end
  end

  # --- Implementación de Comandos ---

  # CONNECT: Conectar o registrar un usuario.
  # Formato: connect <username> <password> <role>
  @spec cmd_connect([String.t()], session()) :: session()
  defp cmd_connect(args, session) do
    if session do
      IO.puts("⚠️  You are already connected as '#{session.username}'. Disconnect first.")
      session
    else
      case args do
        [username, password, role] ->
          case Inmobiliaria.UserManager.connect(username, password, role) do
            {:ok, user_data} ->
              IO.puts("✅ Connected as '#{username}' (role: #{user_data["role"]})")
              %{username: username, role: user_data["role"]}

            {:error, reason} ->
              IO.puts("❌ Connection failed: #{reason}")
              nil
          end

        _ ->
          IO.puts("⚠️  Usage: connect <username> <password> <role>")
          IO.puts("   Roles: cliente, vendedor, arrendador")
          session
      end
    end
  end

  # DISCONNECT: Cerrar sesión del usuario actual.
  @spec cmd_disconnect(session()) :: nil
  defp cmd_disconnect(session) do
    if session do
      IO.puts("👋 Disconnected. Goodbye, #{session.username}!")
    else
      IO.puts("⚠️  You are not connected.")
    end

    nil
  end

  # PUBLISH_PROPERTY: Publicar una propiedad (solo vendedores y arrendadores).
  # Formato: publish_property tipo=X modalidad=X ubicacion=X precio=X habitaciones=X area=X
  @spec cmd_publish_property([String.t()], session()) :: session()
  defp cmd_publish_property(args, session) do
    with {:ok, session} <- require_session(session),
         {:ok, _} <- require_role(session, ["vendedor", "arrendador"]) do
      attrs = parse_key_value_args(args)

      # Mapear nombres en español a claves internas
      property_attrs = %{
        "type" => attrs["tipo"],
        "modality" => attrs["modalidad"],
        "location" => attrs["ubicacion"],
        "price" => attrs["precio"],
        "rooms" => attrs["habitaciones"],
        "area" => attrs["area"]
      }

      case Inmobiliaria.PropertyManager.publish(session.username, property_attrs) do
        {:ok, property_id} ->
          IO.puts("✅ Property published successfully! ID: #{property_id}")

        {:error, reason} ->
          IO.puts("❌ Failed to publish: #{reason}")
      end
    end

    session
  end

  # LIST_PROPERTIES: Listar todas las propiedades disponibles.
  @spec cmd_list_properties(session()) :: session()
  defp cmd_list_properties(session) do
    with {:ok, _session} <- require_session(session) do
      properties = Inmobiliaria.PropertyManager.list_properties()
      print_properties(properties)
    end

    session
  end

  # SEARCH_PROPERTIES: Buscar propiedades con filtros.
  # Formato: search_properties tipo=casa modalidad=venta ubicacion=Armenia
  @spec cmd_search_properties([String.t()], session()) :: session()
  defp cmd_search_properties(args, session) do
    with {:ok, _session} <- require_session(session) do
      raw_filters = parse_key_value_args(args)

      # Mapear filtros en español a claves internas
      filters =
        %{}
        |> maybe_put("type", raw_filters["tipo"])
        |> maybe_put("modality", raw_filters["modalidad"])
        |> maybe_put("location", raw_filters["ubicacion"])
        |> maybe_put("min_price", raw_filters["precio_min"])
        |> maybe_put("max_price", raw_filters["precio_max"])
        |> maybe_put("status", raw_filters["estado"])

      properties = Inmobiliaria.PropertyManager.list_properties(filters)
      print_properties(properties)
    end

    session
  end

  # BUY_PROPERTY: Comprar una propiedad (solo clientes).
  # Formato: buy_property <property_id>
  @spec cmd_buy_property([String.t()], session()) :: session()
  defp cmd_buy_property(args, session) do
    with {:ok, session} <- require_session(session),
         {:ok, _} <- require_role(session, ["cliente"]) do
      case args do
        [property_id] ->
          case Inmobiliaria.PropertyManager.buy_property(property_id, session.username) do
            {:ok, transaction} ->
              IO.puts("✅ Property purchased successfully!")
              IO.puts("   Property: #{transaction["property_id"]}")
              IO.puts("   Price: $#{transaction["price"]}")
              IO.puts("   Location: #{transaction["location"]}")

            {:error, reason} ->
              IO.puts("❌ Purchase failed: #{reason}")
          end

        _ ->
          IO.puts("⚠️  Usage: buy_property <property_id>")
      end
    end

    session
  end

  # RENT_PROPERTY: Arrendar una propiedad (solo clientes).
  # Formato: rent_property <property_id>
  @spec cmd_rent_property([String.t()], session()) :: session()
  defp cmd_rent_property(args, session) do
    with {:ok, session} <- require_session(session),
         {:ok, _} <- require_role(session, ["cliente"]) do
      case args do
        [property_id] ->
          case Inmobiliaria.PropertyManager.rent_property(property_id, session.username) do
            {:ok, transaction} ->
              IO.puts("✅ Property rented successfully!")
              IO.puts("   Property: #{transaction["property_id"]}")
              IO.puts("   Price: $#{transaction["price"]}/month")
              IO.puts("   Location: #{transaction["location"]}")

            {:error, reason} ->
              IO.puts("❌ Rental failed: #{reason}")
          end

        _ ->
          IO.puts("⚠️  Usage: rent_property <property_id>")
      end
    end

    session
  end

  # SEND_MESSAGE: Enviar mensaje al dueño de una propiedad.
  # Formato: send_message <property_id> <message text...>
  @spec cmd_send_message([String.t()], session()) :: session()
  defp cmd_send_message(args, session) do
    with {:ok, session} <- require_session(session) do
      case args do
        [property_id | message_parts] when message_parts != [] ->
          message_text = Enum.join(message_parts, " ")

          case Inmobiliaria.MessageManager.send_message(session.username, property_id, message_text) do
            {:ok, msg} ->
              IO.puts("✅ Message sent to '#{msg["to"]}' about property #{property_id}")

            {:error, reason} ->
              IO.puts("❌ Failed to send message: #{reason}")
          end

        _ ->
          IO.puts("⚠️  Usage: send_message <property_id> <your message here>")
      end
    end

    session
  end

  # READ_MESSAGES: Ver mensajes recibidos.
  @spec cmd_read_messages(session()) :: session()
  defp cmd_read_messages(session) do
    with {:ok, session} <- require_session(session) do
      messages = Inmobiliaria.MessageManager.get_messages_for(session.username)

      if messages == [] do
        IO.puts("📭 No messages.")
      else
        IO.puts("\n📬 Messages for #{session.username}:")
        IO.puts(String.duplicate("-", 60))

        Enum.each(messages, fn msg ->
          IO.puts("  From: #{msg["from"]}")
          IO.puts("  Property: #{msg["property_id"]}")
          IO.puts("  Message: #{msg["message"]}")
          IO.puts("  Time: #{msg["timestamp"]}")
          IO.puts(String.duplicate("-", 60))
        end)
      end
    end

    session
  end

  # MY_SCORE: Ver puntaje del usuario actual.
  @spec cmd_my_score(session()) :: session()
  defp cmd_my_score(session) do
    with {:ok, session} <- require_session(session) do
      case Inmobiliaria.UserManager.get_score(session.username) do
        {:ok, score} ->
          IO.puts("⭐ Your score: #{score} points")

        {:error, reason} ->
          IO.puts("❌ Error: #{reason}")
      end
    end

    session
  end

  # RANKING: Mostrar ranking global o por rol.
  # Formato: ranking [role]
  @spec cmd_ranking([String.t()], session()) :: session()
  defp cmd_ranking(args, session) do
    with {:ok, _session} <- require_session(session) do
      ranked =
        case args do
          [role] -> Inmobiliaria.UserManager.ranking_by_role(role)
          [] -> Inmobiliaria.UserManager.ranking()
        end

      if ranked == [] do
        IO.puts("📊 No ranking data available.")
      else
        label = if args == [], do: "Global", else: "#{hd(args)}"
        IO.puts("\n🏆 #{label} Ranking:")
        IO.puts(String.duplicate("-", 45))
        IO.puts("  #   | Username         | Role        | Score")
        IO.puts(String.duplicate("-", 45))

        ranked
        |> Enum.with_index(1)
        |> Enum.each(fn {user, pos} ->
          IO.puts(
            "  #{String.pad_leading(to_string(pos), 3)} | " <>
              "#{String.pad_trailing(user["username"], 16)} | " <>
              "#{String.pad_trailing(user["role"], 11)} | " <>
              "#{user["score"]}"
          )
        end)

        IO.puts(String.duplicate("-", 45))
      end
    end

    session
  end

  # HELP: Mostrar los comandos disponibles.
  @spec cmd_help(session()) :: session()
  defp cmd_help(session) do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════════╗
    ║                    AVAILABLE COMMANDS                       ║
    ╠══════════════════════════════════════════════════════════════╣
    ║                                                              ║
    ║  CONNECTION                                                  ║
    ║  ─────────                                                   ║
    ║  connect <user> <pass> <role>   Login or register             ║
    ║  disconnect                     Logout                       ║
    ║                                                              ║
    ║  PROPERTIES (vendedor/arrendador)                             ║
    ║  ────────────────────────────────                             ║
    ║  publish_property tipo=X modalidad=X ubicacion=X             ║
    ║      precio=X habitaciones=X area=X                          ║
    ║                                                              ║
    ║  PROPERTIES (all users)                                      ║
    ║  ──────────────────────                                      ║
    ║  list_properties                List available properties    ║
    ║  search_properties <filters>    Search with filters          ║
    ║    Filters: tipo, modalidad, ubicacion, precio_min,          ║
    ║             precio_max, estado                               ║
    ║                                                              ║
    ║  OPERATIONS (cliente)                                        ║
    ║  ────────────────────                                        ║
    ║  buy_property <id>              Buy a property               ║
    ║  rent_property <id>             Rent a property              ║
    ║                                                              ║
    ║  MESSAGING                                                   ║
    ║  ─────────                                                   ║
    ║  send_message <prop_id> <msg>   Message property owner       ║
    ║  read_messages                  Read received messages       ║
    ║                                                              ║
    ║  INFO                                                        ║
    ║  ────                                                        ║
    ║  my_score                       View your score              ║
    ║  ranking                        Global ranking               ║
    ║  ranking <role>                 Ranking by role               ║
    ║                                                              ║
    ║  SYSTEM                                                      ║
    ║  ──────                                                      ║
    ║  help                           Show this help               ║
    ║  exit                           Exit the system              ║
    ║                                                              ║
    ╚══════════════════════════════════════════════════════════════╝
    """)

    session
  end

  # EXIT: Salir del sistema.
  @spec cmd_exit() :: no_return()
  defp cmd_exit do
    IO.puts("\n👋 Thank you for using Inmobiliaria S.A.S. Goodbye!")
    System.halt(0)
  end

  # --- Funciones de Utilidad ---

  # Valida que el usuario esté conectado antes de ejecutar un comando.
  @spec require_session(session()) :: {:ok, map()} | {:error, :not_connected}
  defp require_session(nil) do
    IO.puts("⚠️  You must be connected. Use: connect <user> <pass> <role>")
    {:error, :not_connected}
  end

  defp require_session(session), do: {:ok, session}

  # Valida que el usuario tenga uno de los roles requeridos.
  @spec require_role(map(), [String.t()]) :: {:ok, map()} | {:error, :wrong_role}
  defp require_role(session, allowed_roles) do
    if session.role in allowed_roles do
      {:ok, session}
    else
      IO.puts("⚠️  This command requires role: #{Enum.join(allowed_roles, " or ")}. Your role: #{session.role}")
      {:error, :wrong_role}
    end
  end

  # Parsea argumentos en formato "clave=valor" a un mapa.
  @spec parse_key_value_args([String.t()]) :: map()
  defp parse_key_value_args(args) do
    Enum.reduce(args, %{}, fn arg, acc ->
      case String.split(arg, "=", parts: 2) do
        [key, value] -> Map.put(acc, String.trim(key), String.trim(value))
        _ -> acc
      end
    end)
  end

  # Imprime una lista de propiedades con formato de tabla.
  @spec print_properties([map()]) :: :ok
  defp print_properties([]) do
    IO.puts("📋 No properties found.")
    :ok
  end

  defp print_properties(properties) do
    IO.puts("\n🏠 Properties (#{length(properties)} found):")
    IO.puts(String.duplicate("═", 90))

    IO.puts(
      "  " <>
        String.pad_trailing("ID", 12) <>
        String.pad_trailing("Type", 14) <>
        String.pad_trailing("Modality", 10) <>
        String.pad_trailing("Location", 14) <>
        String.pad_trailing("Price", 16) <>
        String.pad_trailing("Rooms", 7) <>
        String.pad_trailing("Area", 8) <>
        "Owner"
    )

    IO.puts(String.duplicate("─", 90))

    Enum.each(properties, fn prop ->
      IO.puts(
        "  " <>
          String.pad_trailing(prop["id"] || "?", 12) <>
          String.pad_trailing(prop["type"] || "?", 14) <>
          String.pad_trailing(prop["modality"] || "?", 10) <>
          String.pad_trailing(prop["location"] || "?", 14) <>
          String.pad_trailing("$#{prop["price"]}", 16) <>
          String.pad_trailing(prop["rooms"] || "?", 7) <>
          String.pad_trailing("#{prop["area"]}m²", 8) <>
          (prop["owner"] || "?")
      )
    end)

    IO.puts(String.duplicate("═", 90))
    :ok
  end

  # Construye el prompt del CLI según el estado de la sesión.
  @spec build_prompt(session()) :: String.t()
  defp build_prompt(nil), do: "inmobiliaria> "
  defp build_prompt(session), do: "inmobiliaria[#{session.username}]> "

  # Imprime el banner de bienvenida del sistema.
  @spec print_banner() :: :ok
  defp print_banner do
    IO.puts("""

    ╔══════════════════════════════════════════════════════════╗
    ║                                                          ║
    ║            🏠  INMOBILIARIA S.A.S  🏠                    ║
    ║                                                          ║
    ║       Real Estate Management System v1.0.0               ║
    ║       Powered by Elixir/OTP                              ║
    ║                                                          ║
    ╚══════════════════════════════════════════════════════════╝
    """)

    :ok
  end

  # Agrega un valor a un mapa solo si no es nil.
  @spec maybe_put(map(), String.t(), String.t() | nil) :: map()
  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
