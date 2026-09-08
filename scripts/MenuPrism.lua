-- 选关菜单里的淡蓝六棱柱。
-- 只服务选关场景：拖转表现层，松手后 Snap 到 60°。
-- 整档时把窗口关卡的 stencil id 编成颜色，涂到左/正/右三面。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local PointerInput = require "PointerInput"
local LevelCatalog = require "LevelCatalog"
local StencilIdColor = require "StencilIdColor"
local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"
local StillModelCatalog = require "StillModelCatalog"

---@class MenuPrism
---@field scene Scene
---@field camera Camera
---@field cameraNode Node|nil
---@field worldViewport Viewport|nil
---@field root Node|nil
---@field voxelNodes Node[]
---@field maskRoot Node|nil
---@field maskMaterials Material[]
---@field maskLocalYaws number[]
---@field lastStepIndex number|nil
---@field window LevelDefinition[]
---@field exhibitRoot Node|nil
---@field exhibitNodes Node[]
---@field faceLabels Text3D[]
---@field faceChapterLabels Text3D[]
---@field faceTitleLabels Text3D[]
---@field labelLocalYaws number[]
---@field glassRoot Node|nil
---@field rtCameraNode Node|nil
---@field rtCamera Camera|nil
---@field rtViewport Viewport|nil
---@field rtTexture Texture2D|nil
---@field rtDepth Texture2D|nil
---@field rtWidth integer
---@field rtHeight integer
---@field yawDegrees number
---@field visualYawDegrees number
---@field targetYawDegrees number
---@field snapYawDegrees number
---@field phase string
---@field dragStartMouse Vector2|nil
---@field onFrontClicked fun(definition: LevelDefinition)|nil
---@field onFrontEditClicked fun(definition: LevelDefinition|nil)|nil
---@field onExitReady fun(definition: LevelDefinition)|nil
---@field onFrontChapterChanged fun(chapter: number|nil)|nil
---@field onExitDropStarted fun()|nil
---@field onEnterRiseStarted fun(chapter: number|nil)|nil
---@field fogTween {duration: number, clock: number, from: Color, to: Color}|nil
---@field exitTween {duration: number, clock: number, fromY: number, toY: number, definition: LevelDefinition}|nil
---@field enterTween {duration: number, clock: number, fromY: number, toY: number}|nil
---@field restY number
---@field pendingExit LevelDefinition|nil
---@field pendingDrop LevelDefinition|nil
---@field skipFogTween boolean
local MenuPrism = {}
MenuPrism.__index = MenuPrism

local STEP_DEGREES = 60.0
local SNAP_OFFSET_DEGREES = 30.0
local HEIGHT_SCALE = 1.5
local WIDTH_SCALE = 0.75
local DRAG_FOLLOW = 14.0
local SNAP_FOLLOW = 16.0
local SNAP_EPSILON = 0.6
local DRAG_DEADZONE_PIXELS = 8.0
local DRAG_DEGREES_PER_PIXEL = 0.35
local MASK_BIT = 1
local WORLD_BIT = 2
local PRISM_DROP = 1.05
local CLIP_SHADER = "Shaders/BLGL/StencilIdRtClip.shader"
local FACE_LABEL_FONT = "Fonts/MiSans-Regular.ttf"
local FACE_CHAPTER_SIZE = 32.0
local FACE_TITLE_SIZE = 52.0
local FACE_CHAPTER_SCALE = 0.16
local FACE_TITLE_SCALE = 0.145
local FACE_LABEL_LIFT = 0.014
-- 展台铭文：分类行克制、主标题突出，两侧菱形只作校准点。
local FACE_CHAPTER_COLOR = Color(0.62, 0.74, 0.72, 0.90)
local FACE_TITLE_COLOR = Color(0.96, 0.98, 0.94, 1.0)
local FACE_CHAPTER_Y = 0.105
local FACE_TITLE_Y = -0.07
local FACE_ORNAMENT_COLOR = Color(0.70, 0.82, 0.78, 0.55)
local FACE_ORNAMENT_OFFSET_X = 0.24
local FACE_ORNAMENT_Y = 0.11
local FACE_ORNAMENT_SCALE = 0.018
local FACE_PLAQUE_COLOR = Color(0.20, 0.31, 0.32, 1.0)
local FACE_PLAQUE_SIZE = Vector3(0.64, 0.32, 0.012)
local GLASS_SHADER = "Shaders/BLGL/MenuVitrineGlass.shader"
local GLASS_THICKNESS = 0.008
local GLASS_CLEARANCE = 0.50
local GLASS_MIN_HEIGHT = 0.95
-- 罩高按门放大前的尺度锁定，不跟展品缩放。
local GLASS_HEIGHT_SCALE = 0.18 * 1.5
local GLASS_TINT = Color(0.68, 0.82, 0.84, 1.0)
local GLASS_EDGE_TINT = Color(0.94, 0.99, 0.97, 1.0)
local PEDESTAL_CENTER_OFFSET_Y = -0.32
local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"
local PHASE_EXIT = "exit"
local PHASE_ENTER = "enter"
local FOG_TWEEN_DURATION = 0.45
local EXIT_DROP = 8.0
local EXIT_DURATION = 0.85

-- 第二章选关门：assets/Levels/level-2-1.json stillObjects[0]
-- StaticDoor 只有 3 个槽：门板 / 丁达尔 / 门内。门板走 2-1 的 frame 色。
local MENU_CHAPTER2_DOOR_PARAMS = {
    ["slots.frame.colorNeg"] = "#4A536B",
    ["slots.frame.colorMid"] = "#6E8194",
    ["slots.frame.colorPos"] = "#90B1BD",
    ["slots.light.color"] = "#FFD400",
    ["slots.lit.color"] = "#FAD526",
}
local MENU_CHAPTER2_DOOR_SCALE = 0.18 * 1.5 * 1.5
local MENU_ALGERNON_SCALE = 1.25 * 1.25
local MENU_ALGERNON_YAW = 90.0
local MENU_DOOR_YAW = -60.0
local MENU_CHAPTER2_STENCIL_ID = 1
local MENU_CHAPTER3_STENCIL_ID = 2
local MENU_CHAPTER4_STENCIL_ID = 3
local MENU_CHARLIE_MODEL = "Meshes/Player.mdl"
local MENU_CHARLIE_TARGET_HEIGHT = 0.58
local MENU_CHARLIE_SCALE = 1.25 * 1.25
local MENU_CHARLIE_YAW = 90.0 + 4.0 * 60.0 + 180.0
local MENU_CHAPTER3_BUILDING_MODEL_ID = "small_building_Rq572hdKEz"
local MENU_CHAPTER3_BUILDING_SCALE = 0.16 * 3.0 * 1.8
local MENU_CHARLIE_FACE_YAW = 180.0
local MENU_CHARLIE_SLOT_COLORS = {
    Color(0.234497, 0.672245, 0.684455, 1.0),
    Color(0.61092, 0.238724, 0.0336636, 1.0),
    Color(0.800007, 0.571508, 0.2597, 1.0),
    Color(0.214029, 0.0960783, 0.0572623, 1.0),
}

-- 第一章门框淡蓝：assets/Levels/level-1-1.json stillObjects[0].params
local DOOR_FRAME_LOOK = {
    shader = LookApplier.SHADER_TRI_PRISM_LOOK,
    colorNeg = "#6E7A86",
    colorMid = "#9AA0A6",
    colorPos = "#D7E4EA",
    lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
    aoEnabled = true,
    aoColor = "#2A1F1A",
    aoSmooth = 0.18,
    aoBlend = 1.0,
    emissionColor = "#FFF4D2",
    emissionStrength = 0.08,
}

