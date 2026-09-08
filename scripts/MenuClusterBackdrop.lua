-- 选关页章节模型簇。
-- 只消费章节号和进出事件，自己管节点、高度雾材质和升降 tween。
-- 不读 MenuPrism 内部状态，不挂到棱柱根上。

local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"
local StillModelCatalog = require "StillModelCatalog"
local LookApplier = require "LookApplier"
local MenuClusterCatalog = require "MenuClusterCatalog"
local VoxelRenderer = require "VoxelRenderer"
local TriPrismGrid = require "TriPrismGrid"

---@class MenuClusterLayer
---@field id string
---@field node Node
---@field restY number
---@field look table
---@field fog table
---@field entries table[]
---@field voxelMaterials Material[]
---@field tween {duration: number, clock: number, fromY: number, toY: number, remove: boolean}|nil

---@class MenuClusterBackdrop
---@field scene Scene
---@field root Node|nil
---@field layers table<string, MenuClusterLayer>
---@field currentChapter number|nil
---@field fogColor Color|nil
---@field fogColorTween {duration: number, clock: number, from: Color, to: Color}|nil
local MenuClusterBackdrop = {}
MenuClusterBackdrop.__index = MenuClusterBackdrop

local WORLD_BIT = 2
local REST_Y = -1.45
local TRAVEL = 3.6
local SWITCH_DURATION = 0.85
local EXIT_DURATION = 0.85
local FOG_TWEEN_DURATION = 0.45
-- 对齐后的包围盒底。高度雾按簇自己的 fog 表写，不再用全局高度。
local ALIGNED_FOOT_Y = -1.70
local DEFAULT_FOG = { heightA = 0.80, heightB = 0.00, color = "#348AA3" }

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

local function MixColor(fromColor, toColor, t)
    t = Clamp01(t)
    return Color(
        fromColor.r + (toColor.r - fromColor.r) * t,
        fromColor.g + (toColor.g - fromColor.g) * t,
        fromColor.b + (toColor.b - fromColor.b) * t,
        1.0
    )
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
    ---@type Color|nil
    self.fogColor = nil
    ---@type {duration: number, clock: number, from: Color, to: Color}|nil
    self.fogColorTween = nil
    return self
end

function MenuClusterBackdrop:FogOf(definition)
    local fog = (definition and definition.fog) or DEFAULT_FOG
    local look = definition and definition.look
    local color = fog.color
        or (look and look.fogColor)
        or (look and look["slots.wall.fogColor"])
        or DEFAULT_FOG.color
    return {
        heightA = tonumber(fog.heightA) or DEFAULT_FOG.heightA,
        heightB = tonumber(fog.heightB) or DEFAULT_FOG.heightB,
        color = color,
    }
end

function MenuClusterBackdrop:FogOfItem(item, fallback)
    fallback = fallback or DEFAULT_FOG
    local fog = (item and item.fog) or fallback
    return {
        heightA = tonumber(fog.heightA) or fallback.heightA,
        heightB = tonumber(fog.heightB) or fallback.heightB,
        color = fog.color or fallback.color,
    }
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

function MenuClusterBackdrop:ResolveFogColor(fog)
    if self.fogColor then
        return self.fogColor
    end
    return LookApplier.HexToColor(fog and fog.color, Color(0.204, 0.541, 0.639, 1))
end

function MenuClusterBackdrop:ApplyFogToEntry(entry, look, fog)
    if not entry or not entry.model or not entry.asset then
        return
    end
    fog = fog or DEFAULT_FOG
    look = look or {}
    local fogColor = self:ResolveFogColor(fog)
    local fogClear = fog.heightA
    local fogSolid = fog.heightB
    for _, slot in ipairs(entry.asset.slots) do
        local material = entry.slotMaterials and entry.slotMaterials[slot.id]
        if material and slot.shader ~= LookApplier.SHADER_STILL_OBJECT_SOURCE then
            local prefix = "slots." .. slot.id
            local colorNeg = look[prefix .. ".colorNeg"] or look["slots.wall.colorNeg"]
            local colorMid = look[prefix .. ".colorMid"] or look["slots.wall.colorMid"]
            local colorPos = look[prefix .. ".colorPos"] or look["slots.wall.colorPos"]
            if colorNeg then
                material:SetShaderParameter("color_neg", Variant(LookApplier.HexToColor(colorNeg, Color(0.169, 0.435, 0.659, 1))))
            end
            if colorMid then
                material:SetShaderParameter("color_mid", Variant(LookApplier.HexToColor(colorMid, Color(0.494, 0.718, 0.902, 1))))
            end
            if colorPos then
                material:SetShaderParameter("color_pos", Variant(LookApplier.HexToColor(colorPos, Color(1.0, 0.957, 0.910, 1))))
            end
            material:SetShaderParameter("fog_color", Variant(fogColor))
            material:SetShaderParameter("fog_height_a", Variant(fogClear))
            material:SetShaderParameter("fog_height_b", Variant(fogSolid))
            local saturation = look[prefix .. ".gradeSaturation"] or look["slots.wall.gradeSaturation"]
            local value = look[prefix .. ".gradeValue"] or look["slots.wall.gradeValue"]
            local contrast = look[prefix .. ".gradeContrast"] or look["slots.wall.gradeContrast"]
            local haze = look[prefix .. ".gradeHaze"] or look["slots.wall.gradeHaze"]
            if saturation then
                material:SetShaderParameter("grade_saturation", Variant(tonumber(saturation) or 0.55))
            end
            if value then
                material:SetShaderParameter("grade_value", Variant(tonumber(value) or 1.08))
            end
            if contrast then
                material:SetShaderParameter("grade_contrast", Variant(tonumber(contrast) or 0.72))
            end
            if haze then
                material:SetShaderParameter("grade_haze", Variant(tonumber(haze) or 0.22))
            end
        end
    end
