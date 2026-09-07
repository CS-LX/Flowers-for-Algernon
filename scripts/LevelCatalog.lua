-- 玩法关卡目录。
-- 章节名、关卡数、可玩路径和 stencil id 都来自 Levels/catalog.json。
-- 颜色由 StencilIdColor 从 id 生成，不在配置里写死色值。

local StencilIdColor = require "StencilIdColor"
local LookApplier = require "LookApplier"

---@class LevelDefinition
---@field id string
---@field index number
---@field chapter number
---@field code string
---@field chapterLabel string
---@field chapterTitle string
---@field stageName string
---@field title string
---@field subtitle string
---@field sourcePath string
---@field stencilId number
---@field fogColor Color
---@field placeholder boolean|nil

---@class LevelCatalogConfig
---@field whiteboxPath string
---@field emptyStencilId number
---@field backStencilId number
---@field placeholderFogColor Color

local LevelCatalog = {}

local CONFIG_PATH = "Levels/catalog.json"
local FALLBACK_EMPTY_ID = -1
local FALLBACK_BACK_ID = -2
local FALLBACK_CONFIG = {
    whiteboxPath = "Levels/whitebox-level.json",
    emptyStencilId = FALLBACK_EMPTY_ID,
    backStencilId = FALLBACK_BACK_ID,
    chapters = {
        {
            id = 1,
            label = "一",
            title = "跑不过的迷宫",
            stencilId = 0,
            stages = {
                { name = "雾中盲途", sourcePath = "Levels/level-1-1.json", fogColor = "#937754" },
                { name = "虚空足迹", sourcePath = "Levels/level-1-2.json", fogColor = "#937754" },
                { name = "错位之契", sourcePath = "Levels/level-1-3.json", fogColor = "#937754" },
            },
        },
    },
}

---@type LevelDefinition[]
LevelCatalog.LEVELS = {}
---@type LevelCatalogConfig
LevelCatalog.CONFIG = {
    whiteboxPath = "Levels/whitebox-level.json",
    emptyStencilId = FALLBACK_EMPTY_ID,
    backStencilId = FALLBACK_BACK_ID,
    placeholderFogColor = LookApplier.HexToColor("#C9C2B4", Color(0.79, 0.76, 0.71, 1)),
}

LevelCatalog.WHITEBOX_PATH = LevelCatalog.CONFIG.whiteboxPath
LevelCatalog.LEVEL_1_1_PATH = "Levels/level-1-1.json"
LevelCatalog.LEVEL_1_2_PATH = "Levels/level-1-2.json"
LevelCatalog.LEVEL_1_3_PATH = "Levels/level-1-3.json"
LevelCatalog.LEVEL_2_1_PATH = "Levels/level-2-1.json"
LevelCatalog.LEVEL_2_2_PATH = "Levels/level-2-2.json"
LevelCatalog.LEVEL_2_3_PATH = "Levels/level-2-3.json"
LevelCatalog.LEVEL_2_4_PATH = "Levels/level-2-4.json"
LevelCatalog.LEVEL_3_1_PATH = "Levels/level-3-1.json"
LevelCatalog.LEVEL_3_2_PATH = "Levels/level-3-2.json"
LevelCatalog.LEVEL_3_3_PATH = "Levels/level-3-3.json"
LevelCatalog.LEVEL_3_4_PATH = "Levels/level-3-4.json"
LevelCatalog.LEVEL_4_1_PATH = "Levels/level-4-1.json"
LevelCatalog.LEVEL_4_2_PATH = "Levels/level-4-2.json"
LevelCatalog.LEVEL_4_3_PATH = "Levels/level-4-3.json"
LevelCatalog.LEVEL_4_4_PATH = "Levels/level-4-4.json"
LevelCatalog.LEVEL_5_1_PATH = "Levels/level-5-1.json"

local function Repeat(t, length)
    if length <= 0 then
        return 0
    end
    return ((t % length) + length) % length
end

local function ToInt(value, fallback)
    local number = tonumber(value)
    if not number then
        return fallback
    end
    return math.floor(number + 0.5)
end

