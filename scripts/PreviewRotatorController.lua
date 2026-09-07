-- Preview 机关拖动旋转。
-- 只服务 Game Preview：持续拖动表现层，松手后 Snap 到离散 yawSteps。
-- 不改编辑器立刻 SetYawSteps / Rebuild 的工作流。

local PartDefinition = require "PartDefinition"
local PointerInput = require "PointerInput"

local PreviewRotatorController = {}
PreviewRotatorController.__index = PreviewRotatorController

local STEP_DEGREES = 60.0
local DRAG_FOLLOW = 14.0
local SNAP_FOLLOW = 16.0
local SNAP_EPSILON = 0.6
local DRAG_DEADZONE_PIXELS = 8.0
local SLIP_MIN_ANGLE_DEGREES = 8.0
local MIN_HANDLE_RADIUS = 0.35
local HANDLE_PLANE_NORMAL = Vector3.UP

local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"
local PHASE_SLIP = "slip"

local function Clamp01(value)
    return math.max(0.0, math.min(1.0, value))
end

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
    return PointerInput.GetScreenRay(camera)
end

local function GetPointerPosition()
    return PointerInput.Get().position
end

local function IntersectYawPlane(ray, planePoint)
    local plane = Plane(HANDLE_PLANE_NORMAL, planePoint)
    local distance = ray:HitDistance(plane)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    return ray.origin + ray.direction * distance
end

local function FlattenYawVector(vector)
    return Vector3(vector.x, 0, vector.z)
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

function PreviewRotatorController.New(levelDocument, partRenderer, pathRuntime, camera, scene, player, algernon, riderFollow)
    local self = setmetatable({}, PreviewRotatorController)
    self.levelDocument = levelDocument
    self.partRenderer = partRenderer
    self.pathRuntime = pathRuntime
    self.camera = camera
    self.scene = scene
    self.player = player
    self.algernon = algernon
    self.riderFollow = riderFollow
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.baseYawDegrees = 0.0
    self.currentYawDegrees = 0.0
    self.snapYawDegrees = 0.0
    self.dragStartVector = nil
    self.dragStartMouse = nil
    self.dragCommitted = false
    self.pendingClickConsumed = false
    self.autoPick = true
    self.targetYawDegrees = 0.0
    self.visualYawDegrees = 0.0
    self.rotatorFaults = {}
    self.attemptElapsed = 0.0
    self.attemptFaultPrepared = false
    self.stallAttempt = false
    self.slipScheduled = false
    self.slipActive = false
    self.slipElapsed = 0.0
    self.slipStartYawDegrees = 0.0
    self.slowSnapAttempt = false
    self.failedSnapAttempt = false
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

function PreviewRotatorController:SetFault(partId, config)
    if type(partId) ~= "string" or partId == "" then
        return false
    end
    if type(config) ~= "table" then
        self.rotatorFaults[partId] = nil
        return true
    end
    local function Chance(value)
        return Clamp01(tonumber(value) or 0.0)
    end
    self.rotatorFaults[partId] = {
        slipChance = Chance(config.slipChance),
        stallChance = Chance(config.stallChance),
        slowSnapChance = Chance(config.slowSnapChance),
        slipDelay = math.max(0.05, tonumber(config.slipDelay) or 0.45),
    }
    return true
end

function PreviewRotatorController:PrepareFaultAttempt(part)
    if self.attemptFaultPrepared then
        return
    end
    self.attemptFaultPrepared = true
    self.attemptElapsed = 0.0
    self.stallAttempt = false
    self.slipScheduled = false
    self.slipActive = false
    self.slowSnapAttempt = false
    self.failedSnapAttempt = false
    local config = self.rotatorFaults[part.id]
    if not config then
        return
    end
    self.stallAttempt = math.random() < config.stallChance
    self.slipScheduled = not self.stallAttempt and math.random() < config.slipChance
    self.slowSnapAttempt = not self.stallAttempt and not self.slipScheduled
        and math.random() < config.slowSnapChance
    if self.stallAttempt or self.slipScheduled or self.slowSnapAttempt then
        print(string.format(
            "Preview Rotator: fault prepared part=%s stall=%s slip=%s slowSnap=%s",
            part.id,
            tostring(self.stallAttempt),
            tostring(self.slipScheduled),
            tostring(self.slowSnapAttempt)
        ))
    end
