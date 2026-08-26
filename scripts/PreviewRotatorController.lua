-- Preview 机关拖动旋转。
-- 只服务 Game Preview：持续拖动表现层，松手后 Snap 到离散 yawSteps。
-- 不改编辑器立刻 SetYawSteps / Rebuild 的工作流。

local PartDefinition = require "PartDefinition"

local PreviewRotatorController = {}
PreviewRotatorController.__index = PreviewRotatorController

local STEP_DEGREES = 60.0
local SNAP_LERP = 12.0
local SNAP_EPSILON = 0.35
local DRAG_DEADZONE_PIXELS = 6.0
local HANDLE_PLANE_NORMAL = Vector3.UP

local PHASE_IDLE = "idle"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"

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

local function GetScreenRay(camera)
    local mouse = input:GetMousePosition()
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    return camera:GetScreenRay(mouse.x / width, mouse.y / height)
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
    local from = Vector3(fromVector.x, 0, fromVector.z)
    local to = Vector3(toVector.x, 0, toVector.z)
    if from:Length() < 0.001 or to:Length() < 0.001 then
        return 0.0
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

function PreviewRotatorController.New(levelDocument, partRenderer, pathRuntime, camera, scene, player)
    local self = setmetatable({}, PreviewRotatorController)
    self.levelDocument = levelDocument
    self.partRenderer = partRenderer
    self.pathRuntime = pathRuntime
    self.camera = camera
    self.scene = scene
    self.player = player
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.baseYawDegrees = 0.0
    self.currentYawDegrees = 0.0
    self.snapYawDegrees = 0.0
    self.dragStartVector = nil
    self.dragStartMouse = nil
    self.dragCommitted = false
    self.authoredStates = {}
    for _, part in ipairs(self.levelDocument:GetParts()) do
        if part:HasBehavior(PartDefinition.MODE_ROTATOR) then
            self.authoredStates[part.id] = part.transform.rotation.yawSteps
        end
    end
    return self
end

function PreviewRotatorController:RestoreAuthoredStates()
    for partId, steps in pairs(self.authoredStates or {}) do
        local part = self.levelDocument:GetPart(partId)
        if part then
            part:SetYawSteps(steps)
        end
    end
end

function PreviewRotatorController:IsBusy()
    return self.phase ~= PHASE_IDLE
end

function PreviewRotatorController:GetPlayerPartId()
    if not self.player then
        return nil
    end
    local record = self.pathRuntime:GetNode(self.player:GetCurrentNodeKey())
    return record and record.partId or nil
end

-- 角色站在该可动 Part 或其子 Part 上时，禁止拖动。
function PreviewRotatorController:IsOccupiedByPlayer(part)
    local playerPartId = self:GetPlayerPartId()
    if not playerPartId then
        return false
    end
    return playerPartId == part.id
        or self.levelDocument:IsDescendant(playerPartId, part.id)
end

function PreviewRotatorController:PickRotatorPart(ray)
    local bestPart = nil
    local bestDistance = math.huge
    for _, part in ipairs(self.levelDocument:GetParts()) do
        if part:HasBehavior(PartDefinition.MODE_ROTATOR) then
            local distance = self.partRenderer:RaycastPart(part.id, ray)
            if distance and distance < bestDistance then
                bestDistance = distance
                bestPart = part
            end
        end
    end
    return bestPart
end

function PreviewRotatorController:NearestAllowedYaw(part, yawDegrees)
    local rotator = part.behaviors.rotator
    local bestStep = rotator.allowedSteps[1]
    local bestDistance = math.huge
    for _, step in ipairs(rotator.allowedSteps) do
        local target = step * STEP_DEGREES
        local distance = math.abs(ShortestDelta(yawDegrees, target))
        if distance < bestDistance then
            bestDistance = distance
            bestStep = step
        end
    end
    return bestStep, bestStep * STEP_DEGREES
end

function PreviewRotatorController:CommitSnap(part)
    local step = self:NearestAllowedYaw(part, self.currentYawDegrees)
    if not part:SetYawSteps(step) then
        print("Preview Rotator: snap rejected for " .. part.id)
        return false
    end
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local refreshed, errorMessage = self.pathRuntime:RefreshAfterMechanismSnap()
    if not refreshed then
        print("Preview Rotator: path refresh failed: " .. tostring(errorMessage))
        return false
    end
    print(string.format(
        "Preview Rotator: snapped %s to yawSteps=%d (%d deg)",
        part.name,
        part.transform.rotation.yawSteps,
        part.transform.rotation.yawSteps * STEP_DEGREES
    ))
    return true
end

