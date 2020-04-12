
do
  local host, port = "localhost", 5555
  package.path = package.path.. ';.\\Scripts\\?.lua;.\\LuaSocket\\?.lua;'
  local socket = require("socket")
  local tcp = assert(socket.tcp())

--[[function dump(o)
  if type(o) == 'table' then
    local s = '{'
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ','
    end
    return s .. '}\n'
  else
    return tostring(o)
  end
end]]--

local airbaseDeltaAmmo = {}
function buildAirbaseDeltaAmmo()
  local s = ""
  for airbaseName,ammo in pairs(airbaseDeltaAmmo) do
    for ammoType,deltaAmount in pairs(ammo) do
      if deltaAmount ~= 0 then
        local airbase = Airbase.getByName(airbaseName)
        local airbaseId = airbase:getID()
        s = s..""..airbaseId..","..ammoType..","..deltaAmount.."\n"
      end
    end
  end
  return s
end
function sendAirbaseDeltaAmmo()
  local s = buildAirbaseDeltaAmmo()
  if s ~= '' then
    env.info("---------- SENDING:\n"..s.."\n", false)
    tcp:connect(host, port)
    tcp:send(s)
    tcp:close()
  end
end

local Event_Handler = {}
function Event_Handler:onEvent(event)
  if event.id == world.event.S_EVENT_MISSION_END then
    sendAirbaseDeltaAmmo()
  elseif event.id == world.event.S_EVENT_TAKEOFF or event.id == world.event.S_EVENT_LAND then
    local unit = event.initiator
    if unit and event.place then
      local airbaseName = event.place:getName()
      local unitAmmo = unit:getAmmo()
      if unitAmmo then
        for k,v in pairs(unit:getAmmo()) do
          ammoType = tostring(v.desc.typeName)
          ammoAmount = v.count
          if not airbaseDeltaAmmo[airbaseName] then
            airbaseDeltaAmmo[airbaseName] = {}
          end
          if not airbaseDeltaAmmo[airbaseName][ammoType] then 
            airbaseDeltaAmmo[airbaseName][ammoType] = 0
          end
          if event.id == world.event.S_EVENT_TAKEOFF then
            airbaseDeltaAmmo[airbaseName][ammoType] = airbaseDeltaAmmo[airbaseName][ammoType] - ammoAmount
          elseif event.id == world.event.S_EVENT_LAND then
            airbaseDeltaAmmo[airbaseName][ammoType] = airbaseDeltaAmmo[airbaseName][ammoType] + ammoAmount
          end
        end
      end
    end
  end
end
world.addEventHandler(Event_Handler)



end