local function WrapDegrees(degrees)
    local wrapped = degrees % 360.0
    if wrapped > 180.0 then
        wrapped = wrapped - 360.0
    elseif wrapped <= -180.0 then
        wrapped = wrapped + 360.0
    end
    return wrapped
end

local function ShortestDelta(fromDegrees, toDegrees)
    return WrapDegrees(toDegrees - fromDegrees)
end

local function ApproachAngle(current, target, follow, timeStep)
    local remaining = ShortestDelta(current, target)
    local step = remaining * math.min(1.0, follow * timeStep)
    if math.abs(step) > math.abs(remaining) then
        return target
    end
    return current + step
end

local function NearestStepDegrees(yawDegrees)
    local shifted = yawDegrees - SNAP_OFFSET_DEGREES
    local step = math.floor(shifted / STEP_DEGREES + 0.5)
    return step * STEP_DEGREES + SNAP_OFFSET_DEGREES
end

function MenuPrism.New(scene, camera, cameraNode, worldViewport)
    local self = setmetatable({}, MenuPrism)
    self.scene = scene
    self.camera = camera
    ---@type Node|nil
    self.cameraNode = cameraNode
    ---@type Viewport|nil
    self.worldViewport = worldViewport
    ---@type Node|nil
    self.root = nil
    ---@type Node[]
    self.voxelNodes = {}
    ---@type Node|nil
    self.maskRoot = nil
    ---@type Material[]
    self.maskMaterials = {}
    ---@type number[]
    self.maskLocalYaws = {}
    ---@type number|nil
    self.lastStepIndex = nil
    ---@type LevelDefinition[]
    self.window = {}
    ---@type Node|nil
    self.exhibitRoot = nil
    ---@type Node[]
    self.exhibitNodes = {}
    ---@type Text3D[]
    self.faceLabels = {}
    ---@type Text3D[]
    self.faceChapterLabels = {}
    ---@type Text3D[]
    self.faceTitleLabels = {}
    ---@type number[]
    self.labelLocalYaws = {}
    ---@type Node|nil
    self.glassRoot = nil
    ---@type Node|nil
    self.rtCameraNode = nil
    ---@type Camera|nil
    self.rtCamera = nil
    ---@type Viewport|nil
    self.rtViewport = nil
    ---@type Texture2D|nil
    self.rtTexture = nil
    ---@type Texture2D|nil
    self.rtDepth = nil
    self.rtWidth = 0
    self.rtHeight = 0
    self.yawDegrees = 0.0
    self.visualYawDegrees = 0.0
    self.targetYawDegrees = 0.0
    self.snapYawDegrees = 0.0
    self.phase = PHASE_IDLE
    ---@type Vector2|nil
    self.dragStartMouse = nil
    ---@type fun(definition: LevelDefinition)|nil
    self.onFrontClicked = nil
    ---@type fun(definition: LevelDefinition|nil)|nil
    self.onFrontEditClicked = nil
    ---@type fun(definition: LevelDefinition)|nil
    self.onExitReady = nil
    ---@type fun(chapter: number|nil)|nil
    self.onFrontChapterChanged = nil
    ---@type fun()|nil
    self.onExitDropStarted = nil
    ---@type fun(chapter: number|nil)|nil
    self.onEnterRiseStarted = nil
    ---@type table|nil
    self.fogTween = nil
    ---@type table|nil
    self.exitTween = nil
    ---@type table|nil
    self.enterTween = nil
    self.restY = -PRISM_DROP
    ---@type LevelDefinition|nil
    self.pendingExit = nil
    ---@type LevelDefinition|nil
    self.pendingDrop = nil
    self.skipFogTween = false
    return self
end

local function Clamp01(value)
    if value < 0.0 then
        return 0.0
    end
    if value > 1.0 then
        return 1.0
    end
    return value
end

-- 由慢到快：t^3。
local function EaseInCubic(t)
    return t * t * t
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

local CAMERA_FRONT_YAW = 180.0

local function ColorForLevel(definition)
    return LevelCatalog.GetColor(definition)
end

function MenuPrism:StepIndexFromYaw(yawDegrees)
    return math.floor(yawDegrees / STEP_DEGREES)
end

function MenuPrism:CenterIndexFromStep(stepIndex)
    local count = #LevelCatalog.GetAll()
    if count <= 0 then
        return 1
    end
    local wrapped = ((stepIndex % count) + count) % count
    return wrapped + 1
end

function MenuPrism:UpdateWindow()
    local stepIndex = self.lastStepIndex or 0
    local centerIndex = self:CenterIndexFromStep(stepIndex)
    self.window = LevelCatalog.GetWindow(centerIndex)
    local left = self.window[1]
    local center = self.window[2]
    local right = self.window[3]
    self:TweenFogToFront(center)
    if self.onFrontChapterChanged then
        self.onFrontChapterChanged(center and center.chapter or nil)
    end
    print(string.format(
        "MenuPrism: window [%s][%s][%s]",
        left and left.code or "--",
        center and center.code or "--",
        right and right.code or "--"
    ))
end

function MenuPrism:UpdateFrontFaceColors()
    if #self.maskMaterials == 0 then
        return
    end
    local frontIndex = 1
    local bestDelta = 999.0
    for i = 1, #self.maskLocalYaws do
        local worldYaw = self.maskLocalYaws[i] + self.visualYawDegrees
        local delta = math.abs(WrapDegrees(worldYaw - CAMERA_FRONT_YAW))
        if delta < bestDelta then
            bestDelta = delta
            frontIndex = i
        end
    end
    self:UpdateWindow()
    local faceCount = #self.maskMaterials
    -- 面号增大 = 世界 yaw 增大 = 屏幕左侧。
    local leftIndex = (frontIndex % faceCount) + 1
    local rightIndex = ((frontIndex - 2 + faceCount) % faceCount) + 1
    local left = self.window[1]
    local center = self.window[2]
    local right = self.window[3]
    local centerIndex = 1
    if center then
        centerIndex = center.index
    end
    for i = 1, faceCount do
        local color = LevelCatalog.GetBackColor()
        if i == frontIndex then
            color = ColorForLevel(center)
        elseif i == leftIndex then
            color = ColorForLevel(left)
        elseif i == rightIndex then
            color = ColorForLevel(right)
        end
        self.maskMaterials[i]:SetShaderParameter("base_color", Variant(color))
    end
    self:UpdateFaceLabels(centerIndex, frontIndex)
    print(string.format(
        "MenuPrism: faces left=%s front=%s right=%s",
        left and left.code or "--",
        center and center.code or "--",
        right and right.code or "--"
    ))
end

function MenuPrism:LevelForFaceYaw(localYaw, centerIndex, frontMaskIndex)
    local count = #LevelCatalog.GetAll()
    if count <= 0 then
        return nil
    end
    local worldYaw = localYaw + self.visualYawDegrees
    local fromFront = WrapDegrees(worldYaw - CAMERA_FRONT_YAW)
    local steps = math.floor(fromFront / STEP_DEGREES + 0.5)
    -- 与 mask 槽一致：屏幕右 yaw 更小 → +1，屏幕左 yaw 更大 → -1。
    local slot = -steps
    while slot > 3 do
        slot = slot - 6
    end
    while slot < -2 do
        slot = slot + 6
    end
    return LevelCatalog.GetByIndex(centerIndex + slot)
