local Replica = require(script.Parent.Parent.replica)

export type Public<T> = {
	Destroy: (self: State<T>) -> nil,
	Batch: (self: State<T>, batchedUpdate: () -> ()) -> nil
}

export type State<T> = {
	Data: T,
	
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
} & Public<T>

local ReactiveState = {}
local Methods = {}
Methods.__index = Methods

----------------------------------------------
-- General Helpers
----------------------------------------------

local function isValid<T>(State: State<T>, path: {string})
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

	return rule == true or rule == "all" or type(rule) == "table"
end

local function CreateShape(data, schema)
	local result = {}

	for key, value in schema do
		if key == "all" then
			continue
		end

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

local function Update<T>(State, path, value)
	if not isValid(State, path) then return end

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
local function UpdatePath(State, path, value)
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
	depth = depth or #path

	local newPath = path

	if currentKey ~= nil then
		newPath = table.clone(path)
		newPath[#newPath + 1] = currentKey
	end

	local cache = ProxyCache[target]
	if not cache then
		cache = {}
		ProxyCache[target] = cache
	end

	local node = cache
	for i = 1, #newPath do
		local key = newPath[i]

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
					newPath,
					#newPath,
					k
				)
			end
		
			if value ~= nil then
				return value
			end
		
			return State[k]
		end,
	
		__newindex = function(_, k, value)
			local updatePath = table.clone(newPath)
			updatePath[#updatePath + 1] = k

			UpdatePath(State, updatePath, value)
		end
	})

	return proxy
end

----------------------------------------------
-- Public API
----------------------------------------------

function Methods.Batch<T>(self: State<T>, callback)
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

function Methods.Destroy<T>(self: State<T>)
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

function ReactiveState.new<T>(Name: string, Params: {Schema: {[string]: boolean}, Data: T? | {}}) : T & Public<T>
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