end

function MenuClusterBackdrop:WriteFogColor(color)
    if not color then
        return
    end
    self.fogColor = color
    for _, layer in pairs(self.layers) do
        for _, bound in ipairs(layer.entries or {}) do
            local entry = bound.entry
            if entry and entry.slotMaterials and entry.asset then
                for _, slot in ipairs(entry.asset.slots) do
                    if slot.shader ~= LookApplier.SHADER_STILL_OBJECT_SOURCE then
                        local material = entry.slotMaterials[slot.id]
                        if material then
                            material:SetShaderParameter("fog_color", Variant(color))
                        end
                    end
                end
            end
            local voxelMaterial = bound.material
            if voxelMaterial then
                voxelMaterial:SetShaderParameter("fog_color", Variant(color))
            end
        end
        for _, material in ipairs(layer.voxelMaterials or {}) do
            material:SetShaderParameter("fog_color", Variant(color))
        end
    end
end

function MenuClusterBackdrop:SetFogColorNow(color)
    self.fogColorTween = nil
    self:WriteFogColor(color)
end

function MenuClusterBackdrop:TweenFogColorTo(color, instant)
    if not color then
        return
    end
    if instant or not self.fogColor then
        self:SetFogColorNow(color)
        return
    end
    self.fogColorTween = {
        duration = FOG_TWEEN_DURATION,
        clock = 0.0,
        from = Color(self.fogColor.r, self.fogColor.g, self.fogColor.b, 1.0),
        to = color,
    }
end

function MenuClusterBackdrop:FogColorOf(definition)
    local fog = self:FogOf(definition)
    return LookApplier.HexToColor(fog.color, Color(0.204, 0.541, 0.639, 1))
end

---@param material Material
---@param look table|nil
---@param fog table|nil
function MenuClusterBackdrop:ApplyVoxelFog(material, look, fog)
    if not material then
        return
    end
    if not look or look.shader ~= LookApplier.SHADER_TRI_PRISM_LOOK_HEIGHT_FOG then
        return
    end
    fog = fog or DEFAULT_FOG
    material:SetShaderParameter("fog_height_a", Variant(fog.heightA or DEFAULT_FOG.heightA))
    material:SetShaderParameter("fog_height_b", Variant(fog.heightB or DEFAULT_FOG.heightB))
    material:SetShaderParameter("fog_color", Variant(self:ResolveFogColor(fog)))
end

---@param parent Node
---@param stack table
---@param look table|nil
---@param fog table|nil
function MenuClusterBackdrop:BindVoxelStack(parent, stack, look, fog)
    local holder = parent:CreateChild("ClusterVoxel_" .. tostring(stack.id))
    holder.position = Vector3(stack.x, ALIGNED_FOOT_Y - REST_Y, stack.z)
    holder.rotation = Quaternion(stack.yaw or 0.0, Vector3.UP)
    holder.scale = Vector3(0.42, 0.42, 0.42)
    local material = LookApplier.CreatePartMaterial(look)
    self:ApplyVoxelFog(material, look, fog)
    local grid = TriPrismGrid.New(VoxelRenderer.DEFAULT_EDGE, VoxelRenderer.DEFAULT_HEIGHT)
    local spawned = 0
    for _, cell in ipairs(stack.cells or {}) do
        local source = {
            hexQ = cell.q,
            hexR = cell.r,
            sector = cell.s,
            layer = cell.l,
            rotation = 0,
            material = 1,
        }
        local center, rotation = grid:GetVoxelTransform(source)
        local node = VoxelRenderer.CreateVoxel(self.scene, center, Color(1, 1, 1, 1), {
            parent = holder,
            edgeLength = grid.edgeLength,
            height = grid.voxelHeight,
            rotation = rotation,
            name = string.format("Voxel_%s_%s_%s_%s", tostring(cell.q), tostring(cell.r), tostring(cell.s), tostring(cell.l)),
            material = material,
        })
        local drawable = node:GetComponent("CustomGeometry")
        if drawable then
            drawable.viewMask = WORLD_BIT
            drawable.castShadows = false
        end
        spawned = spawned + 1
    end
    print(string.format("MenuClusterBackdrop: voxel stack %s cells=%d", tostring(stack.id), spawned))
    return { holder = holder, material = material, item = stack }
