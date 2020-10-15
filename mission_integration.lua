do

local DCS_SERVER_ADDRESS="95.216.78.27"
local DCS_SERVER_PORT="19001"
local DCS_SERVER_PASSWORD="JQN2nMWEj3nLBTnrrV1b"

local logpref = "DCSFF /----------/ "
env.info(logpref.."Included", false)

env.info(logpref.."Adding sockets", false)
package.path = package.path.. ';.\\Scripts\\?.lua;.\\LuaSocket\\?.lua;'
local socket = require("socket")
local host = "localhost"
local port = 5555
env.info(logpref.."Adding sockets OK", false)

-- fuel capacity for each vehicle in tons (not kg!)
-- fuel types
--   jet_fuel
--   gasoline
--   methanol_mixture
--   diesel
local fuelCapacity = {
  ["FA-18C_hornet"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 4.9
  },
  ["F-16C_50"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 3.249
  },
  ["F-15C"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 6.103
  },
  ["F-14B"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 7.348
  },
  ["Su-27"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 9.400
  },
  ["Su-33"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 9.500
  },
  ["MiG-29S"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 3.493
  },
  ["Su-25T"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 3.790
  },
  ["UH-1H"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 0.631
  },
  ["Ka-50"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 1.450
  },
  ["Mi-8MT"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 1.929
  },
  ["SA342M"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 0.416
  },
  ["AV8BNA"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 3.519
  },
  ["M-2000C"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 3.165
  },
  ["JF-17"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 2.325
  },
  ["A-10C"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 5.029
  },
  ["A-10C_2"] = {
    ["type"] = "jet_fuel",
    ["capacity"] = 5.029
  }
}

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
  if name == nil then
    return nil
  end
  _, _, result = string.find(name, "%["..property..":([^\]]+)%]")
  return result
end

-------------------------------------------------------------------------------

--   M  I S S I O N    M A N A G E M E N T

-------------------------------------------------------------------------------

function onMissionStart()
  env.info(logpref.."Initiating mission start triggers", false)
  sendToDaemon("S", "{\"address\": \""..DCS_SERVER_ADDRESS.."\", \"port\": "..DCS_SERVER_PORT..", \"password\": \""..DCS_SERVER_PASSWORD.."\"}")
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
  sendAirbaseDelta()
end

-------------------------------------------------------------------------------

--   U N I T   M A N A G E M E N T

-------------------------------------------------------------------------------

local deadUnits = {}
local originalUnitsPosition = {}
local movedUnits = {}
local spawnedGroups = {}
local unitsCount = {}

function calculateMovedUnits()
  env.info(logpref.."Calculating moved units", false)
  for k,v in pairs(spawnedGroups) do
    if v ~= nil then
      local u = v:getUnit(1)
      if u ~= nil then
        local p = u:getPosition()
        env.info(logpref.."Calculating unit "..k, false)
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
    movedUnits = {}
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
    deadUnits = {}
  end
end

local groupTemplates = {
  ["SA_6"] = {
    "Kub 1S91 str",
    "Kub 2P25 ln",
    "Kub 2P25 ln",
    "Kub 2P25 ln"
  },
  ["SA_11"] = {
    "SA-11 Buk CC 9S470M1",
    "SA-11 Buk SR 9S18M1",
    "5p73 s-125 ln",
    "5p73 s-125 ln",
    "5p73 s-125 ln"
  },
  ["SA_HAWK"] = {
    "Hawk pcp",
    "Hawk sr",
    "Hawk cwar",
    "Hawk tr",
    "Hawk ln",
    "Hawk ln",
    "Hawk ln"
  },
  ["SA_PATRIOT"] = {
    "Patriot ECS",
    "Patriot cp",
    "Patriot AMG",
    "Patriot EPP",
    "Patriot str",
    "Patriot ln",
    "Patriot ln",
    "Patriot ln",
    "Patriot ln"
  },
  ["SA_10"] = {
    "S-300PS 40B6M tr",
    "S-300PS 40B6MD sr",
    "S-300PS 54K6 cp",
    "S-300PS 64H6E sr",
    "S-300PS 5P85C ln",
    "S-300PS 5P85C ln",
    "S-300PS 5P85C ln",
    "S-300PS 5P85C ln"
  }
}

function makeGroup(templatetype, name, type, x, y, a)
  --env.info("type:"..templatetype,true)
  -- explode groups into predefined templates
  if groupTemplates[templatetype] ~= nil then
    return makeSparseUnits(name, groupTemplates[templatetype], x, y, a)
  elseif templatetype == "AWACS" then
    return makeAWACS(name, x, y)
  elseif templatetype == "TANKER" then
    return makeTANKER(name, x, y)
  else
    return makeSparseUnits(name, {type}, x, y, a)
  end