function PreviewRotatorController:CaptureDrag(part, ray, mouse, fromYawDegrees)
    local pivotPosition = self.partRenderer:GetPivotWorldPosition(part.id)
    if not pivotPosition then
        return false
    end
    local hit = IntersectYawPlane(ray, pivotPosition)
    if not hit then
        return false
    end
    self.phase = PHASE_DRAG
    self.activePart = part
    self.baseYawDegrees = fromYawDegrees
    self.currentYawDegrees = fromYawDegrees
    self.snapYawDegrees = fromYawDegrees
    self.dragStartVector = hit - pivotPosition
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    self.dragCommitted = true
    return true
end

function PreviewRotatorController:BeginDrag(part, ray, mouse)
    if self.player and self.player:IsWalking() then
        return false
    end
    if self:IsOccupiedByPlayer(part) then
        print("Preview Rotator: blocked, player occupies " .. part.id)
        return false
    end
    if not self:CaptureDrag(part, ray, mouse, part.transform.rotation.yawSteps * STEP_DEGREES) then
        return false
    end
    self.dragCommitted = false
    print("Preview Rotator: drag start " .. part.id)
    return true
end

function PreviewRotatorController:InterruptSnap(ray, mouse)
    local part = self.activePart
    if not part then
        return false
    end
    if not self:CaptureDrag(part, ray, mouse, self.currentYawDegrees) then
        return false
    end
    print("Preview Rotator: snap interrupted, resume drag " .. part.id)
    return true
end

function PreviewRotatorController:UpdateDrag()
    local part = self.activePart
    local pivotPosition = self.partRenderer:GetPivotWorldPosition(part.id)
    if not pivotPosition then
        return
    end
    local mouse = input:GetMousePosition()
    if not self.dragCommitted then
        local dx = mouse.x - self.dragStartMouse.x
        local dy = mouse.y - self.dragStartMouse.y
        if dx * dx + dy * dy < DRAG_DEADZONE_PIXELS * DRAG_DEADZONE_PIXELS then
            return
        end
        self.dragCommitted = true
    end
    local hit = IntersectYawPlane(GetScreenRay(self.camera), pivotPosition)
    if not hit then
        return
    end
    self.currentYawDegrees = self.baseYawDegrees - SignedYawDelta(self.dragStartVector, hit - pivotPosition)
    self.partRenderer:SetVisualYaw(part.id, self.currentYawDegrees)
end

function PreviewRotatorController:BeginSnap()
    local part = self.activePart
    if not self.dragCommitted then
        self.partRenderer:SetVisualYaw(part.id, self.baseYawDegrees)
        self.phase = PHASE_IDLE
        self.activePart = nil
        return false
    end
    local _, snappedDegrees = self:NearestAllowedYaw(part, self.currentYawDegrees)
    self.snapYawDegrees = self.currentYawDegrees + ShortestDelta(self.currentYawDegrees, snappedDegrees)
    self.phase = PHASE_SNAP
    return true
end

function PreviewRotatorController:UpdateSnap(timeStep)
    local part = self.activePart
    local remaining = ShortestDelta(self.currentYawDegrees, self.snapYawDegrees)
    if math.abs(remaining) <= SNAP_EPSILON then
        self.currentYawDegrees = self.snapYawDegrees
        self:CommitSnap(part)
        self.phase = PHASE_IDLE
        self.activePart = nil
        return
    end
    self.currentYawDegrees = self.currentYawDegrees + remaining * math.min(1.0, SNAP_LERP * timeStep)
    self.partRenderer:SetVisualYaw(part.id, self.currentYawDegrees)
end

-- 返回 true 表示本帧已经消费点击，Preview 不要再拿去走角色。
function PreviewRotatorController:Update(timeStep)
    if self.phase == PHASE_DRAG then
        if input:GetMouseButtonDown(MOUSEB_LEFT) then
            self:UpdateDrag()
        else
            self:BeginSnap()
        end
        return true
    end
    if self.phase == PHASE_SNAP then
        if input:GetMouseButtonPress(MOUSEB_LEFT) then
            local ray = GetScreenRay(self.camera)
            local part = self:PickRotatorPart(ray)
            if part and self.activePart and part.id == self.activePart.id then
                self:InterruptSnap(ray, input:GetMousePosition())
                return true
            end
        end
        self:UpdateSnap(timeStep)
        return true
    end
    if not input:GetMouseButtonPress(MOUSEB_LEFT) then
        return false
    end
    if self.player and self.player:IsWalking() then
        return false
    end
    local ray = GetScreenRay(self.camera)
    local part = self:PickRotatorPart(ray)
    if not part then
        return false
    end
    print("Preview Rotator: picked " .. part.id)
    return self:BeginDrag(part, ray, input:GetMousePosition())
end

return PreviewRotatorController
