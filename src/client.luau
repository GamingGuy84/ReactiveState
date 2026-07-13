local LemonSignal = require(script.Parent.lemonsignal)
local Replica = require(script.Parent.replica)

type Signal = typeof(LemonSignal.new())

export type Public<T> = (T | {any}) & {
    GetChangedSignal: ({string}) -> Signal,
    GetDescendantsChangedSignal: ({string}) -> Signal,
    GetArrayInsertedSignal: ({string}) -> Signal,
    GetArrayRemovedSignal: ({string}) -> Signal,
    GetArrayChangedSignal: ({string}) -> Signal,
}

export type State<T> = {
    Data: T,

    GetChangedSignal: ({string}) -> Signal,
    GetDescendantsChangedSignal: ({string}) -> Signal,
    GetArrayInsertedSignal: ({string}) -> Signal,
    GetArrayRemovedSignal: ({string}) -> Signal,
    GetArrayChangedSignal: ({string}) -> Signal,

    MetaData: {
        Signals: {
            Changed: {[{string}]: Signal},
            DescendantsChanged: {[{string}]: Signal},
            ArrayInserted: {[{string}]: Signal},
            ArrayRemoved: {[{string}]: Signal},
            ArrayChanged: {[{string}]: Signal},
        }
    },
}

local ReactiveState = {}
local Methods = {}
Methods.__index = Methods

----------------------------------------------
-- Helpers
----------------------------------------------

local function HandleSignal(signalHolder, path)
    if signalHolder[path] then
        return signalHolder[path]
    end

    signalHolder[path] = LemonSignal.new()
    return signalHolder[path]
end

----------------------------------------------
-- Private Methods
----------------------------------------------

function Methods:_FireSignals(action, path, newValue, oldValue)
    local signals = self.MetaData.Signals

    -- Exact path changed
    local changed = signals.Changed[path]
    if changed then
        changed:Fire(newValue, oldValue)
    end

    -- Every ancestor's DescendantsChanged
    for i = 1, #path do
        local ancestor = table.create(i)

        for j = 1, i do
            ancestor[j] = path[j]
        end

        local signal = signals.DescendantsChanged[ancestor]

        if signal then
            signal:Fire(path, newValue, oldValue)
        end
    end

    -- Array signals
    if action == "TableInsert" then
        local signal = signals.ArrayInserted[path]

        if signal then
            signal:Fire(newValue, #self.Data)
        end

    elseif action == "TableRemove" then
        local signal = signals.ArrayRemoved[path]

        if signal then
            signal:Fire(oldValue)
        end

    elseif action == "Set" or action == "SetValues" then
        local signal = signals.ArrayChanged[path]

        if signal then
            signal:Fire(newValue, oldValue)
        end
    end
end

function Methods:_UpdatePath(action, path, newValue, oldValue, dontFireSignal: boolean?)
    if typeof(path) ~= "table" then
        return
    end

    local current = self.Data

    for i = 1, #path - 1 do
        current = current[path[i]]
    end

    current[path[#path]] = newValue

    if dontFireSignal then return end

    self:_FireSignals(action, path, newValue, oldValue)
end

----------------------------------------------
-- Public Methods
----------------------------------------------

function Methods.GetChangedSignal<T>(self: State<T>, path)
    return HandleSignal(self.MetaData.Signals.Changed, path)
end

function Methods.GetDescendantsChangedSignal<T>(self: State<T>, path)
    return HandleSignal(self.MetaData.Signals.DescendantsChanged, path)
end

function Methods.GetArrayInsertedSignal<T>(self: State<T>, path)
    return HandleSignal(self.MetaData.Signals.ArrayInserted, path)
end

function Methods.GetArrayRemovedSignal<T>(self: State<T>, path)
    return HandleSignal(self.MetaData.Signals.ArrayRemoved, path)
end

function Methods.GetArrayChangedSignal<T>(self: State<T>, path)
    return HandleSignal(self.MetaData.Signals.ArrayChanged, path)
end

----------------------------------------------
-- Constructor
----------------------------------------------

function ReactiveState.OnNew<T>(Name: string) : Public<T>
    ------------------------
    -- State Initialization
    ------------------------
    
    local State = {
        Data = {

        },

        MetaData = {
            Signals = {
                Changed = {},
                DescendantsChanged = {},
                ArrayInserted = {},
                ArrayRemoved = {},
                ArrayChanged = {},
            }
        }
    }

    -- fallback onto Methods
    setmetatable(State.Data, Methods)

    ------------------------
    -- Replica Initialization
    ------------------------

    Replica.OnNew(Name, function(replica)
        replica:OnChange(function(action, path, newValue, oldValue)
            State:_UpdatePath(action, path, newValue, oldValue)
        end)
    
        table.clear(State.Data)
        
        for k, v in pairs(replica.Data) do
            State.Data[k] = v
        end

        for path, value in pairs(replica.Data or {}) do
            State:_UpdatePath(nil, path, value, nil, true)
        end
    end)

    return State.Data
end

Replica.RequestData()

return ReactiveState