-- Preview 机关拖动平移。
-- 只服务 Game Preview：沿 Q / R / Layer 连续拖动，松手后 Snap 到半格。
-- 不改编辑器立刻改网格坐标的工作流。

local PartDefinition = require "PartDefinition"
local PointerInput = require "PointerInput"
local ControlSettings = require "ControlSettings"

local PreviewMoverController = {}
PreviewMoverController.__index = PreviewMoverController

local DRAG_FOLLOW = 14.0
local SNAP_FOLLOW = 16.0
local SNAP_EPSILON = 0.012
local DRAG_DEADZONE_PIXELS = 8.0
local SNAP_STEP = 0.5
local LAYER_SENSITIVITY = 0.012

local PHASE_IDLE = "idle"
local PHASE_PENDING = "pending"
local PHASE_DRAG = "drag"
local PHASE_SNAP = "snap"

local function CopyVector(vector)
    return Vector3(vector.x, vector.y, vector.z)
end

local function SnapToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

local function GetScreenRay(camera)
    return PointerInput.GetScreenRay(camera)
end

local function GetPointerPosition()
    return PointerInput.Get().position
end

local function IntersectHorizontalPlane(ray, planeY)
    local plane = Plane(Vector3.UP, Vector3(0, planeY, 0))
    local distance = ray:HitDistance(plane)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    return ray.origin + ray.direction * distance
end

local function ApproachVector(current, target, follow, timeStep)
    local remaining = target - current
    local step = remaining * math.min(1.0, follow * timeStep)
    if step:Length() >= remaining:Length() then
        return CopyVector(target)
    end
    return current + step
end

function PreviewMoverController.New(levelDocument, partRenderer, pathRuntime, camera, player, algernon, riderFollow)
    local self = setmetatable({}, PreviewMoverController)
    self.levelDocument = levelDocument
    self.partRenderer = partRenderer
    self.pathRuntime = pathRuntime
    self.camera = camera
    self.player = player
    self.algernon = algernon
    self.riderFollow = riderFollow
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.basePosition = Vector3.ZERO
    self.currentPosition = Vector3.ZERO
    self.targetPosition = Vector3.ZERO
    self.visualPosition = Vector3.ZERO
    self.snapPosition = Vector3.ZERO
    self.dragStartHit = nil
    self.dragStartMouse = nil
    self.dragCommitted = false
    self.pendingClickConsumed = false
    self.autoPick = true
    self.authoredPositions = {}
    for _, part in ipairs(self.levelDocument:GetParts()) do
        if part:HasBehavior(PartDefinition.MODE_MOVER) then
            self.authoredPositions[part.id] = CopyVector(Vector3(
                part.transform.position.x,
                part.transform.position.y,
                part.transform.position.z
            ))
        end
    end
    return self
end

function PreviewMoverController:RestoreAuthoredStates()
    for partId, position in pairs(self.authoredPositions or {}) do
        local part = self.levelDocument:GetPart(partId)
        if part then
            part:SetPosition(position)
        end
    end
end

function PreviewMoverController:IsBusy()
    return self.phase == PHASE_DRAG or self.phase == PHASE_SNAP
end

function PreviewMoverController:ConsumePendingClick()
    local consumed = self.pendingClickConsumed
    self.pendingClickConsumed = false
    return consumed
end

function PreviewMoverController:GetPlayerPartId()
    if not self.player then
        return nil
    end
    local record = self.pathRuntime:GetNode(self.player:GetCurrentNodeKey())
    return record and record.partId or nil
end

function PreviewMoverController:IsPlayerOnPart(part)
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

function PreviewMoverController:IsWalkingOnPart(part)
    if self.riderFollow then
        return self.riderFollow:IsWalkingOnPart(self.player, part)
    end
    return self.player
        and self.player:IsWalking()
        and self:IsPlayerOnPart(part)
end

function PreviewMoverController:SetPlayerLocked(locked)
    if self.riderFollow then
        self.riderFollow:LockPlayer(locked)
        return
    end
    if self.player and self.player.SetMechanismLocked then
        self.player:SetMechanismLocked(locked)
    end
end

function PreviewMoverController:FollowRider()
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

function PreviewMoverController:PickMoverPart(ray)
    local bestPart = nil
    local bestDistance = math.huge
    for _, part in ipairs(self.levelDocument:GetParts()) do
        if part:HasBehavior(PartDefinition.MODE_MOVER) then
            local distance = self.partRenderer:RaycastPart(part.id, ray)
            if distance and distance < bestDistance then
                bestDistance = distance
                bestPart = part
            end
        end
    end
    return bestPart, bestDistance
