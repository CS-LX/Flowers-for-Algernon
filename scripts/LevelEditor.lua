-- Level Editor 总协调器。
-- 负责关卡级 Part 选择、PartRoot 派生显示与 Level/Part 编辑模式切换。
-- 局部体素编辑仍交给 VoxelSandbox，关卡数据仍由 LevelDocument 持有。

local PartEditSession = require "PartEditSession"
local UI = require("urhox-libs/UI")
local PartRootRenderer = require "PartRootRenderer"
local LevelEditorUI = require "LevelEditorUI"
local VoxelSandbox = require "VoxelSandbox"

local LevelEditor = {}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function SnapToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

---@class LevelEditor
---@field scene Scene
---@field cameraNode Node
---@field camera Camera
---@field debugRenderer DebugRenderer
---@field levelDocument table
---@field edgeLength number
---@field voxelHeight number
---@field partRenderer table
---@field selectedPartId string|nil
---@field mode string
---@field partEditor table|nil
---@field ui table|nil
---@field transformGrid table
---@field editorCamera table
LevelEditor.__index = LevelEditor

function LevelEditor.New(scene, cameraNode, camera, debugRenderer, levelDocument, edgeLength, voxelHeight)
    local self = setmetatable({}, LevelEditor)
    self.scene = scene
    self.cameraNode = cameraNode
    self.camera = camera
    self.debugRenderer = debugRenderer
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.partRenderer = PartRootRenderer.New(scene, edgeLength, voxelHeight)
    self.selectedPartId = nil
    self.mode = "level"
    self.partEditor = nil
    self.ui = nil
    self.transformGrid = {
        snapStep = 0.5,
        hexQ = 0,
        hexR = 0,
        layer = 0,
    }
    self.editorCamera = {
        projection = "orthographic",
        focus = Vector3(0, 0, 0),
        yaw = 0.0,
        pitch = 30.0,
        distance = 18.0,
        orthoSize = 12.0,
        fov = 45.0,
    }
    self:ResetEditorCamera()
    return self
end

function LevelEditor:Start()
    self:EnterLevelMode()
end

function LevelEditor:GetSelectedPart()
    return self.selectedPartId and self.levelDocument:GetPart(self.selectedPartId) or nil
end

function LevelEditor:ResetEditorCamera()
    local settings = self.levelDocument.fixedCamera
    self.editorCamera.projection = "orthographic"
    self.editorCamera.focus = Vector3(settings.target.x, settings.target.y, settings.target.z)
    self.editorCamera.yaw = settings.yaw
    self.editorCamera.pitch = settings.pitch
    self.editorCamera.distance = settings.orthoSize * 1.5
    self.editorCamera.orthoSize = settings.orthoSize
    self.editorCamera.fov = 45.0
    self:ApplyEditorCamera()
end

function LevelEditor:ApplyEditorCamera()
    local state = self.editorCamera
    local yaw = math.rad(state.yaw)
    local pitch = math.rad(state.pitch)
    local horizontal = math.cos(pitch) * state.distance
    local offset = Vector3(
        math.sin(yaw) * horizontal,
        math.sin(pitch) * state.distance,
        -math.cos(yaw) * horizontal
    )
    self.cameraNode.position = state.focus + offset
    self.cameraNode:LookAt(state.focus)
    self.camera.orthographic = state.projection == "orthographic"
    self.camera.orthoSize = state.orthoSize
    self.camera.fov = state.fov
    self.camera.nearClip = self.levelDocument.fixedCamera.nearClip
    self.camera.farClip = self.levelDocument.fixedCamera.farClip
end

function LevelEditor:ToggleEditorProjection()
    local state = self.editorCamera
    state.projection = state.projection == "orthographic" and "perspective" or "orthographic"
    self:ApplyEditorCamera()
    self:RefreshLevelUI("编辑预览投影：" .. (state.projection == "orthographic" and "正交" or "透视"))
end

function LevelEditor:FocusSelectedPart()
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local root = self.partRenderer:GetRoot(part.id)
    local minPoint, maxPoint = self.partRenderer:GetLocalBounds(part.id)
    if not root or not minPoint or not maxPoint then
        return false
    end
    local localCenter = (minPoint + maxPoint) * 0.5
    self.editorCamera.focus = root.worldTransform * localCenter
    self:ApplyEditorCamera()
    self:RefreshLevelUI("编辑预览已聚焦：" .. part.name)
    return true
