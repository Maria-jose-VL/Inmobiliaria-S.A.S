defmodule Inmobiliaria.Application do
  @moduledoc """
  Punto de entrada de la aplicación OTP.

  Arranca el árbol de supervisión principal que incluye:
  - UserManager: GenServer para gestión de usuarios y autenticación
  - MessageManager: GenServer para el sistema de mensajería
  - PropertySupervisor: DynamicSupervisor que supervisa cada propiedad como proceso
  """

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # GenServer para gestión de usuarios (registro, login, puntajes, ranking)
      Inmobiliaria.UserManager,
      # GenServer para mensajería entre usuarios
      Inmobiliaria.MessageManager,
      # DynamicSupervisor que crea un GenServer por cada propiedad publicada
      Inmobiliaria.PropertySupervisor
    ]

    opts = [strategy: :one_for_one, name: Inmobiliaria.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
