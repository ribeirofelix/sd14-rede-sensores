local rpc = require "luarpc2"

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

myobj1 = { foo = 
             function (a, b, s)
               return a+b, "alo alo"
             end,
          boo = 
             function (n)
               return n
             end
        }
myobj2 = { foo = 
             function (a, b, s)
               return a-b, "tchau"
             end,
          boo = 
             function (n)
               return 1
             end
        }

myobj3 = { foo =
              function (a, b, c)
                return a+b, b-c
              end,
           bar = 
              function ()
                print "Hello World!"
              end,
           boo =
              function (a)
                return 1 --a:len()--"string " .. a
              end
        }

-- cria servidores:
print "Creating servant 1"
serv1 = rpc.createServant (myobj3, "interface2.lua")
--print "Creating servant 2"
--serv2 = rpc.createServant (myobj3, "interface2.lua")
--print "Creating servant 3"
--serv3 = rpc.createServant (myobj3, "interface2.lua")
-- usa as infos retornadas em serv1 e serv2 para divulgar contato 
-- (IP e porta) dos servidores
print("Obj1 ip: " .. serv1.ip .. " port: " .. serv1.port)
--print("Obj2 ip: " .. serv2.ip .. " port: " .. serv2.port)
--print("Obj3 ip: " .. serv3.ip .. " port: " .. serv3.port)

publishContact(serv1,"interface2.lua")
--publishContact(serv2,"interface2.lua")
--publishContact(serv3,"interface2.lua")

-- accept client

rpc.waitIncoming()

