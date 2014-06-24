--
-- TOSSAM
-- author: Bruno Silvestre
-- e-mail: brunoos@inf.ufg.br
--
local codec  = require("tossam.codec")
local serial = require("tossam.serial")
local sf     = require("tossam.sf")

local string = require("string")
local table  = require("table")

local type         = type
local print        = print
local pairs        = pairs
local ipairs       = ipairs
local tonumber     = tonumber
local setmetatable = setmetatable

module("tossam")

local strheader = [[
nx_struct header[0] {
  nx_uint8_t  am;
  nx_uint16_t dst;
  nx_uint16_t src;
  nx_uint8_t  len;
  nx_uint8_t  grp;
  nx_uint8_t  type;
};
]]

local defheader = (codec.parser(strheader))[1]

local function register(conn, str)
   local defs, err = codec.parser(str)
   if err then return false, err end
   local tmp = {}
   for i, def in ipairs(defs) do
     if conn.defs[def.id] or tmp[def.id] then
        return false, "AM type already defined: " .. def.name
     else
        tmp[def.id] = true
     end
   end
   for i, def in ipairs(defs) do
     conn.defs[def.id]   = def
     conn.defs[def.name] = def
   end
   return true
end

local function registered(conn)
  local defs = {}
  for k, v in pairs(conn.defs) do
    if type(k) == "string" then
      defs[k] = v.id
    end
  end
  return defs
end

local function unregister(conn, id)
  local def = conn.defs[id]
  if def then
    conn.defs[def.id]   = nil
    conn.defs[def.name] = nil
    return true
  end
  return false
end

local function close(conn)
   return conn.port:close()
end

local function receive(conn)
   local pck, msg = conn.port:recv()
   if not pck then return nil,msg end
   local head = codec.decode(defheader, pck, 1)
   local def = conn.defs[head.type]
   if not def then
      return nil, "Unknown AM type"
   end
   -- skip the header
   local payload = codec.decode(def, pck, 9)
   payload[1] = def.id
   payload[2] = def.name
   return payload
end

local function send(conn, payload, def, target)
   def = def or payload[1]
   if (type(def) ~= "number" and type(def) ~= "string") then
      return false, "Invalid parameters"
   end
   def = conn.defs[def]
   if not def then
      return false, "Unknown AM type"
   end
   payload = codec.encode(def, payload)
   local head = {
      am   = 0,
      src  = 0,
      dst  = target or 0xffff,
      len  = #payload,
      grp  = 0x22,
      type = def.id,
   }
   head = codec.encode(defheader, head)
   if conn.port:send(head..payload) then
      return true
   end
   return false, "Could not send the message"
end

local meta = { }
meta.__index = {
  close      = close,
  send       = send,
  receive    = receive,
  register   = register,
  registered = registered,
  unregister = unregister,
}

function connect(link,timeout)
  local port, msg
  local patt = "([^@]+)@([^:]+):(.+)"
  local kind, arg1, arg2 = string.match(link, patt)
  if kind == "serial" then
    port, msg = serial.open(arg1, tonumber(arg2) or arg2)
  elseif kind == "sf" then
    port, msg = sf.open(arg1, tonumber(arg2),timeout)
  else
    return nil, "invalid connection type"
  end
  if not port then
    return nil, msg
  end
  local conn = { port = port, defs = {} }
  return setmetatable(conn, meta)
end
