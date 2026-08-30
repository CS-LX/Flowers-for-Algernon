-- 玩法关卡容器。
-- Init 加载游戏内配置的关卡 JSON 并启动 GamePreview；Dispose 完整拆除场景。
-- 只读 assets/Levels，不读用户关卡编辑器存档（levels/default-level.json）。
-- 不依赖 LevelEditor / OverlayViewManager；玩法自己驱动 Scene。

local GamePreview = require "GamePreview"
local LevelDocument = require "LevelDocument"
local TriPrismGrid = require "TriPrismGrid"
local VoxelRenderer = require "VoxelRenderer"

---@class LevelSession
---@field definition LevelDefinition
---@field edgeLength number
---@field voxelHeight number
---@field grid table
---@field levelDocument table|nil
---@field preview table|nil
---@field sourcePath string|nil
---@field started boolean
local LevelSession = {}
LevelSession.__index = LevelSession

local FALLBACK_JSON_PATHS = {
    "Levels/whitebox-level.json",
}

local function IsResourcePath(path)
    return type(path) == "string" and path:find("^Levels/") ~= nil
end

local function ReadFileText(path)
    if not fileSystem:FileExists(path) then
        return nil, "file does not exist: " .. tostring(path)
    end
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        return nil, "cannot open file: " .. tostring(path)
    end
    local json = file:ReadString()
    file:Close()
    if type(json) ~= "string" or json == "" then
        return nil, "file is empty: " .. tostring(path)
    end
    print("LevelSession: loaded File " .. path)
    return json
end

local function ReadText(path)
    if not path or path == "" then
        return nil, "empty level path"
    end
    -- docs/ 不在资源根里。GetResource / GetFile 会打引擎 ERROR，不能先试。
    if not IsResourcePath(path) then
        return ReadFileText(path)
    end
    local resolved = path
    local uuidPathOk, uuidPath = pcall(function()
        return cache:GetResUuidPath(path)
    end)
    if uuidPathOk and type(uuidPath) == "string" and uuidPath ~= "" then
        resolved = uuidPath
        print("LevelSession: uuid path " .. path .. " -> " .. uuidPath)
    end
    local jsonFile = cache:GetResource("JSONFile", resolved) --[[@as JSONFile?]]
    if jsonFile then
        local json = jsonFile:ToString()
        if type(json) == "string" and json ~= "" then
            print("LevelSession: loaded JSONFile " .. path)
            return json
        end
    end
    local fileJson, fileError = ReadFileText(path)
    if fileJson then
        return fileJson
    end
    return nil, fileError or ("cannot open level json: " .. tostring(path))
end

local function LoadInlineJson(sourcePath)
    local paths = { sourcePath }
    for _, fallback in ipairs(FALLBACK_JSON_PATHS) do
        if fallback ~= sourcePath then
            paths[#paths + 1] = fallback
        end
    end
    local errors = {}
    for _, path in ipairs(paths) do
        local json, readError = ReadText(path)
        if json then
            print("LevelSession: loaded inline json from " .. path)
            return json, path
        end
        errors[#errors + 1] = tostring(path) .. " (" .. tostring(readError) .. ")"
    end
    return nil, "无法读取关卡 JSON：" .. table.concat(errors, "; ")
end

function LevelSession.New(definition, edgeLength, voxelHeight)
    local self = setmetatable({}, LevelSession)
    self.definition = definition
    self.edgeLength = edgeLength or VoxelRenderer.DEFAULT_EDGE
    self.voxelHeight = voxelHeight or VoxelRenderer.DEFAULT_HEIGHT
    self.grid = TriPrismGrid.New(self.edgeLength, self.voxelHeight)
    ---@type table|nil
    self.levelDocument = nil
    ---@type table|nil
    self.preview = nil
    ---@type string|nil
    self.sourcePath = nil
    self.started = false
    return self
end

function LevelSession:Init()
    if self.started then
        return false, "level session already started"
    end
    local json, sourceOrError = LoadInlineJson(self.definition.sourcePath)
    if not json then
        return false, sourceOrError
    end
    self.sourcePath = sourceOrError
    local document, loadError = LevelDocument.LoadInlineRuntime(json, self.grid)
    if not document then
        return false, loadError
    end
    self.levelDocument = document
    self.preview = GamePreview.New(
        self.levelDocument,
        self.edgeLength,
        self.voxelHeight
    )
    local started, startError = self.preview:Start()
    if not started then
        self:Dispose()
        return false, startError
    end
    self.started = true
    print(string.format(
        "LevelSession Init: id=%s title=%s name=%s parts=%d source=%s",
        tostring(self.definition.id),
        tostring(self.definition.title),
        tostring(self.levelDocument.name),
        #self.levelDocument:GetParts(),
        tostring(self.sourcePath)
    ))
    return true
end

function LevelSession:Update(timeStep)
    if self.preview then
        self.preview:Update(timeStep)
    end
end

function LevelSession:Dispose()
    print(string.format(
        "LevelSession Dispose: id=%s started=%s",
        self.definition and self.definition.id or "nil",
        tostring(self.started)
    ))
    if self.preview then
        self.preview:Stop()
        self.preview = nil
    end
    self.levelDocument = nil
    self.sourcePath = nil
    self.started = false
end

return LevelSession
