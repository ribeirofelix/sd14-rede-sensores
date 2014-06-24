--
-- TOSSAM
-- author: Bruno Silvestre
-- e-mail: brunoos@inf.ufg.br
--
local bit   = require("bit")
local rs232 = require("luars232")

local string = require("string")
local table  = require("table")
local io     = require("io")

local type   = type
local next   = next
local pairs  = pairs
local ipairs = ipairs
local unpack = unpack
local print  = print

local setmetatable = setmetatable

local band   = bit.band
local bor    = bit.bor
local bxor   = bit.bxor
local rshift = bit.rshift
local lshift = bit.lshift

module("tossam.serial")

-- HDLC flags
local HDLC_SYNC   = 0x7E
local HDLC_ESCAPE = 0x7D
local HDLC_MAGIC  = 0x20

-- Framer-level message type
local SERIAL_PROTO_ACK            = 67
local SERIAL_PROTO_PACKET_ACK     = 68
local SERIAL_PROTO_PACKET_NOACK   = 69
local SERIAL_PROTO_PACKET_UNKNOWN = 255

local seqno   = 42
local timeout = 100
local MTU     = 255

local mote2baud = {
  eyesifx    = rs232.RS232_BAUD_57600,
  intelmote2 = rs232.RS232_BAUD_115200,
  iris       = rs232.RS232_BAUD_57600,
  mica       = rs232.RS232_BAUD_19200,
  mica2      = rs232.RS232_BAUD_57600,
  mica2dot   = rs232.RS232_BAUD_19200,
  micaz      = rs232.RS232_BAUD_57600,
  shimmer    = rs232.RS232_BAUD_115200,
  telos      = rs232.RS232_BAUD_115200,
  telosb     = rs232.RS232_BAUD_115200,
  tinynode   = rs232.RS232_BAUD_115200,
  tmote      = rs232.RS232_BAUD_115200,
  ucmini     = rs232.RS232_BAUD_115200,
}

--- DEBUG
local function printf(str, ...)
  print(string.format(str, ...))
end

local function printb(buffer)
  for k, v in ipairs(buffer) do
    io.stdout:write(string.format("%X ", v))
  end
  io.stdout:write("\n")
end
---

local function checksum(buffer)
  local crc = 0
  for k, v in ipairs(buffer) do
    crc = band(bxor(crc, lshift(v, 8)), 0xFFFF)
    for i = 1, 8 do
      if band(crc, 0x8000) == 0 then
        crc = band(lshift(crc, 1), 0xFFFF)
      else
        crc = band(bxor(lshift(crc, 1), 0x1021), 0xFFFF)
      end
    end
  end
  return crc
end

local function lowrecv(port, rbuf)
  local err
  local data
  local size
  while true do
    err, data, size = port:read(1, timeout)
    if err == rs232.RS232_ERR_TIMEOUT then
      --return nil, "timeout"
    elseif err == rs232.RS232_ERR_NOERROR then
      data = string.byte(data)
      if rbuf.sync then
        if rbuf.count >= MTU or (rbuf.escape and data == HDLC_SYNC) then
          rbuf.sync = false
        elseif rbuf.escape then
          rbuf.escape = false
          data = bxor(data, HDLC_MAGIC)
          rbuf.count = rbuf.count + 1
          rbuf.buffer[rbuf.count] = data
        elseif data == HDLC_ESCAPE then
          rbuf.escape = true
        elseif data == HDLC_SYNC then
          local buffer = rbuf.buffer
          local count  = rbuf.count
          rbuf.buffer = {}
          rbuf.count  = 0
          if count > 2 then
            local b1 = table.remove(buffer, count)
            local b2 = table.remove(buffer, count-1)
            local crc = bor(lshift(b1, 8), b2)
            if crc == checksum(buffer) then
              local kind = table.remove(buffer, 1)
              return buffer, kind
            end
          end
        else
          rbuf.count = rbuf.count + 1
          rbuf.buffer[rbuf.count] = data
        end
      elseif data == HDLC_SYNC then
        rbuf.sync   = true
        rbuf.escape = false
        rbuf.buffer = {}
        rbuf.count  = 0
      end
    else
      rbuf.sync   = false
      rbuf.escape = false
      return nil, rs232.error_tostring(err)
    end
  end
