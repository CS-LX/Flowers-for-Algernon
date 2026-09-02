-- 选关菜单里的淡蓝六棱柱。
-- 只服务选关场景：拖转表现层，松手后 Snap 到 60°。不进关卡数据，不挂 UI。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local PointerInput = require "PointerInput"

---@class MenuPrism
---@field scene Scene
---@field camera Camera
---@field cameraNode Node|nil
---@field worldViewport Viewport|nil
---@field root Node|nil
---@field voxelNodes Node[]
---@field maskRoot Node|nil
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
local PRISM_DROP = 0.55
local PREVIEW_HEIGHT = 160
local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"

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
    return self
end

function MenuPrism:ApplyVisualYaw(yawDegrees)
    self.visualYawDegrees = yawDegrees
    if self.root then
        self.root.rotation = Quaternion(yawDegrees, Vector3.UP)
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
    self.root.position = Vector3(0.0, -PRISM_DROP, 0.0)
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
    local maskMaterial = LookApplier.CreateStillObjectUnlitMaterial({
        color = "#FF0000",
        opaque = true,
    })
    local technique = maskMaterial:GetTechnique(0)
    if technique and technique:HasPass("base") then
        local pass = technique:GetPass("base")
        pass:SetBlendMode(BLEND_REPLACE)
        pass:SetDepthWrite(true)
    end
    -- 挂在棱柱根上，跟着一起转。
    -- 六个三棱柱中心距 = edge/√3，整体外接半径 = 2*edge/√3。
    -- 面宽取外接六边形边长 = 2*edge/√3，面心距 = √3/2 * 边长 = edge。
    self.maskRoot = self.root:CreateChild("MenuMaskQuads")
    local hexSide = edgeLength * 2.0 / math.sqrt(3.0)
    local radius = hexSide * math.sqrt(3.0) * 0.5
    local faceWidth = hexSide
    local faceHeight = prismHeight * 0.85
    local thickness = 0.02
    local centerY = prismHeight + faceHeight * 0.5
    for i = 0, 5 do
        local yaw = i * 60.0
        local rad = math.rad(yaw)
        local node = self.maskRoot:CreateChild("MaskQuad_" .. tostring(i + 1))
        node.position = Vector3(math.sin(rad) * radius, centerY, math.cos(rad) * radius)
        node.rotation = Quaternion(yaw, Vector3.UP)
        node.scale = Vector3(faceWidth, faceHeight, thickness)
        local model = node:CreateComponent("StaticModel")
        model:SetModel(cache:GetResource("Model", "Models/Box.mdl"))
        model:SetMaterial(maskMaterial)
        model.viewMask = MASK_BIT
        model.castShadows = false
    end
    print("MenuPrism: six red mask quads parented to prism")
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

function MenuPrism:CancelPending()
    self.phase = PHASE_IDLE
    self.dragStartMouse = nil
end

function MenuPrism:Update(timeStep)
    self:ResizeRtIfNeeded()
    self:SyncRtCamera()
    if self.rtTexture then
        local surface = self.rtTexture:GetRenderSurface()
        if surface then
            surface:QueueUpdate()
        end
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
