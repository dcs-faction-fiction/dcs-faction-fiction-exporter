do
  if ffeExporterInitialized ~= true then
    ffeExporterInitialized = true;
    local file;
    local lfs = require('lfs');
    local ts = os.time()
    local PrevLuaExportAfterNextFrame = LuaExportAfterNextFrame;
    local PrevLuaExportStop = LuaExportStop;
    log.write('DATA.EXPORT',log.INFO,'---------------ENTR');
    LuaExportAfterNextFrame = function()
      PrevLuaExportAfterNextFrame();
      if not file then
        local exporterfile = lfs.writedir()..os.date('%Y%m%d%H%M%S', ts)..'.txt';
        log.write('DATA.EXPORT',log.INFO,'---------------EXPORTERFILE'..exporterfile);
        file = io.open(exporterfile, "a");
      end
      if file then
        file:write("frame\n");
      end
    end
    LuaExportStop = function()
      LuaExportAfterNextFrame();
      if file then io.close(file); file = nil; end
    end
  end
end
