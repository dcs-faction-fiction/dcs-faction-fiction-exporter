do
  if ffeExporterInitialized ~= true then

    ffeExporterInitialized = true
    local file
    local lastT = LoGetModelTime()
    local lfs = require('lfs')
    local ts = os.time()
    local PrevLuaExportAfterNextFrame = LuaExportAfterNextFrame
    local PrevLuaExportStop = LuaExportStop
    log.write('DATA.EXPORT',log.INFO,'Data exporter is initializing')


    LuaExportAfterNextFrame = function()
      PrevLuaExportAfterNextFrame()
      if not file then
        -- do -10 so that the first iteration will also print the values.
        lastT = LoGetModelTime() - 10
        local exporterfile = lfs.writedir()..os.date('%Y%m%d%H%M%S', ts)..'.txt'
        log.write('DATA.EXPORT',log.INFO,'Data eporter file will be: '..exporterfile)
        file = io.open(exporterfile, "a")
      end
      if file then
        local newT = LoGetModelTime()
        local deltaT = newT - lastT
        if deltaT > 10 then
          lastT = newT
          log.write('DATA.EXPORT',log.INFO,'Tick is tickling: '..lastT)
          file:write("frame\n")
        end
      end
    end
    LuaExportStop = function()
      LuaExportAfterNextFrame()
      if file then io.close(file) file = nil end
      log.write('DATA.EXPORT',log.INFO,'Data exporter is closed.')
      world.removeEventHandler(eventHandler)
    end

  end
end
