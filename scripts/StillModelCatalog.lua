-- 静物模型资产目录。
-- sidecar 描述模型、分槽 shader、Inspector 字段和 driver。
-- 关卡实例只存 modelId 和覆盖值，不复制整份资产。

local LookApplier = require "LookApplier"

local StillModelCatalog = {}

local CATALOG_DIR = "StillModels/"
-- Preview 打包后 JSON 会变成 UUID 文件名，ScanDir/FileExists 扫不到原路径。
-- 已知 sidecar 必须走 ResourceCache，才能解析到 uuid://StillModelDoorSidecar01。
local KNOWN_SIDECARS = {
    "StillModels/Door.json",
    "StillModels/StaticDoor.json",
    "StillModels/Algernon.json",
    "StillModels/StillCube.json",
    "StillModels/StillCapsule.json",
    "StillModels/StillCylinder.json",
    "StillModels/StillTriPrism.json",
}
local cached_ = nil

local function CopyTable(value)
    if type(value) ~= "table" then
        return value
    end
    local result = {}
    for key, item in pairs(value) do
        result[key] = CopyTable(item)
    end
    return result
end

local function NormalizeHex(value, fallback)
    return LookApplier.NormalizeHex(value, fallback or "#FFFFFF")
end

local function NormalizeId(value)
    if type(value) ~= "string" then
        return ""
    end
    return value
end

local function NormalizeOp(value)
    if value == ">" or value == ">=" or value == "<" or value == "<=" or value == "==" or value == "~=" then
        return value
    end
    return ">"
end

local function NormalizeVisibleWhen(source)
    if type(source) ~= "table" or type(source.driver) ~= "string" or source.driver == "" then
        return nil
    end
    return {
        driver = source.driver,
        op = NormalizeOp(source.op),
        value = (tonumber(source.value) or 0.0) * 1.0,
    }
end

local function NormalizePass(source)
    source = source or {}
    return {
        cullFront = source.cullFront == true,
        additive = source.additive == true,
        fadeUseObjectY = source.fadeUseObjectY == true,
        vFade = math.max(0.0, math.min(1.0, (tonumber(source.vFade) or 0.0) * 1.0)),
        opaque = source.opaque == true,
    }
end

local function NormalizeSlotParams(shader, source)
    source = source or {}
    if shader == LookApplier.SHADER_STILL_OBJECT_UNLIT then
        local albedoMap = type(source.albedoMap) == "string" and source.albedoMap or ""
        return {
            color = NormalizeHex(source.color or source.baseColor, "#FFE14A"),
            albedoMap = albedoMap,
        }
    end
    return {
        colorNeg = NormalizeHex(source.colorNeg, "#A98F80"),
        colorMid = NormalizeHex(source.colorMid, "#CDBBA3"),
        colorPos = NormalizeHex(source.colorPos, "#F1E6C2"),
        lightAxis = {
            x = tonumber((source.lightAxis or {}).x) or 0.35,
            y = tonumber((source.lightAxis or {}).y) or 1.0,
            z = tonumber((source.lightAxis or {}).z) or 0.25,
        },
    }
end

local function NormalizeShader(value)
    if value == LookApplier.SHADER_STILL_OBJECT_UNLIT then
        return LookApplier.SHADER_STILL_OBJECT_UNLIT
    end
    return LookApplier.SHADER_STILL_OBJECT_BASE
end

local function NormalizeSlot(source, fallbackIndex)
    source = source or {}
    local id = NormalizeId(source.id)
    if id == "" then
        id = "slot_" .. tostring(fallbackIndex)
    end
    local shader = NormalizeShader(source.shader)
    local index = math.floor(tonumber(source.index) or fallbackIndex)
    return {
        index = index,
        id = id,
        label = type(source.label) == "string" and source.label or id,
        shader = shader,
        params = NormalizeSlotParams(shader, source.params),
        pass = NormalizePass(source.pass),
        visibleWhen = NormalizeVisibleWhen(source.visibleWhen),
    }
end

local function NormalizeInspect(source, slots)
    local known = {}
    for _, slot in ipairs(slots) do
        known["slots." .. slot.id] = slot
    end
    local result = {}
    for _, item in ipairs(source or {}) do
        if type(item) == "table" and type(item.path) == "string" then
            local slotId, field = item.path:match("^slots%.([%w_]+)%.([%w_]+)$")
            local slot = slotId and known["slots." .. slotId] or nil
            if slot and type(field) == "string" and slot.params[field] ~= nil and type(slot.params[field]) == "string" and field ~= "albedoMap" then
                result[#result + 1] = {
                    path = "slots." .. slotId .. "." .. field,
                    label = type(item.label) == "string" and item.label or (slot.label .. " " .. field),
                    type = item.type == "color" and "color" or "color",
                    slotId = slotId,
                    field = field,
                }
            end
        end
    end
    return result
