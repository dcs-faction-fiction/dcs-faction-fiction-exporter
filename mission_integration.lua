do


function dump(o)
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
end



local host, port = "localhost", 5555
package.path = package.path.. ';.\\Scripts\\?.lua;.\\LuaSocket\\?.lua;'
local socket = require("socket")

function sendToDaemon(cmd, s)
  env.info("---------- CONNECTING: "..host..":"..port, false)
  local c = assert(socket.connect(host, port))
  env.info("---------- SENDING: "..cmd..s, false)
  c:send(cmd..s.."\n\n")
  c:close()
  env.info("---------- CLOSED", false)
end





-------------------------------------------------------------------------------

--   U N I T   M A N A G E M E N T

-------------------------------------------------------------------------------

local deadUnits = {}

function sendDeadUnits()
  local s = ""
  local c = "["
  for k,v in pairs(deadUnits) do
    s = s..c.."\""..v.."\""
    c = ","
  end
  if s and s ~= "" then
    s = s.."]"
    sendToDaemon("D", s)
  end
end
-- lazy initialize/position units
function positionAndActivate(cntry_id, group_data, unit_data)
  _, _, lat = string.find(group_data.name, "%[lat:([0-9%.]+)%]")
  _, _, lon = string.find(group_data.name, "%[lon:([0-9%.]+)%]")
  local point = coord.LLtoLO(lat, lon)
  local newGroupData = {
    ["visible"] = false,
    ["taskSelected"] = true,
    ["route"] = {},
    ["groupId"] = 2,
    ["tasks"] = {}, 
    ["hidden"] = false,
    ["y"] = point.z,
    ["x"] = point.x,
    ["name"] = "Ground Group",
    ["start_time"] = 0,
    ["task"] = "Ground Nothing",
    ["units"] = {
      [1] = {
        ["type"] = unit_data.type,
        ["transportable"] = {["randomTransportable"] = false},
        ["unitId"] = 2,
        ["skill"] = "Excellent",
        ["y"] = point.z,
        ["x"] = point.x,
        ["name"] = "",
        ["playerCanDrive"] = true,
        ["heading"] = 0,
      },
    },
  }
  env.info("---------- LAZY INIT OF: "..group_data.name.."  LAT: "..lat.."  LON: "..lon, false)
  coalition.addGroup(cntry_id, Group.Category.GROUND, newGroupData)
end
for coa_name, coa_data in pairs(env.mission.coalition) do
  if (coa_name == 'red' or coa_name == 'blue') and type(coa_data) == 'table' then
    if coa_data.country then
      for cntry_id, cntry_data in pairs(coa_data.country) do
        if type(cntry_data) == 'table' then
          for obj_type_name, obj_type_data in pairs(cntry_data) do
            if obj_type_name == "vehicle" then
              if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then
                for group_num, group_data in pairs(obj_type_data.group) do
                  if group_data and group_data.units and type(group_data.units) == 'table' then
                    if string.match(group_data.name, '%[lat:.+%]') and  string.match(group_data.name, '%[lon:.+%]') then
                      for unit_num, unit_data in pairs(group_data.units) do
                        positionAndActivate(cntry_id, group_data, unit_data)
                      end
                    end
                  end
                end
              end
            end
          end
        end
      end
    end
  end
end




-------------------------------------------------------------------------------

--   A I R B A S E   W A R E H O U S E S

-------------------------------------------------------------------------------


local airbaseDeltaAmmo = {}

function buildAirbaseDeltaAmmo()
  local s = ""
  for airbaseName,ammo in pairs(airbaseDeltaAmmo) do
    for ammoType,deltaAmount in pairs(ammo) do
      if deltaAmount ~= 0 then
        if s ~= "" then
          s = s..","
        end
        s = s.."{\"airbase\":\""..airbaseName.."\",\"type\":\""..ammoType.."\",\"amount\":"..deltaAmount.."}\n"
      end
    end
  end
  return "{\"data\":["..s.."]}"
end

function sendAirbaseDeltaAmmo()
  local s = buildAirbaseDeltaAmmo()
  if s and s ~= "" then
    sendToDaemon("W", s)
  end
end

function changeAirbaseDeltaAmmo(airbaseKey, typeKey, amount)
  if not airbaseDeltaAmmo[airbaseKey] then
    airbaseDeltaAmmo[airbaseKey] = {}
  end
  if not airbaseDeltaAmmo[airbaseKey][typeKey] then 
    airbaseDeltaAmmo[airbaseKey][typeKey] = 0
  end
  airbaseDeltaAmmo[airbaseKey][typeKey] = airbaseDeltaAmmo[airbaseKey][typeKey] + amount
end




-------------------------------------------------------------------------------

--   E V E N T S

-------------------------------------------------------------------------------


local Event_Handler = {}
function Event_Handler:onEvent(event)
  if event.id == world.event.S_EVENT_MISSION_START then
    sendToDaemon("S", "")
  elseif event.id == world.event.S_EVENT_MISSION_END then
    sendAirbaseDeltaAmmo()
    sendDeadUnits()
  elseif event.id == world.event.S_EVENT_DEAD then
    local group = Unit.getGroup(event.initiator)
    _, _, uuid = string.find(group:getName(), "%[UUID:(.+)%]")
    if uuid and uuid ~= "" then
      env.info("---------- DESTROYED: "..uuid)
      table.insert(deadUnits, uuid)
    end
  elseif event.id == world.event.S_EVENT_TAKEOFF or event.id == world.event.S_EVENT_LAND then
    local unit = event.initiator
    if unit and event.place then
      local airbaseName = event.place:getName()
      local unitAmmo = unit:getAmmo()
      local typeName = unit:getDesc().typeName
      if typeName then
        -- This is the plane itself
        if event.id == world.event.S_EVENT_TAKEOFF then
          changeAirbaseDeltaAmmo(airbaseName, typeName, -1)
        elseif event.id == world.event.S_EVENT_LAND then
          changeAirbaseDeltaAmmo(airbaseName, typeName, 1)
        end
      end
      if unitAmmo then
        -- This is for the ammp for the plane
        for k,v in pairs(unit:getAmmo()) do
          ammoType = tostring(v.desc.typeName)
          ammoAmount = v.count
          if event.id == world.event.S_EVENT_TAKEOFF then
            changeAirbaseDeltaAmmo(airbaseName, ammoType, -ammoAmount)
          elseif event.id == world.event.S_EVENT_LAND then
            changeAirbaseDeltaAmmo(airbaseName, ammoType, ammoAmount)
          end
        end
      end
    end
  end
end
world.addEventHandler(Event_Handler)



end