end

function makeAWACS(name, x, y)
  return {
    ["modulation"] = 0,
    ["tasks"] = {},
    ["task"] = "AWACS",
    ["uncontrolled"] = false,
    ["taskSelected"] = true,
    ["route"] = {
      ["points"] = {
        [1] = {
          ["alt"] = 9144,
          ["action"] = "Turning Point",
          ["alt_type"] = "BARO",
          ["speed"] = 150,
          ["task"] = {
              ["id"] = "ComboTask",
              ["params"] = {
                ["tasks"] = {
                  [1] = {
                    ["enabled"] = true,
                    ["auto"] = true,
                    ["id"] = "AWACS",
                    ["number"] = 1,
                    ["params"] = { },
                  },
                  [2] = {
                    ["enabled"] = true,
                    ["auto"] = true,
                    ["id"] = "WrappedAction",
                    ["number"] = 2,
                    ["params"] = {
                      ["action"] = {
                        ["id"] = "EPLRS",
                        ["params"] = {
                          ["value"] = true,
                        },
                      },
                    },
                  },
                  [3] = {
                    ["enabled"] = true,
                    ["auto"] = false,
                    ["id"] = "Orbit",
                    ["number"] = 3,
                    ["params"] = {
                      ["altitude"] = 9144,
                      ["pattern"] = "Circle",
                      ["speed"] = 128.47222222222,
                      ["speedEdited"] = true,
                    },
                  },
              },
            },
          },
          ["type"] = "Turning Point",
          ["ETA"] = 0,
          ["ETA_locked"] = true,
          ["y"] = y,
          ["x"] = x,
          ["name"] = "DictKey_WptName_8",
          ["formation_template"] = "",
          ["speed_locked"] = true,
        },
      }, -- end of ["points"]
    }, -- end of ["route"]
    ["hidden"] = false,
    ["units"] = {
      [1] = {
        ["alt"] = 9144,
        ["alt_type"] = "BARO",
        ["livery_id"] = "nato",
        ["skill"] = "Average",
        ["speed"] = 150,
        ["type"] = "E-3A",
        ["psi"] = 0,
        ["y"] = y,
        ["x"] = x,
        ["name"] = "U "..tostring(name),
        ["payload"] =  {
          ["pylons"] = { },
          ["fuel"] = "65000",
          ["flare"] = 60,
          ["chaff"] = 120,
          ["gun"] = 100,
        },
        ["heading"] = 0,
        ["callsign"] = {
          [1] = 1,
          [2] = 1,
          [3] = 1,
          ["name"] = "Overlord11",
        },
        ["onboard_num"] = "010",
      },
    },
    ["y"] = y,
    ["x"] = x,
    ["name"] = "G "..tostring(name),
    ["communication"] = true,
    ["start_time"] = 0,
    ["frequency"] = 251,
  }
end

function makeTANKER(name, x, y)
  return {
      ["modulation"] = 0,
      ["tasks"] = 
      {
      }, -- end of ["tasks"]
      ["task"] = "Refueling",
      ["uncontrolled"] = false,
      ["taskSelected"] = true,
      ["route"] = 
      {
          ["points"] = 
          {
              [1] = 
              {
                  ["alt"] = 4572,
                  ["action"] = "Turning Point",
                  ["alt_type"] = "BARO",
                  ["speed"] = 150,
                  ["task"] = 
                  {
                      ["id"] = "ComboTask",
                      ["params"] = 
                      {
                          ["tasks"] = 
                          {
                              [1] = 
                              {
                                  ["enabled"] = true,
                                  ["auto"] = true,
                                  ["id"] = "Tanker",
                                  ["number"] = 1,
                                  ["params"] = 
                                  {
                                  }, -- end of ["params"]
                              }, -- end of [1]
                              [2] = 
                              {
                                  ["enabled"] = true,
                                  ["auto"] = true,
                                  ["id"] = "WrappedAction",
                                  ["number"] = 2,
                                  ["params"] = 
                                  {
                                      ["action"] = 
                                      {
                                          ["id"] = "ActivateBeacon",
                                          ["params"] = 
                                          {
                                              ["type"] = 4,
                                              ["frequency"] = 1088000000,
                                              ["callsign"] = "TKR",
                                              ["channel"] = 1,
                                              ["modeChannel"] = "X",
                                              ["bearing"] = true,
                                              ["system"] = 4,
                                          }, -- end of ["params"]
                                      }, -- end of ["action"]
                                  }, -- end of ["params"]
                              }, -- end of [2]
                              [3] = 
                              {
                                  ["enabled"] = true,
                                  ["auto"] = false,
                                  ["id"] = "Orbit",
                                  ["number"] = 3,
                                  ["params"] = 
                                  {
                                      ["altitude"] = 4572,
                                      ["pattern"] = "Circle",
                                      ["speed"] = 128.47222222222,
                                      ["speedEdited"] = true,
                                  }, -- end of ["params"]
                              }, -- end of [3]
                          }, -- end of ["tasks"]
                      }, -- end of ["params"]
                  }, -- end of ["task"]
                  ["type"] = "Turning Point",
                  ["ETA"] = 0,
                  ["ETA_locked"] = true,
                  ["y"] = y,
                  ["x"] = x,
                  ["name"] = "G",
                  ["formation_template"] = "",
                  ["speed_locked"] = true,
              }, -- end of [1]
          }, -- end of ["points"]
      }, -- end of ["route"]
      ["hidden"] = false,
      ["units"] = 
      {
          [1] = 
          {
              ["alt"] = 4572,
              ["alt_type"] = "BARO",
              ["livery_id"] = "100th ARW",
              ["skill"] = "Average",
              ["speed"] = 150,
              ["type"] = "KC135MPRS",
              ["psi"] = 0,
              ["y"] = y,
              ["x"] = x,
              ["name"] = "U "..tostring(name),
              ["payload"] = 
              {
                  ["pylons"] = 
                  {
                  }, -- end of ["pylons"]
                  ["fuel"] = 90700,
                  ["flare"] = 60,
                  ["chaff"] = 120,
                  ["gun"] = 100,
              }, -- end of ["payload"]
              ["heading"] = 0,
              ["callsign"] = 
              {
                  [1] = 1,
                  [2] = 1,
                  [3] = 1,
                  ["name"] = "Texaco11",
              }, -- end of ["callsign"]
              ["onboard_num"] = "010",
          }, -- end of [1]
      }, -- end of ["units"]
      ["y"] = y,
      ["x"] = x,
      ["name"] = "G "..tostring(name),
      ["communication"] = true,
      ["start_time"] = 0,
      ["frequency"] = 251,
  }
