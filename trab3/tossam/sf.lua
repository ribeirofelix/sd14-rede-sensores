local socket = require("socket")
local string = require("string")

local setmetatable = setmetatable

module("tossam.sf")

local function recv(sf)
  local len, msg = sf.conn:receive(1)
  if msg then
    return nil, msg
  end
  len = string.byte(len)
  if len == 0 then
    return nil, "invalid packet length"
  end
  local pkt, msg = sf.conn:receive(len)
  if msg then
    return nil, msg
  end
  return pkt
end

local function send(sf, data)
  local len = #data
  len = string.char(len)
  local succ, msg = sf.conn:send(len)
  if msg then
    return false, msg
  end
  succ, msg = sf.conn:send(data)
  if msg then
    return false, msg
  end
  return true
end

local function close(sf)
  return sf.conn:close()
end

local meta = {
  __index = {
    recv  = recv,
    send  = send,
    close = close,
  }
}

function open(host, port, timeout)
  local conn = socket.tcp()
  local succ, msg = conn:connect(host, port)
  conn:settimeout(timeout)
  if not succ then
    return nil, msg
  end
  -- Receive their version
  local version = conn:receive(2)
  -- Send our version
  conn:send("U ")

  -- Valid version?
  if version ~= "U " then
    return nil, "invalid version"
  end

  local sf = { conn = conn }

  return setmetatable(sf, meta)
end
