local tossam = require("tossam") 
local exit = false
local msgId = nil
requestMessage = {
		id		= 1,
		source	= 0,
		target	= 1,
		d8		= {0, 0, 0, 0},
		d16		= {0, 0, 0, 0},
		d32		= {0, 0}
	}
local messageStructure = [[ 
	  nx_struct msg_serial [151] { 
		nx_uint8_t id;
		nx_uint16_t source;
		nx_uint16_t target;	
		nx_uint8_t  d8[4]; 
		nx_uint16_t d16[4];
		nx_uint32_t d32[2];
	  }; 
	]]

function copyMessage(msg)
	local newMsg = {}
	newMsg.id = msg.id
	newMsg.source = msg.source
	newMsg.target = msg.target
	newMsg.d8 = {}
	newMsg.d16 = {}
	newMsg.d32 = {}
	for i = 1, 4 do
		newMsg.d8[i] = msg.d8[i]
		newMsg.d16[i] = msg.d16[i]
		newMsg.d32[i] = msg.d32[i]
	end
	return newMsg
end

function printMessage (msg)
	print("------------------------------") 
	print("msgID: "..msg.id, "Source: ".. msg.source, "Target: ".. msg.target) 
	print("d8:",unpack(msg.d8))
	print("d16:",unpack(msg.d16))
	print("d32:",unpack(msg.d32))
end

function collectTemperatures ()
	local mote = tossam.connect("sf@localhost:9002",1)
	if not(mote) then print("Connection error!"); return(1); end
	mote:register(messageStructure)
	msg2 = copyMessage(requestMessage)
	mote:send(msg2,151,1)

	while (mote) do
		print "mote"

		local stat, msg, emsg = pcall(function() return mote:receive() end) 
		if stat then
			
			if msg then
				printMessage(msg)
				msg.d8[1] = 2; -- para que os nos da rede ignorem essa mensagem;
				msg.source = 0
				msg.target = 1
				mote:send(msg, 151,1)
			else
				if emsg == "closed" then
					print("\nConnection closed!")
					exit = true
					break 
				elseif emsg =="timeout" then
					print "Time out."
					
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

collectTemperatures()