end

function LevelEditor:HandleEditorCameraInput()
    if self.mode ~= "level" or UI.IsPointerOverUI() then
        return
    end

    local state = self.editorCamera
    local mouseMove = input:GetMouseMove()
    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        state.yaw = state.yaw + mouseMove.x * 0.22
        state.pitch = Clamp(state.pitch + mouseMove.y * 0.18, 8.0, 82.0)
    elseif input:GetMouseButtonDown(MOUSEB_MIDDLE) then
        local worldPerPixel = state.projection == "orthographic"
            and state.orthoSize / math.max(1, graphics:GetHeight())
            or state.distance * 0.0015
        local rotation = self.cameraNode.worldRotation
        local screenRight = rotation * Vector3.RIGHT
        local screenUp = rotation * Vector3.UP
        state.focus = state.focus
            - screenRight * mouseMove.x * worldPerPixel
            + screenUp * mouseMove.y * worldPerPixel
    end

    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 then
        local zoomFactor = wheel > 0 and 0.90 or (1.0 / 0.90)
        if state.projection == "orthographic" then
            state.orthoSize = Clamp(state.orthoSize * zoomFactor, 2.0, 48.0)
        else
            state.distance = Clamp(state.distance * zoomFactor, 2.0, 60.0)
        end
    end
    self:ApplyEditorCamera()
    if self.ui then
        self.ui:SetCameraState(state)
    end
end

function LevelEditor:EnterLevelMode()
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    self.mode = "level"
    self:ApplyEditorCamera()

    local built, errorMessage = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        error(errorMessage)
    end
    if not self.selectedPartId then
        local parts = self.levelDocument:GetParts()
        self.selectedPartId = parts[1] and parts[1].id or nil
    end
    local selectedPart = self:GetSelectedPart()
    if selectedPart then
        self:SyncTransformGrid(selectedPart)
    end

    self.ui = LevelEditorUI.New(self)
    self.ui:Build()
    self:RefreshLevelUI("Level View：" .. self.levelDocument.name)
    print("Level Editor: entered level mode")
end

function LevelEditor:SyncTransformGrid(part)
    local position = part.transform.position
    local grid = self.partRenderer.grid
    local rawQ, rawR = grid:WorldToHexFloat(position)
    self.transformGrid.hexQ = SnapToStep(rawQ, self.transformGrid.snapStep)
    self.transformGrid.hexR = SnapToStep(rawR, self.transformGrid.snapStep)
    self.transformGrid.layer = SnapToStep(
        position.y / self.voxelHeight,
        self.transformGrid.snapStep
    )
end

function LevelEditor:GetSnappedWorldPosition(hexQ, hexR, layer)
    return self.partRenderer.grid:GetHexCenter(
        hexQ,
        hexR,
        layer * self.voxelHeight
    )
end

function LevelEditor:SetSelectedGridCoordinate(axis, value)
    local part = self:GetSelectedPart()
    if not part or not part:CanTransform("move") then
        return false
    end
    local numeric = tonumber(value)
    if not numeric then
        self:RefreshLevelUI("网格坐标必须是数字")
        return false
    end
    numeric = SnapToStep(numeric, self.transformGrid.snapStep)
    if axis == "hexQ" or axis == "hexR" then
        self.transformGrid[axis] = numeric
    elseif axis == "layer" then
        self.transformGrid.layer = numeric
    else
        return false
    end

    local position = self:GetSnappedWorldPosition(
        self.transformGrid.hexQ,
        self.transformGrid.hexR,
        self.transformGrid.layer
    )
    if not part:SetPosition(position) then
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    self:RefreshLevelUI(string.format(
        "%s 已吸附到 Q %.1f / R %.1f / Layer %.1f",
        part.name,
        self.transformGrid.hexQ,
        self.transformGrid.hexR,
        self.transformGrid.layer
    ))
    return true
end

function LevelEditor:SnapSelectedPartToGrid()
    local part = self:GetSelectedPart()
    if not part or not part:CanTransform("move") then
        return false
    end
    self:SyncTransformGrid(part)
    local position = self:GetSnappedWorldPosition(
        self.transformGrid.hexQ,
        self.transformGrid.hexR,
        self.transformGrid.layer
    )
    if not part:SetPosition(position) then
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    self:RefreshLevelUI("已吸附当前 Part 到三棱柱网格")
    return true