end

function makeSparseUnits(name, types, x, y, a)
  local group = {
    ["tasks"] = {},
    ["visible"] = true,
    ["hidden"] = false,
    ["hiddenOnMFD"] = true,
    ["uncontrollable"] = false,
    ["name"] = "G "..tostring(name),
    ["start_time"] = 0,
    ["task"] = "Ground Nothing",
    ["x"] = tonumber(x),
    ["y"] = tonumber(y),
    ["units"] = {},
    ["route"] = {
      ["spans"] = {},
      ["points"] = {
        [1] = {
          ["alt"] = 0,
          ["type"] = "Turning Point",
          ["ETA"] = 0,
          ["alt_type"] = "BARO",
          ["formation_template"] = "",
          ["y"] = tonumber(x),
          ["x"] = tonumber(y),
          ["name"] = "G "..tostring(name),
          ["ETA_locked"] = true,
            ["speed"] = 0,
            ["action"] = "Off Road",
            ["task"] = {
              ["id"] = "ComboTask",
              ["params"] = {
                ["tasks"] = {
                  [1] = {
                    ["enabled"] = true,
                    ["auto"] = false,
                    ["id"] = "WrappedAction",
                    ["number"] = 1,
                    ["params"] = {
                      ["action"] = {
                        ["id"] = "Option",
                        ["params"] = {
                          ["name"] = 9,
                          ["value"] = 2,
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
  }
  local lx = x
  local ly = y
  local angle = -90
  local distance = 0
  local ct = 0
  for i,v in ipairs(types) do
    local noiseangle = (math.random()-0.5) * 50
    local noisedist = (math.random()-0.5) * 40
    local dx = math.cos(math.rad(angle+noiseangle)) * distance+noisedist
    local dy = math.sin(math.rad(angle+noiseangle)) * distance+noisedist
    table.insert(group["units"], {
      ["type"] = tostring(v),
      ["name"] = "U "..tostring(name).. " "..v,
      ["heading"] = a,
      ["playerCanDrive"] = true,
      ["skill"] = "Average",
      ["x"] = tonumber(lx+dx),
      ["y"] = tonumber(ly+dy),
      ["transportable"] = {["randomTransportable"] = false}
    })
    angle = angle + 90
    if distance == 0 then
      distance = 60
    end
    if angle == 360 then
      angle = 0
      distance = distance + 60
    end
    ct = ct + 1
  end
  local uuid = getProperty("UUID", name)
  unitsCount[uuid] = ct
  return group
end

-- lazy initialize/position units
function positionAndActivate(cntry_id, group_data, unit_data)
  local uuid = getProperty("UUID", group_data.name)
  local type = getProperty("grouptype", group_data.name)
  local lat = getProperty("lat", group_data.name)
  local lon = getProperty("lon", group_data.name)
  local point = coord.LLtoLO(lat, lon)
  local ngd = makeGroup(type, group_data.name, unit_data.type, point.x, point.z, 0)
  local category = Group.Category.GROUND
  if type == "AWACS" or type == "TANKER" then
    coalition.addGroup(cntry_id, Group.Category.AIRPLANE, ngd)
    env.info(logpref.."LAZY INIT OF PLANE: "..group_data.name, false)
  else
    local group = coalition.addGroup(cntry_id, Group.Category.GROUND, ngd)
    if group ~= nil then
      if groupTemplates[type] == nil then
        -- Only manage moving units if they are not a group but only a single unit.
        spawnedGroups[uuid] = group
        originalUnitsPosition[uuid] = {
          ["x"] = point.x,
          ["y"] = point.z
        }
      end
      env.info(logpref.."LAZY INIT OF: "..group_data.name, false)
    end
  end
end




-------------------------------------------------------------------------------

--   A I R B A S E   W A R E H O U S E S

-------------------------------------------------------------------------------


local airbaseDeltaAmmo = {}
local airbaseDeltaFuel = {}

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
  for airbaseName,fuel in pairs(airbaseDeltaFuel) do
    for fuelType,deltaAmount in pairs(fuel) do
      if deltaAmount ~= 0 then
        if s ~= "" then
          s = s..","
        end
        s = s.."{\"airbase\":\""..airbaseName.."\",\"type\":\""..fuelType.."\",\"amount\":"..deltaAmount.."}\n"
      end
    end
  end
  return "{\"data\":["..s.."]}"
end

function sendAirbaseDelta()
  local s = buildAirbaseDeltaAmmo()
  if s and s ~= "" then
    sendToDaemon("W", s)
    airbaseDeltaAmmo = {}
    airbaseDeltaFuel = {}
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

function changeAirbaseDeltaFuel(airbaseKey, fuelType, tons)
  if not airbaseDeltaFuel[airbaseKey] then
    airbaseDeltaFuel[airbaseKey] = {}
  end
  if not airbaseDeltaFuel[airbaseKey][fuelType] then 
    airbaseDeltaFuel[airbaseKey][fuelType] = 0
  end
  airbaseDeltaFuel[airbaseKey][fuelType] = airbaseDeltaFuel[airbaseKey][fuelType] + tons
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
    local name = event.initiator:getName()
    env.info(logpref.."UNIT DEAD: "..name, false)
    local uuid = getProperty("UUID", name)
    if uuid and uuid ~= "" then
      if unitsCount[uuid] ~= nil then
        env.info(logpref.."DECREASING COUNT FOR UNIT: "..uuid)
        unitsCount[uuid] = unitsCount[uuid] - 1
        if (unitsCount[uuid] <= 0) then
          env.info(logpref.."DECREASING TO 0 DESTROYED COUNT FOR UNIT: "..uuid)
          table.insert(deadUnits, uuid)
        end
      else
        env.info(logpref.."SINGLE UNIT GROUP DESTROYED: "..uuid)
        table.insert(deadUnits, uuid)
      end
    end
  elseif event.id == world.event.S_EVENT_TAKEOFF or event.id == world.event.S_EVENT_LAND then
    local unit = event.initiator
    local name = unit:getName()
    if unit and event.place then
      local airbaseName = event.place:getName()
      local unitFuel = unit:getFuel()
      local unitAmmo = unit:getAmmo()
      local typeName = unit:getDesc().typeName
      if event.id == world.event.S_EVENT_TAKEOFF then
        env.info(logpref.."UNIT TAKEOFF: "..name)
      elseif event.id == world.event.S_EVENT_LAND then
        env.info(logpref.."UNIT LAND: "..name)
      end
      if typeName then
        -- This is the plane itself
        if event.id == world.event.S_EVENT_TAKEOFF then
          changeAirbaseDeltaAmmo(airbaseName, typeName, -1)
        elseif event.id == world.event.S_EVENT_LAND then
          changeAirbaseDeltaAmmo(airbaseName, typeName, 1)
        end
        -- calculate the fuel
        if unitFuel ~= 0 and fuelCapacity[typeName] ~= nil then
          local fuelType = fuelCapacity[typeName].type
          local fuelTons = unitFuel * fuelCapacity[typeName].capacity
          env.info(logpref.."Fuel takeoff/landing for "..typeName..", fuel type is "..fuelType..", relative="..unitFuel.." tons="..fuelTons)
          if event.id == world.event.S_EVENT_TAKEOFF then
            changeAirbaseDeltaFuel(airbaseName, fuelType, -fuelTons)
          elseif event.id == world.event.S_EVENT_LAND then
            changeAirbaseDeltaFuel(airbaseName, fuelType, fuelTons)
          end
        end
      end
      if unitAmmo then
        -- This is for the ammo for the plane
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