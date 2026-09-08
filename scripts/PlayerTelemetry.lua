-- 玩家遥测。只负责内存态、云读写和查询。
-- 不引用关卡、导演或 HUD；调用方用关卡 id 和节点 id 交互。

local PlayerTelemetry = {}

local CLOUD_KEY = "player_progress"
local DIRTY_FLUSH_DELAY = 0.6

local data = {
    cleared = {},
    finishedGame = false,
    paths = {},
}

local currentLevelId = nil
local currentPath = nil
local loaded = false
local loadStarted = false
---@type fun()[]
local loadCallbacks = {}
local dirty = false
local saving = false
local pendingSave = false
local flushDelay = 0.0
local saveGeneration = 0

local function CopyStringList(list)
    local copy = {}
    if type(list) ~= "table" then
        return copy
    end
    for i = 1, #list do
        local value = list[i]
        if type(value) == "string" and value ~= "" then
            copy[#copy + 1] = value
        end
    end
    return copy
end

local function CopyStringSet(source)
    local copy = {}
    if type(source) ~= "table" then
        return copy
    end
    for key, value in pairs(source) do
        if type(key) == "string" and key ~= "" and value then
            copy[key] = true
        end
    end
    return copy
end

local function NormalizePayload(payload)
    local nextData = {
        cleared = {},
        finishedGame = false,
        paths = {},
    }
    if type(payload) ~= "table" then
        return nextData
    end
    nextData.cleared = CopyStringSet(payload.cleared)
    nextData.finishedGame = payload.finishedGame == true
    if type(payload.paths) == "table" then
        for levelId, path in pairs(payload.paths) do
            if type(levelId) == "string" and levelId ~= "" then
                nextData.paths[levelId] = CopyStringList(path)
            end
        end
    end
    return nextData
end

local function Snapshot()
    local paths = {}
    for levelId, path in pairs(data.paths) do
        paths[levelId] = CopyStringList(path)
    end
    if currentLevelId and currentPath then
        paths[currentLevelId] = CopyStringList(currentPath)
    end
    return {
        cleared = CopyStringSet(data.cleared),
        finishedGame = data.finishedGame == true,
        paths = paths,
    }
end

local function CloudAvailable()
    return clientCloud ~= nil and type(clientCloud.Set) == "function" and type(clientCloud.Get) == "function"
end

local function FinishLoad()
    loaded = true
    local callbacks = loadCallbacks
    loadCallbacks = {}
    for i = 1, #callbacks do
        callbacks[i]()
    end
end

local function MarkDirty()
    dirty = true
    flushDelay = DIRTY_FLUSH_DELAY
end

local function CommitCurrentPath()
    if not currentLevelId or not currentPath then
        return
    end
    data.paths[currentLevelId] = CopyStringList(currentPath)
end

function PlayerTelemetry.Save(reason)
    flushDelay = 0.0
    if not dirty then
        return false
    end
    if saving then
        pendingSave = true
        return true
    end
    if not CloudAvailable() then
        print("PlayerTelemetry: cloud unavailable, keep local " .. tostring(reason))
        return false
    end
    CommitCurrentPath()
    dirty = false
    saving = true
    pendingSave = false
    saveGeneration = saveGeneration + 1
    local generation = saveGeneration
    local payload = Snapshot()
    clientCloud:Set(CLOUD_KEY, payload, {
        ok = function()
            if generation == saveGeneration then
                saving = false
                print("PlayerTelemetry: saved " .. tostring(reason))
                if pendingSave or dirty then
                    pendingSave = false
                    dirty = true
                    PlayerTelemetry.Save("retry")
                end
            end
        end,
        error = function(code, message)
            if generation == saveGeneration then
                saving = false
                dirty = true
                print(string.format(
                    "PlayerTelemetry: save failed reason=%s code=%s message=%s",
                    tostring(reason),
                    tostring(code),
                    tostring(message)
                ))
            end
        end,
    })
    return true
end

function PlayerTelemetry.Load(onLoaded)
    if type(onLoaded) == "function" then
        loadCallbacks[#loadCallbacks + 1] = onLoaded
    end
    if loaded then
        FinishLoad()
        return
    end
    if loadStarted then
        return
    end
    loadStarted = true
    if not CloudAvailable() then
        print("PlayerTelemetry: cloud unavailable, empty local profile")
        FinishLoad()
        return
    end
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            local payload = values and values[CLOUD_KEY]
            data = NormalizePayload(payload)
            print(string.format(
                "PlayerTelemetry: loaded finished=%s",
                tostring(data.finishedGame)
            ))
            FinishLoad()
        end,
        error = function(code, message)
            print(string.format(
                "PlayerTelemetry: load failed code=%s message=%s",
                tostring(code),
                tostring(message)
            ))
            FinishLoad()
        end,
    })
end

function PlayerTelemetry.BeginLevel(levelId, spawnNodeKey)
    if type(levelId) ~= "string" or levelId == "" then
        return false
    end
    CommitCurrentPath()
    currentLevelId = levelId
    currentPath = {}
    if type(spawnNodeKey) == "string" and spawnNodeKey ~= "" then
        currentPath[1] = spawnNodeKey
    end
    data.paths[levelId] = CopyStringList(currentPath)
    MarkDirty()
    print("PlayerTelemetry: begin " .. levelId)
    return true
end

function PlayerTelemetry.RecordNode(nodeKey)
    if not currentLevelId or type(nodeKey) ~= "string" or nodeKey == "" then
        return false
    end
    if not currentPath then
        currentPath = {}
    end
    if currentPath[#currentPath] == nodeKey then
        return false
    end
    currentPath[#currentPath + 1] = nodeKey
    data.paths[currentLevelId] = CopyStringList(currentPath)
    MarkDirty()
    return true
end

function PlayerTelemetry.ClearLevel(levelId)
    if type(levelId) ~= "string" or levelId == "" then
        return false
    end
    CommitCurrentPath()
    data.cleared[levelId] = true
    MarkDirty()
    print("PlayerTelemetry: cleared " .. levelId)
    PlayerTelemetry.Save("clear:" .. levelId)
    return true
end

function PlayerTelemetry.FinishGame()
    CommitCurrentPath()
    data.finishedGame = true
    MarkDirty()
    print("PlayerTelemetry: finished game")
    PlayerTelemetry.Save("finish")
    return true
end

function PlayerTelemetry.AbandonLevel()
    CommitCurrentPath()
    currentLevelId = nil
    currentPath = nil
    if dirty then
        PlayerTelemetry.Save("abandon")
    end
end

function PlayerTelemetry.Update(timeStep)
    if not dirty or saving then
        return
    end
    if flushDelay <= 0.0 then
        return
    end
    local nextDelay = flushDelay - timeStep
    if nextDelay > 0.0 then
        flushDelay = nextDelay
        return
    end
    PlayerTelemetry.Save("idle")
end

function PlayerTelemetry.HasCleared(levelId)
    return type(levelId) == "string" and data.cleared[levelId] == true
end

function PlayerTelemetry.GetCleared()
    return CopyStringSet(data.cleared)
end

function PlayerTelemetry.HasFinishedGame()
    return data.finishedGame == true
end

function PlayerTelemetry.GetPath(levelId)
    if currentLevelId == levelId and currentPath then
        return CopyStringList(currentPath)
    end
    return CopyStringList(data.paths[levelId])
end

function PlayerTelemetry.IsLoaded()
    return loaded
end

return PlayerTelemetry