end

local function lowsend(port, str)
  local buffer = { string.byte(str, 1, #str) }

  table.insert(buffer, 1, SERIAL_PROTO_PACKET_ACK)
  table.insert(buffer, 2, seqno)
  seqno = ((seqno + 1) % 255)

  local crc = checksum(buffer) 
  buffer[#buffer+1] = band(crc, 0xFF)
  buffer[#buffer+1] = band(rshift(crc, 8))

  local pack = {HDLC_SYNC}
  for k, v in ipairs(buffer) do
    if v == HDLC_SYNC or v == HDLC_ESCAPE then
      pack[#pack+1] = HDLC_ESCAPE
      pack[#pack+1] = band(bxor(v, HDLC_MAGIC), 0xFF)
    else
      pack[#pack+1] = v
    end
  end
  pack[#pack+1] = HDLC_SYNC

  str = string.char(unpack(pack))

  while true do
    local err = port:write(str, timeout)
    if err == rs232.RS232_ERR_NOERROR then
      return true
    elseif err == RS232_ERR_TIMEOUT then
      --return false, "timeout"
    else
      return false, rs232.error_tostring(err)
    end
  end
end

function send(srl, str)
  local succ, errmsg = lowsend(srl.port, str)
  if succ then
    local pack, kind = lowrecv(srl.port, srl.rbuf)
    if kind == SERIAL_PROTO_ACK then
      return true, true
    elseif kind == SERIAL_PROTO_PACKET_NOACK then
      srl.queue[#srl.queue+1] = pack
    end
    return true, false
  end
  return false, errmsg
end

function recv(srl)
  if next(srl.queue) then
    local buffer = table.remove(srl.queue, 1)
    return string.char(unpack(buffer))
  end
  while true do
    local buffer, kind = lowrecv(srl.port, srl.rbuf)
    if not buffer then
      return nil, kind
    elseif kind == SERIAL_PROTO_PACKET_NOACK then
      return string.char(unpack(buffer))
    end
  end
end

function close(srl)
  srl.port:close()
end

local meta = {
  __index = {
    recv  = recv,
    send  = send,
    close = close,
  }
}

function open(portname, baud)
  if type(baud) == "string" then
    baud = mote2baud[baud]
    if not baud then
      return nil, "Invalid baud rate"
    end
  elseif type(baud) == "number" then
    baud = rs232["RS232_BAUD_" .. tostring(baud)]
    if not baud then
      return nil, "Invalid baud rate"
    end
  else
    return nil, "Invalid baud rate"
  end

  local err, port = rs232.open(portname)
  if err ~= rs232.RS232_ERR_NOERROR then
    return nil, rs232.error_tostring(err)
  end
  
  if port:set_baud_rate(baud) ~= rs232.RS232_ERR_NOERROR                    or
     port:set_data_bits(rs232.RS232_DATA_8) ~= rs232.RS232_ERR_NOERROR      or
     port:set_parity(rs232.RS232_PARITY_NONE) ~= rs232.RS232_ERR_NOERROR    or
     port:set_stop_bits(rs232.RS232_STOP_1) ~= rs232.RS232_ERR_NOERROR      or
     port:set_flow_control(rs232.RS232_FLOW_OFF) ~= rs232.RS232_ERR_NOERROR
  then
     port:close()
     return nil, "Serial port setup error"
  end

  local srl = {
    rbuf = {
      buffer  = nil,
      count   = 0,
      escape  = false,
      sync    = false,
    },
    queue = {},
    port  = port,
  }

  return setmetatable(srl, meta)
end
