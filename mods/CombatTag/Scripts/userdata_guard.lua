-- Protect UE4SS LuaMadeSimple __index from missing/invalid uservalue #3.
-- The shipped implementation checks only LUA_TNIL, but lua_getiuservalue
-- returns LUA_TNONE when the slot does not exist. Its following rawget can
-- dereference the uninitialized payload of a nil TValue and crash the process.
-- This guard raises a catchable Lua error BEFORE entering that native path.
local G={wrapped=setmetatable({},{__mode='k'})}
assert(debug and debug.getmetatable and debug.getuservalue,'Lua debug userdata API unavailable')
local function members(v)
    local t=debug.getuservalue(v,3)
    if type(t)~='table' then
        error('CombatTag rejected UE4SS userdata with a missing/invalid member table',3)
    end
    return t
end
function G.protect(v)
    if type(v)~='userdata' then return v end
    local mt=debug.getmetatable(v)
    if type(mt)~='table' or type(rawget(mt,'__index'))~='function' then return v end
    if not G.wrapped[mt] then
        local index=rawget(mt,'__index')
        mt.__index=function(self,key)
            members(self)
            return index(self,key)
        end
        G.wrapped[mt]=true
    end
    return v
end
function G.unwrap(v)
    if type(v)~='userdata' then return v end
    G.protect(v)
    -- Only actual remote-parameter wrappers have a registered get method.
    -- Do not probe every UObject/struct with v:get() inside pcall: pcall cannot
    -- catch a native access violation caused by the __index implementation.
    local getter=rawget(members(v),'get')
    if type(getter)=='function' then return G.protect(getter(v)) end
    return v
end
return G
