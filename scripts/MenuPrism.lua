-- 选关菜单里的淡蓝六棱柱。
-- 只服务选关场景：拖转表现层，松手后 Snap 到 60°。不进关卡数据，不挂 UI。

local VoxelRenderer = require "VoxelRenderer"
local LookApplier = require "LookApplier"
local PointerInput = require "PointerInput"

---@class MenuPrism
---@field scene Scene
---@field camera Camera
---@field root Node|nil
---@field voxelNodes Node[]
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

function MenuPrism.New(scene, camera)
    local self = setmetatable({}, MenuPrism)
    self.scene = scene
    self.camera = camera
    ---@type Node|nil
    self.root = nil
    ---@type Node[]
    self.voxelNodes = {}
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
    self.root = self.scene:CreateChild("MenuPrismRoot")
    self.root.position = Vector3(0.0, 0.0, 0.0)
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
    self:ApplyVisualYaw(SNAP_OFFSET_DEGREES)
    self.yawDegrees = SNAP_OFFSET_DEGREES
    self.targetYawDegrees = SNAP_OFFSET_DEGREES
    self.snapYawDegrees = SNAP_OFFSET_DEGREES
    print("MenuPrism: pale-blue hex prism ready")
    return true
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
    if self.root then
        self.root:Remove()
        self.root = nil
    end
    self.voxelNodes = {}
    self.phase = PHASE_IDLE
end

return MenuPrism