end

function PreviewMoverController:GetEnabledAxes(part)
    local axes = part.behaviors.mover and part.behaviors.mover.axes or {}
    return {
        q = axes.q ~= false,
        r = axes.r ~= false,
        layer = axes.layer ~= false,
    }
end

function PreviewMoverController:WorldToGrid(position)
    local hexQ, hexR = self.partRenderer.grid:WorldToHexFloat(position)
    return hexQ, hexR, position.y / self.partRenderer.voxelHeight
end

function PreviewMoverController:GridToWorld(hexQ, hexR, layer)
    return self.partRenderer.grid:GetHexCenter(
        hexQ,
        hexR,
        layer * self.partRenderer.voxelHeight
    )
end

function PreviewMoverController:ClampAxis(value, minValue, maxValue)
    if minValue ~= nil then
        value = math.max(minValue, value)
    end
    if maxValue ~= nil then
        value = math.min(maxValue, value)
    end
    return value
end

function PreviewMoverController:ConstrainGrid(part, hexQ, hexR, layer)
    local baseQ, baseR, baseLayer = self:WorldToGrid(self.basePosition)
    local axes = self:GetEnabledAxes(part)
    local mover = part.behaviors.mover or {}
    if not axes.q then
        hexQ = baseQ
    else
        hexQ = self:ClampAxis(hexQ, mover.minQ, mover.maxQ)
    end
    if not axes.r then
        hexR = baseR
    else
        hexR = self:ClampAxis(hexR, mover.minR, mover.maxR)
    end
    if not axes.layer then
        layer = baseLayer
    else
        layer = self:ClampAxis(layer, mover.minLayer, mover.maxLayer)
    end
    return hexQ, hexR, layer
end

function PreviewMoverController:SnapGrid(part, hexQ, hexR, layer)
    hexQ, hexR, layer = self:ConstrainGrid(part, hexQ, hexR, layer)
    return SnapToStep(hexQ, SNAP_STEP), SnapToStep(hexR, SNAP_STEP), SnapToStep(layer, SNAP_STEP)
end

function PreviewMoverController:ApplyVisualPosition(position)
    local part = self.activePart
    if not part then
        return
    end
    self.visualPosition = CopyVector(position)
    self.currentPosition = CopyVector(position)
    self.partRenderer:SetVisualPosition(part.id, position)
    self:FollowRider()
end

function PreviewMoverController:SampleTargetPosition()
    local part = self.activePart
    if not part then
        return nil
    end
    local axes = self:GetEnabledAxes(part)
    local ray = GetScreenRay(self.camera)
    local hexQ, hexR, layer = self:WorldToGrid(self.basePosition)
    if axes.q or axes.r then
        local hit = IntersectHorizontalPlane(ray, self.basePosition.y)
        if hit and self.dragStartHit then
            local delta = hit - self.dragStartHit
            local unconstrained = self.basePosition + Vector3(delta.x, 0, delta.z)
            hexQ, hexR = self.partRenderer.grid:WorldToHexFloat(unconstrained)
        end
    end
    if axes.layer and self.dragStartMouse then
        local mouse = GetPointerPosition()
        layer = layer + (self.dragStartMouse.y - mouse.y) * ControlSettings.LayerPixelsToStep()
    end
    hexQ, hexR, layer = self:ConstrainGrid(part, hexQ, hexR, layer)
    return self:GridToWorld(hexQ, hexR, layer)
end

function PreviewMoverController:BeginPending(part, ray, mouse)
    if self:IsWalkingOnPart(part) then
        print("Preview Mover: blocked, player is walking on " .. part.id)
        return false
    end
    local hit = IntersectHorizontalPlane(ray, part.transform.position.y)
    if not hit then
        return false
    end
    self.phase = PHASE_PENDING
    self.activePart = part
    self.basePosition = CopyVector(Vector3(
        part.transform.position.x,
        part.transform.position.y,
        part.transform.position.z
    ))
    self.currentPosition = CopyVector(self.basePosition)
    self.targetPosition = CopyVector(self.basePosition)
    self.visualPosition = CopyVector(self.basePosition)
    self.snapPosition = CopyVector(self.basePosition)
    self.dragStartHit = hit
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    self.dragCommitted = false
    self.pendingClickConsumed = false
    return true
end

function PreviewMoverController:PromotePendingToDrag()
    local part = self.activePart
    if not part then
        return false
    end
    self.phase = PHASE_DRAG
    self.dragCommitted = true
    self:SetPlayerLocked(true)
    self:FollowRider()
    print("Preview Mover: drag start " .. part.id)
    return true