end

function LevelEditor:SetSelectedYawSteps(value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local steps = tonumber(value)
    if not steps or not part:SetYawSteps(steps) then
        self:RefreshLevelUI("Yaw 必须是允许的 0..5 离散状态")
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    self:RefreshLevelUI(string.format(
        "%s Yaw：%d（%d°）",
        part.name,
        part.transform.rotation.yawSteps,
        part.transform.rotation.yawSteps * 60
    ))
    return true
end

function LevelEditor:SelectPart(partId)
    if not self.levelDocument:GetPart(partId) then
        return false
    end
    self.selectedPartId = partId
    self:SyncTransformGrid(self:GetSelectedPart())
    self:RefreshLevelUI("已选择 Part：" .. self:GetSelectedPart().name)
    return true
end

function LevelEditor:RefreshLevelUI(status)
    if self.ui then
        self.ui:Refresh()
        self.ui:SetStatus(status or "Level View")
    end
end

function LevelEditor:OpenSelectedPart()
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local session, errorMessage = PartEditSession.Open(self.partRenderer.grid, part)
    if not session then
        if self.ui then
            self.ui:SetStatus("无法打开 Part：" .. tostring(errorMessage))
        end
        return false
    end

    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
    self.mode = "part"
    self.partEditor = VoxelSandbox.New(
        self.scene,
        self.cameraNode,
        self.camera,
        self.debugRenderer,
        self.edgeLength,
        self.voxelHeight,
        session
    )
    self.partEditor.onBackToLevel = function()
        self:BackToLevel()
    end
    self.partEditor:Start()
    print("Level Editor: opened Part " .. part.name)
    return true
end

function LevelEditor:BackToLevel()
    if self.mode ~= "part" or not self.partEditor then
        return false
    end
    self.partEditor:SaveDocument()
    self:EnterLevelMode()
    return true
end

function LevelEditor:SaveLevel()
    local saved, errorMessage = self.levelDocument:Save()
    if not saved then
        self:RefreshLevelUI("关卡保存失败：" .. tostring(errorMessage))
        return false
    end
    self:RefreshLevelUI("已保存关卡：" .. self.levelDocument.name)
    return true
end

function LevelEditor:RotateSelectedPart(deltaSteps)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    deltaSteps = deltaSteps or 1
    local nextStep = part.transform.rotation.yawSteps + deltaSteps
    if not part:SetYawSteps(nextStep) then
        self:RefreshLevelUI("当前 Part 不允许使用该 Yaw 状态")
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    self:RefreshLevelUI(string.format(
        "%s Yaw：%d（%d°）",
        part.name,
        part.transform.rotation.yawSteps,
        part.transform.rotation.yawSteps * 60
    ))
    return true
end

function LevelEditor:DrawSelectionGizmo()
    if self.mode ~= "level" or not self.selectedPartId then
        return
    end
    local root = self.partRenderer:GetRoot(self.selectedPartId)
    local minPoint, maxPoint = self.partRenderer:GetLocalBounds(self.selectedPartId)
    if not root or not minPoint or not maxPoint then
        return
    end

    local corners = {
        Vector3(minPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, minPoint.z),
        Vector3(maxPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, minPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, minPoint.z),
        Vector3(maxPoint.x, maxPoint.y, maxPoint.z),
        Vector3(minPoint.x, maxPoint.y, maxPoint.z),
    }
    local world = {}
    for index, corner in ipairs(corners) do
        world[index] = root.worldTransform * corner
    end
    local edges = {
        { 1, 2 }, { 2, 3 }, { 3, 4 }, { 4, 1 },
        { 5, 6 }, { 6, 7 }, { 7, 8 }, { 8, 5 },
        { 1, 5 }, { 2, 6 }, { 3, 7 }, { 4, 8 },
    }
    local color = Color(0.44, 0.84, 1.0, 1.0)
    for _, edge in ipairs(edges) do
        self.debugRenderer:AddLine(world[edge[1]], world[edge[2]], color, false)
    end
end

function LevelEditor:Refresh()
    if self.mode == "level" then
        self:HandleEditorCameraInput()
        self:DrawSelectionGizmo()
    elseif self.partEditor then
        self.partEditor:Refresh()
    end
end

function LevelEditor:Stop()
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
end

return LevelEditor
