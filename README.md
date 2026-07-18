# ReactiveState

ReactiveState is a lightweight Luau state layer for Roblox built on top of Replica. It gives you a schema-aware, proxy-based server state and a mirrored, event-driven client view for shared data.

---

## Features

- Proxy-based server state with natural table syntax
- Server-side schema validation for writes
- Batched updates with `:Batch(...)`
- Replica-backed replication to clients
- Event-driven client signals for changes, descendants, arrays, and dictionaries
- Simple `Get` and `OnReady` APIs for client-side reads

---

## Installation

Place ReactiveState in a shared location such as ReplicatedStorage and require it from scripts on both sides:

```lua
local ReactiveState = require(path.to.ReactiveState)
```

The module exposes two entry points:

```lua
local client = ReactiveState.client
local server = ReactiveState.server
```

---

## Server Example

```lua
local ReactiveState = require(path.to.ReactiveState)
local server = ReactiveState.server

local state = server.new("PlayerState", {
    Schema = {
        Health = true,
        Stats = {
            Damage = true,
        },
    },
    Data = {
        Health = 100,
        Stats = {
            Damage = 10,
        },
    },
})

state.Health = 90

state:Batch(function()
    state.Health = 80
    state.Stats.Damage = 15
end)

state:Destroy()
```

---

## Client Example

```lua
local ReactiveState = require(path.to.ReactiveState)
local client = ReactiveState.client

local state = client.OnNew("PlayerState")

state:OnReady(function()
    print("Health:", state:Get({"Health"}))
end)

local healthSignal = state:GetChangedSignal({"Health"})
healthSignal:Connect(function(newValue, oldValue, path)
    print("Health changed:", newValue, oldValue, path)
end)
```

---

## API

### Server

```lua
local server = ReactiveState.server

local state = server.new(Name: string, Params: {
    Schema: {[string]: boolean | any},
    Data: T? | {}
})
```

Methods:

```lua
state:Batch(callback)
state:Destroy()
```

The server-side object is a proxy, so writes such as `state.Health = 100` are routed through the replica layer.

### Client

```lua
local client = ReactiveState.client

local state = client.OnNew(Name: string)
```

Methods:

```lua
state:OnReady(callback)
state:Get(path: {string})
state:GetChangedSignal(path)
state:GetDescendantsChangedSignal(path)
state:GetArrayInsertedSignal(path)
state:GetArrayRemovedSignal(path)
state:GetArrayChangedSignal(path)
state:GetDictionaryAddedSignal(path)
state:GetDictionaryRemovedSignal(path)
state:GetDictionaryChangedSignal(path)
```

---

## How It Works

ReactiveState uses Replica as the replication transport. On the server, updates are written to a proxy-backed state object and forwarded to a Replica instance. On the client, the same Replica is observed and mirrored into a local state table. The result is a natural table-like API that still stays synced across the network.

---

## Limitations

- Best suited for small-to-medium state trees rather than large ECS-style worlds
- Server writes are validated against the provided schema
- The client view is a snapshot of the currently replicated state and updates through change signals
- The package assumes you are already using or are willing to use Replica as the transport layer
