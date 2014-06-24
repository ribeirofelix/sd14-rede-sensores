rpc = require "luarpc2"
function counsumeIpPort(interface)
	
	local text = io.open("deploy", "r" ):read("*a")
	
	local linestbl = {}
	if text ~= "" then
		iteLines = string.gmatch(text,'[^\r\n]+') 
		for line in  iteLines do 
			table.insert(linestbl,line)
			
			if(interface == line) then
				-- if the current line is the required interface
				-- we'll consume the next line to get ip/port
				ipportline = iteLines()
				table.insert(linestbl,ipportline)
				if ipportline then
					local ipportmatch = string.gmatch( ipportline , "%S+" )
					ip, port = ipportmatch() , ipportmatch()	
				end
				break
			end
		end
		for line in iteLines do
			table.insert(linestbl,line)
		end

		local file = io.open("deploy","w")
		file:write(table.concat(linestbl,"\n") .. "\n")
		file:close()

		return ip,port
	end
end


describe("Simple call to getTemperature ", function()

		local timeStart
		local p1 
		setup(function ()
			local  ip , port = counsumeIpPort("interface.lua")
			 p1 = rpc.createProxy( ip, port   , "interface.lua")
			 print( ip .. " " .. port )
		end)

		before_each(function() timeStart = os.clock()  end)

		after_each(function () print("Time :" .. (os.clock() - timeStart))	end)

	

		it("simple ", function  ()		
			p1.setDeltaTime(1)
			for i= 1,10000 do	
			local a  = p1.getTemperature(21)
			print(a)		
			end	
		end)
end)

