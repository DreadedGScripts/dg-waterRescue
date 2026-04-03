local REPO = 'DreadedGScripts/dg-waterRescue'
local BRANCH = 'main'

local function trim(value)
    return (tostring(value or ''):gsub('^%s+', ''):gsub('%s+$', ''))
end

local function parseVersion(text)
    if type(text) ~= 'string' then
        return nil
    end

    local version = text:match("version%s+['\"]([^'\"]+)['\"]")
    return version and trim(version) or nil
end

local function splitVersion(version)
    local parts = {}
    for number in tostring(version or ''):gmatch('%d+') do
        parts[#parts + 1] = tonumber(number) or 0
    end
    return parts
end

local function compareVersions(current, latest)
    local currentParts = splitVersion(current)
    local latestParts = splitVersion(latest)
    local maxLen = math.max(#currentParts, #latestParts)

    for index = 1, maxLen do
        local currentValue = currentParts[index] or 0
        local latestValue = latestParts[index] or 0
        if currentValue < latestValue then
            return -1
        end
        if currentValue > latestValue then
            return 1
        end
    end

    return 0
end

CreateThread(function()
    Wait(2500)

    local resourceName = GetCurrentResourceName()
    local currentVersion = trim(GetResourceMetadata(resourceName, 'version', 0) or '')
    if currentVersion == '' then
        print(('[%s] Version check skipped: missing local version metadata.'):format(resourceName))
        return
    end

    local url = ('https://raw.githubusercontent.com/%s/%s/fxmanifest.lua'):format(REPO, BRANCH)
    PerformHttpRequest(url, function(statusCode, body)
        if statusCode ~= 200 then
            print(('[%s] Version check failed: HTTP %s'):format(resourceName, tostring(statusCode)))
            return
        end

        local latestVersion = parseVersion(body)
        if not latestVersion then
            print(('[%s] Version check failed: could not parse remote version.'):format(resourceName))
            return
        end

        local comparison = compareVersions(currentVersion, latestVersion)
        if comparison < 0 then
            print(('[%s] Update available: current %s, latest %s (%s)'):format(resourceName, currentVersion, latestVersion, REPO))
        elseif comparison == 0 then
            print(('[%s] Version check OK: %s'):format(resourceName, currentVersion))
        else
            print(('[%s] Version check notice: local version %s is ahead of GitHub %s'):format(resourceName, currentVersion, latestVersion))
        end
    end, 'GET')
end)