end

function MenuPrism:FaceCopy(definition)
    if not definition then
        return "第    章", "—"
    end
    local label = tostring(definition.chapterLabel or definition.chapter or "")
    local chapter = "第" .. label .. "章"
    local title = definition.stageName or "—"
    if definition.placeholder then
        title = "—"
    end
    return chapter, title
end

function MenuPrism:UpdateFaceLabels(centerIndex, frontMaskIndex)
    for i = 1, #self.labelLocalYaws do
        local localYaw = self.labelLocalYaws[i] or 0.0
        local definition = self:LevelForFaceYaw(localYaw, centerIndex, frontMaskIndex)
        local chapter, title = self:FaceCopy(definition)
        local chapterLabel = self.faceChapterLabels[i]
        local titleLabel = self.faceTitleLabels[i]
        if chapterLabel then
            chapterLabel:SetText(chapter)
        end
        if titleLabel then
            titleLabel:SetText(title)
        end
    end
end

function MenuPrism:PlaceholderFogColor()
    return LevelCatalog.CONFIG.placeholderFogColor
end

function MenuPrism:SetFogColorNow(color)
    self.fogTween = nil
    if not self.scene or not color then
        return
    end
    LookApplier.SetFogColor(self.scene, color)
end

function MenuPrism:TweenFogToFront(definition)
    if not self.scene then
        return
    end
    if self.skipFogTween then
        return
    end
    local fromColor = LookApplier.GetFogColor(self.scene, self:PlaceholderFogColor())
    local toColor = LevelCatalog.GetFogColor(definition, self:PlaceholderFogColor())
    self.fogTween = {
        duration = FOG_TWEEN_DURATION,
        clock = 0.0,
        from = fromColor,
        to = toColor,
    }
end

function MenuPrism:UpdateFogTween(timeStep)
    local tween = self.fogTween
    if not tween then
        return
    end
    tween.clock = tween.clock + timeStep
    local t = Clamp01(tween.clock / tween.duration)
    LookApplier.SetFogColor(self.scene, MixColor(tween.from, tween.to, t))
    if t >= 1.0 then
        self.fogTween = nil
    end
end

function MenuPrism:YawForCenterIndex(centerIndex)
    local count = #LevelCatalog.GetAll()
    if count <= 0 then
        return SNAP_OFFSET_DEGREES
    end
    local wrapped = ((centerIndex - 1) % count + count) % count
    return wrapped * STEP_DEGREES + SNAP_OFFSET_DEGREES
end

function MenuPrism:FocusLevel(definition, fogColor)
    if not definition then
        return
    end
    local yaw = self:YawForCenterIndex(definition.index)
    self.skipFogTween = true
    self:ApplyVisualYaw(yaw)
    self.yawDegrees = yaw
    self.targetYawDegrees = yaw
    self.snapYawDegrees = yaw
    self.skipFogTween = false
    self:SetFogColorNow(fogColor or LevelCatalog.GetFogColor(definition, self:PlaceholderFogColor()))
    print(string.format(
        "MenuPrism: focus %s yaw=%.1f",
        definition.code,
        yaw
    ))
end

function MenuPrism:BeginEnterRise()
    if not self.root then
        return false
    end
    self.phase = PHASE_ENTER
    self.dragStartMouse = nil
    self.exitTween = nil
    local restY = self.restY
    self.root.position = Vector3(0.0, restY - EXIT_DROP, 0.0)
    self.enterTween = {
        duration = EXIT_DURATION,
        clock = 0.0,
        fromY = restY - EXIT_DROP,
        toY = restY,
    }
    print(string.format("MenuPrism: enter rise from y=%.3f", restY - EXIT_DROP))
    if self.onEnterRiseStarted then
        local front = self:FrontLevel()
        self.onEnterRiseStarted(front and front.chapter or nil)
    end
    return true
end

function MenuPrism:UpdateEnterRise(timeStep)
    local tween = self.enterTween
    local root = self.root
    if not tween or not root then
        return
    end
    local nextClock = tween.clock + timeStep
    tween.clock = nextClock
    local t = Clamp01(nextClock / tween.duration)
    -- 下落 t^3 由慢到快；升起 (1-(1-t)^3) 由快到慢。
    local eased = 1.0 - (1.0 - t) * (1.0 - t) * (1.0 - t)
    local y = tween.fromY + (tween.toY - tween.fromY) * eased
    local pos = root.position
    root.position = Vector3(pos.x, y, pos.z)
    if t >= 1.0 then
        self.enterTween = nil
        self.phase = PHASE_IDLE
        print("MenuPrism: enter rise finished")
    end
end

function MenuPrism:BeginExitDrop(definition)
    if self.phase == PHASE_EXIT then
        return true
    end
    if not self.root then
        if self.onExitReady then
            self.onExitReady(definition)
        end
        return true
    end
    self.phase = PHASE_EXIT
    self.dragStartMouse = nil
    self.enterTween = nil
    local fromY = self.root.position.y
    self.exitTween = {
        duration = EXIT_DURATION,
        clock = 0.0,
        fromY = fromY,
        toY = fromY - EXIT_DROP,
        definition = definition,
    }
    print(string.format("MenuPrism: exit drop from y=%.3f", fromY))
    if self.onExitDropStarted then
        self.onExitDropStarted()
    end
    return true
end

function MenuPrism:UpdateExitDrop(timeStep)
    local tween = self.exitTween
    local root = self.root
    if not tween or not root then
        return
    end
    local nextClock = tween.clock + timeStep
    tween.clock = nextClock
    local t = Clamp01(nextClock / tween.duration)
    local y = tween.fromY + (tween.toY - tween.fromY) * EaseInCubic(t)
    local pos = root.position
    root.position = Vector3(pos.x, y, pos.z)
    if t >= 1.0 then
        self.exitTween = nil
        print("MenuPrism: exit drop finished")
        self.pendingExit = tween.definition
    end
end

function MenuPrism:ApplyVisualYaw(yawDegrees)
    self.visualYawDegrees = yawDegrees
    if self.root then
        self.root.rotation = Quaternion(yawDegrees, Vector3.UP)
    end
    local stepIndex = self:StepIndexFromYaw(yawDegrees)
    if stepIndex ~= self.lastStepIndex then
        self.lastStepIndex = stepIndex
        self:UpdateFrontFaceColors()
    end
end

