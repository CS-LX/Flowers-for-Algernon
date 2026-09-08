-- 选关页章节模型簇。
-- 只消费章节号和进出事件，自己管节点、高度雾材质和升降 tween。
-- 不读 MenuPrism 内部状态，不挂到棱柱根上。

local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"
local StillModelCatalog = require "StillModelCatalog"
local LookApplier = require "LookApplier"
local MenuClusterCatalog = require "MenuClusterCatalog"

---@class MenuClusterLayer
---@field id string
---@field node Node
---@field restY number
---@field look table
---@field entries table[]
---@field tween {duration: number, clock: number, fromY: number, toY: number, remove: boolean}|nil

---@class MenuClusterBackdrop
---@field scene Scene
---@field root Node|nil
---@field layers table<string, MenuClusterLayer>
---@field currentChapter number|nil
---@field fogClear number
---@field fogSolid number
---@field fogColor Color|nil
local MenuClusterBackdrop = {}
MenuClusterBackdrop.__index = MenuClusterBackdrop

local WORLD_BIT = 2
local REST_Y = -1.45
local TRAVEL = 3.6
local SWITCH_DURATION = 0.85
local EXIT_DURATION = 0.85
-- 对齐后的包围盒底。高度雾用验收过的世界高度。
local ALIGNED_FOOT_Y = -1.70
local FOG_HEIGHT_A = 0.80
local FOG_HEIGHT_B = 0.00

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

-- 下落 t^3 由慢到快；升起 1-(1-t)^3 由快到慢。
local function EaseInCubic(t)
    return t * t * t
end

local function EaseOutCubic(t)
    local inv = 1.0 - t
    return 1.0 - inv * inv * inv
end

local function ChapterKey(chapter)
    return "chapter_" .. tostring(chapter)
end

function MenuClusterBackdrop.New(scene)
    local self = setmetatable({}, MenuClusterBackdrop)
    self.scene = scene
    ---@type Node|nil
    self.root = nil
    ---@type table<string, MenuClusterLayer>
    self.layers = {}
    ---@type number|nil
    self.currentChapter = nil
    self.fogClear = FOG_HEIGHT_A
    self.fogSolid = FOG_HEIGHT_B
    ---@type Color|nil
    self.fogColor = nil
    return self
end

function MenuClusterBackdrop:EnsureRoot()
    if self.root or not self.scene then
        return self.root
    end
    self.root = self.scene:CreateChild("MenuClusterRoot")
    self.root.position = Vector3(0.0, 0.0, 0.0)
    return self.root
end

function MenuClusterBackdrop:ModelFootY(asset)
    if not asset or not asset.modelPath or asset.modelPath == "" then
        return 0.0
    end
    local resource = cache:GetResource("Model", asset.modelPath)
    if not resource then
        return 0.0
    end
    local minY = resource.boundingBox.min.y
    local offsetY = asset.rootOffset and asset.rootOffset.y or 0.0
    local scaleY = asset.rootScale and asset.rootScale.y or 1.0
    return offsetY + minY * scaleY
end

function MenuClusterBackdrop:ResolveFogColor(look)
    if self.fogColor then
        return self.fogColor
    end
    return LookApplier.HexToColor(look and look["slots.wall.fogColor"], Color(0.204, 0.541, 0.639, 1))
end

function MenuClusterBackdrop:ApplyFogToEntry(entry, look, fogClear, fogSolid)
    if not entry or not entry.model or not entry.asset then
        return
    end
    local fogColor = self:ResolveFogColor(look)
    for _, slot in ipairs(entry.asset.slots) do
        local material = entry.slotMaterials and entry.slotMaterials[slot.id]
        if material then
            material:SetShaderParameter("color_neg", Variant(LookApplier.HexToColor(look["slots.wall.colorNeg"], Color(0.169, 0.435, 0.659, 1))))
            material:SetShaderParameter("color_mid", Variant(LookApplier.HexToColor(look["slots.wall.colorMid"], Color(0.494, 0.718, 0.902, 1))))
            material:SetShaderParameter("color_pos", Variant(LookApplier.HexToColor(look["slots.wall.colorPos"], Color(1.0, 0.957, 0.910, 1))))
            material:SetShaderParameter("fog_color", Variant(fogColor))
            material:SetShaderParameter("fog_height_a", Variant(fogClear))
            material:SetShaderParameter("fog_height_b", Variant(fogSolid))
            material:SetShaderParameter("grade_saturation", Variant(tonumber(look["slots.wall.gradeSaturation"]) or 0.55))
            material:SetShaderParameter("grade_value", Variant(tonumber(look["slots.wall.gradeValue"]) or 1.08))
            material:SetShaderParameter("grade_contrast", Variant(tonumber(look["slots.wall.gradeContrast"]) or 0.72))
            material:SetShaderParameter("grade_haze", Variant(tonumber(look["slots.wall.gradeHaze"]) or 0.22))
        end
    end
