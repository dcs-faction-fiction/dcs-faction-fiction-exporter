do
  if ffeExporterInitialized~=true then
    ffeExporterInitialized=true;
    local PrevLuaExportStart=LuaExportStart;
    local PrevLuaExportAfterNextFrame=LuaExportAfterNextFrame;
    local PrevLuaExportStop=LuaExportStop;
    LuaExportStart=function()
      PrevLuaExportStart();
    end
    LuaExportAfterNextFrame=function()
      PrevLuaExportAfterNextFrame();
    end
    LuaExportStop=function()
      LuaExportAfterNextFrame();
    end
  end
end
