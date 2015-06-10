-----------------------------------------------------
--name       : bios/drone_control.lua
--description: a remote control for drones (drone bios)
--author     : mpmxyz
--github page: https://github.com/mpmxyz/ocprograms
--forum page : none
-----------------------------------------------------

--TODO: goto
--TODO: feedback
assert(xpcall(function()
local INIT_PORT = 1
local MAX_STEP_SIZE = 8

--define helper functions
local function encrypt(msg, key)
  --appending checksum and encrypting
  key = key or ""
  
  local chars = {}
  local sum = 0
  for i = 1, #msg + 1 do
    local char = i <= #msg and msg:byte(i) or sum
    local keyChar = (key == "" and 0) or key:byte((i - 1) % #key + 1)
    sum = (sum - char) % 256
    chars[i] = string.char((char + keyChar) % 256)
  end
  return table.concat(chars)
end
local function decrypt(msg, key)
  --appending checksum and encrypting
  key = key or ""
  
  local chars = {}
  local sum = 0
  for i = 1, #msg do
    local keyChar = (key == "" and 0) or key:byte((i - 1) % #key + 1)
    local char = (msg:byte(i) - keyChar) % 256
    sum = (sum + char) % 256
    chars[i] = string.char(char)
  end
  if sum ~= 0 then
    --checksum failed
    return nil
  end
  return table.concat(chars, "", 1, #msg - 1)
end
--encoding and decoding of drone protocol
local function encode(drone_id, key, msg)
  return "drone" .. drone_id .. " " .. encrypt(msg, key)
end
local function decode(drone_id, key, msg)
  local id, msg = msg:match("^drone(%S+) (.-)$")
  if id == drone_id then
    return decrypt(msg, key)
  end
end

local function onMessage(reactionTable, sender, port, msg)
  
end

--get components
local function getComponent(name)
  local address = component.list(name)()
  return address and component.proxy(address)
end
local eeprom = getComponent("eeprom")
local drone = getComponent("drone")
local modem = getComponent("modem")
local leash = getComponent("leash")
print = drone.setStatusText

--get id, port and key
local drone_id, drone_port, drone_key = eeprom.getData():match("^(%S*) (%S*) ?(.-)$")
drone_port = tonumber(drone_port)

--show id on screen
print(drone_id .. "\n\n")
--wait for messages
modem.open(INIT_PORT)
modem.open(drone_port)

local dx, dy, dz = 0, 0, 0

local actionEnvs = {
  [INIT_PORT] = {
    id = function(address, port)
      modem.send(address, port, encode(drone_id, drone_key, "port("..drone_port..")"))
    end,
  },
  [drone_port] = {
    move = function(x, y, z)
      dx = dx + x
      dy = dy + y
      dz = dz + z
    end,
    swing   = drone.swing,
    place   = drone.place,
    select  = drone.select,
    leash   = leash and leash.leash,
    unleash = leash and leash.unleash,
  },
}

local nextUpdate = computer.uptime()
while true do
  local timeToUpdate = nextUpdate - computer.uptime()

  if timeToUpdate <= 0 then
    dx = math.max(math.min(dx, MAX_STEP_SIZE), -MAX_STEP_SIZE)
    dy = math.max(math.min(dy, MAX_STEP_SIZE), -MAX_STEP_SIZE)
    dz = math.max(math.min(dz, MAX_STEP_SIZE), -MAX_STEP_SIZE)
    drone.move(dx, dy, dz)
    print(dx .. "," .. dy ..","..dz)
    dx, dy, dz = 0, 0, 0
    nextUpdate = computer.uptime() + 1.0
    timeToUpdate = 1.0
  end
  local event, receiverAddress, senderAddress, port, dist, msg = computer.pullSignal(timeToUpdate)
  if event == "modem_message" and type(msg) == "string" then
    local actionEnv = actionEnvs[port]
    if actionEnv then
      msg = decode(drone_id, drone_key, msg)
      if msg then
        local func, err = load(msg, nil, nil, semetatable({},{__index=actionEnv})
        if func then
          func, err = xpcall(func, debug.traceback)
        end
        if not func then
          modem.send(senderAddress, drone_port, encode(drone_id, drone_key, ("status%q"):format(tostring(err))))
        end
      end
    end
  end
end
--on message: decrypt and verify, execute
--
end, debug.traceback))