end

function MenuClusterBackdrop:SetFogColor(color)
    if not color then
        return
    end
    self.fogColor = color
    for _, layer in pairs(self.layers) do
        for _, bound in ipairs(layer.entries or {}) do
            local entry = bound.entry
            if entry and entry.slotMaterials then
                for _, material in pairs(entry.slotMaterials) do
                    material:SetShaderParameter("fog_color", Variant(color))
                end
            end
        end
    end
end

function MenuClusterBackdrop:BindItem(parent, item, look)
    local asset = StillModelCatalog.Get(item.modelId)
    if not asset then
        print("MenuClusterBackdrop: unknown modelId " .. tostring(item.modelId))
        return nil
    end
    local scale = item.scale or 1.0
    local localFoot = self:ModelFootY(asset)
    local holderY = ALIGNED_FOOT_Y - REST_Y - localFoot * scale
    local object = StillObject.New({
        id = item.id,
        name = item.id,
        modelId = item.modelId,
        params = look,
        paramStore = {
            [item.modelId] = look,
        },
        transform = {
            position = { x = item.x, y = holderY, z = item.z },
            rotation = { x = 0.0, y = item.yaw, z = 0.0 },
            scale = { x = scale, y = scale, z = scale },
        },
    })
    local holder = parent:CreateChild("ClusterItem_" .. item.id)
    holder.position = Vector3(item.x, holderY, item.z)
    holder.rotation = Quaternion(item.yaw, Vector3.UP)
    holder.scale = Vector3(scale, scale, scale)
    local entry = StillObjectRuntime.Bind(holder, object)
    if not entry or not entry.model then
        print("MenuClusterBackdrop: bind failed " .. tostring(item.modelId))
        holder:Remove()
        return nil
    end
    entry.model.viewMask = WORLD_BIT
    entry.model.castShadows = false
    return { holder = holder, entry = entry, item = item }
end

