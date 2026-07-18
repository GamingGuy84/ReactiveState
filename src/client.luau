local LemonSignal = require(script.Parent.Parent.lemonsignal)
local Replica = require(script.Parent.Parent.replica)

type Signal = typeof(LemonSignal.new())

export type Public = {
    GetDictionaryAddedSignal: (Public: Public, Path:{string}) -> Signal,
    GetDictionaryRemovedSignal: (Public: Public, Path:{string}) -> Signal,
    GetDictionaryChangedSignal: (Public: Public, Path:{string}) -> Signal,
    GetArrayInsertedSignal: (Public: Public, Path: {string}) -> Signal,
    GetArrayRemovedSignal: (Public: Public, Path: {string}) -> Signal,
    GetArrayChangedSignal: (Public: Public, Path: {string}) -> Signal,
    GetChangedSignal: (Public: Public, Path:{string}) -> Signal,
    GetDescendantsChangedSignal: (Public: Public, Path: {string}) -> Signal,

    OnReady: (Public: Public, Callback: () -> ()) -> nil,
    Get: (Public: Public, Path: {string}) -> any
}

export type State<T> = {
    Signals: {
        Changed: {[{string}]: Signal},
        DescendantsChanged: {[{string}]: Signal},
        ArrayInserted: {[{string}]: Signal},
        ArrayRemoved: {[{string}]: Signal},
        ArrayChanged: {[{string}]: Signal},
        DictionaryAdded: {[{string}]: Signal},
        DictionaryRemoved: {[{string}]: Signal},
        DictionaryChanged: {[{string}]: Signal}
    },

    OnReadyCallbacks: {() -> ()}
}

local ReactiveState = {}
local Methods = {}
Methods.__index = Methods

local Private = setmetatable({}, {__mode = "k"})

----------------------------------------------
-- Helpers
----------------------------------------------

local function GetPath(Path: {string}) : string
    return table.concat(Path, ".")
end


local function GetParentPath(Path: {string})
    local Parent = {}

    for i = 1, #Path - 1 do
        Parent[i] = Path[i]
    end

    return Parent
end


local function HandleSignal(signalHolder, path)
    local stringPath = GetPath(path)

    if signalHolder[stringPath] then
        return signalHolder[stringPath]
    end

    signalHolder[stringPath] = LemonSignal.new()

    return signalHolder[stringPath]
end

