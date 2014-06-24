
local Mod = {}

Mod.lastInterface = nil
Mod.errorPrefix = "___ERRORPC: "
Mod.createdServants = {}
Mod.socket = require "socket"

-- Validates a table as an acceptable interface for this library, returns interface if it's ok or nil otherwise
function Mod.ValidateInterface (interfaceObj)
	local a = interfaceObj
	
	if type(a) ~= "table" or not a.methods or type(a.methods) ~= "table" then
		return  nil
	end
	for i, v in pairs (a.methods) do
		if not v.resulttype or type(v.resulttype)~="string" then
			return nil
		elseif v.resulttype~="void" and v.resulttype~="double" and v.resulttype~="char" and v.resulttype~="string" then
			return nil
		end

		if not v.args or type(v.args)~="table" then 
			return nil
		end

		local noInArg, noOutArg, noInOutArg = 0, 0, 0

		for i2, v2 in ipairs (v.args) do
			if type(v2)~="table" or not v2.direction or type(v2.direction)~="string" or not v2.type or type(v2.type)~="string" then
				return nil
			elseif v2.direction~="in" and v2.direction~="out" and v2.direction~="inout" then
				return nil
			elseif v2.type~="double" and v2.type~="char" and v2.type~="string" then
				return nil
			end

			if v2.direction == "in" then
				noInArg = noInArg + 1
			elseif v2.direction == "out" then
				noOutArg = noOutArg + 1
			else
				noInOutArg = noInOutArg + 1
			end
		end

		v.noInArg = noInArg
		v.noOutArg = noOutArg
		v.noInOutArg = noInOutArg
	end
	return a
end

-- Keeps a reference to the last validated interface (or nil)
function interface (a)
	Mod.lastInterface = Mod.ValidateInterface(a)
end

