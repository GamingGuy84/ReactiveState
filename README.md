# ReactiveState

ReactiveState is a lightweight Luau state layer for Roblox that sits on top of Replica. It gives you a simple, proxy-based state tree on the server and a mirrored, event-driven view on the client.

The module is split into two entry points:

- `ReactiveState.client` for listening to replica-backed state changes
- `ReactiveState.server` for creating and updating server-owned state

## How it works

ReactiveState uses Replica as the transport and replication mechanism.

- On the server, `ReactiveState.server.new(...)` creates a Replica-backed state object, exposes a proxy for writing data, and replicates updates to connected clients.
- On the client, `ReactiveState.client.OnNew(...)` subscribes to a Replica by name and mirrors the current data into a local state object.

In other words, ReactiveState does not replace Replica; it provides a convenient reactive wrapper around it.

## Client API

The client module is exposed through `require(...).client`.

### `OnNew(Name: string)`

Creates a local reactive state view for a Replica with the given name.

```lua
local ReactiveState = require(path.to.ReactiveState)
local client = ReactiveState.client

local data, signals = client.OnNew("MyState")

print(data.SomeKey)

signals.OnAdded:Connect(function(value)
    print("Added:", value)
end)

signals.OnUpdated:Connect(function(path, newValue)
    print("Updated:", path, newValue)
end)

signals.OnDestroyed:Connect(function(value)
    print("Destroyed:", value)
end)
```

### Client types

```lua
export type State = {
    Data: {[string | any]: any},

    Signals: Signals,
}

export type Signals = {
    OnAdded: lemonsignal.Signal<any>,
    OnDestroyed: lemonsignal.Signal<any>,
    OnUpdated: lemonsignal.Signal<{string | any}, any>,
}
```

### Client behavior

- `Data` is the current mirrored state tree.
- `Signals.OnAdded` fires when a new table-based value is introduced.
- `Signals.OnUpdated` fires when an existing value changes.
- `Signals.OnDestroyed` fires when a table-based value is removed.

## Server API

The server module is exposed through `require(...).server`.

### `new(Name: string, Params)`

Creates a new server-managed state object and returns a proxy that can be used like a normal table.

```lua
local ReactiveState = require(path.to.ReactiveState)
local server = ReactiveState.server

local state = server.new("MyState", {
    Schema = {
        Player = true,
        Health = true,
    },
    Data = {
        Player = {
            Name = "Alice",
            Health = 100,
        },
    },
})

state.Player.Health = 90

state:Batch(function()
    state.Player.Health = 80
    state.Player.Name = "Bob"
end)

state:Destroy()
```

### Server methods

- `state:Batch(callback)`
  - Buffers writes and applies them together.
  - Useful for making a sequence of edits appear as one update.

- `state:Destroy()`
  - Tears down the server state and destroys its underlying Replica.

### Server types

```lua
export type Public = {
    Destroy: (self: State) -> nil,
    Batch: (self: State, batchedUpdate: () -> ()) -> nil,
}

export type State = {
    Data: {[string | any]: any},

    MetaData: {
        Name: string,
        Replica: any,
        _Schema: {
            [string]: boolean | any,
        },
        CompiledSchema: {
            [string]: boolean | any,
        },
        Batching: boolean,

        PendingUpdates: {},
        PendingCursor: number,
    },
} & Public
```

### Server behavior

- Writes are validated against the provided schema.
- Nested table values are turned into proxy-friendly shapes.
- Updates are sent through the underlying Replica instance.
- The returned object is a proxy, so reading and assigning values feels natural while still routing updates through the replica layer.

## Notes

- ReactiveState is designed for small-to-medium reactive state trees rather than full ECS-style systems.
- The server API should be used when you want authoritative state changes.
- The client API should be used when you want a local, reactive view of shared state.
