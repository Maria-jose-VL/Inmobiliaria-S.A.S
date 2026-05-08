defmodule InmobiliariaTest do
  @moduledoc """
  Tests unitarios para el sistema Inmobiliaria S.A.S.

  Cubre las funcionalidades principales:
  - Persistencia: lectura/escritura de archivos
  - Ubicaciones: validación de ciudades
  - Usuarios: registro, autenticación, puntajes, ranking
  - Propiedades: publicación, consulta, compra, arriendo
  - Mensajería: envío y recepción de mensajes
  """

  use ExUnit.Case

  # ============================================================
  # Tests del módulo de Persistencia
  # ============================================================

  describe "Inmobiliaria.Persistence" do
    test "writes and reads records correctly" do
      test_file = "test_persistence.dat"
      records = [
        %{"name" => "alice", "age" => "30"},
        %{"name" => "bob", "age" => "25"}
      ]

      Inmobiliaria.Persistence.write_records(test_file, records)
      loaded = Inmobiliaria.Persistence.read_records(test_file)

      assert length(loaded) == 2
      assert Enum.any?(loaded, fn r -> r["name"] == "alice" and r["age"] == "30" end)
      assert Enum.any?(loaded, fn r -> r["name"] == "bob" and r["age"] == "25" end)

      # Cleanup
      File.rm(Inmobiliaria.Persistence.data_path(test_file))
    end

    test "appends records to a file" do
      test_file = "test_append.dat"
      Inmobiliaria.Persistence.write_records(test_file, [%{"id" => "1"}])
      Inmobiliaria.Persistence.append_record(test_file, %{"id" => "2"})

      loaded = Inmobiliaria.Persistence.read_records(test_file)
      assert length(loaded) == 2

      # Cleanup
      File.rm(Inmobiliaria.Persistence.data_path(test_file))
    end

    test "returns empty list for non-existent file" do
      result = Inmobiliaria.Persistence.read_records("nonexistent_file.dat")
      assert result == []
    end
  end

  # ============================================================
  # Tests del módulo de Ubicaciones
  # ============================================================

  describe "Inmobiliaria.Location" do
    test "lists available locations" do
      locations = Inmobiliaria.Location.list()
      assert is_list(locations)
      assert length(locations) > 0
    end

    test "validates known locations (case-insensitive)" do
      assert Inmobiliaria.Location.valid?("Armenia")
      assert Inmobiliaria.Location.valid?("armenia")
      assert Inmobiliaria.Location.valid?("BOGOTA")
    end

    test "rejects unknown locations" do
      refute Inmobiliaria.Location.valid?("Atlantis")
      refute Inmobiliaria.Location.valid?("Gotham")
    end
  end

  # ============================================================
  # Tests del módulo de Usuarios
  # ============================================================

  describe "Inmobiliaria.UserManager" do
    test "registers a new user on first connect" do
      unique = "test_user_#{System.unique_integer([:positive])}"
      result = Inmobiliaria.UserManager.connect(unique, "pass123", "cliente")
      assert {:ok, user} = result
      assert user["role"] == "cliente"
      assert user["username"] == unique
    end

    test "authenticates existing user with correct password" do
      unique = "test_auth_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(unique, "mypass", "vendedor")
      result = Inmobiliaria.UserManager.connect(unique, "mypass", "vendedor")
      assert {:ok, _user} = result
    end

    test "rejects incorrect password" do
      unique = "test_badpass_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(unique, "correct", "cliente")
      result = Inmobiliaria.UserManager.connect(unique, "wrong", "cliente")
      assert {:error, "Incorrect password"} = result
    end

    test "rejects invalid role" do
      unique = "test_badrole_#{System.unique_integer([:positive])}"
      result = Inmobiliaria.UserManager.connect(unique, "pass", "admin")
      assert {:error, _reason} = result
    end

    test "retrieves user score" do
      unique = "test_score_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(unique, "pass", "cliente")
      assert {:ok, 0} = Inmobiliaria.UserManager.get_score(unique)
    end

    test "adds points to user" do
      unique = "test_points_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(unique, "pass", "cliente")
      Inmobiliaria.UserManager.add_points(unique)
      assert {:ok, 10} = Inmobiliaria.UserManager.get_score(unique)
    end

    test "returns ranking sorted by score" do
      ranked = Inmobiliaria.UserManager.ranking()
      assert is_list(ranked)

      # Verify descending order
      scores = Enum.map(ranked, & &1["score"])
      assert scores == Enum.sort(scores, :desc)
    end
  end

  # ============================================================
  # Tests del módulo de Propiedades
  # ============================================================

  describe "Inmobiliaria.PropertyManager" do
    setup do
      # Create a seller for publishing
      seller = "test_seller_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(seller, "pass", "vendedor")
      %{seller: seller}
    end

    test "publishes a valid property", %{seller: seller} do
      attrs = %{
        "type" => "casa",
        "modality" => "venta",
        "location" => "Armenia",
        "price" => "300000000",
        "rooms" => "4",
        "area" => "180"
      }

      assert {:ok, property_id} = Inmobiliaria.PropertyManager.publish(seller, attrs)
      assert String.starts_with?(property_id, "prop")
    end

    test "rejects invalid property type", %{seller: seller} do
      attrs = %{
        "type" => "castillo",
        "modality" => "venta",
        "location" => "Armenia",
        "price" => "100",
        "rooms" => "1",
        "area" => "50"
      }

      assert {:error, _reason} = Inmobiliaria.PropertyManager.publish(seller, attrs)
    end

    test "rejects invalid location", %{seller: seller} do
      attrs = %{
        "type" => "casa",
        "modality" => "venta",
        "location" => "Atlantis",
        "price" => "100",
        "rooms" => "1",
        "area" => "50"
      }

      assert {:error, _reason} = Inmobiliaria.PropertyManager.publish(seller, attrs)
    end

    test "lists properties with filters", %{seller: seller} do
      attrs = %{
        "type" => "apartamento",
        "modality" => "arriendo",
        "location" => "Bogota",
        "price" => "2000000",
        "rooms" => "2",
        "area" => "60"
      }

      {:ok, _id} = Inmobiliaria.PropertyManager.publish(seller, attrs)

      # Filter by type
      results = Inmobiliaria.PropertyManager.list_properties(%{"type" => "apartamento"})
      assert length(results) > 0
      assert Enum.all?(results, fn p -> p["type"] == "apartamento" end)
    end

    test "allows a client to buy a property", %{seller: seller} do
      buyer = "test_buyer_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(buyer, "pass", "cliente")

      attrs = %{
        "type" => "casa",
        "modality" => "venta",
        "location" => "Medellin",
        "price" => "500000000",
        "rooms" => "3",
        "area" => "120"
      }

      {:ok, property_id} = Inmobiliaria.PropertyManager.publish(seller, attrs)
      assert {:ok, transaction} = Inmobiliaria.PropertyManager.buy_property(property_id, buyer)
      assert transaction["operation"] == "compra"
      assert transaction["client"] == buyer
      assert transaction["responsible"] == seller
    end

    test "prevents buying an already sold property", %{seller: seller} do
      buyer1 = "buyer1_#{System.unique_integer([:positive])}"
      buyer2 = "buyer2_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(buyer1, "pass", "cliente")
      Inmobiliaria.UserManager.connect(buyer2, "pass", "cliente")

      attrs = %{
        "type" => "oficina",
        "modality" => "venta",
        "location" => "Cali",
        "price" => "400000000",
        "rooms" => "5",
        "area" => "200"
      }

      {:ok, property_id} = Inmobiliaria.PropertyManager.publish(seller, attrs)

      # First buyer succeeds
      assert {:ok, _} = Inmobiliaria.PropertyManager.buy_property(property_id, buyer1)

      # Second buyer fails (already sold)
      assert {:error, _reason} = Inmobiliaria.PropertyManager.buy_property(property_id, buyer2)
    end
  end

  # ============================================================
  # Tests del módulo de Mensajería
  # ============================================================

  describe "Inmobiliaria.MessageManager" do
    test "sends and retrieves messages for a property" do
      seller = "msg_seller_#{System.unique_integer([:positive])}"
      client = "msg_client_#{System.unique_integer([:positive])}"
      Inmobiliaria.UserManager.connect(seller, "pass", "vendedor")
      Inmobiliaria.UserManager.connect(client, "pass", "cliente")

      attrs = %{
        "type" => "lote",
        "modality" => "venta",
        "location" => "Pereira",
        "price" => "100000000",
        "rooms" => "0",
        "area" => "500"
      }

      {:ok, property_id} = Inmobiliaria.PropertyManager.publish(seller, attrs)

      # Client sends a message
      assert {:ok, msg} =
               Inmobiliaria.MessageManager.send_message(client, property_id, "Is this still available?")

      assert msg["from"] == client
      assert msg["to"] == seller

      # Seller reads messages
      messages = Inmobiliaria.MessageManager.get_messages_for(seller)
      assert Enum.any?(messages, fn m -> m["from"] == client end)
    end
  end
end
