defmodule Inmobiliaria.MixProject do
  use Mix.Project

  @moduledoc """
  Configuración del proyecto Mix para Inmobiliaria S.A.S.

  Define las dependencias, la aplicación OTP y las configuraciones
  de compilación del sistema inmobiliario.
  """

  def project do
    [
      app: :inmobiliaria,
      version: "1.0.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Inmobiliaria.Application, []}
    ]
  end

  defp deps do
    []
  end
end
