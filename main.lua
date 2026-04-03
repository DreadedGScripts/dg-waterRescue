-- Compatibility bootstrap for legacy fxmanifest setups that still reference `main.lua`.
-- Loads the modular client files in correct order.

local function includeClientFile(path)
    local resource = GetCurrentResourceName()
    local code = LoadResourceFile(resource, path)
    if not code then
        print(('[dg-waterRescue] Compatibility loader: missing file %s'):format(path))
        return false
    end

    local chunk, err = load(code, ('@%s/%s'):format(resource, path))
    if not chunk then
        print(('[dg-waterRescue] Compatibility loader: failed to load %s (%s)'):format(path, err or 'unknown error'))
        return false
    end

    local ok, runtimeErr = pcall(chunk)
    if not ok then
        print(('[dg-waterRescue] Compatibility loader: runtime error in %s (%s)'):format(path, runtimeErr or 'unknown error'))
        return false
    end

    return true
end

includeClientFile('client/utils.lua')
includeClientFile('client/framework.lua')
includeClientFile('client/routing.lua')
includeClientFile('client/rescue.lua')
includeClientFile('client/main.lua')
