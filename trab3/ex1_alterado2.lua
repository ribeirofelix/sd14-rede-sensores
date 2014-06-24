local tossam = require("tossam") 

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

function printMessage (msg)
	print("------------------------------") 
	print("msgID: "..msg.id, "Source: ".. msg.source, "Target: ".. msg.target) 
	print("d8:",unpack(msg.d8))
	print("d16:",unpack(msg.d16))
	print("d32:",unpack(msg.d32))
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

function getTemperature(nodeId, timeout )
	exit = false

	timeout = ( type(timeout) == "number" and timeout ) or 15

	while not(exit) do
		local mote = tossam.connect("sf@localhost:9002",1)
	--	local micaz = tossam.connect("serial@/dev/ttyUSB1:micaz",1)
		if not(mote) then print("Connection error!"); return(1); end

		mote:register(msgRegister)
		local msg2 = createNewRequestMessage()
		mote:send(msg2,151,1)

		local startTime = os.time()
		while (mote) do
			--
			if (os.time()-startTime>timeout) then
				exit = true
				break
			else
				--print "Stay"
			end
			
			local stat, msg, emsg = pcall(function() return mote:receive() end) 
			if stat then
				if msg then
					if ( ( ( nodeId and msg.source == nodeId) or ( not nodeId and msg.source ~= 0 ) ) and msg.d8[1] == 1) then
						printMessage(msg)
					else
						--print "False"
					end
					msg.source = 0
					msg.target = 1
					mote:send(msg, 151,1)
				else
					if emsg == "closed" then
						print("\nConnection closed!")
						exit = true
						break 
						end
					end
			else
				print("\nreceive() got an error:"..msg)
				exit = true
				break
			end
		end

		mote:unregister()
		mote:close() 
	end
end


getTemperature(21)
print "todos agora"
getTemperature()