local function DecodeJsonText(json, source)
    local ok, data = pcall(cjson.decode, json)
    if ok and type(data) == "table" then
        return data
    end
    print("LevelCatalog: decode failed " .. source .. " " .. tostring(data))
    return nil
end

local function ReadJsonFile(path)
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        return nil
    end
    local json = file:ReadString()
    file:Close()
    return DecodeJsonText(json, path)
end

local function LoadConfigJson()
    local resolved = CONFIG_PATH
    local uuidPathOk, uuidPath = pcall(function()
        return cache:GetResUuidPath(CONFIG_PATH)
    end)
    if uuidPathOk and type(uuidPath) == "string" and uuidPath ~= "" then
        resolved = uuidPath
        print("LevelCatalog: uuid path " .. CONFIG_PATH .. " -> " .. uuidPath)
    end
    local jsonFile = cache:GetResource("JSONFile", resolved) --[[@as JSONFile?]]
    if jsonFile then
        local json = jsonFile:ToString()
        local data = DecodeJsonText(json, "JSONFile:" .. CONFIG_PATH)
        if data then
            print("LevelCatalog: loaded JSONFile " .. CONFIG_PATH)
            return data
        end
    end
    if fileSystem:FileExists(CONFIG_PATH) then
        local data = ReadJsonFile(CONFIG_PATH)
        if data then
            print("LevelCatalog: loaded File " .. CONFIG_PATH)
            return data
        end
    end
    print("LevelCatalog: missing " .. CONFIG_PATH)
    return nil
end