end

function PreviewRotatorController:IsFaultAttemptActive()
    return self.stallAttempt or self.slipScheduled or self.slipActive or self.slowSnapAttempt
end

function PreviewRotatorController:FinishAttempt()
    self.attemptFaultPrepared = false
    self.stallAttempt = false
    self.slipScheduled = false
    self.slipActive = false
    self.slipElapsed = 0.0
    self.slowSnapAttempt = false
    self.failedSnapAttempt = false
end

function PreviewRotatorController:IsBusy()
    return self.phase == PHASE_DRAG or self.phase == PHASE_SNAP or self.phase == PHASE_SLIP
end

function PreviewRotatorController:ConsumePendingClick()
    local consumed = self.pendingClickConsumed
    self.pendingClickConsumed = false
    return consumed
end

function PreviewRotatorController:GetPlayerPartId()
    if not self.player then
        return nil
    end
    local record = self.pathRuntime:GetNode(self.player:GetCurrentNodeKey())
    return record and record.partId or nil
end

function PreviewRotatorController:IsPlayerOnPart(part)
    if self.riderFollow then
        return self.riderFollow:IsOnPart(self.player, part)
    end
    local playerPartId = self:GetPlayerPartId()
    if not playerPartId then
        return false
    end
    return playerPartId == part.id
        or self.levelDocument:IsDescendant(playerPartId, part.id)
end

-- 只有角色正在该 Part 上走路时才禁止拖动。静止站在路径节点上允许转，并跟随 Part。
function PreviewRotatorController:IsWalkingOnPart(part)
    if self.riderFollow then
        return self.riderFollow:IsWalkingOnPart(self.player, part)
    end
    return self.player
        and self.player:IsWalking()
        and self:IsPlayerOnPart(part)
end

function PreviewRotatorController:SetPlayerLocked(locked)
    if self.riderFollow then
        self.riderFollow:LockPlayer(locked)
        return
    end
    if self.player and self.player.SetMechanismLocked then
        self.player:SetMechanismLocked(locked)
    end
end

function PreviewRotatorController:FollowRider()
    if not self.activePart then
        return
    end
    if self.riderFollow then
        self.riderFollow:SyncOnPart(self.activePart)
        return
    end
    if self.player and self:IsPlayerOnPart(self.activePart) then
        self.player:FollowCurrentNodeVisual(self.partRenderer)
    end
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
    self:FollowRider()
    self:SetPlayerLocked(false)
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
    self.targetYawDegrees = fromYawDegrees
    self.visualYawDegrees = fromYawDegrees
    self.snapYawDegrees = fromYawDegrees
    self.dragStartVector = hit - pivotPosition
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    self.dragCommitted = true
    return true
end

function PreviewRotatorController:BeginPending(part, ray, mouse)
    if self:IsWalkingOnPart(part) then
        print("Preview Rotator: blocked, player is walking on " .. part.id)
        return false
    end
    local pivotPosition = self.partRenderer:GetPivotWorldPosition(part.id)
    if not pivotPosition then
        return false
    end
    local hit = IntersectYawPlane(ray, pivotPosition)
    if not hit then
        return false
    end
    self.phase = PHASE_PENDING
    self.activePart = part
    self.baseYawDegrees = part.transform.rotation.yawSteps * STEP_DEGREES
    self.currentYawDegrees = self.baseYawDegrees
    self.targetYawDegrees = self.baseYawDegrees
    self.visualYawDegrees = self.baseYawDegrees
    self.snapYawDegrees = self.baseYawDegrees
    self.dragStartVector = hit - pivotPosition
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    self.dragCommitted = false
    self.pendingClickConsumed = false
    self:FinishAttempt()
    return true
end

function PreviewRotatorController:PromotePendingToDrag()
    local part = self.activePart
    if not part then
        return false
    end
    self.phase = PHASE_DRAG
    self.dragCommitted = true
    self:PrepareFaultAttempt(part)
    self:SetPlayerLocked(true)
    self:FollowRider()
    print("Preview Rotator: drag start " .. part.id)
    return true
end

function PreviewRotatorController:CancelPendingAsClick()
    self.pendingClickConsumed = true
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.dragCommitted = false
    self:FinishAttempt()
    return true
