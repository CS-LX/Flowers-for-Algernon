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
---@field labelLocalYaws number[]
---@field rtCameraNode Node|nil
---@field rtCamera Camera|nil
---@field rtViewport Viewport|nil
---@field rtTexture Texture2D|nil
---@field rtDepth Texture2D|nil
---@field preview BorderImage|nil
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
local FACE_LABEL_SIZE = 72.0
local FACE_LABEL_SCALE = 0.25
local FACE_LABEL_LIFT = 0.012
local FACE_LABEL_COLOR = Color(0.10, 0.14, 0.20, 1.0)
local PREVIEW_HEIGHT = 160
local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"
local PHASE_EXIT = "exit"
local PHASE_ENTER = "enter"
local FOG_TWEEN_DURATION = 0.45
local EXIT_DROP = 8.0
local EXIT_DURATION = 0.85

-- 第一章门框淡蓝：assets/Levels/chapter-1.json stillObjects[0].params
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
    ---@type number[]
    self.labelLocalYaws = {}
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
    ---@type BorderImage|nil
    self.preview = nil
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

function MenuPrism:UpdateFaceLabels(centerIndex, frontMaskIndex)
    for i, label in ipairs(self.faceLabels) do
        local localYaw = self.labelLocalYaws[i] or 0.0
        local definition = self:LevelForFaceYaw(localYaw, centerIndex, frontMaskIndex)
        label:SetText(definition and definition.code or "--")
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
    self.restY = -PRISM_DROP
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
    self:BuildFaceLabels(edgeLength)
    self:BuildExhibits(height)
    self:ApplyVisualYaw(SNAP_OFFSET_DEGREES)
    self.yawDegrees = SNAP_OFFSET_DEGREES
    self.targetYawDegrees = SNAP_OFFSET_DEGREES
    self.snapYawDegrees = SNAP_OFFSET_DEGREES
    self:CreatePreview()
    self:SyncRtCamera()
    print("MenuPrism: pale-blue hex prism + red mask RT ready")
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
    self:SyncPreviewSize()
    print(string.format("MenuPrism: RT resized to %dx%d", width, height))
end

function MenuPrism:BuildMaskQuads(edgeLength, prismHeight)
    if not self.root then
        return
    end
    -- 挂在棱柱根上，跟着一起转。
    -- 六个三棱柱中心距 = edge/√3，整体外接半径 = 2*edge/√3。
    -- 面宽取外接六边形边长 = 2*edge/√3，面心距 = √3/2 * 边长 = edge。
    -- 本地 yaw 加 30°，与下方棱柱侧面中点对齐。
    -- 颜色只在 floor(yaw/60) 整档变化时更新：正对相机的面绿，其余红。
    self.maskRoot = self.root:CreateChild("MenuMaskQuads")
    self.maskMaterials = {}
    self.maskLocalYaws = {}
    local hexSide = edgeLength * 2.0 / math.sqrt(3.0)
    local radius = hexSide * math.sqrt(3.0) * 0.5
    local faceWidth = hexSide
    local faceHeight = prismHeight * 0.85
    local thickness = 0.02
    local centerY = prismHeight + faceHeight * 0.5
    for i = 0, 5 do
        local yaw = i * 60.0 + SNAP_OFFSET_DEGREES
        local rad = math.rad(yaw)
        local node = self.maskRoot:CreateChild("MaskQuad_" .. tostring(i + 1))
        node.position = Vector3(math.sin(rad) * radius, centerY, math.cos(rad) * radius)
        node.rotation = Quaternion(yaw, Vector3.UP)
        node.scale = Vector3(faceWidth, faceHeight, thickness)
        local material = LookApplier.CreateStillObjectUnlitMaterial({
            color = "#FF0000",
            opaque = true,
        })
        local technique = material:GetTechnique(0)
        if technique and technique:HasPass("base") then
            local pass = technique:GetPass("base")
            pass:SetBlendMode(BLEND_REPLACE)
            pass:SetDepthWrite(true)
        end
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

