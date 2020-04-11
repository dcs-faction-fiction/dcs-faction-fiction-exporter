do
	if ffeExporterInitialized~=true then
		ffeExporterInitialized=true;
        do
            local PrevLuaExportStart=LuaExportStart;
            local PrevLuaExportAfterNextFrame=LuaExportAfterNextFrame;
            local PrevLuaExportStop=LuaExportStop;
            LuaExportStart=function()
                
                if PrevLuaExportStart then
                    PrevLuaExportStart();
                end
            end
            LuaExportAfterNextFrame=function()
                
                if PrevLuaExportAfterNextFrame then
                    PrevLuaExportAfterNextFrame();
                end
            end
            LuaExportStop=function()
                
                if PrevLuaExportStop then
                    PrevLuaExportStop();
                end
            end
        end
    end
end
