-- InMobi plugin

local Library = require "CoronaLibrary"

-- Create library
local lib = Library:new{ name="plugin.inMobi", publisherId="com.coronalabs", version=4 }

-------------------------------------------------------------------------------
-- BEGIN
-------------------------------------------------------------------------------

-- This sample implements the following Lua:
-- 
--    local inMobi = require "plugin.inMobi"
--    inMobi.init()
--    

local function showWarning(functionName)
    print( functionName .. " WARNING: The InMobi plugin is only supported on Android & iOS devices. Please build for device")
end

function lib.init()
    showWarning("inMobi.init()")
end

function lib.load()
    showWarning("inMobi.load()")
end

function lib.isLoaded()
    showWarning("inMobi.isLoaded()")
end

function lib.show()
    showWarning("inMobi.show()")
end

function lib.hide()
    showWarning("inMobi.hide()")
end

function lib.setUserDetails()
    showWarning("inMobi.setUserDetails()")
end

-------------------------------------------------------------------------------
-- END
-------------------------------------------------------------------------------

-- Return an instance
return lib