function MenuClusterBackdrop:SpawnLayer(chapter, definition, y)
    local root = self:EnsureRoot()
    if not root then
        return nil
    end
    local key = ChapterKey(chapter)
    if self.layers[key] then
        return self.layers[key]
    end
    local node = root:CreateChild("MenuCluster_" .. definition.id)
    -- 高度雾按世界 Y。先放在静止高度绑定，再按真实 world AABB 写雾。
    node.position = Vector3(0.0, REST_Y, 0.0)
    local spawned = {}
    for _, item in ipairs(definition.items) do
        local bound = self:BindItem(node, item, definition.look)
        if bound then
            spawned[#spawned + 1] = bound
        end
    end
    self.fogClear = FOG_HEIGHT_A
    self.fogSolid = FOG_HEIGHT_B
    for _, bound in ipairs(spawned) do
        local box = bound.entry.model.worldBoundingBox
        self:ApplyFogToEntry(bound.entry, definition.look, self.fogClear, self.fogSolid)
        print(string.format(
            "MenuClusterBackdrop: %s worldFoot=%.3f worldTop=%.3f fogA=%.3f fogB=%.3f",
            bound.item.modelId,
            box.min.y,
            box.max.y,
            self.fogClear,
            self.fogSolid
        ))
    end
    node.position = Vector3(0.0, y, 0.0)
    local layer = {
        id = definition.id,
        node = node,
        restY = REST_Y,
        look = definition.look,
        entries = spawned,
        tween = nil,
    }
    self.layers[key] = layer
    print(string.format(
        "MenuClusterBackdrop: spawn %s chapter=%s items=%d y=%.3f",
        definition.id,
        tostring(chapter),
        #spawned,
        y
    ))
    return layer
end

function MenuClusterBackdrop:StartTween(layer, fromY, toY, duration, remove)
    if not layer or not layer.node then
        return
    end
    layer.node.position = Vector3(0.0, fromY, 0.0)
    layer.tween = {
        duration = duration,
        clock = 0.0,
        fromY = fromY,
        toY = toY,
        remove = remove == true,
    }
end

function MenuClusterBackdrop:RemoveLayer(key)
    local layer = self.layers[key]
    if not layer then
        return
    end
    if layer.node then
        layer.node:Remove()
    end
    self.layers[key] = nil
end

function MenuClusterBackdrop:SetChapter(chapter, instant)
    local number = tonumber(chapter)
    if not number then
        self:HideCurrent(instant)
        self.currentChapter = nil
        return
    end
    number = math.floor(number + 0.5)
    if self.currentChapter == number then
        local current = self.layers[ChapterKey(number)]
        if current and not current.tween then
            return
        end
    end
    local definition = MenuClusterCatalog.Get(number)
    local previous = self.currentChapter
    self.currentChapter = number
    if previous and previous ~= number then
        local oldLayer = self.layers[ChapterKey(previous)]
        if oldLayer then
            local fromY = oldLayer.node and oldLayer.node.position.y or REST_Y
            if instant then
                self:RemoveLayer(ChapterKey(previous))
            else
                self:StartTween(oldLayer, fromY, fromY - TRAVEL, SWITCH_DURATION, true)
            end
        end
    end
    if not definition then
        print("MenuClusterBackdrop: no cluster for chapter " .. tostring(number))
        return
    end
    local layer = self.layers[ChapterKey(number)] or self:SpawnLayer(number, definition, REST_Y - TRAVEL)
    if not layer then
        return
    end
    if instant then
        layer.tween = nil
        layer.node.position = Vector3(0.0, REST_Y, 0.0)
        print("MenuClusterBackdrop: show " .. definition.id .. " instant")
        return
    end
    if previous == number then
        return
    end
    self:StartTween(layer, REST_Y - TRAVEL, REST_Y, SWITCH_DURATION, false)
    print("MenuClusterBackdrop: rise " .. definition.id)
end

function MenuClusterBackdrop:HideCurrent(instant)
    for key, layer in pairs(self.layers) do
        local fromY = layer.node and layer.node.position.y or REST_Y
        if instant then
            self:RemoveLayer(key)
        else
            self:StartTween(layer, fromY, fromY - TRAVEL, SWITCH_DURATION, true)
        end
    end
    self.currentChapter = nil
end

function MenuClusterBackdrop:BeginExitDrop()
    for _, layer in pairs(self.layers) do
        local fromY = layer.node and layer.node.position.y or REST_Y
        self:StartTween(layer, fromY, REST_Y - TRAVEL, EXIT_DURATION, false)
    end
    print("MenuClusterBackdrop: exit drop")
end

function MenuClusterBackdrop:BeginEnterRise(chapter)
    local number = tonumber(chapter)
    if not number then
        self:HideCurrent(false)
        return
    end
    number = math.floor(number + 0.5)
    self.currentChapter = number
    local definition = MenuClusterCatalog.Get(number)
    if not definition then
        print("MenuClusterBackdrop: enter rise has no cluster chapter=" .. tostring(number))
        return
    end
    local layer = self.layers[ChapterKey(number)] or self:SpawnLayer(number, definition, REST_Y - TRAVEL)
    if not layer then
        return
    end
    self:StartTween(layer, REST_Y - TRAVEL, REST_Y, EXIT_DURATION, false)
    print("MenuClusterBackdrop: enter rise chapter=" .. tostring(chapter))
end

function MenuClusterBackdrop:Update(timeStep)
    local finished = {}
    for key, layer in pairs(self.layers) do
        local tween = layer.tween
        if tween and layer.node then
            tween.clock = tween.clock + timeStep
            local t = Clamp01(tween.clock / tween.duration)
            local eased
            if tween.toY < tween.fromY then
                eased = EaseInCubic(t)
            else
                eased = EaseOutCubic(t)
            end
            local y = tween.fromY + (tween.toY - tween.fromY) * eased
            local pos = layer.node.position
            layer.node.position = Vector3(pos.x, y, pos.z)
            if t >= 1.0 then
                layer.tween = nil
                if tween.remove then
                    finished[#finished + 1] = key
                end
            end
        end
    end
    for _, key in ipairs(finished) do
        self:RemoveLayer(key)
    end
end

function MenuClusterBackdrop:Destroy()
    if self.root then
        self.root:Remove()
        self.root = nil
    end
    self.layers = {}
    self.currentChapter = nil
    self.fogClear = FOG_HEIGHT_A
    self.fogSolid = FOG_HEIGHT_B
    self.fogColor = nil
end

return MenuClusterBackdrop
