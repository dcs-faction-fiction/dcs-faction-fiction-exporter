do

local logpref = "DCSFF /----------/ "
env.info(logpref.."Included", false)

env.info(logpref.."Adding sockets", false)
package.path = package.path.. ';.\\Scripts\\?.lua;.\\LuaSocket\\?.lua;'
local socket = require("socket")
local host = "localhost"
local port = 5555
env.info(logpref.."Adding sockets OK", false)

function dump(o)
  if type(o) == 'table' then
    local s = '{\n'
    for k,v in pairs(o) do
      if type(k) ~= 'number' then k = '"'..k..'"' end
      s = s .. '['..k..'] = ' .. dump(v) .. ',\n'
    end
    return s .. '}'
  elseif type(o) == 'string' then
    return '"'..tostring(o)..'"'
  else
    return tostring(o)
  end
end

function sendToDaemon(cmd, s)
  env.info(logpref.."CONNECTING: "..host..":"..port, false)
  local c = assert(socket.connect(host, port))
  env.info(logpref.."SENDING: "..cmd..s, false)
  c:send(cmd..s.."\n\n")
  c:close()
  env.info(logpref.."CLOSED", false)
end

function getProperty(property, name)
  _, _, result = string.find(name, "%["..property..":([^\]]+)%]")
  return result
end

-------------------------------------------------------------------------------

--   M  I S S I O N    M A N A G E M E N T

-------------------------------------------------------------------------------

function onMissionStart()
  env.info(logpref.."Initiating mission start triggers", false)
  sendToDaemon("S", "")
  env.info(logpref.."Positioning units", false)
  for coa_name, coa_data in pairs(env.mission.coalition) do
    if (coa_name == 'red' or coa_name == 'blue') and type(coa_data) == 'table' then
      if coa_data.country then
        for cntry_num, cntry_data in pairs(coa_data.country) do
          if type(cntry_data) == 'table' then
            for obj_type_name, obj_type_data in pairs(cntry_data) do
              if obj_type_name == "vehicle" then
                if ((type(obj_type_data) == 'table') and obj_type_data.group and (type(obj_type_data.group) == 'table') and (#obj_type_data.group > 0)) then
                  for group_num, group_data in pairs(obj_type_data.group) do
                    if group_data and group_data.units and type(group_data.units) == 'table' then
                      if string.match(group_data.name, '%[lat:.+%]') and  string.match(group_data.name, '%[lon:.+%]') then
                        for unit_num, unit_data in pairs(group_data.units) do
                          positionAndActivate(cntry_data.id, group_data, unit_data)
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
  env.info(logpref.."Positioning units OK", false)
end

function onMissionEnd()
  calculateMovedUnits()
  sendDeadUnits()
  sendMovedUnits()
  -- This is last becasue warehouse info terminates the mission with an event on server side
  sendAirbaseDeltaAmmo()
end

-------------------------------------------------------------------------------

--   U N I T   M A N A G E M E N T

-------------------------------------------------------------------------------

local deadUnits = {}
local originalUnitsPosition = {}
local movedUnits = {}
local spawnedGroups = {}

function calculateMovedUnits()
  env.info(logpref.."Calculating moved units", false)
  for k,v in pairs(spawnedGroups) do
    local u = v:getUnit(1)
    local p = u:getPosition()
    local ox = math.modf(originalUnitsPosition[k].x)
    local oy = math.modf(originalUnitsPosition[k].y)
    local nx = math.modf(p.p.x)
    local ny = math.modf(p.p.z)
    if ox ~= nx or oy ~= ny then
      env.info(logpref.."Calculating moved units:"..u:getName().." ox="..ox.." ox="..ox.." nx="..nx.." ny="..ny, false)
      local lat, lon = coord.LOtoLL({x = nx, y = 0, z = ny})
      movedUnits[k] = {}
      movedUnits[k].lat = lat
      movedUnits[k].lon = lon
    end
  end
end

function sendMovedUnits()
  local s = ""
  local c = "["
  for k,v in pairs(movedUnits) do
    local l = "\"latitude\": "..v.lat..",\"longitude\":"..v.lon..",\"altitude\":0,\"angle\":0"
    local u = "{\"id\": \""..k.."\", \"location\":{"..l.."}}"
    s = s..c..u
    c = ","
  end
  if s and s ~= "" then
    s = s.."]"
    sendToDaemon("M", s)
  end
end

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
  local uuid = getProperty("UUID", group_data.name)
  local lat = getProperty("lat", group_data.name)
  local lon = getProperty("lon", group_data.name)
  local point = coord.LLtoLO(lat, lon)
  local ngd = {
    ["route"] = {},
    ["tasks"] = {},
    ["visible"] = true,
    ["hidden"] = false,
    ["uncontrollable"] = false,
    ["name"] = "G "..tostring(group_data.name),
    ["start_time"] = 0,
    ["task"] = "Ground Nothing",
    ["x"] = tonumber(point.x),
    ["y"] = tonumber(point.z),
    ["units"] = {
      [1] = {
        ["type"] = tostring(unit_data.type),
        ["name"] = "U "..tostring(group_data.name),
        ["heading"] = 0,
        ["playerCanDrive"] = true,
        ["skill"] = "Average",
        ["x"] = tonumber(point.x),
        ["y"] = tonumber(point.z),
        ["transportable"] = {["randomTransportable"] = false}
      }
    }
  }
  local group = coalition.addGroup(cntry_id, Group.Category.GROUND, ngd)
  spawnedGroups[uuid] = group
  originalUnitsPosition[uuid] = {
    ["x"] = point.x,
    ["y"] = point.z
  }
  env.info(logpref.."LAZY INIT OF: "..group_data.name, false)
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
    onMissionStart()
  elseif event.id == world.event.S_EVENT_MISSION_END then
    onMissionEnd()
  elseif event.id == world.event.S_EVENT_DEAD then
    local group = Unit.getGroup(event.initiator)
    local uuid = getProperty("UUID", group_data.name)
    if uuid and uuid ~= "" then
      env.info(logpref.."DESTROYED: "..uuid)
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