local function BuildCatalog(config)
    LevelCatalog.LEVELS = {}
    local chapters = config.chapters
    if type(chapters) ~= "table" then
        print("LevelCatalog: chapters missing")
        return
    end
    local index = 1
    for chapterOrder = 1, #chapters do
        local chapter = chapters[chapterOrder]
        if type(chapter) == "table" then
            local chapterId = math.max(1, ToInt(chapter.id, chapterOrder))
            local label = tostring(chapter.label or chapterId)
            local title = tostring(chapter.title or "")
            local stencilId = ToInt(chapter.stencilId, chapterId - 1)
            local stages = chapter.stages
            if type(stages) == "table" then
                for stage = 1, #stages do
                    local stageInfo = stages[stage]
                    if type(stageInfo) == "table" then
                        local code = string.format("%d-%d", chapterId, stage)
                        local path = type(stageInfo.sourcePath) == "string" and stageInfo.sourcePath or ""
                        local stageName = tostring(stageInfo.name or "占位")
                        local fogHex = type(stageInfo.fogColor) == "string" and stageInfo.fogColor or nil
                        ---@type LevelDefinition
                        local definition = {
                            id = string.format("ch%d_%d", chapterId, stage),
                            index = index,
                            chapter = chapterId,
                            code = code,
                            chapterLabel = label,
                            chapterTitle = title,
                            stageName = stageName,
                            title = string.format("%s %s", code, stageName),
                            subtitle = string.format("第%s章 · %s", label, title),
                            sourcePath = path,
                            stencilId = stencilId,
                            fogColor = LookApplier.HexToColor(fogHex, LevelCatalog.CONFIG.placeholderFogColor),
                            placeholder = path == "",
                        }
                        LevelCatalog.LEVELS[index] = definition
                        index = index + 1
                    end
                end
            end
        end
    end
    print("LevelCatalog: built " .. tostring(#LevelCatalog.LEVELS) .. " levels")
end

local function ApplyConfig(config)
    config = config or {}
    LevelCatalog.CONFIG.whiteboxPath = type(config.whiteboxPath) == "string" and config.whiteboxPath or "Levels/whitebox-level.json"
    LevelCatalog.CONFIG.emptyStencilId = ToInt(config.emptyStencilId, FALLBACK_EMPTY_ID)
    LevelCatalog.CONFIG.backStencilId = ToInt(config.backStencilId, FALLBACK_BACK_ID)
    LevelCatalog.CONFIG.placeholderFogColor = LookApplier.HexToColor(
        config.placeholderFogColor,
        LookApplier.HexToColor("#C9C2B4", Color(0.79, 0.76, 0.71, 1))
    )
    LevelCatalog.WHITEBOX_PATH = LevelCatalog.CONFIG.whiteboxPath
    BuildCatalog(config)
end

ApplyConfig(LoadConfigJson() or FALLBACK_CONFIG)

function LevelCatalog.GetAll()
    return LevelCatalog.LEVELS
end

function LevelCatalog.GetById(id)
    for _, definition in ipairs(LevelCatalog.LEVELS) do
        if definition.id == id then
            return definition
        end
    end
    return nil
end

function LevelCatalog.GetByIndex(index)
    if type(index) ~= "number" then
        return nil
    end
    local count = #LevelCatalog.LEVELS
    if count <= 0 then
        return nil
    end
    return LevelCatalog.LEVELS[Repeat(index - 1, count) + 1]
end

function LevelCatalog.GetChapter(definition)
    if not definition then
        return 0
    end
    return math.max(1, ToInt(definition.chapter, 1))
end

function LevelCatalog.GetStencilId(definition)
    if not definition then
        return LevelCatalog.CONFIG.emptyStencilId
    end
    return ToInt(definition.stencilId, LevelCatalog.CONFIG.emptyStencilId)
end

function LevelCatalog.GetEmptyColor()
    return StencilIdColor.ToColor(LevelCatalog.CONFIG.emptyStencilId)
end

function LevelCatalog.GetBackColor()
    return StencilIdColor.ToColor(LevelCatalog.CONFIG.backStencilId)
end

function LevelCatalog.GetColor(definition)
    return StencilIdColor.ToColor(LevelCatalog.GetStencilId(definition))
end

-- 循环三格窗口。centerIndex 为 1-based 正面关卡号。
function LevelCatalog.GetWindow(centerIndex)
    local left = LevelCatalog.GetByIndex(centerIndex - 1)
    local center = LevelCatalog.GetByIndex(centerIndex)
    local right = LevelCatalog.GetByIndex(centerIndex + 1)
    return { left, center, right }
end

function LevelCatalog.GetNext(id)
    local current = LevelCatalog.GetById(id)
    if not current then
        return nil
    end
    for _, definition in ipairs(LevelCatalog.LEVELS) do
        if definition.index > current.index and not definition.placeholder and definition.sourcePath ~= "" then
            return definition
        end
    end
    return nil
end

function LevelCatalog.IsPlayable(definition)
    if not definition then
        return false
    end
    if definition.placeholder then
        return false
    end
    return type(definition.sourcePath) == "string" and definition.sourcePath ~= ""
end

function LevelCatalog.GetFogColor(definition, fallback)
    fallback = fallback or LevelCatalog.CONFIG.placeholderFogColor
    if not definition then
        return fallback
    end
    return definition.fogColor or fallback
end

-- 只读内置关卡 JSON。失败不写盘，调用方再决定是否回退白模。
function LevelCatalog.ReadSourceJson(path)
    if type(path) ~= "string" or path == "" then
        return nil, "empty level path"
    end
    local resolved = path
    local uuidPathOk, uuidPath = pcall(function()
        return cache:GetResUuidPath(path)
    end)
    if uuidPathOk and type(uuidPath) == "string" and uuidPath ~= "" then
        resolved = uuidPath
        print("LevelCatalog: uuid path " .. path .. " -> " .. uuidPath)
    end
    local jsonFile = cache:GetResource("JSONFile", resolved) --[[@as JSONFile?]]
    if jsonFile then
        local json = jsonFile:ToString()
        if type(json) == "string" and json ~= "" then
            print("LevelCatalog: loaded JSONFile " .. path)
            return json
        end
    end
    if fileSystem:FileExists(path) then
        local file = File(path, FILE_READ)
        if file and file:IsOpen() then
            local json = file:ReadString()
            file:Close()
            if type(json) == "string" and json ~= "" then
                print("LevelCatalog: loaded File " .. path)
                return json
            end
        end
    end
    return nil, "cannot open level json: " .. tostring(path)
end

return LevelCatalog