end

function PreviewRotatorController:CancelPendingQuietly()
    self.pendingClickConsumed = false
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.dragCommitted = false
    self:FinishAttempt()
    return true
end

function PreviewRotatorController:HasPendingPart(part)
    return self.phase == PHASE_PENDING and self.activePart and part and self.activePart.id == part.id
end

function PreviewRotatorController:GetPendingDragScore()
    if self.phase ~= PHASE_PENDING or not self.activePart or not self.dragStartMouse then
        return 0.0
    end
    local mouse = GetPointerPosition()
    local dx = mouse.x - self.dragStartMouse.x
    local dy = mouse.y - self.dragStartMouse.y
    if dx * dx + dy * dy < DRAG_DEADZONE_PIXELS * DRAG_DEADZONE_PIXELS then
        return 0.0
    end
    local pivotPosition = self.partRenderer:GetPivotWorldPosition(self.activePart.id)
    if not pivotPosition or not self.dragStartVector then
        return 0.0
    end
    local hit = IntersectYawPlane(GetScreenRay(self.camera), pivotPosition)
    if not hit then
        return 0.0
    end
    local handle = hit - pivotPosition
    local angle = math.abs(SignedYawDelta(self.dragStartVector, handle) or 0.0)
    local startRadius = FlattenYawVector(self.dragStartVector):Length()
    local currentRadius = FlattenYawVector(handle):Length()
    local radial = math.abs(currentRadius - startRadius)
    return angle * math.max(0.25, HandleRadiusWeight(handle)) - radial * 18.0
end

function PreviewRotatorController:InterruptSnap(ray, mouse)
    local part = self.activePart
    if not part then
        return false
    end
    if not self:CaptureDrag(part, ray, mouse, self.currentYawDegrees) then
        return false
    end
    self:PrepareFaultAttempt(part)
    print("Preview Rotator: snap interrupted, resume drag " .. part.id)
    return true
end

function PreviewRotatorController:SampleTargetYaw()
    local part = self.activePart
    local pivotPosition = self.partRenderer:GetPivotWorldPosition(part.id)
    if not pivotPosition then
        return nil
    end
    local hit = IntersectYawPlane(GetScreenRay(self.camera), pivotPosition)
    if not hit then
        return nil
    end
    local handle = hit - pivotPosition
    local delta = SignedYawDelta(self.dragStartVector, handle)
    if not delta then
        return nil
    end
    -- 靠近轴心时平面角变化极快，压低灵敏度，避免塔跟着鼠标乱跳。
    return self.baseYawDegrees + delta * HandleRadiusWeight(handle)
end

function PreviewRotatorController:ApplyVisualYaw(yawDegrees)
    local part = self.activePart
    if not part then
        return
    end
    self.visualYawDegrees = yawDegrees
    self.currentYawDegrees = yawDegrees
    self.partRenderer:SetVisualYaw(part.id, yawDegrees)
    self:FollowRider()
end

function PreviewRotatorController:UpdateDrag(timeStep)
    local part = self.activePart
    if not part then
        return
    end
    self.attemptElapsed = self.attemptElapsed + timeStep
    local config = self.rotatorFaults[part.id]
    if self.slipScheduled
        and config
        and self.attemptElapsed >= config.slipDelay
        and math.abs(ShortestDelta(self.baseYawDegrees, self.visualYawDegrees)) >= SLIP_MIN_ANGLE_DEGREES then
        self.slipScheduled = false
        self.slipActive = true
        self.slipElapsed = 0.0
        self.slipStartYawDegrees = self.visualYawDegrees
        self.phase = PHASE_SLIP
        print("Preview Rotator: slipped back during drag " .. part.id)
        return
    end
    local target = self:SampleTargetYaw()
    if target and not self.stallAttempt then
        self.targetYawDegrees = target
    end
    self:ApplyVisualYaw(ApproachAngle(
        self.visualYawDegrees,
        self.targetYawDegrees,
        DRAG_FOLLOW,
        timeStep
    ))
end