function MenuPrism:BuildFaceLabels(edgeLength)
    self.faceLabels = {}
    self.labelLocalYaws = {}
    if #self.voxelNodes == 0 then
        return
    end
    local font = cache:GetResource("Font", FACE_LABEL_FONT)
    if not font then
        print("MenuPrism: missing face label font")
        return
    end
    -- Text3D 必须保留默认字体材质；自定义 shader 会冲掉字形图集，变成方块。
    local radius = edgeLength / math.sqrt(3.0)
    local outward = radius * 0.5 + FACE_LABEL_LIFT
    for i, voxelNode in ipairs(self.voxelNodes) do
        local labelNode = voxelNode:CreateChild("FaceLabel_" .. tostring(i))
        labelNode.position = Vector3(outward, 0.0, 0.0)
        labelNode.rotation = Quaternion(-90.0, Vector3.UP)
        labelNode.scale = Vector3(FACE_LABEL_SCALE, FACE_LABEL_SCALE, FACE_LABEL_SCALE)
        local text = labelNode:CreateComponent("Text3D")
        text:SetFont(font, FACE_LABEL_SIZE)
        text:SetText("--")
        text:SetColor(FACE_LABEL_COLOR)
        text:SetAlignment(HA_CENTER, VA_CENTER)
        text:SetTextAlignment(HA_CENTER)
        text:SetFaceCameraMode(FC_NONE)
        text:SetFixedScreenSize(false)
        text.viewMask = WORLD_BIT
        self.faceLabels[#self.faceLabels + 1] = text
        self.labelLocalYaws[#self.labelLocalYaws + 1] = (i - 1) * STEP_DEGREES + 90.0
    end
    print("MenuPrism: six solid-face labels ready")
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

function MenuPrism:CreateClipMaterial(stencilId, look)
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
    local technique = material:GetTechnique(0)
    if technique and technique:HasPass("base") then
        local pass = technique:GetPass("base")
        pass:SetBlendMode(BLEND_REPLACE)
        pass:SetDepthWrite(true)
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
    self.exhibitNodes[#self.exhibitNodes + 1] = entry.node
    return entry.node
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

    local cube = self:AddExhibitModel(
        self.exhibitRoot,
        "ExhibitCube",
        BoxGeometry(0.38, 0.38, 0.38):ToModel(),
        1,
        { color = "#90B1BD" }
    )
    cube.position = Vector3(0.0, 0.19, 0.0)

    local cylinder = self:AddExhibitModel(
        self.exhibitRoot,
        "ExhibitCylinder",
        CylinderGeometry(0.16, 0.16, 0.42, 16, 1, false):ToModel(),
        2,
        { color = "#72856F" }
    )
    cylinder.position = Vector3(0.0, 0.21, 0.0)

    local prism = self:AddExhibitModel(
        self.exhibitRoot,
        "ExhibitTriPrism",
        CylinderGeometry(0.24, 0.24, 0.42, 3, 1, false):ToModel(),
        3,
        { color = "#8064A4" }
    )
    prism.position = Vector3(0.0, 0.21, 0.0)

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

function MenuPrism:CreatePreview()
    local rtTexture = self.rtTexture
    if not rtTexture then
        print("MenuPrism: preview skipped, no RT texture")
        return
    end
    self.preview = BorderImage:new()
    self.preview:SetTexture(rtTexture)
    self.preview:SetFullImageRect()
    self.preview:SetAlignment(HA_RIGHT, VA_BOTTOM)
    self.preview:SetPosition(-16, -16)
    ui.root:AddChild(self.preview)
    self:SyncPreviewSize()
    print("MenuPrism: RT preview attached")
end

function MenuPrism:SyncPreviewSize()
    if not self.preview or self.rtWidth <= 0 or self.rtHeight <= 0 then
        return
    end
    local height = PREVIEW_HEIGHT
    local width = math.floor(height * self.rtWidth / self.rtHeight + 0.5)
    if width < 8 then
        width = 8
    end
    self.preview:SetSize(width, height)
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
    if self.preview then
        self.preview:Remove()
        self.preview = nil
    end
    self.maskRoot = nil
    self.maskMaterials = {}
    self.maskLocalYaws = {}
    self.lastStepIndex = nil
    self.window = {}
    self.exhibitRoot = nil
    self.exhibitNodes = {}
    self.faceLabels = {}
    self.labelLocalYaws = {}
    self.onFrontClicked = nil
    self.onFrontEditClicked = nil
    self.onExitReady = nil
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