end

function PreviewMoverController:CancelPendingAsClick()
    self.pendingClickConsumed = true
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.dragCommitted = false
    return true
end

function PreviewMoverController:CancelPendingQuietly()
    self.pendingClickConsumed = false
    self.phase = PHASE_IDLE
    self.activePart = nil
    self.dragCommitted = false
    return true
end

function PreviewMoverController:HasPendingPart(part)
    return self.phase == PHASE_PENDING and self.activePart and part and self.activePart.id == part.id
end

function PreviewMoverController:GetPendingDragScore()
    if self.phase ~= PHASE_PENDING or not self.activePart or not self.dragStartMouse then
        return 0.0
    end
    local mouse = GetPointerPosition()
    local dx = mouse.x - self.dragStartMouse.x
    local dy = mouse.y - self.dragStartMouse.y
    if dx * dx + dy * dy < DRAG_DEADZONE_PIXELS * DRAG_DEADZONE_PIXELS then
        return 0.0
    end
    local axes = self:GetEnabledAxes(self.activePart)
    local score = 0.0
    if (axes.q or axes.r) and self.dragStartHit then
        local hit = IntersectHorizontalPlane(GetScreenRay(self.camera), self.basePosition.y)
        if hit then
            local delta = hit - self.dragStartHit
            score = score + Vector3(delta.x, 0, delta.z):Length() * 8.0
        end
    end
    if axes.layer then
        score = score + math.abs(dy) * LAYER_SENSITIVITY * 4.0
    end
    return score
end

function PreviewMoverController:InterruptSnap(ray, mouse)
    local part = self.activePart
    if not part then
        return false
    end
    local hit = IntersectHorizontalPlane(ray, self.currentPosition.y)
    if not hit then
        return false
    end
    self.phase = PHASE_DRAG
    self.basePosition = CopyVector(self.currentPosition)
    self.dragStartHit = hit
    self.dragStartMouse = Vector2(mouse.x, mouse.y)
    self.dragCommitted = true
    print("Preview Mover: snap interrupted, resume drag " .. part.id)
    return true
end

function PreviewMoverController:UpdateDrag(timeStep)
    local target = self:SampleTargetPosition()
    if target then
        self.targetPosition = target
    end
    self:ApplyVisualPosition(ApproachVector(
        self.visualPosition,
        self.targetPosition,
        DRAG_FOLLOW,
        timeStep
    ))
end

function PreviewMoverController:BeginSnap()
    local part = self.activePart
    if not self.dragCommitted then
        self:CancelPendingAsClick()
        return false
    end
    local hexQ, hexR, layer = self:WorldToGrid(self.targetPosition)
    hexQ, hexR, layer = self:SnapGrid(part, hexQ, hexR, layer)
    self.snapPosition = self:GridToWorld(hexQ, hexR, layer)
    self.targetPosition = CopyVector(self.snapPosition)
    self.phase = PHASE_SNAP
    return true
end

function PreviewMoverController:CommitSnap(part)
    if not part:SetPosition(self.snapPosition) then
        print("Preview Mover: snap rejected for " .. part.id)
        return false
    end
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local refreshed, errorMessage = self.pathRuntime:RefreshAfterMechanismSnap()
    if not refreshed then
        print("Preview Mover: path refresh failed: " .. tostring(errorMessage))
        return false
    end
    self:FollowRider()
    self:SetPlayerLocked(false)
    local hexQ, hexR, layer = self:WorldToGrid(part.transform.position)
    print(string.format(
        "Preview Mover: snapped %s to Q %.1f / R %.1f / Layer %.1f",
        part.name,
        hexQ,
        hexR,
        layer
    ))
    return true
end

function PreviewMoverController:UpdateSnap(timeStep)
    local part = self.activePart
    local remaining = self.snapPosition - self.visualPosition
    if remaining:Length() <= SNAP_EPSILON then
        self:ApplyVisualPosition(self.snapPosition)
        self:CommitSnap(part)
        self.phase = PHASE_IDLE
        self.activePart = nil
        return
    end
    self:ApplyVisualPosition(ApproachVector(
        self.visualPosition,
        self.snapPosition,
        SNAP_FOLLOW,
        timeStep
    ))
end

function PreviewMoverController:Update(timeStep)
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
    if self.phase == PHASE_SNAP then
        if pointer.pressed then
            local ray = GetScreenRay(self.camera)
            local part = self:PickMoverPart(ray)
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
    local part = self:PickMoverPart(ray)
    if not part then
        return false
    end
    return self:BeginPending(part, ray, pointer.position)
end

return PreviewMoverController
