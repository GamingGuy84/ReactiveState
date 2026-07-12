local lemonsignal = require(script.Parent.lemonsignal)
local Replica = require(script.Parent.replica)

export type State = {
    Data: {[string | any]: any},
    
    Signals: Signals
}

export type Signals = {
    OnAdded: lemonsignal.Signal<any>,
    OnDestroyed: lemonsignal.Signal<any>,
    OnUpdated: lemonsignal.Signal<{string | any}, any>,
}

local NetworkingService = {}
local Methods = {}
Methods.__index = Methods

----------------------------------------------
-- Helpers
----------------------------------------------

----------------------------------------------
-- Methods
----------------------------------------------

function Methods._UpdatePath(self: State, path: {}, v: any)
    if not v then return end
    if typeof(path) ~= "table" then 
        return
    end

    local current = self.Data
    
    for i = 1, #path - 1 do
        current = current[path[i]]
    end
    
    current[path[#path]] = v
end

----------------------------------------------
-- Constructor
----------------------------------------------

function NetworkingService.OnNew(Name: string)

    ------------------------
    -- State Initialization
    ------------------------
    
    local State = {
        Data = {

        },

        Signals = {
            OnAdded = lemonsignal.new(),
            OnUpdated = lemonsignal.new(),
            OnDestroyed = lemonsignal.new(),
        }
    }
    
    setmetatable(State, Methods)

    ------------------------
    -- Replica Initialization
    ------------------------

    Replica.OnNew(Name, function(replica)
        local function createData(path, newValue, oldValue)
            State.Signals.OnAdded:Fire(newValue)
            State:_UpdatePath(path, newValue)
        end
    
        local function destroyData(path, newValue, oldValue)
            State.Signals.OnDestroyed:Fire(newValue)
            State:_UpdatePath(path, newValue)
        end
    
        local function applyUpdate(path, newValue, oldValue)
            State.Signals.OnUpdated:Fire(path, newValue)
            State:_UpdatePath(path, newValue)
        end
    
        replica:OnChange(function(_, path, newValue, oldValue)
            -- added
            if oldValue == nil and type(newValue) == "table" then
                createData(path, newValue, oldValue)
                return
            end
    
            -- removed
            if newValue == nil and type(oldValue) == "table" then
                destroyData(path, newValue, oldValue)
                return
            end
    
            -- changed
            applyUpdate(path, newValue, oldValue)
        end)
    
        table.clear(State.Data)
        
        for k, v in pairs(replica.Data) do
            State.Data[k] = v
        end

        for path, value in pairs(replica.Data or {}) do
            createData(path, value)
        end
    end)

    return State.Data, State.Signals :: Signals
end

Replica.RequestData()

return NetworkingService