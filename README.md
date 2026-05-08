# 🏠 Inmobiliaria S.A.S

Sistema de gestión inmobiliaria construido con **Elixir/OTP** que simula el flujo real de una inmobiliaria, aplicando concurrencia, supervisión, persistencia y comunicación entre procesos.

## 📋 Descripción

El sistema permite gestionar múltiples propiedades, solicitudes y negociaciones en paralelo. Soporta usuarios con roles (cliente, vendedor, arrendador), publicación de propiedades, operaciones de compra/arriendo, mensajería y ranking de actividad.

## 🏗️ Arquitectura

```
┌─────────────────────────────────────────────────┐
│              Inmobiliaria.Supervisor            │
│                 (one_for_one)                    │
├─────────────┬──────────────┬────────────────────┤
│ UserManager │ MessageManager│ PropertySupervisor │
│ (GenServer) │  (GenServer)  │ (DynamicSupervisor)│
│             │               │                    │
│ - Registro  │ - Envío       │  ┌──────────────┐  │
│ - Login     │ - Recepción   │  │ Property #1  │  │
│ - Puntajes  │ - Historial   │  │ (GenServer)  │  │
│ - Ranking   │               │  ├──────────────┤  │
│             │               │  │ Property #2  │  │
│             │               │  │ (GenServer)  │  │
│             │               │  ├──────────────┤  │
│             │               │  │ Property #N  │  │
│             │               │  │ (GenServer)  │  │
│             │               │  └──────────────┘  │
└─────────────┴──────────────┴────────────────────┘
```

## 📁 Estructura del Proyecto

```
inmobiliaria/
├── lib/
│   └── inmobiliaria/
│       ├── application.ex          # Punto de entrada OTP
│       ├── server.ex               # CLI interactivo (REPL)
│       ├── property.ex             # GenServer por propiedad
│       ├── property_supervisor.ex  # DynamicSupervisor
│       ├── property_manager.ex     # Orquestador de propiedades
│       ├── user_manager.ex         # GenServer de usuarios
│       ├── message_manager.ex      # GenServer de mensajería
│       ├── location.ex             # Validación de ubicaciones
│       └── persistence.ex          # Utilidades de archivos
├── data/
│   ├── users.dat                   # Usuarios y puntajes
│   ├── properties.dat              # Propiedades registradas
│   ├── results.log                 # Historial de operaciones
│   ├── messages.log                # Mensajes entre usuarios
│   └── locations.dat               # Ubicaciones válidas
├── test/
│   ├── inmobiliaria_test.exs
│   └── test_helper.exs
├── mix.exs
└── README.md
```

## 🚀 Inicio Rápido

### Prerrequisitos
- Elixir >= 1.14
- Erlang/OTP >= 24

### Instalación

```bash
# Clonar el repositorio
git clone <repo-url>
cd Inmobiliaria-S.A.S

# Obtener dependencias
mix deps.get

# Compilar
mix compile
```

### Ejecución

```bash
# Iniciar el sistema interactivo
iex -S mix

# Luego ejecutar:
Inmobiliaria.Server.start()
```

### Ejecutar Tests

```bash
mix test
```

## 💻 Comandos Disponibles

### Conexión
| Comando | Descripción |
|---------|-------------|
| `connect <user> <pass> <role>` | Login o registro automático |
| `disconnect` | Cerrar sesión |

### Propiedades (vendedor/arrendador)
| Comando | Descripción |
|---------|-------------|
| `publish_property tipo=X modalidad=X ubicacion=X precio=X habitaciones=X area=X` | Publicar propiedad |

### Consulta (todos)
| Comando | Descripción |
|---------|-------------|
| `list_properties` | Listar propiedades disponibles |
| `search_properties tipo=X modalidad=X ubicacion=X precio_min=X precio_max=X` | Buscar con filtros |

### Operaciones (cliente)
| Comando | Descripción |
|---------|-------------|
| `buy_property <id>` | Comprar propiedad |
| `rent_property <id>` | Arrendar propiedad |

### Mensajería
| Comando | Descripción |
|---------|-------------|
| `send_message <prop_id> <mensaje>` | Enviar mensaje al dueño |
| `read_messages` | Leer mensajes recibidos |

### Información
| Comando | Descripción |
|---------|-------------|
| `my_score` | Ver puntaje personal |
| `ranking` | Ranking global |
| `ranking <role>` | Ranking por rol |
| `help` | Mostrar ayuda |
| `exit` | Salir |

## 📖 Flujo de Ejemplo

```
# 1. Carlos se conecta como vendedor
inmobiliaria> connect carlos 1234 vendedor
✅ Connected as 'carlos' (role: vendedor)

# 2. Carlos publica una casa en venta
inmobiliaria[carlos]> publish_property tipo=casa modalidad=venta ubicacion=Armenia precio=300000000 habitaciones=4 area=180
✅ Property published successfully! ID: prop00001

# 3. Ana se conecta como cliente
inmobiliaria> connect ana 4321 cliente
✅ Connected as 'ana' (role: cliente)

# 4. Ana consulta propiedades
inmobiliaria[ana]> list_properties

# 5. Ana envía un mensaje al vendedor
inmobiliaria[ana]> send_message prop00001 Hola, me interesa esta casa

# 6. Ana compra la propiedad
inmobiliaria[ana]> buy_property prop00001
✅ Property purchased successfully!

# 7. Ver ranking
inmobiliaria[ana]> ranking
```

## 🔧 Conceptos OTP Aplicados

- **GenServer**: Cada propiedad, el gestor de usuarios y el gestor de mensajes son GenServers independientes
- **DynamicSupervisor**: Supervisa dinámicamente los procesos de propiedades
- **Concurrencia**: Múltiples usuarios y propiedades operando simultáneamente
- **Tolerancia a fallos**: Si un proceso de propiedad falla, el supervisor lo reinicia
- **Persistencia**: Datos almacenados en archivos de texto plano (.dat/.log)

## 📊 Sistema de Puntajes

| Rol | Puntos por operación |
|-----|---------------------|
| Cliente (compra/arriendo) | +10 |
| Vendedor/Arrendador | +15 |

## 👥 Autores

Proyecto Final - Programación 3 (2026-1)