end

local function NormalizeDriver(source)
    source = source or {}
    local id = NormalizeId(source.id)
    if id == "" then
        return nil
    end
    local range = source.range or { 0, 1 }
    local minValue = (tonumber(range[1]) or 0.0) * 1.0
    local maxValue = (tonumber(range[2]) or 1.0) * 1.0
    if maxValue < minValue then
        minValue, maxValue = maxValue, minValue
    end
    local axis = source.axis
    if axis ~= "X" and axis ~= "Y" and axis ~= "Z" then
        axis = "Y"
    end
    return {
        id = id,
        label = type(source.label) == "string" and source.label or id,
        type = source.type == "animationTime" and "animationTime" or "boneTranslate",
        bone = type(source.bone) == "string" and source.bone or "",
        animation = type(source.animation) == "string" and source.animation or "",
        axis = axis,
        distance = (tonumber(source.distance) or 0.0) * 1.0,
        min = minValue,
        max = maxValue,
    }
end

local function NormalizeAsset(source, fallbackId)
    source = source or {}
    local id = NormalizeId(source.id)
    if id == "" then
        id = fallbackId
    end
    local builder = type(source.builder) == "string" and source.builder or ""
    local modelPath = type(source.modelPath) == "string" and source.modelPath or ""
    if id == "" or (modelPath == "" and builder == "") then
        return nil
    end
    local slots = {}
    for index, item in ipairs(source.slots or {}) do
        slots[#slots + 1] = NormalizeSlot(item, index - 1)
    end
    local drivers = {}
    for _, item in ipairs(source.drivers or {}) do
        local driver = NormalizeDriver(item)
        if driver then
            drivers[#drivers + 1] = driver
        end
    end
    local rootRotation = source.rootRotation or {}
    local rootOffset = source.rootOffset or {}
    local rootScale = source.rootScale or {}
    local bounds = nil
    if type(source.bounds) == "table" and type(source.bounds.min) == "table" and type(source.bounds.max) == "table" then
        bounds = {
            min = {
                x = tonumber(source.bounds.min.x) or 0.0,
                y = tonumber(source.bounds.min.y) or 0.0,
                z = tonumber(source.bounds.min.z) or 0.0,
            },
            max = {
                x = tonumber(source.bounds.max.x) or 0.0,
                y = tonumber(source.bounds.max.y) or 0.0,
                z = tonumber(source.bounds.max.z) or 0.0,
            },
        }
    end
    return {
        id = id,
        label = type(source.label) == "string" and source.label or id,
        builder = builder,
        modelPath = modelPath,
        component = source.component == "AnimatedModel" and "AnimatedModel" or "StaticModel",
        bounds = bounds,
        rootRotation = {
            x = tonumber(rootRotation.x) or 0.0,
            y = tonumber(rootRotation.y) or 0.0,
            z = tonumber(rootRotation.z) or 0.0,
        },
        rootOffset = {
            x = tonumber(rootOffset.x) or 0.0,
            y = tonumber(rootOffset.y) or 0.0,
            z = tonumber(rootOffset.z) or 0.0,
        },
        rootScale = {
            x = tonumber(rootScale.x) or 1.0,
            y = tonumber(rootScale.y) or 1.0,
            z = tonumber(rootScale.z) or 1.0,
        },
        slots = slots,
        inspect = NormalizeInspect(source.inspect, slots),
        drivers = drivers,
    }
end

local function DecodeJsonText(json, source)
    local ok, data = pcall(cjson.decode, json)
    if ok and type(data) == "table" then
        return data
    end
    print("StillModelCatalog: decode failed " .. source .. " " .. tostring(data))
    return nil
end

local function ReadJsonFile(path)
    local file = File(path, FILE_READ)
    if not file or not file:IsOpen() then
        print("StillModelCatalog: cannot open " .. path)
        return nil
    end
    local json = file:ReadString()
    file:Close()
    return DecodeJsonText(json, path)
end

local function LoadJson(path)
    -- Preview 打包后原路径不存在，先让 ResourceCache 解析 uuid:// 再读真实文件。
    local resolved = path
    local uuidPathOk, uuidPath = pcall(function()
        return cache:GetResUuidPath(path)
    end)
    if uuidPathOk and type(uuidPath) == "string" and uuidPath ~= "" then
        resolved = uuidPath
        print("StillModelCatalog: uuid path " .. path .. " -> " .. uuidPath)
    end
    local jsonFile = cache:GetResource("JSONFile", resolved)
    if jsonFile then
        local json = jsonFile:ToString()
        local data = DecodeJsonText(json, "JSONFile:" .. path)
        if data then
            print("StillModelCatalog: loaded JSONFile " .. path)
            return data
        end
    end
    if fileSystem:FileExists(path) then
        local data = ReadJsonFile(path)
        if data then
            print("StillModelCatalog: loaded File " .. path)
            return data
        end
    else
        print("StillModelCatalog: missing File " .. path)
    end
    return nil
end

local function CollectSidecarPaths()
    local paths = {}
    local seen = {}
    local function AddPath(path)
        if type(path) == "string" and path ~= "" and not seen[path] then
            seen[path] = true
            paths[#paths + 1] = path
        end
    end
    for _, path in ipairs(KNOWN_SIDECARS) do
        AddPath(path)
    end
    local names = fileSystem:ScanDir(CATALOG_DIR, "*.json", SCAN_FILES, false) or {}
    for _, name in ipairs(names) do
        AddPath(CATALOG_DIR .. name)
    end
    table.sort(paths)
    return paths
end

function StillModelCatalog.Load(force)
    if cached_ and not force then
        return cached_
    end
    local assets = {}
    local order = {}
    for _, path in ipairs(CollectSidecarPaths()) do
        local data = LoadJson(path)
        local idFromFile = path:match("([^/]+)%.json$") or ""
        local asset = data and NormalizeAsset(data, idFromFile) or nil
        if asset and not assets[asset.id] then
            assets[asset.id] = asset
            order[#order + 1] = asset.id
            print("StillModelCatalog: loaded " .. asset.id .. " from " .. path)
        elseif not asset then
            print("StillModelCatalog: skipped " .. path)
        end
    end
    cached_ = { assets = assets, order = order }
    print(string.format("StillModelCatalog: %d assets", #order))
    return cached_
end

function StillModelCatalog.Get(id)
    if type(id) ~= "string" or id == "" then
        return nil
    end
    return StillModelCatalog.Load().assets[id]
end

function StillModelCatalog.List()
    local catalog = StillModelCatalog.Load()
    local result = {}
    for _, id in ipairs(catalog.order) do
        result[#result + 1] = catalog.assets[id]
    end
    return result
end

function StillModelCatalog.Options()
    local options = { { value = "", label = "未绑定模型（Box）" } }
    for _, asset in ipairs(StillModelCatalog.List()) do
        options[#options + 1] = { value = asset.id, label = asset.label }
    end
    return options
end

function StillModelCatalog.GetSlot(asset, slotId)
    if not asset then
        return nil
    end
    for _, slot in ipairs(asset.slots) do
        if slot.id == slotId then
            return slot
        end
    end
    return nil
end

function StillModelCatalog.GetDriver(asset, driverId)
    if not asset then
        return nil
    end
    for _, driver in ipairs(asset.drivers) do
        if driver.id == driverId then
            return driver
        end
    end
    return nil
end

function StillModelCatalog.DefaultParams(asset)
    local params = {}
    if not asset then
        return params
    end
    for _, slot in ipairs(asset.slots) do
        for field, value in pairs(slot.params) do
            if type(value) ~= "table" then
                params["slots." .. slot.id .. "." .. field] = value
            end
        end
    end
    return params
end

function StillModelCatalog.DefaultDrivers(asset)
    local drivers = {}
    if not asset then
        return drivers
    end
    for _, driver in ipairs(asset.drivers) do
        drivers[driver.id] = driver.min
    end
    return drivers
end

function StillModelCatalog.ResolveParam(asset, overrides, path)
    if type(overrides) == "table" and overrides[path] ~= nil then
        return overrides[path]
    end
    local slotId, field = tostring(path or ""):match("^slots%.([%w_]+)%.([%w_]+)$")
    local slot = StillModelCatalog.GetSlot(asset, slotId)
    if slot and field then
        return slot.params[field]
    end
    return nil
end

function StillModelCatalog.SlotLook(asset, slot, overrides)
    slot = slot or {}
    local look = CopyTable(slot.params) or {}
    local pass = slot.pass or {}
    look.cullFront = pass.cullFront == true
    look.additive = pass.additive == true
    look.fadeUseObjectY = pass.fadeUseObjectY == true
    look.vFade = pass.vFade or 0.0
    look.opaque = pass.opaque == true
    if asset then
        for field, _ in pairs(slot.params or {}) do
            local path = "slots." .. slot.id .. "." .. field
            local value = StillModelCatalog.ResolveParam(asset, overrides, path)
            if value ~= nil then
                look[field] = value
            end
        end
    end
    return look
end

function StillModelCatalog.CopyTable(value)
    return CopyTable(value)
end

return StillModelCatalog
