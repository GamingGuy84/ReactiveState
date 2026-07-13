type client = typeof(require(script.client))
type server = typeof(require(script.server))

return setmetatable({}, {
    __index = function(_, key)
        if key == "client" then
            return require(script.client)
        elseif key == "server" then
            return require(script.server)
        end

        return nil
    end
}) :: {
    client: client,
    server: server
}