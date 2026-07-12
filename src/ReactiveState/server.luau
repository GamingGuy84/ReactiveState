local Replica = require(script.Parent.replica)

export type Public = {
	Destroy: (self: State) -> nil,
	Batch: (self: State, batchedUpdate: () -> ()) -> nil
}

export type State = {
	Data: {[string | any]: any},
	
	MetaData: {
		Name: string,
		Replica: any,
		_Schema: {
			[string]: boolean | any
		},
		CompiledSchema: {
			[string]: boolean | any
		},
		Batching: boolean,
		
		PendingUpdates: {},
		PendingCursor: number,
	},
} & Public

local ReactiveState = {}
local Methods = {}
Methods.__index = Methods

----------------------------------------------
-- General Helpers
----------------------------------------------

local function isValid(State: State, path: {string})
    local rule = State.MetaData._Schema

    for i = 1, #path do
        if type(rule) ~= "table" then
            return false
        end

        rule = rule[path[i]] or rule.all

        if rule == nil then
            return false
        end
    end

    return rule == true or type(rule) == "table"
end

local function CreateShape(data, schema)
	local result = {}

	for key, value in schema do
		if type(value) == "table" then
			result[key] = CreateShape(data[key] or {}, value)
		else
			result[key] = data[key]
		end
	end

	return result
end

----------------------------------------------
-- Writing Helpers
----------------------------------------------

local function Update(State: State, path, value)
	if not isValid(State, path, value) then return end
	
	local length = #path
	if not length or length == 0 then 
		return
	end

	local current = State.Data 
	for i = 1, length - 1 do 
		current = current[path[i]] 
	end 
	
	current[path[length]] = value

	State.MetaData.Replica:Set(path, value)
end

-- Catches all writes (from batching and individual)
local function UpdatePath(State: State, path, value)
	local metaData = State.MetaData

	if metaData.Batching then
		local count = metaData.PendingCursor + 1
		
		-- packed arrays for performance
		metaData.PendingUpdates[count] = path
		metaData.PendingUpdates[count + 1] = value
		metaData.PendingCursor = count
	else
		Update(State, path, value)
	end
end

----------------------------------------------
-- Proxy Helpers
----------------------------------------------

local ProxyCache = setmetatable({}, {
	__mode = "k"
})

local function CreateProxy(State, target, path, depth, currentKey)
    depth = depth or 0

    if currentKey ~= nil then
        path[depth + 1] = currentKey
        depth += 1
    end

    local cache = ProxyCache[target]
    if not cache then
        cache = {}
        ProxyCache[target] = cache
    end

    local node = cache
    for i = 1, depth do
        local key = path[i]

        local nextNode = node[key]
        if not nextNode then
            nextNode = {}
            node[key] = nextNode
        end

        node = nextNode
    end

    if node.__proxy then
        return node.__proxy
    end

    local proxy = {}
    node.__proxy = proxy

    setmetatable(proxy, {
        __index = function(_, k)
            local value = target[k]

            if type(value) == "table" then
                return CreateProxy(
                    State,
                    value,
                    path,
                    depth,
                    k
                )
            end

            if value ~= nil then
                return value
            end

            return State[k]
        end,

        __newindex = function(_, k, value)
            target[k] = value
            UpdatePath(State, target, k, value)
        end
    })

    return proxy
end

----------------------------------------------
-- Public API
----------------------------------------------

function Methods.Batch(self: State, callback)
	local metaData = self.MetaData

	metaData.Batching = true

	local success, err = xpcall(callback, debug.traceback)

	metaData.Batching = false

	-- Better error handling at the cost of performance (minor)
	if not success then
		metaData.PendingCursor = 0
		table.clear(metaData.PendingUpdates)

		error(err, 0)
	end

	local pending = metaData.PendingUpdates
	local count = metaData.PendingCursor
	
	for i = 1, count, 2 do
		Update(self, pending[i], pending[i + 1])
	end

	table.clear(pending)
	metaData.PendingCursor = 0
end

function Methods.Destroy(self: State)
	local metaData = self.MetaData

	if metaData.Destroyed then
		return
	end

	metaData.Destroyed = true
	metaData.Batching = false

	table.clear(metaData.PendingUpdates)
	metaData.PendingCursor = 0

	if metaData.Replica then
		metaData.Replica:Destroy()
		metaData.Replica = nil
	end

	metaData._Schema = nil
	self.Data = nil
end

----------------------------------------------
-- Constructor
----------------------------------------------

function ReactiveState.new(Name: string, Params: {Schema: {[string]: boolean}, Data: {[any]: any}?}) : Public
	local Data = Params.Data or {}
	local Schema = Params.Schema or {}

	Data = CreateShape(Data, Schema)

    ------------------------
    -- Replica Initialization
    ------------------------

	local token = Replica.Token(Name)
	local replica = Replica.New({
		Data = Data,
		Token = token
	})

    ------------------------
    -- State Initialization
    ------------------------

	local State = {
		Data = Data,

		MetaData = {
			Name = Name,
			Replica = replica,
			_Schema = Schema,
			Batching = false,
			PendingCursor = 0,
			PendingUpdates = {},
			BatchPendingPaths = {},
			BatchPendingKeys = {},
		}
	}

    setmetatable(State, Methods)

    ------------------------
    -- Proxy Initialization
    ------------------------

    local proxy = CreateProxy(State, State.Data, {})

	replica:Replicate()

    return proxy
end

return ReactiveState