function MenuPrism:Build()
    if not self.scene then
        return false
    end
    local look = LookApplier.CopyPartLook(DOOR_FRAME_LOOK)
    local material = LookApplier.CreatePartMaterial(look)
    local height = VoxelRenderer.DEFAULT_HEIGHT * HEIGHT_SCALE
    local edgeLength = VoxelRenderer.DEFAULT_EDGE * WIDTH_SCALE
    self:LockSkyboxToWorld()
    self:CreateRt()
    self.root = self.scene:CreateChild("MenuPrismRoot")
    self.restY = -PRISM_DROP + PEDESTAL_CENTER_OFFSET_Y
    self.root.position = Vector3(0.0, self.restY, 0.0)
    self.voxelNodes = VoxelRenderer.CreateHexagonOfVoxels(
        self.scene,
        Vector3(0.0, 0.0, 0.0),
        {
            Color(0.70, 0.74, 0.76, 1.0),
            Color(0.70, 0.74, 0.76, 1.0),
            Color(0.70, 0.74, 0.76, 1.0),
            Color(0.70, 0.74, 0.76, 1.0),
            Color(0.70, 0.74, 0.76, 1.0),
            Color(0.70, 0.74, 0.76, 1.0),
        },
        {
            parent = self.root,
            edgeLength = edgeLength,
            height = height,
            material = material,
        }
    )
    for _, node in ipairs(self.voxelNodes) do
        local drawable = node:GetComponent("CustomGeometry")
        if drawable then
            drawable.viewMask = WORLD_BIT
            drawable.castShadows = false
        end
    end
    self:BuildMaskQuads(edgeLength, height)
    self:BuildGlassHood(edgeLength, height)
    self:BuildFaceLabels(edgeLength)
    self:BuildExhibits(height)
    self:ApplyVisualYaw(SNAP_OFFSET_DEGREES)
    self.yawDegrees = SNAP_OFFSET_DEGREES
    self.targetYawDegrees = SNAP_OFFSET_DEGREES
    self.snapYawDegrees = SNAP_OFFSET_DEGREES
    self:SyncRtCamera()
    print("MenuPrism: pale-blue hex prism + mask RT ready")
    return true
end

local function CurrentViewportSize()
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()
    if width < 8 then
        width = 8
    end
    if height < 8 then
        height = 8
    end
    return width, height
end

function MenuPrism:LockSkyboxToWorld()
    if not self.scene then
        return
    end
    local skyboxes = self.scene:GetComponents("Skybox", true)
    local count = 0
    for _, skybox in ipairs(skyboxes or {}) do
        skybox.viewMask = WORLD_BIT
        count = count + 1
    end
    print("MenuPrism: locked Skybox viewMask count=" .. tostring(count))
end

function MenuPrism:CreateMaskRenderPath()
    if not self.worldViewport then
        print("MenuPrism: no world viewport to clone RenderPath")
        return nil
    end
    -- Lua 没有 RenderPath() / RenderPath:new()。从主 Viewport Clone。
    local path = self.worldViewport:GetRenderPath():Clone()
    for index = 0, path:GetNumCommands() - 1 do
        local command = path:GetCommand(index)
        if command.type == CMD_CLEAR then
            command.clearFlags = CLEAR_COLOR | CLEAR_DEPTH | CLEAR_STENCIL
            command.useFogColor = false
            command.clearColor = Color(0.0, 0.0, 0.0, 1.0)
            command.clearDepth = 1.0
            command.clearStencil = 0
            command.enabled = true
        elseif command.type == CMD_SCENEPASS then
            command.enabled = true
        else
            command.enabled = false
        end
        path:SetCommand(index, command)
    end
    return path
end