-- Verifies data types, return true if data is consistent or false otherwise
-- methodName: name of the method
-- interface: interface object
-- data: table of data to be verified
-- direction: "in" if data are arguments or "out" if data are returns
-- Note: it also calculates missing arguments/returns
-- Note (2): it also delete extra arguments/returns from data
function Mod.VerifyData(methodName, interface, data, direction)
	-- checks whether direction is correctly given
	local inDir, outDir = false, false
	if direction=="in" then
		inDir = true
	elseif direction=="out" then
		outDir = true
	else
		return nil
	end

	interfaceArgs = interface.methods[methodName].args
	local noData = 1

	if outDir then
		-- check if there wasn't an execution error
		if type(data[noData])~="boolean" then
			return false
		end
		if not data[noData] then
			if type(data[noData+1])~="string" or data.n~=2 then
				return false
			else
				return true
			end
		end

		-- there was no error, first result should match the resulttype in interface
		noData = noData + 1
		if not Mod.validateType(interface.methods[methodName].resulttype, type(data[noData])) then
			return false
		end
		noData = noData + 1
	end

	-- if data are arguments, verify all arguments "in" and "inout"
	-- if data are returns, verify all remaining returns
	for i, v in ipairs (interfaceArgs) do
		if (v.direction~="in" and outDir or v.direction~="out" and inDir) then
			if not (noData > #data) then
				if not Mod.validateType(v.type, type(data[noData])) then
					return false
				end
			end
			noData = noData + 1
		end
	end

	-- calculate missing arguments
	local noDataArgs = interface.methods[methodName].noInOutArg
	if inDir then
		noDataArgs = noDataArgs + interface.methods[methodName].noInArg 
	else
		noDataArgs = noDataArgs + interface.methods[methodName].noOutArg + 2
	end

	data.null = noDataArgs - #data

	-- delete extra arguments
	local noExtraArg = - data.null

	while (noExtraArg>0) do
		data[noDataArgs+noExtraArg] = nil
		noExtraArg = noExtraArg - 1
	end
	return true
end

-- Validates types, return true if type1 is equivalent to type2
-- Ex: in Lua, type of 5 is "number", but in the interface of this library, it's "double"
function Mod.validateType( type1 , type2 )
	if type1=="nil" or type2=="nil" then
		return true
	elseif type1=="double" and type2=="number" or type1=="number" and type2=="double" then
		return true
	elseif type1=="string" and type2=="char" or type1=="char" and type2=="string" then
		return true
	else
		return type1==type2
	end
end

function Mod.createStringMessage(str, errorString)
	local strMsg = string.gsub(str, '\\', '\\\\')
	strMsg = string.gsub(strMsg, '\"', '\\\"')
	strMsg = string.gsub(strMsg, '\n', '\\n')
	if not errorString then
		strMsg = '\"' .. strMsg .. '\"'
	end
	return strMsg .. "\n"
end

function Mod.retrieveString(strMsg, errorString)
	local str = ""
	if not errorString then
		str = string.sub(strMsg, 2, -2)
	else
		str = strMsg
	end
	str = string.gsub(str, '\\\\', '\\')
	str = string.gsub(str, '\\\"', '\"')
	str = string.gsub(str, '\\n', '\n')
	return str
end

-- Creates a message assuming there are no extra or missing arguments/returns
function Mod.createMessage(methodName, t)
	-- t is a table with arguments or results
	local msg = ""
	if methodName then
		msg = msg .. methodName .. "\n"
	end
	if t[1]==false then
		local errorString = Mod.errorPrefix .. t[2]
		msg = Mod.createStringMessage(errorString, true)
		return msg
	end
	for i, v in pairs (t) do
		if i~="n" and i~="null" then
			if (type(v)=="string") then
				msg = msg .. Mod.createStringMessage(v, false)
			elseif type(v)=="number" then
				msg = msg .. v .. "\n"
			elseif type(v)=="nil" then
				msg = msg .. "nil\n"
			end
		end
	end
	local i = 0
	if (t.null) then
		while (i<t.null) do
			msg = msg .. "nil\n"
			i = i + 1
		end
	end
	return msg
end

-- Actually makes rpc call
function Mod.rpcCall (proxy, methodName, args)
	local ip = proxy.ip
	local port = proxy.port
	local interface = proxy.interface
	-- Verify Arguments
	local argsOk = Mod.VerifyData(methodName, interface, args, "in")
	if not argsOk then
		print ( Mod.errorPrefix .. "Tentativa de chamar " .. methodName .. " com argumentos inválidos.\n" )
		return nil
	end
	local results = {}
	--Create connection
	
	local connection = nil

	-- Check if connection was created once:
	if not proxy.isConnected then 
		proxy.connection = assert(Mod.socket.connect(ip, port))
		proxy.isConnected = true
		--print("Created connection " .. ip .. ":" .. port)
		proxy.connection:setoption("tcp-nodelay", true)
	end
	connection = proxy.connection

	if connection then
		--Serialize message
		local msg = Mod.createMessage(methodName,args)

		-- TODO : verificar com a erica se pode tirar esse getsocketname
		local gIp,gPort
		local trySend  = function () local bytes, _ = connection:send(msg) 
									 gIp,gPort = connection:getsockname()
									 return bytes
						 end
	
		while not trySend() do
			proxy.connection = assert(Mod.socket.connect(ip, port))
			proxy.connection:setoption("tcp-nodelay", true)
			connection = proxy.connection
		end

			
		--Receive message
		local resultsStrings = Mod.retrieveDataStrings(connection, methodName, interface, "out")
		if resultsStrings then
			results = Mod.retrieveData(resultsStrings, methodName, interface, "out") 
		else

		end
	
	else
		--Couldn't connect, what to do?
	end
	return table.unpack(results)
end

-- Receives a certain number of messages from connection, according to direction
-- direction is "in" if arguments are expected, direction is "out" if returns are expected
function Mod.retrieveDataStrings(connection, methodName, interfaceObj, direction)
	local noData = 0
	if direction == "in" then
		noData = interfaceObj.methods[methodName].noInArg+interfaceObj.methods[methodName].noInOutArg
	elseif direction == "out" then
		noData = interfaceObj.methods[methodName].noOutArg+interfaceObj.methods[methodName].noInOutArg + 1
	else
		return nil
	end

	local i = 0
	local dataString = {}
    while (i<noData) do
      local msg, e = connection:receive()
      if not e then
        table.insert(dataString, msg)
        local byte = string.find(msg, Mod.errorPrefix, 1)
        if byte and byte==1 then
        	break
        end
      else
      --	print "Could not receive message"
      	return nil
      end
      i = i + 1
    end
    return dataString
end

-- Convert strings received by retrieveDataStrings to types expected by interface
function Mod.retrieveData(dataStrings, methodName, interfaceObj, inOut)
	local inDir = false
	local outDir = false
	if inOut == "in" then
		inDir = true
	elseif inOut == "out" then
		outDir = true
	else
		return nil
	end

	local data = {}
	local noData = 1

	if outDir then
		local byte = string.find(dataStrings[1], Mod.errorPrefix, 1)
        if byte and byte==1 then
        	print(Mod.retrieveString(dataStrings[1], true))
        	return data
        end
		local restype = interfaceObj.methods[methodName].resulttype
		if restype == "string" or restype == "char" then
			data[noData] = Mod.retrieveString(dataStrings[noData], false)
		elseif restype == "double" then
			data[noData] = tonumber(dataStrings[noData])
		end
		noData = noData + 1
	end

	for i, v in ipairs (interfaceObj.methods[methodName].args) do
		if (v.direction~="in" and outDir or v.direction~="out" and inDir) then
			if dataStrings[noData] ~= "nil" then
				if v.type == "string" or v.type == "char" then
					data[noData] = Mod.retrieveString(dataStrings[noData], false)
				elseif v.type == "double" then
					data[noData] = tonumber(dataStrings[noData])
				end
			end
			noData = noData + 1
		end
	end

	-- missing data
	data.null = noData - 1 - #data
	return data
end

-- Searches a servant by its ip and port in createdServants
-- Used so that server is able to identify which servant should handle the request
function Mod.searchServant (ip, port)
  for _, v in ipairs(Mod.createdServants) do
  	--print ("Searching servant " .. v.ip .. ":" .. v.port)
    --if (v.ip==ip and v.port==port) then
    if v.port==port then
      return v
    end
  end
end

-- Creates a table that can be used in socket.select
function Mod.newset()
    local reverse = {}
    local set = {}
    return setmetatable(set, {__index = {
        insert = function(set, value)
            if not reverse[value] then
                table.insert(set, value)
                reverse[value] = #set
            end
        end,
        remove = function(set, value)
            local index = reverse[value]
            if index then
                reverse[value] = nil
                local top = table.remove(set)
                if top ~= value then
                    reverse[top] = index
                    set[index] = top
                end
            end
        end
    }})
end

-- Answers the request
function Mod.answerRequest (client, servant, set)
	-- Receive message with method name
	local msg, errorRec = client:receive()
	if not errorRec then
		local answer = ""

		-- Check if method was implemented by servant's object
		local method = servant.object[msg]
		if method then
			--print("Method " .. msg .. " declared")

			-- Receives messages with arguments
			local argsStrings = Mod.retrieveDataStrings(client, msg, servant.interface, "in")
			--print("Arguments " .. table.concat(argsStrings, " "))

			-- Convert arguments (string) received into expected typed values
			local args = Mod.retrieveData(argsStrings, msg, servant.interface, "in")

			-- Make protected call and pack results
			results = table.pack(pcall(method, table.unpack(args)))

			-- Check if results are typed as expected
			resultsOk = Mod.VerifyData(msg, servant.interface, results, "out")
			if resultsOk then
				answer = Mod.createMessage(nil, results)
			else
				answer = Mod.errorPrefix .. "Method \"" .. msg .. "\" returned invalid values.\n"
			end
		else
			-- receive arguments even thought method is not implemented
			Mod.retrieveDataStrings(client, msg, servant.interface, "in")
			answer = Mod.errorPrefix .. "Method \"" .. msg .. "\" not declared in servant.\n"
		end
		--print ("Mensagem de Retorno \n" .. answer .. "Fim mensagem de retorno")

		-- Send answer
		local bytes, errorSend = client:send(answer)
		if not bytes then
			-- couldn't send answer: what to do?
			print "Couldn't send answer"
		end
		--print "--------"
	-- else
	-- 	set:remove(client)
	-- 	local index = nil
	-- 	for i, v in ipairs (activeConnections) do
	-- 		if v == client then
	-- 			index = i
	-- 		end
	-- 	end
	-- 	table.remove(activeConnections, index)
	-- 	print "Couldn\'t handle request"
	end
end

function Mod.activateConnection (connection, servant, set)
	--print "Activating connection "

	if not activeConnections then
		activeConnections = {}
	end
	print (#activeConnections .. " Connected clients")
	local cIp, cPort = connection:getsockname()
	for _, v in ipairs (activeConnections) do
		--print (v:getpeername())
		local vIp, vPort = v:getsockname()
		if cIp == vIp and cPort == vPort then
			print ("Cliente ainda conectado " .. vIp .. ":" .. vPort)
			return connection
		end
	end
	if #activeConnections==3 then
		local removedConnection = table.remove(activeConnections, 1)
		local ip, port = removedConnection:getsockname()
		removedConnection:close()
		print ("Cliente desconectado " .. ip .. ":" .. port)
		set:remove(removedConnection)
	end
	local client = assert(servant.server:accept())
	client:setoption("tcp-nodelay", true)
	print ("Cliente conectado " .. servant.ip .. ":" .. servant.port)
	set:insert(client)
	table.insert(activeConnections, client)
	return client
end

function Mod.createServant (obj, interfaceFile)
	dofile(interfaceFile)
	local interfaceObj = Mod.lastInterface
	if not interfaceObj then
		-- TO DO: throw error
		return nil
	end
	
	local server = assert(Mod.socket.bind("*", 0))
	server:setoption("tcp-nodelay", true)
	local ip, port = server:getsockname()

	local servant = {}
	servant.server = server
	servant.ip = ip
	servant.port = port
	servant.object = obj
	servant.interface = interfaceObj

	table.insert(Mod.createdServants, servant)
	return servant
end

function Mod.createProxy (ip, port, interfaceFile)
	
	dofile(interfaceFile)
	
	local interfaceObj = Mod.lastInterface
	if not interfaceObj then 
		print ( Mod.errorPrefix .. "Interface \"".. interfaceFile .. "\" inválida!")
		return nil 
	end

	local proxy = {}
	proxy.interface = interfaceObj
	proxy.port = port
	proxy.ip = ip
	proxy.isConnected = false -- proxy is NOT Connected

	--metatable
	local mt = {}
	mt.__index = function (t, k)
					local method = proxy.interface.methods[k]
					if not method then
						proxy[k] =  function (...)
										print(Mod.errorPrefix .. "Method \"" .. k .. "\" not found")
									end
						return proxy[k]
					else
						proxy[k] = 	function (...)
										return Mod.rpcCall(proxy, k, table.pack(...))
									end
						return proxy[k]
					end
				end
	setmetatable(proxy, mt)
	return proxy
end

function Mod.waitIncoming ()
	local set = Mod.newset()
	for _, v in ipairs (Mod.createdServants) do
		set:insert(v.server)
	end

	while (true) do
		local socketsToRead = Mod.socket.select(set, nil)
		print (#socketsToRead .. " sockets to read of " .. #set .. " sockets ")
		for i, v in ipairs (socketsToRead) do
			local ip, port = v:getsockname()
			if ip and port then
				print ("Heard from " .. ip .. ":" .. port)
				local servant = Mod.searchServant (ip, port)
				if not servant then
					print ("No servant in " .. ip .. ":" .. port)
					--set:remove(v)
				else
					local client = Mod.activateConnection(v, servant, set)
					--local client = assert(servant.server:accept())
					Mod.answerRequest(client, servant, set)
				end
			end
	  	end	    
	end
end

return Mod