function PreviewRotatorController:UpdateSlip(timeStep)
    local part = self.activePart
    if not part then
        return
    end
    self.slipElapsed = self.slipElapsed + timeStep
    local progress = Clamp01(self.slipElapsed / 0.32)
    local eased = 1.0 - (1.0 - progress) * (1.0 - progress)
    local yaw = self.slipStartYawDegrees
        + ShortestDelta(self.slipStartYawDegrees, self.baseYawDegrees) * eased
    self:ApplyVisualYaw(yaw)
    if progress >= 1.0 then
        self:ApplyVisualYaw(self.baseYawDegrees)
        self:SetPlayerLocked(false)
        self.phase = PHASE_IDLE
        self.activePart = nil
        self.dragCommitted = false
        self:FinishAttempt()
        print("Preview Rotator: slip recovery finished")
    end
end

function PreviewRotatorController:BeginSnap()
    local part = self.activePart
    if not self.dragCommitted then
        self:CancelPendingAsClick()
        return false
    end
    if self.stallAttempt then
        self.snapYawDegrees = self.baseYawDegrees
        self.targetYawDegrees = self.snapYawDegrees
        self.slowSnapAttempt = false
        self.failedSnapAttempt = true
        self.phase = PHASE_SNAP
        print("Preview Rotator: stalled drag snaps back " .. part.id)
        return true
    end
    local _, snappedDegrees = self:NearestAllowedYaw(part, self.targetYawDegrees)
    self.snapYawDegrees = self.visualYawDegrees + ShortestDelta(self.visualYawDegrees, snappedDegrees)
    self.targetYawDegrees = self.snapYawDegrees
    self.phase = PHASE_SNAP
    return true
end

function PreviewRotatorController:UpdateSnap(timeStep)
    local part = self.activePart
    local remaining = ShortestDelta(self.visualYawDegrees, self.snapYawDegrees)
    if math.abs(remaining) <= SNAP_EPSILON then
        self:ApplyVisualYaw(self.snapYawDegrees)
        if self.failedSnapAttempt then
            self:SetPlayerLocked(false)
            self.phase = PHASE_IDLE
            self.activePart = nil
            self.dragCommitted = false
            self:FinishAttempt()
            print("Preview Rotator: failed snap returned to authored yaw")
            return
        end
        local committed = self:CommitSnap(part)
        if not committed then
            self:ApplyVisualYaw(self.baseYawDegrees)
            self:SetPlayerLocked(false)
            print("Preview Rotator: snap cleanup after rejected commit")
        end
        self.phase = PHASE_IDLE
        self.activePart = nil
        self.dragCommitted = false
        self:FinishAttempt()
        return
    end
    local follow = self.slowSnapAttempt and SNAP_FOLLOW * 0.5 or SNAP_FOLLOW
    self:ApplyVisualYaw(ApproachAngle(
        self.visualYawDegrees,
        self.snapYawDegrees,
        follow,
        timeStep
    ))
end

-- 按手势分流：按下先 pending，拖过死区才旋转，原地松开把点击交还给寻路。
function PreviewRotatorController:Update(timeStep)
    local pointer = PointerInput.Get()
    if self.phase == PHASE_PENDING then
        if not pointer.down then
            self:CancelPendingAsClick()
            return false
        end
        local mouse = pointer.position
        local dx = mouse.x - self.dragStartMouse.x
        local dy = mouse.y - self.dragStartMouse.y
        if dx * dx + dy * dy >= DRAG_DEADZONE_PIXELS * DRAG_DEADZONE_PIXELS then
            self:PromotePendingToDrag()
            self:UpdateDrag(timeStep)
            return true
        end
        return true
    end
    if self.phase == PHASE_DRAG then
        if pointer.down then
            self:UpdateDrag(timeStep)
        else
            self:BeginSnap()
        end
        return true
    end
    if self.phase == PHASE_SLIP then
        self:UpdateSlip(timeStep)
        return true
    end
    if self.phase == PHASE_SNAP then
        if pointer.pressed then
            local ray = GetScreenRay(self.camera)
            local part = self:PickRotatorPart(ray)
            if part and self.activePart and part.id == self.activePart.id then
                self:InterruptSnap(ray, pointer.position)
                return true
            end
        end
        self:UpdateSnap(timeStep)
        return true
    end
    if not self.autoPick or not pointer.pressed then
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
    return self:BeginPending(part, ray, pointer.position)
end

return PreviewRotatorController