function MenuPrism:CreateRt()
    local width, height = CurrentViewportSize()
    self.rtTexture = Texture2D:new()
    self.rtTexture:SetNumLevels(1)
    self.rtTexture:SetFilterMode(FILTER_NEAREST)
    self.rtTexture:SetAddressMode(COORD_U, ADDRESS_CLAMP)
    self.rtTexture:SetAddressMode(COORD_V, ADDRESS_CLAMP)
    local created = self.rtTexture:SetSize(width, height, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    if not created then
        print("MenuPrism: failed to create color RT")
        return false
    end
    self.rtDepth = Texture2D:new()
    self.rtDepth:SetNumLevels(1)
    local depthCreated = self.rtDepth:SetSize(width, height, Graphics:GetDepthStencilFormat(), TEXTURE_DEPTHSTENCIL)
    if not depthCreated then
        print("MenuPrism: failed to create depth-stencil RT")
        return false
    end
    local surface = self.rtTexture:GetRenderSurface()
    surface:SetLinkedDepthStencil(self.rtDepth:GetRenderSurface())
    self.rtCameraNode = self.scene:CreateChild("MenuMaskCamera")
    self.rtCamera = self.rtCameraNode:CreateComponent("Camera")
    self.rtCamera.orthographic = true
    self.rtCamera.viewMask = MASK_BIT
    local maskPath = self:CreateMaskRenderPath()
    if not maskPath then
        return false
    end
    self.rtViewport = Viewport:new(self.scene, self.rtCamera, maskPath)
    surface:SetViewport(0, self.rtViewport)
    surface:SetUpdateMode(SURFACE_UPDATEALWAYS)
    self.rtWidth = width
    self.rtHeight = height
    print(string.format("MenuPrism: RT %dx%d created", width, height))
    return true
end

function MenuPrism:SyncRtCamera()
    if not self.rtCameraNode or not self.rtCamera or not self.cameraNode or not self.camera then
        return
    end
    self.rtCameraNode.worldPosition = self.cameraNode.worldPosition
    self.rtCameraNode.worldRotation = self.cameraNode.worldRotation
    self.rtCamera.orthographic = self.camera.orthographic
    self.rtCamera.orthoSize = self.camera.orthoSize
    self.rtCamera.fov = self.camera.fov
    self.rtCamera.nearClip = self.camera.nearClip
    self.rtCamera.farClip = self.camera.farClip
    self.rtCamera.aspectRatio = self.camera.aspectRatio
end

function MenuPrism:ResizeRtIfNeeded()
    if not self.rtTexture or not self.rtDepth then
        return
    end
    local width, height = CurrentViewportSize()
    if width == self.rtWidth and height == self.rtHeight then
        return
    end
    local colorOk = self.rtTexture:SetSize(width, height, Graphics:GetRGBAFormat(), TEXTURE_RENDERTARGET)
    local depthOk = self.rtDepth:SetSize(width, height, Graphics:GetDepthStencilFormat(), TEXTURE_DEPTHSTENCIL)
    if not colorOk or not depthOk then
        print(string.format("MenuPrism: RT resize failed %dx%d", width, height))
        return
    end
    local surface = self.rtTexture:GetRenderSurface()
    surface:SetLinkedDepthStencil(self.rtDepth:GetRenderSurface())
    if self.rtViewport then
        surface:SetViewport(0, self.rtViewport)
    end
    surface:SetUpdateMode(SURFACE_UPDATEALWAYS)
    self.rtWidth = width
    self.rtHeight = height
    print(string.format("MenuPrism: RT resized to %dx%d", width, height))
end

function MenuPrism:BuildMaskQuads(edgeLength, prismHeight)
    if not self.root then
        return
    end
    -- 挂在棱柱根上，跟着一起转。
    -- 下方六棱柱边长 = edge，顶点半径 = edge，侧面边心距 = (√3/2)*edge。
    -- 面片中心必须落在边心距上，面宽 = edge，相邻面才能在顶点相接。
    -- 用中心距 edge/√3 会缩进一圈，出现图里的六角断层。
    -- 本地 yaw 加 30°，正对侧面中点。
    self.maskRoot = self.root:CreateChild("MenuMaskQuads")
    self.maskMaterials = {}
    self.maskLocalYaws = {}
    local radius = edgeLength * math.sqrt(3.0) * 0.5
    local faceWidth = edgeLength
    local faceHeight = prismHeight * 0.85 * 3.0
    local thickness = 0.02
    local centerY = prismHeight + faceHeight * 0.5
    for i = 0, 5 do
        local yaw = i * 60.0 + SNAP_OFFSET_DEGREES
        local rad = math.rad(yaw)
        local node = self.maskRoot:CreateChild("MaskQuad_" .. tostring(i + 1))
        node.position = Vector3(math.sin(rad) * radius, centerY, math.cos(rad) * radius)
        node.rotation = Quaternion(yaw, Vector3.UP)
        node.scale = Vector3(faceWidth, faceHeight, thickness)
        local material = LookApplier.CreateStencilMaskMaterial(Color(1.0, 0.0, 0.0, 1.0))
        local model = node:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(material)
        model.viewMask = MASK_BIT
        model.castShadows = false
        self.maskMaterials[#self.maskMaterials + 1] = material
        self.maskLocalYaws[#self.maskLocalYaws + 1] = yaw
    end
    print("MenuPrism: six mask faces ready")
end

function MenuPrism:CreateFaceText(parent, name, fontPath, fontSize, color, localY, scale)
    local node = parent:CreateChild(name)
    node.position = Vector3(0.0, localY, -0.022)
    node.scale = Vector3(scale, scale, scale)
    local text = node:CreateComponent("Text3D")
    text:SetFont(cache:GetResource("Font", fontPath), fontSize)
    text:SetText("")
    text:SetColor(color)
    text:SetAlignment(HA_CENTER, VA_CENTER)
    text:SetTextAlignment(HA_CENTER)
    text:SetFaceCameraMode(FC_NONE)
    text:SetFixedScreenSize(false)
    text:SetTextEffect(TE_NONE)
    text.viewMask = WORLD_BIT
    return text
end

function MenuPrism:CreateGlassMaterial()
    local material = Material:new()
    if not material:SetSurfaceShader(GLASS_SHADER) then
        print("MenuPrism: failed to load vitrine glass shader")
        return nil
    end
    material:SetShaderParameter("glass_tint", Variant(GLASS_TINT))
    material:SetShaderParameter("fresnel_tint", Variant(GLASS_EDGE_TINT))
    material:SetShaderParameter("face_alpha", Variant(0.025))
    material:SetShaderParameter("fresnel_alpha", Variant(0.18))
    material:SetShaderParameter("fresnel_power", Variant(3.0))
    return material
end

function MenuPrism:BindGlassDrawable(node)
    local drawable = node:GetComponent("StaticModel")
    if not drawable then
        drawable = node:GetComponent("CustomGeometry")
    end
    if drawable then
        drawable.viewMask = WORLD_BIT
        drawable.castShadows = false
    end
end

function MenuPrism:GetExhibitHeight()
    local resource = cache:GetResource("Model", "Meshes/StaticDoor.mdl")
    if not resource then
        return GLASS_MIN_HEIGHT
    end
    local bounds = resource.boundingBox
    local rotation = Quaternion(90.0, Vector3.RIGHT)
    local rotated = bounds:Transformed(Matrix3x4(Vector3.ZERO, rotation, 1.0))
    local height = rotated.max.y - rotated.min.y
    return math.max(GLASS_MIN_HEIGHT, height * GLASS_HEIGHT_SCALE + GLASS_CLEARANCE)
end

function MenuPrism:CreateGlassShellGeometry(edgeLength, bottomY, topY)
    local geometry = self.glassRoot:CreateComponent("CustomGeometry")
    geometry:SetNumGeometries(2)
    geometry:BeginGeometry(0, TRIANGLE_LIST)
    local radius = edgeLength
    local bottom = {}
    local top = {}
    for i = 0, 5 do
        local angle = math.rad(i * 60.0 + SNAP_OFFSET_DEGREES)
        bottom[i + 1] = Vector3(math.cos(angle) * radius, bottomY, -math.sin(angle) * radius)
        top[i + 1] = Vector3(math.cos(angle) * radius, topY, -math.sin(angle) * radius)
    end
    for i = 1, 6 do
        local nextIndex = i % 6 + 1
        local a = bottom[i]
        local b = bottom[nextIndex]
        local c = top[nextIndex]
        local d = top[i]
        local normal = Vector3(-(b - a).z, 0.0, (b - a).x):Normalized()
        geometry:DefineVertex(a)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(0, 0))
        geometry:DefineVertex(b)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(1, 0))
        geometry:DefineVertex(c)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(1, 1))
        geometry:DefineVertex(a)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(0, 0))
        geometry:DefineVertex(c)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(1, 1))
        geometry:DefineVertex(d)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(0, 1))
    end
    local normal = Vector3.UP
    local center = Vector3(0.0, topY, 0.0)
    for i = 1, 6 do
        local nextIndex = i % 6 + 1
        geometry:DefineVertex(center)
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(0.5, 0.5))
        geometry:DefineVertex(top[i])
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(0, 0))
        geometry:DefineVertex(top[nextIndex])
        geometry:DefineNormal(normal)
        geometry:DefineColor(Color(1, 1, 1, 1))
        geometry:DefineTexCoord(Vector2(1, 1))
    end
    geometry:Commit()
    local material = self:CreateGlassMaterial()
    if not material then
        return nil
    end
    geometry:SetMaterial(material)
    geometry.viewMask = WORLD_BIT
    geometry.castShadows = false
    return geometry
end

function MenuPrism:BuildGlassHood(edgeLength, prismHeight)
    if not self.root then
        return
    end
    self.glassRoot = self.root:CreateChild("MenuGlassHood")
    local glassHeight = self:GetExhibitHeight()
    local bottomY = prismHeight - GLASS_THICKNESS * 0.5
    local topY = bottomY + glassHeight
    self:CreateGlassShellGeometry(edgeLength, bottomY, topY)
    print(string.format("MenuPrism: continuous vitrine shell height=%.3f", glassHeight))
end

function MenuPrism:CreatePlaqueMaterial()
    -- 与底座同色相的淡蓝灰，更深、饱和度略收。
    return LookApplier.CreateStillObjectBaseMaterial({
        colorNeg = "#4A5460",
        colorMid = "#5E6A76",
        colorPos = "#74818C",
        lightAxis = { x = 0.35, y = 1.0, z = 0.25 },
    })
end

function MenuPrism:CreateDiamond(parent, name, x, y)
    local node = parent:CreateChild(name)
    node.position = Vector3(x, y, -0.02)
    node.scale = Vector3(FACE_ORNAMENT_SCALE, FACE_ORNAMENT_SCALE, 0.006)
    node.rotation = Quaternion(45.0, Vector3.FORWARD)
    local model = node:CreateComponent("StaticModel")
    model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/NoTextureUnlit.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(FACE_ORNAMENT_COLOR))
    model:SetMaterial(material)
    model.viewMask = WORLD_BIT
    model.castShadows = false
    return node
end