end

function MenuClusterBackdrop:BindItem(parent, item, look)
    local asset = StillModelCatalog.Get(item.modelId)
    if not asset then
        print("MenuClusterBackdrop: unknown modelId " .. tostring(item.modelId))
        return nil
    end
    local scale = item.scale or 1.0
    local extraY = tonumber(item.y) or 0.0
    local localFoot = self:ModelFootY(asset)
    local holderY = ALIGNED_FOOT_Y - REST_Y - localFoot * scale + extraY
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
    if item.modelId == "monitor" then
        self:GradeSourceMonitor(entry, look)
    end
    return { holder = holder, entry = entry, item = item }
end

function MenuClusterBackdrop:GradeSourceMonitor(entry, look)
    if not entry or not entry.slotMaterials then
        return
    end
    local source = entry.slotMaterials.screen
    if not source then
        return
    end
    local material = source:Clone("MenuClusterMonitor")
    if not material then
        return
    end
    -- 选关背景是冷灰绿。克隆材质后压饱和、染雾色，只影响簇里的监视器。
    local fogHex = (look and look["slots.wall.fogColor"]) or "#102121"
    local fogColor = LookApplier.HexToColor(fogHex, Color(0.063, 0.129, 0.129, 1))
    local tint = Color(
        fogColor.r * 0.78 + 0.18,
        fogColor.g * 0.78 + 0.22,
        fogColor.b * 0.78 + 0.24,
        1.0
    )
    material:SetShaderParameter("MatDiffColor", Variant(tint))
    entry.slotMaterials.screen = material
    if entry.model then
        for _, slot in ipairs(entry.asset.slots) do
            if slot.id == "screen" then
                entry.model:SetMaterial(slot.index, material)
                break
            end
        end
    end
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
    local voxelMaterials = {}
    local fog = self:FogOf(definition)
    if definition.kind == "voxels" then
        for _, stack in ipairs(definition.stacks or {}) do
            local bound = self:BindVoxelStack(node, stack, definition.look, fog)
            if bound then
                spawned[#spawned + 1] = bound
                voxelMaterials[#voxelMaterials + 1] = bound.material
            end
        end
        print(string.format(
            "MenuClusterBackdrop: voxel fog A=%.3f B=%.3f color=%s",
            fog.heightA,
            fog.heightB,
            tostring(fog.color)
        ))
    else
        for _, item in ipairs(definition.items or {}) do
            local bound = self:BindItem(node, item, definition.look)
            if bound then
                spawned[#spawned + 1] = bound
            end
        end
        for _, bound in ipairs(spawned) do
            local box = bound.entry.model.worldBoundingBox
            local itemFog = self:FogOfItem(bound.item, fog)
            self:ApplyFogToEntry(bound.entry, definition.look, itemFog)
            print(string.format(
                "MenuClusterBackdrop: %s worldFoot=%.3f worldTop=%.3f fogA=%.3f fogB=%.3f",
                bound.item.modelId,
                box.min.y,
                box.max.y,
                itemFog.heightA,
                itemFog.heightB
            ))
        end
    end
    node.position = Vector3(0.0, y, 0.0)
    local layer = {
        id = definition.id,
        node = node,
        restY = REST_Y,
        look = definition.look,
        fog = fog,
        entries = spawned,
        voxelMaterials = voxelMaterials,
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
    self:TweenFogColorTo(self:FogColorOf(definition), instant)
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
        self:HideCurrent(true)
        return
    end
    number = math.floor(number + 0.5)
    local keep = ChapterKey(number)
    local stale = {}
    for key in pairs(self.layers) do
        if key ~= keep then
            stale[#stale + 1] = key
        end
    end
    for _, key in ipairs(stale) do
        self:RemoveLayer(key)
    end
    self.currentChapter = number
    local definition = MenuClusterCatalog.Get(number)
    if not definition then
        print("MenuClusterBackdrop: enter rise has no cluster chapter=" .. tostring(number))
        return
    end
    self:TweenFogColorTo(self:FogColorOf(definition), true)
    local layer = self.layers[keep] or self:SpawnLayer(number, definition, REST_Y - TRAVEL)
    if not layer then
        return
    end
    self:StartTween(layer, REST_Y - TRAVEL, REST_Y, EXIT_DURATION, false)
    print("MenuClusterBackdrop: enter rise chapter=" .. tostring(chapter))
end

function MenuClusterBackdrop:UpdateFogColorTween(timeStep)
    local tween = self.fogColorTween
    if not tween then
        return
    end
    tween.clock = tween.clock + timeStep
    local t = Clamp01(tween.clock / tween.duration)
    self:WriteFogColor(MixColor(tween.from, tween.to, t))
    if t >= 1.0 then
        self.fogColorTween = nil
    end
end

function MenuClusterBackdrop:Update(timeStep)
    self:UpdateFogColorTween(timeStep)
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
    self.fogColor = nil
    self.fogColorTween = nil
end

return MenuClusterBackdrop
