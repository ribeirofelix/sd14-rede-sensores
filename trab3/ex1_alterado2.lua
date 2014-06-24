local tossam = require("tossam") 
local rpc = require "luarpc2" 


-- declarations

serverObj = {} 

local exit = false

local newRequestNumber = 12

local msgRegister = [[ 
		  nx_struct msg_serial [151] { 
			nx_uint8_t id;
			nx_uint16_t source;
			nx_uint16_t target;	
			nx_uint8_t  d8[4]; 
			nx_uint16_t d16[4];
			nx_uint32_t d32[2];
		  }; 
		]]

local deltaTimeRequest = 5

local msgBuffer = {}


-- Helper functions to the server

-- Publish the ip/port of the interface in the deploy file
function publishContact( serv , interface)
      local text = io.open("deploy", "r" ):read("*a")
      local result = "" 
      local firstOfInterface = true
      
      --print(text)
      if text ~= "" then

        for line in string.gmatch(text,'[^\r\n]+') do
          print(line)
          if(line == interface) then -- there's ip/port deployed to this interface
            firstOfInterface = false
            result = result  .. interface .. "\n" ..  serv.ip .. " " .. serv.port .. "\n"
          else
            result = result  .. line .. "\n"
          end
        end
        if firstOfInterface then
          result = result  .. interface .. "\n" ..  serv.ip .. " " .. serv.port .. "\n"
        end
      else 
        result =   interface .. "\n" .. serv.ip .. " " .. serv.port .. "\n"
      end

      file = io.open("deploy","w")

      file:write(result)
      file:close()
end


-- serialize a table
function serialize( o )
	local srl 
	if type(o) == "number" then
		srl = o
	elseif type(o) == "string" then
		srl = string.format("%q",o)
	elseif type(o) == "table" then
		srl = "{\n"
		for k,v in pairs(o) do
			srl = srl ..  " [" .. k .. "] = "
			srl = srl .. serialize(v)
			srl = srl .. ",\n"
		end
		srl = srl .. "}\n"
	else
		error("Cannot serialize a" .. type(o))
	end
	return srl
end

function printMessage (msg)
	print("------------------------------") 
	print("msgID: "..msg.id, "Source: ".. msg.source, "Target: ".. msg.target) 
	print("d8:",unpack(msg.d8))
	print("d16:",unpack(msg.d16))
	print("d32:",unpack(msg.d32))
	return serialize(msg)
end


function createNewRequestMessage ()
	local msg = {
			id		= newRequestNumber,
			source	= 0,
			target	= 1,
			d8		= {2, 0, 0, 0},
			d16		= {0, 0, 0, 0},
			d32		= {0, 0}
			}
	newRequestNumber = newRequestNumber + 1
	return msg
end

-- Update buffer with current timestamp
function updateBuffer(msgTbl)
	msgBuffer[msgTbl.source] = { time =  os.time() , msg = msgTbl  }
end

-- verify if the nodeId is in the buffer AND the delta time still valid
function hasMsgBuffer(nodeId)
	return msgBuffer[nodeId] and msgBuffer[nodeId].time + deltaTimeRequest >= os.time()
end

10h+ 5 <= 10h4



-- Main functions of the server : exported to the clients

function serverObj.setDeltaTime(seconds)
	deltaTimeRequest = seconds
end


function serverObj.getTemperature(nodeId, timeout )
	exit = false
	allMsgs = ""

	timeout = ( type(timeout) == "number" and timeout ) or 15

	while not(exit) do
		local mote = tossam.connect("sf@localhost:9002",1)
		if not(mote) then print("Connection error!"); return(1); end

		mote:register(msgRegister)
		local msg2 = createNewRequestMessage()
		mote:send(msg2,151,1)

		local startTime = os.time()
		while (mote) do

			if (os.time()-startTime>timeout) then
				exit = true
				break
			end
			if hasMsgBuffer(nodeId) then 
				return serialize(msgBuffer[nodeId].msg)
			else
				local stat, msg, emsg = pcall(function() return mote:receive() end) 
				if stat then
					if msg then 
						if (  nodeId and msg.source == nodeId  and msg.d8[1] == 1) then
							updateBuffer(msg)
							return serialize(msg)
						elseif  not nodeId and msg.source ~= 0 then						
							updateBuffer(msg)		
							allMsgs = allMsgs .. serialize(msg)			
						end
						msg.source = 0
						msg.target = 1
						mote:send(msg, 151,1)
					elseif emsg == "closed" then
						print("\nConnection closed!")
						exit = true
						break 
					end
				else
					print("\nreceive() got an error:"..msg)
					exit = true
					break
				end
			end
		end

		mote:unregister()
		mote:close() 
	end
	return allMsgs
	
end


--Servant creation and publication
serv = rpc.createServant(serverObj , "interface.lua" )
publishContact(serv,"interface.lua" )
-- Wait for clients
rpc.waitIncoming()