function MenuPrism:BuildFaceLabels(edgeLength)
    self.faceLabels = {}
    self.faceChapterLabels = {}
    self.faceTitleLabels = {}
    self.labelLocalYaws = {}
    if #self.voxelNodes == 0 then
        return
    end
    local font = cache:GetResource("Font", FACE_LABEL_FONT)
    if not font then
        print("MenuPrism: missing face label font")
        return
    end
    -- 实体三棱柱外侧面的边心距是 edge/(2√3)，铭牌只贴在面中央。
    local outward = edgeLength / (2.0 * math.sqrt(3.0)) + FACE_LABEL_LIFT
    for i, voxelNode in ipairs(self.voxelNodes) do
        local plaque = voxelNode:CreateChild("FacePlaque_" .. tostring(i))
        plaque.position = Vector3(outward, 0.0, 0.0)
        plaque.rotation = Quaternion(-90.0, Vector3.UP)
        local plateNode = plaque:CreateChild("PlaqueSurface")
        plateNode.scale = FACE_PLAQUE_SIZE
        local plate = plateNode:CreateComponent("StaticModel")
        plate:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        plate:SetMaterial(self:CreatePlaqueMaterial())
        plate.viewMask = WORLD_BIT
        plate.castShadows = false
        self:CreateDiamond(plaque, "DiamondLeft", -FACE_ORNAMENT_OFFSET_X, FACE_ORNAMENT_Y)
        self:CreateDiamond(plaque, "DiamondRight", FACE_ORNAMENT_OFFSET_X, FACE_ORNAMENT_Y)
        local chapter = self:CreateFaceText(
            plaque,
            "Chapter",
            FACE_LABEL_FONT,
            FACE_CHAPTER_SIZE,
            FACE_CHAPTER_COLOR,
            FACE_CHAPTER_Y,
            FACE_CHAPTER_SCALE
        )
        local title = self:CreateFaceText(
            plaque,
            "Title",
            FACE_LABEL_FONT,
            FACE_TITLE_SIZE,
            FACE_TITLE_COLOR,
            FACE_TITLE_Y,
            FACE_TITLE_SCALE
        )
        self.faceChapterLabels[#self.faceChapterLabels + 1] = chapter
        self.faceTitleLabels[#self.faceTitleLabels + 1] = title
        self.faceLabels[#self.faceLabels + 1] = title
        self.labelLocalYaws[#self.labelLocalYaws + 1] = (i - 1) * STEP_DEGREES + 90.0
    end
    print("MenuPrism: six plinth plaques ready")
end

local function ColorFromLook(look, fallback)
    fallback = fallback or Color(0.957, 0.945, 0.918, 1.0)
    if not look then
        return fallback
    end
    if type(look) ~= "table" then
        return fallback
    end
    local hex = LookApplier.NormalizeHex(look.color or look.baseColor, "")
    if type(hex) ~= "string" then
        return fallback
    end
    local cleaned = hex:gsub("#", "")
    local r = tonumber(cleaned:sub(1, 2), 16)
    local g = tonumber(cleaned:sub(3, 4), 16)
    local b = tonumber(cleaned:sub(5, 6), 16)
    if not r or not g or not b then
        return fallback
    end
    return Color(r / 255.0, g / 255.0, b / 255.0, 1.0)
end

function MenuPrism:CreateClipMaterial(stencilId, look, doubleSided, twoTone)
    look = look or {}
    local material = Material:new()
    if not material:SetSurfaceShader(CLIP_SHADER) then
        print("MenuPrism: failed to load clip shader")
        return LookApplier.CreateStillObjectUnlitMaterial({
            color = look.color or "#F4F1EA",
            opaque = true,
        })
    end
    material:SetShaderParameter("base_color", Variant(ColorFromLook(look)))
    material:SetShaderParameter("stencil_color", Variant(StencilIdColor.ToColor(stencilId)))
    material:SetShaderParameter("use_albedo_map", Variant(0.0))
    material:SetShaderParameter("two_tone", Variant(twoTone and 1.0 or 0.0))
    material:SetShaderParameter("light_axis", Variant(Vector3(0.35, 1.0, 0.25)))
    material:SetShaderParameter("shade_saturation", Variant(0.2))
    material:SetShaderParameter("shade_value", Variant(0.1))
    local albedoMap = type(look.albedoMap) == "string" and look.albedoMap or ""
    if albedoMap ~= "" then
        local texture = cache:GetResource("Texture2D", albedoMap)
        if texture then
            material:SetSurfaceTexture("albedo_map", texture)
            material:SetShaderParameter("use_albedo_map", Variant(1.0))
        end
    end
    if self.rtTexture then
        material:SetSurfaceTexture("mask_rt", self.rtTexture)
    end
    if doubleSided then
        material:SetCullMode(CULL_NONE)
    end
    local technique = material:GetTechnique(0)
    if technique and technique:HasPass("base") then
        local pass = technique:GetPass("base")
        pass:SetBlendMode(BLEND_REPLACE)
        pass:SetDepthWrite(true)
        if doubleSided then
            pass:SetCullMode(CULL_NONE)
        end
    end
    return material
end

function MenuPrism:BindClipToDrawable(drawable, stencilId, look)
    if not drawable then
        return
    end
    local material = self:CreateClipMaterial(stencilId, look)
    local geoCount = drawable:GetNumGeometries()
    if geoCount <= 1 then
        drawable:SetMaterial(material)
        return
    end
    for geoIndex = 0, geoCount - 1 do
        drawable:SetMaterial(geoIndex, material)
    end
end

function MenuPrism:AddExhibitModel(parent, name, model, stencilId, look)
    if not model then
        print("MenuPrism: missing exhibit model " .. name)
        return nil
    end
    local node = parent:CreateChild(name)
    local drawable = node:CreateComponent("StaticModel")
    drawable:SetModel(model)
    self:BindClipToDrawable(drawable, stencilId, look)
    drawable.viewMask = WORLD_BIT
    drawable.castShadows = false
    self.exhibitNodes[#self.exhibitNodes + 1] = node
    return node
end

function MenuPrism:AddAlgernonExhibit(parent, stencilId)
    local object = StillObject.New({
        id = "menu_algernon",
        name = "ExhibitAlgernon",
        modelId = "algernon",
    })
    local entry = StillObjectRuntime.Bind(parent, object)
    if not entry or not entry.node or not entry.model then
        print("MenuPrism: failed to bind Algernon exhibit")
        return nil
    end
    local asset = entry.asset
    local geoCount = entry.model:GetNumGeometries()
    for _, slot in ipairs(asset.slots) do
        if slot.index >= 0 and slot.index < geoCount then
            local look = StillModelCatalog.SlotLook(asset, slot, object:GetActiveParams())
            entry.model:SetMaterial(slot.index, self:CreateClipMaterial(stencilId, look))
        end
    end
    entry.model.viewMask = WORLD_BIT
    entry.model.castShadows = false
    local current = entry.node.scale
    local yawed = entry.node.rotation * Quaternion(MENU_ALGERNON_YAW, Vector3.UP)
    entry.node.rotation = yawed
    entry.node.scale = Vector3(
        current.x * MENU_ALGERNON_SCALE,
        current.y * MENU_ALGERNON_SCALE,
        current.z * MENU_ALGERNON_SCALE
    )
    local pos = entry.node.position
    entry.node.position = Vector3(pos.x, pos.y * MENU_ALGERNON_SCALE, pos.z)
    self.exhibitNodes[#self.exhibitNodes + 1] = entry.node
    return entry.node
end

function MenuPrism:CreateMenuStillClipMaterial(slot, look, stencilId)
    local stencilColor = StencilIdColor.ToColor(stencilId)
    if slot.shader == LookApplier.SHADER_STILL_OBJECT_UNLIT then
        if look.additive then
            return LookApplier.CreateMenuStillObjectUnlitClipMaterial(look, stencilColor, self.rtTexture)
        end
        -- 门内不透明，走阿尔吉侬同款 clip，写入深度挡住丁达尔。
        look.opaque = true
        return self:CreateClipMaterial(stencilId, look)
    end
    return LookApplier.CreateMenuStillObjectBaseClipMaterial(look, stencilColor, self.rtTexture)
end

function MenuPrism:AddDoorExhibit(parent, stencilId)
    local object = StillObject.New({
        id = "menu_static_door",
        name = "ExhibitDoor",
        modelId = "static_door",
        params = MENU_CHAPTER2_DOOR_PARAMS,
    })
    local asset = StillModelCatalog.Get("static_door")
    local resource = cache:GetResource("Model", "Meshes/StaticDoor.mdl")
    if not asset or not resource then
        print("MenuPrism: missing StaticDoor asset/model")
        return nil
    end
    -- 选关用无骨骼、固定开门的 StaticDoor。
    local node = parent:CreateChild("ExhibitDoor")
    local rotation = asset.rootRotation
    node.rotation = Quaternion(MENU_DOOR_YAW, Vector3.UP)
        * Quaternion(rotation.x, Vector3.RIGHT)
        * Quaternion(rotation.y, Vector3.UP)
        * Quaternion(rotation.z, Vector3.FORWARD)
    local drawable = node:CreateComponent("StaticModel")
    drawable:SetModel(resource)
    drawable.viewMask = WORLD_BIT
    drawable.castShadows = false
    local geoCount = drawable:GetNumGeometries()
    local overrides = object:GetActiveParams()
    for _, slot in ipairs(asset.slots) do
        if slot.index >= 0 and slot.index < geoCount then
            local look = StillModelCatalog.SlotLook(asset, slot, overrides)
            drawable:SetMaterial(slot.index, self:CreateMenuStillClipMaterial(slot, look, stencilId))
        end
    end
    local scale = MENU_CHAPTER2_DOOR_SCALE
    node.scale = Vector3(scale, scale, scale)
    local offset = asset.rootOffset or { x = 0, y = 0.02, z = 0 }
    local unscaled = resource.boundingBox:Transformed(Matrix3x4(Vector3.ZERO, node.rotation, 1.0))
    local lift = -unscaled.min.y * scale + (offset.y or 0.0) * scale
    node.position = Vector3(0.0, lift, 0.0)
    local world = node:GetWorldPosition()
    print(string.format(
        "MenuPrism: chapter 2 StaticDoor geos=%d scale=%.3f lift=%.3f world=(%.3f, %.3f, %.3f)",
        geoCount,
        scale,
        lift,
        world.x,
        world.y,
        world.z
    ))
    self.exhibitNodes[#self.exhibitNodes + 1] = node
    return node
end

function MenuPrism:AddCharlieExhibit(parent, stencilId)
    local model = cache:GetResource("Model", MENU_CHARLIE_MODEL)
    if not model then
        print("MenuPrism: missing Charlie exhibit " .. MENU_CHARLIE_MODEL)
        return nil
    end
    local bounds = model.boundingBox
    local height = bounds.max.y - bounds.min.y
    if height < 0.001 then
        height = MENU_CHARLIE_TARGET_HEIGHT
    end
    local fitScale = MENU_CHARLIE_TARGET_HEIGHT / height
    local node = parent:CreateChild("ExhibitCharlie")
    node.rotation = Quaternion(MENU_CHARLIE_YAW, Vector3.UP)
    node.scale = Vector3(MENU_CHARLIE_SCALE, MENU_CHARLIE_SCALE, MENU_CHARLIE_SCALE)
    local mesh = node:CreateChild("Mesh")
    mesh.position = Vector3(0.0, -bounds.min.y * fitScale, 0.0)
    mesh.rotation = Quaternion(MENU_CHARLIE_FACE_YAW, Vector3.UP)
    mesh.scale = Vector3(fitScale, fitScale, fitScale)
    local drawable = mesh:CreateComponent("StaticModel")
    drawable:SetModel(model)
    drawable.viewMask = WORLD_BIT
    drawable.castShadows = false
    local cloakGeoIndex = 0
    local bestDelta = 999999
    local geoCount = drawable:GetNumGeometries()
    for geoIndex = 0, geoCount - 1 do
        local geometry = model:GetGeometry(geoIndex, 0)
        local vertexCount = geometry and geometry:GetVertexCount() or 0
        local delta = math.abs(vertexCount - 10)
        if delta < bestDelta then
            bestDelta = delta
            cloakGeoIndex = geoIndex
        end
    end
    for geoIndex = 0, geoCount - 1 do
        local color = MENU_CHARLIE_SLOT_COLORS[geoIndex + 1] or MENU_CHARLIE_SLOT_COLORS[1]
        local look = { color = string.format("#%02X%02X%02X",
            math.floor(color.r * 255.0 + 0.5),
            math.floor(color.g * 255.0 + 0.5),
            math.floor(color.b * 255.0 + 0.5)
        ) }
        local material = self:CreateClipMaterial(stencilId, look, geoIndex == cloakGeoIndex, true)
        drawable:SetMaterial(geoIndex, material)
    end
    local world = node:GetWorldPosition()
    print(string.format(
        "MenuPrism: chapter 4 Charlie geos=%d fit=%.3f scale=%.3f yaw=%.1f world=(%.3f, %.3f, %.3f)",
        geoCount,
        fitScale,
        MENU_CHARLIE_SCALE,
        MENU_CHARLIE_YAW,
        world.x,
        world.y,
        world.z
    ))
    self.exhibitNodes[#self.exhibitNodes + 1] = node
    return node
end

function MenuPrism:AddSmallBuildingExhibit(parent, stencilId)
    local asset = StillModelCatalog.Get(MENU_CHAPTER3_BUILDING_MODEL_ID)
    local resource = cache:GetResource("Model", "Meshes/SmallBuilding_Rq572hdKEz.mdl")
    if not asset or not resource then
        print("MenuPrism: missing chapter 3 building exhibit")
        return nil
    end
    local node = parent:CreateChild("ExhibitSmallBuilding")
    local drawable = node:CreateComponent("StaticModel")
    drawable:SetModel(resource)
    drawable.viewMask = WORLD_BIT
    drawable.castShadows = false
    local geoCount = drawable:GetNumGeometries()
    for _, slot in ipairs(asset.slots) do
        if slot.index >= 0 and slot.index < geoCount then
            local look = StillModelCatalog.SlotLook(asset, slot)
            look.fogHeightA = 0.0
            look.fogHeightB = 0.0
            look.colorPos = "#FFF7EE"
            look.colorMid = "#6AADE6"
            look.colorNeg = "#1A6FBF"
            look.gradeSaturation = 0.85
            look.gradeContrast = 0.92
            look.gradeHaze = 0.0
            look.gradeValue = 1.04
            drawable:SetMaterial(
                slot.index,
                LookApplier.CreateStillObjectMeshTintClipMaterial(
                    look,
                    StencilIdColor.ToColor(stencilId),
                    self.rtTexture
                )
            )
        end
    end
    local scale = MENU_CHAPTER3_BUILDING_SCALE
    node.scale = Vector3(scale, scale, scale)
    local unscaled = resource.boundingBox:Transformed(Matrix3x4(Vector3.ZERO, node.rotation, 1.0))
    local lift = -unscaled.min.y * scale
    node.position = Vector3(0.0, lift, 0.0)
    node.rotation = Quaternion(30.0, Vector3.UP)
    local world = node:GetWorldPosition()
    print(string.format(
        "MenuPrism: chapter 3 SmallBuilding geos=%d scale=%.3f lift=%.3f world=(%.3f, %.3f, %.3f)",
        geoCount,
        scale,
        lift,
        world.x,
        world.y,
        world.z
    ))
    self.exhibitNodes[#self.exhibitNodes + 1] = node
    return node
end

function MenuPrism:BuildExhibits(prismHeight)
    if not self.root then
        return
    end
    -- 挂在棱柱根上跟着转。贴实体六棱柱顶面，不抬到空心六面高度。
    self.exhibitRoot = self.root:CreateChild("MenuExhibits")
    self.exhibitNodes = {}
    self.exhibitRoot.position = Vector3(0.0, prismHeight, 0.0)
    print(string.format("MenuPrism: exhibits on solid top y=%.3f", prismHeight))

    self:AddAlgernonExhibit(self.exhibitRoot, 0)
    self:AddDoorExhibit(self.exhibitRoot, MENU_CHAPTER2_STENCIL_ID)
    self:AddSmallBuildingExhibit(self.exhibitRoot, MENU_CHAPTER3_STENCIL_ID)
    self:AddCharlieExhibit(self.exhibitRoot, MENU_CHAPTER4_STENCIL_ID)

    local sphere = self:AddExhibitModel(
        self.exhibitRoot,
        "ExhibitSphere",
        SphereGeometry(0.20, 16, 12):ToModel(),
        4,
        { color = "#BDA07A" }
    )
    sphere.position = Vector3(0.0, 0.20, 0.0)
    print("MenuPrism: five stencil exhibits ready")
end

function MenuPrism:SampleTargetYaw()
    local startMouse = self.dragStartMouse
    if not startMouse then
        return nil
    end
    local dx = PointerInput.Get().position.x - startMouse.x
    return self.yawDegrees - dx * DRAG_DEGREES_PER_PIXEL
end

function MenuPrism:BeginPending(mouse)
    if not self.root then
        return false
    end
    self.phase = PHASE_PENDING
    self.yawDegrees = self.visualYawDegrees
    self.targetYawDegrees = self.visualYawDegrees
    self.snapYawDegrees = self.visualYawDegrees
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    return true
end

function MenuPrism:PromotePendingToDrag()
    self.phase = PHASE_DRAG
    print("MenuPrism: drag start")
end

function MenuPrism:UpdateDrag(timeStep)
    local target = self:SampleTargetYaw()
    if target then
        self.targetYawDegrees = target
    end
    self:ApplyVisualYaw(ApproachAngle(
        self.visualYawDegrees,
        self.targetYawDegrees,
        DRAG_FOLLOW,
        timeStep
    ))
end

function MenuPrism:BeginSnap()
    local snapped = NearestStepDegrees(self.targetYawDegrees)
    self.snapYawDegrees = self.visualYawDegrees + ShortestDelta(self.visualYawDegrees, snapped)
    self.targetYawDegrees = self.snapYawDegrees
    self.phase = PHASE_SNAP
    print(string.format("MenuPrism: snap to %.0f deg", snapped))
    return true
end

function MenuPrism:UpdateSnap(timeStep)
    local remaining = ShortestDelta(self.visualYawDegrees, self.snapYawDegrees)
    if math.abs(remaining) <= SNAP_EPSILON then
        self:ApplyVisualYaw(self.snapYawDegrees)
        self.yawDegrees = self.snapYawDegrees
        self.phase = PHASE_IDLE
        self.dragStartMouse = nil
        print(string.format("MenuPrism: snapped yaw=%.0f", self.yawDegrees))
        return
    end
    self:ApplyVisualYaw(ApproachAngle(
        self.visualYawDegrees,
        self.snapYawDegrees,
        SNAP_FOLLOW,
        timeStep
    ))
end

function MenuPrism:FrontLevel()
    return self.window and self.window[2] or nil
end

function MenuPrism:IsPlayable(definition)
    if not definition then
        return false
    end
    if definition.placeholder then
        return false
    end
    return type(definition.sourcePath) == "string" and definition.sourcePath ~= ""
end

function MenuPrism:IsEditHeld()
    return input:GetKeyDown(KEY_E)
end

function MenuPrism:TryEnterFrontLevel()
    local definition = self:FrontLevel()
    if self:IsEditHeld() then
        print("MenuPrism: front edit click " .. tostring(definition and definition.code or "whitebox"))
        if self.onFrontEditClicked then
            self.onFrontEditClicked(definition)
        end
        return true
    end
    if not definition or not self:IsPlayable(definition) then
        print("MenuPrism: front click ignored, placeholder or empty")
        return false
    end
    print("MenuPrism: front click " .. definition.code)
    self.pendingDrop = definition
    return true
end

function MenuPrism:CancelPending()
    self.phase = PHASE_IDLE
    self.dragStartMouse = nil
end

function MenuPrism:Update(timeStep)
    if self.pendingExit then
        local definition = self.pendingExit
        self.pendingExit = nil
        if self.onExitReady then
            self.onExitReady(definition)
        end
        return
    end
    if self.pendingDrop then
        local definition = self.pendingDrop
        self.pendingDrop = nil
        self:BeginExitDrop(definition)
        return
    end
    if self.phase ~= PHASE_EXIT then
        self:ResizeRtIfNeeded()
        self:SyncRtCamera()
        if self.rtTexture then
            local surface = self.rtTexture:GetRenderSurface()
            if surface then
                surface:QueueUpdate()
            end
        end
    end
    self:UpdateFogTween(timeStep)
    if self.phase == PHASE_EXIT then
        self:UpdateExitDrop(timeStep)
        return
    end
    if self.phase == PHASE_ENTER then
        self:UpdateEnterRise(timeStep)
        return
    end
    PointerInput.BeginFrame()
    local pointer = PointerInput.Get()
    if self.phase == PHASE_IDLE then
        if pointer.pressed then
            self:BeginPending(pointer.position)
        end
        return
    end
    if self.phase == PHASE_PENDING then
        if not pointer.down then
            self:TryEnterFrontLevel()
            self:CancelPending()
            return
        end
        local startMouse = self.dragStartMouse
        if not startMouse then
            self:CancelPending()
            return
        end
        local mouse = pointer.position
        local dx = mouse.x - startMouse.x
        if math.abs(dx) >= DRAG_DEADZONE_PIXELS then
            self:PromotePendingToDrag()
            self:UpdateDrag(timeStep)
        end
        return
    end
    if self.phase == PHASE_DRAG then
        if pointer.down then
            self:UpdateDrag(timeStep)
        else
            self:BeginSnap()
        end
        return
    end
    if self.phase == PHASE_SNAP then
        self:UpdateSnap(timeStep)
    end
end

function MenuPrism:Destroy()
    self.maskRoot = nil
    self.maskMaterials = {}
    self.maskLocalYaws = {}
    self.lastStepIndex = nil
    self.window = {}
    self.exhibitRoot = nil
    self.exhibitNodes = {}
    self.faceLabels = {}
    self.faceChapterLabels = {}
    self.faceTitleLabels = {}
    self.labelLocalYaws = {}
    self.glassRoot = nil
    self.onFrontClicked = nil
    self.onFrontEditClicked = nil
    self.onExitReady = nil
    self.onFrontChapterChanged = nil
    self.onExitDropStarted = nil
    self.onEnterRiseStarted = nil
    self.fogTween = nil
    self.exitTween = nil
    self.pendingExit = nil
    self.pendingDrop = nil
    if self.rtCameraNode then
        self.rtCameraNode:Remove()
        self.rtCameraNode = nil
    end
    if self.root then
        self.root:Remove()
        self.root = nil
    end
    self.voxelNodes = {}
    self.rtViewport = nil
    self.rtTexture = nil
    self.rtDepth = nil
    self.rtCamera = nil
    self.phase = PHASE_IDLE
end

return MenuPrism
