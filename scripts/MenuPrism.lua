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
---@field dragStartVector Vector3|nil
---@field dragStartMouse Vector2|nil
local MenuPrism = {}
MenuPrism.__index = MenuPrism

local STEP_DEGREES = 60.0
local DRAG_FOLLOW = 14.0
local SNAP_FOLLOW = 16.0
local SNAP_EPSILON = 0.6
local DRAG_DEADZONE_PIXELS = 8.0
local MIN_HANDLE_RADIUS = 0.35
local HANDLE_PLANE_NORMAL = Vector3.UP
local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"

-- 第一章门框淡蓝：assets/Levels/chapter-1.json stillObjects[0].params
local DOOR_FRAME_LOOK = {
    shader = LookApplier.SHADER_TRI_PRISM_LOOK,
    colorNeg = "#959CA2",
    colorMid = "#9AA0A6",
    colorPos = "#B2BDC1",
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

local function FlattenYawVector(vector)
    return Vector3(vector.x, 0, vector.z)
end

local function IntersectYawPlane(ray, planePoint)
    local plane = Plane(HANDLE_PLANE_NORMAL, planePoint)
    local distance = ray:HitDistance(plane)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    return ray.origin + ray.direction * distance
end

local function SignedYawDelta(fromVector, toVector)
    local from = FlattenYawVector(fromVector)
    local to = FlattenYawVector(toVector)
    if from:Length() < 0.001 or to:Length() < 0.001 then
        return nil
    end
    from = from:Normalized()
    to = to:Normalized()
    local angle = from:Angle(to)
    local cross = from:CrossProduct(to)
    if HANDLE_PLANE_NORMAL:DotProduct(cross) < 0 then
        return -angle
    end
    return angle
end

local function HandleRadiusWeight(vector)
    local radius = FlattenYawVector(vector):Length()
    if radius >= MIN_HANDLE_RADIUS then
        return 1.0
    end
    return radius / MIN_HANDLE_RADIUS
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
    local step = math.floor(yawDegrees / STEP_DEGREES + 0.5)
    return step * STEP_DEGREES
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
    ---@type Vector3|nil
    self.dragStartVector = nil
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
    local height = VoxelRenderer.DEFAULT_HEIGHT
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
            edgeLength = VoxelRenderer.DEFAULT_EDGE,
            height = height,
            material = material,
        }
    )
    self:ApplyVisualYaw(0.0)
    print("MenuPrism: pale-blue hex prism ready")
    return true
end

function MenuPrism:HitPrism(ray)
    for _, node in ipairs(self.voxelNodes) do
        local drawable = node:GetComponent("CustomGeometry")
        if drawable then
            local distance = ray:HitDistance(drawable.worldBoundingBox)
            if distance and distance ~= M_INFINITY and distance >= 0 then
                return true
            end
        end
    end
    return false
end

function MenuPrism:SampleTargetYaw()
    if not self.root or not self.dragStartVector then
        return nil
    end
    local hit = IntersectYawPlane(PointerInput.GetScreenRay(self.camera), self.root.worldPosition)
    if not hit then
        return nil
    end
    local handle = hit - self.root.worldPosition
    local delta = SignedYawDelta(self.dragStartVector, handle)
    if not delta then
        return nil
    end
    return self.yawDegrees + delta * HandleRadiusWeight(handle)
end

function MenuPrism:BeginPending(ray, mouse)
    if not self.root then
        return false
    end
    local hit = IntersectYawPlane(ray, self.root.worldPosition)
    if not hit then
        return false
    end
    self.phase = PHASE_PENDING
    self.yawDegrees = self.visualYawDegrees
    self.targetYawDegrees = self.visualYawDegrees
    self.snapYawDegrees = self.visualYawDegrees
    self.dragStartVector = hit - self.root.worldPosition
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
        self.dragStartVector = nil
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
    self.dragStartVector = nil
    self.dragStartMouse = nil
end

function MenuPrism:Update(timeStep)
    PointerInput.BeginFrame()
    local pointer = PointerInput.Get()
    if self.phase == PHASE_IDLE then
        if pointer.pressed then
            local ray = PointerInput.GetScreenRay(self.camera)
            if self:HitPrism(ray) then
                self:BeginPending(ray, pointer.position)
            end
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
        local dy = mouse.y - startMouse.y
        if dx * dx + dy * dy >= DRAG_DEADZONE_PIXELS * DRAG_DEADZONE_PIXELS then
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