local function DiffArray(newArray, oldArray)
    local changes = {}

    local maxLength = math.max(#newArray, #oldArray)

    for index = 1, maxLength do
        
        local newValue = newArray[index]
        local oldValue = oldArray[index]

        if oldValue == nil and newValue ~= nil then
            
            table.insert(changes, {
                Type = "Inserted",
                Index = index,
                Value = newValue
            })

        elseif oldValue ~= nil and newValue == nil then
            
            table.insert(changes, {
                Type = "Removed",
                Index = index,
                OldValue = oldValue
            })

        elseif newValue ~= oldValue then
            
            table.insert(changes, {
                Type = "Changed",
                Index = index,
                Value = newValue,
                OldValue = oldValue
            })
        end
    end

    return changes
end

local function DiffDictionary(newDict, oldDict)

    local changes = {}

    -- Added or changed
    for key, newValue in pairs(newDict) do
        
        local oldValue = oldDict[key]

        if oldValue == nil then
            
            table.insert(changes, {
                Type = "Added",
                Key = key,
                Value = newValue
            })
            
        elseif oldValue ~= newValue then
            
            table.insert(changes, {
                Type = "Changed",
                Key = key,
                Value = newValue,
                OldValue = oldValue
            })
        end
    end


    -- Removed
    for key, oldValue in pairs(oldDict) do
        
        if newDict[key] == nil then
            
            table.insert(changes, {
                Type = "Removed",
                Key = key,
                OldValue = oldValue
            })
        end
    end


    return changes
end

local function getPrivateState<T>(state: Public) : State<T>
    return Private[state]
end

----------------------------------------------
-- Private Methods
----------------------------------------------

function Methods:_FireSignals(path, newValue, oldValue)

    local private = getPrivateState(self)

    if not private then
        warn("No private state can be found")
        return
    end


    local signals = private.Signals
    local stringPath = GetPath(path)



    ------------------------------------
    -- Exact value changed
    ------------------------------------

    local changedSignal = signals.Changed[stringPath]

    if changedSignal then
        changedSignal:Fire(
            newValue,
            oldValue,
            path
        )
    end



    ------------------------------------
    -- Descendants changed
    ------------------------------------

    

    local current = ""

    for _, part in ipairs(path) do
        
        current = current == ""
            and tostring(part)
            or current .. "." .. tostring(part)


        local signal = signals.DescendantsChanged[current]

        if signal then
            signal:Fire(
                newValue,
                oldValue,
                path
            )
        end
    end



    ------------------------------------
    -- Whole array replaced
    ------------------------------------

    local arraySignal = signals.ArrayChanged[stringPath]

    if arraySignal then
        
        arraySignal:Fire(
            newValue,
            oldValue,
            path
        )
    end


    ------------------------------------
    -- Dictionary diff
    ------------------------------------

    local parentPath = GetParentPath(path)

    if #parentPath > 0 then

        local parentNew = self:Get(parentPath)

        if type(parentNew) == "table" and type(oldValue) ~= "table" then
            
            local parentOld = table.clone(parentNew)
            parentOld[path[#path]] = oldValue

            local changes = DiffDictionary(parentNew, parentOld)

            for _, change in ipairs(changes) do
                
                local signalPath = GetPath(parentPath)

                if change.Type == "Added" then
                    
                    local signal = signals.DictionaryAdded[signalPath]

                    if signal then
                        local fullPath = table.clone(parentPath)
                        table.insert(fullPath, change.Key)
                        
                        signal:Fire(
                            fullPath,
                            change.Value
                        )
                    end

                elseif change.Type == "Removed" then
                    
                    local signal = signals.DictionaryRemoved[signalPath]

                    if signal then
                        signal:Fire(
                            change.Key,
                            change.OldValue,
                            parentPath
                        )
                    end

                elseif change.Type == "Changed" then
                    
                    local signal = signals.DictionaryChanged[signalPath]

                    if signal then
                        signal:Fire(
                            change.Key,
                            change.Value,
                            change.OldValue,
                            parentPath
                        )
                    end
                end
            end
        end
    end

    ------------------------------------
    -- Array diff
    ------------------------------------
    if type(newValue) == "table" and type(oldValue) == "table" then
        
        local changes = DiffArray(
            newValue,
            oldValue
        )


        for _, change in ipairs(changes) do

            if change.Type == "Inserted" then
                
                local signal =
                    signals.ArrayInserted[stringPath]


                if signal then
                    signal:Fire(
                        change.Index,
                        change.Value,
                        path
                    )
                end



            elseif change.Type == "Removed" then
                
                local signal =
                    signals.ArrayRemoved[stringPath]


                if signal then
                    signal:Fire(
                        change.Index,
                        change.OldValue,
                        path
                    )
                end



            elseif change.Type == "Changed" then
                
                local signal =
                    signals.ArrayChanged[stringPath]


                if signal then
                    signal:Fire(
                        change.Index,
                        change.Value,
                        change.OldValue,
                        path
                    )
                end
            end
        end
    end



    ------------------------------------
    -- Nested array element changed
    ------------------------------------

    if #parentPath > 0 then
        
        local parentString = GetPath(parentPath)

        local parentArraySignal =
            signals.ArrayChanged[parentString]


        local index = path[#path - 1]


        if parentArraySignal and typeof(index) == "number" then
            
            parentArraySignal:Fire(
                index,
                newValue,
                oldValue,
                path
            )
        end
    end
end

function Methods:_UpdatePath(path, newValue, oldValue, dontFireSignal: boolean?)
    if typeof(path) ~= "table" then
        return
    end

    local current = self

    for i = 1, #path - 1 do
        current = current[path[i]]
    end

    current[path[#path]] = newValue

    if dontFireSignal then return end

    self:_FireSignals(path, newValue, oldValue)
end

----------------------------------------------
-- Public Methods
----------------------------------------------

function Methods.GetChangedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.Changed, path)
end

function Methods.GetDescendantsChangedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.DescendantsChanged, path)
end

function Methods.GetArrayInsertedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.ArrayInserted, path)
end

function Methods.GetArrayRemovedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.ArrayRemoved, path)
end

function Methods.GetArrayChangedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.ArrayChanged, path)
end

function Methods.GetDictionaryAddedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.DictionaryAdded, path)
end

function Methods.GetDictionaryRemovedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.DictionaryRemoved, path)
end

function Methods.GetDictionaryChangedSignal<T>(self: Public, path)
    local private = getPrivateState(self)
    return HandleSignal(private.Signals.DictionaryChanged, path)
end

function Methods.OnReady(self: Public, Callback: () -> ())
    local private = getPrivateState(self)
    table.insert(private.OnReadyCallbacks, Callback)
end

function Methods.Get(self: Public, path: {string})
    local current = self
    
    for i = 1, #path - 1 do
        current = current[path[i]]
    end
    
    return current[path[#path]]
end

----------------------------------------------
-- Constructor
----------------------------------------------

function ReactiveState.OnNew<T>(Name: string) : T & Public
    ------------------------
    -- State Initialization
    ------------------------

    local State = {}
    
    Private[State] = {
        Signals = {
            Changed = {},
            DescendantsChanged = {},
        
            ArrayInserted = {},
            ArrayRemoved = {},
            ArrayChanged = {},
        
            DictionaryAdded = {},
            DictionaryRemoved = {},
            DictionaryChanged = {},
        },

        OnReadyCallbacks = {

        }
    }

    -- fallback onto Methods
    setmetatable(State, Methods)

    ------------------------
    -- Replica Initialization
    ------------------------
    Replica.OnNew(Name, function(replica)
        replica:OnChange(function(_, path, newValue, oldValue)
            State:_UpdatePath(path, newValue, oldValue)
        end)
    
        table.clear(State)
        
        for k, v in pairs(replica.Data) do
            State:_UpdatePath({k}, v, nil, true)
        end

        local readyCallbacks = Private[State].OnReadyCallbacks

        for _, callback in ipairs(readyCallbacks or {}) do 
            callback()
        end
    end)        

    return State :: T & Public
end

Replica.RequestData()

return ReactiveState