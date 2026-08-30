-- Level Editor 总协调器。
-- 负责关卡级 Part 选择、PartRoot 派生显示与 Level/Part 编辑模式切换。
-- 局部体素编辑仍交给 VoxelSandbox，关卡数据仍由 LevelDocument 持有。

local PartEditSession = require "PartEditSession"
local PartDefinition = require "PartDefinition"
local StillObject = require "StillObject"
local UI = require("urhox-libs/UI")
local PartRootRenderer = require "PartRootRenderer"
local LevelEditorUI = require "LevelEditorUI"
local VoxelSandbox = require "VoxelSandbox"
local OverlayRenderer = require "LevelEditorOverlayRenderer"
local OverlayViewManager = require "OverlayViewManager"
local GamePreview = require "GamePreview"
local FixedGameCamera = require "FixedGameCamera"
local PathRuntime = require "PathRuntime"
local LookApplier = require "LookApplier"
local ScreenColorPicker = require "ScreenColorPicker"

local LevelEditor = {}

local function Clamp(value, minimum, maximum)
    return math.max(minimum, math.min(maximum, value))
end

local function SnapToStep(value, step)
    return math.floor(value / step + 0.5) * step
end

local function GetCopyBaseName(name)
    local base, suffix = name:match("^(.-) %((%d+)%)$")
    if base and suffix then
        return base, tonumber(suffix)
    end
    return name, nil
end

local function SanitizePartId(text)
    local id = (text or "part"):lower():gsub("[^%w]+", "_"):gsub("^_+", ""):gsub("_+$", "")
    return id ~= "" and id or "part"
end

---@class LevelEditor
---@field scene Scene
---@field cameraNode Node
---@field camera Camera
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

local function CreateFixedEvaluationCamera(scene, levelDocument)
    return FixedGameCamera.Create(
        scene,
        "PathEvaluationCamera",
        levelDocument.fixedCamera
    )
end

function LevelEditor.New(scene, cameraNode, camera, mainViewport, levelDocument, edgeLength, voxelHeight)
    local self = setmetatable({}, LevelEditor)
    self.scene = scene
    self.cameraNode = cameraNode
    self.camera = camera
    self.mainViewport = mainViewport
    self.levelDocument = levelDocument
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.partRenderer = PartRootRenderer.New(scene, edgeLength, voxelHeight)
    self.evaluationCameraNode, self.evaluationCamera =
        CreateFixedEvaluationCamera(scene, levelDocument)
    self.pathRuntime = PathRuntime.New(levelDocument, self.partRenderer.grid)
    self.overlayViewManager = OverlayViewManager.New(mainViewport, cameraNode, camera)
    self.overlayRenderer = OverlayRenderer.New(
        self.overlayViewManager:GetEditorScene(),
        self.overlayViewManager:GetEditorCameraNode(),
        self.overlayViewManager:GetEditorCamera()
    )
    self.pathHoveredNodeKey = nil
    self.pathPickMode = nil
    self.pathPickedFromKey = nil
    self.pathPickedToKey = nil
    self.selectedPartId = nil
    self.selectedStillObjectId = nil
    self.mode = "level"
    self.partEditor = nil
    self.gamePreview = nil
    self.ui = nil
    self.pendingLoadWarning = levelDocument.loadWarning
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

function LevelEditor:ShowLoadWarning()
    local warning = self.pendingLoadWarning
    if not warning then
        return
    end
    self.pendingLoadWarning = nil
    UI.Modal.Alert({
        title = warning.title or "关卡已损坏",
        message = warning.message or "已恢复默认关卡。",
        buttonText = "知道了",
    })
    self:RefreshLevelUI(warning.title or "关卡已损坏，已恢复默认关卡")
end

function LevelEditor:Start()
    self:EnterLevelMode()
    self:ShowLoadWarning()
    self.pathRuntime:ConfigureEvaluation(
        self.partRenderer,
        self.evaluationCameraNode,
        self.evaluationCamera,
        {}
    )
    self.pathRuntime:Rebuild()
    local summary = self.pathRuntime:GetSummary()
    print(string.format(
        "PathRuntime graph: edges=%d localFixed=%d accepted=%d rejected=%d insufficient=%d topology=%d",
        summary.effectiveEdgeCount,
        self.pathRuntime:GetLocalFixedEdgeCount(),
        summary.acceptedCount,
        summary.rejectedCount,
        summary.insufficientCount or 0,
        summary.topologyVersion
    ))
end

function LevelEditor:GetSelectedPart()
    return self.selectedPartId and self.levelDocument:GetPart(self.selectedPartId) or nil
end

function LevelEditor:GetSelectedStillObject()
    return self.selectedStillObjectId and self.levelDocument:GetStillObject(self.selectedStillObjectId) or nil
end

function LevelEditor:ClearSelection()
    self.selectedPartId = nil
    self.selectedStillObjectId = nil
end

function LevelEditor:SelectObject(objectId)
    if self.levelDocument:GetPart(objectId) then
        return self:SelectPart(objectId)
    end
    if self.levelDocument:GetStillObject(objectId) then
        return self:SelectStillObject(objectId)
    end
    return false
end

function LevelEditor:ResetEditorCamera()
    local settings = self.levelDocument.fixedCamera
    self.editorCamera.projection = FixedGameCamera.PROJECTION
    self.editorCamera.focus = Vector3(settings.target.x, settings.target.y, settings.target.z)
    self.editorCamera.yaw = FixedGameCamera.YAW
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
    local object = self:GetSelectedStillObject() or self:GetSelectedPart()
    if not object then
        return false
    end
    local root = self.partRenderer:GetRoot(object.id)
    local minPoint, maxPoint = self.partRenderer:GetLocalBounds(object.id)
    if not root or not minPoint or not maxPoint then
        return false
    end
    local localCenter = (minPoint + maxPoint) * 0.5
    self.editorCamera.focus = root.worldTransform * localCenter
    self:ApplyEditorCamera()
    self:RefreshLevelUI("编辑预览已聚焦：" .. object.name)
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
    if self.gamePreview then
        self.gamePreview:Stop()
        self.gamePreview = nil
    end
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    self.overlayViewManager:BindEditor(self.mainViewport)
    self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
    self.overlayRenderer:EnterLevelMode()
    self.overlayRenderer:BindCamera(
        self.overlayViewManager:GetEditorCameraNode(),
        self.overlayViewManager:GetEditorCamera()
    )
    self.mode = "level"
    self:ApplyEditorCamera()
    self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
    self.overlayRenderer:SyncCamera()

    LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
    local built, errorMessage = self.partRenderer:Rebuild(self.levelDocument)
    if not built then
        error(errorMessage)
    end
    if not self.selectedPartId then
        local parts = self.levelDocument:GetParts()
        self.selectedPartId = parts[1] and parts[1].id or nil
    end
    self.overlayRenderer:SyncCamera()
    local selectedPart = self:GetSelectedPart()
    if selectedPart then
        self:SyncTransformGrid(selectedPart)
    end

    self.ui = LevelEditorUI.New(self)
    self.ui:Build()
    self:RefreshLevelUI("Level View：" .. self.levelDocument.name)
    print("Level Editor: entered level mode")
end

function LevelEditor:AllocatePartId(baseName)
    local base = SanitizePartId(baseName)
    local index = 1
    local id = "part_" .. base
    while self.levelDocument:HasId(id) or fileSystem:FileExists("parts/" .. id .. ".json") do
        index = index + 1
        id = "part_" .. base .. "_" .. tostring(index)
    end
    return id
end

function LevelEditor:AllocateCopyName(sourceName)
    local baseName = GetCopyBaseName(sourceName)
    local suffix = 1
    while true do
        local candidate = baseName .. " (" .. tostring(suffix) .. ")"
        local exists = false
        for _, part in ipairs(self.levelDocument:GetParts()) do
            if part.name == candidate then
                exists = true
                break
            end
        end
        if not exists then
            return candidate
        end
        suffix = suffix + 1
    end
end

function LevelEditor:CreateEmptyPart(name)
    local partName = name and name ~= "" and name or "新 Part"
    local id = self:AllocatePartId(partName)
    local path = "parts/" .. id .. ".json"
    local session = PartEditSession.New(self.partRenderer.grid, {
        id = id,
        name = partName,
        path = path,
    })
    local saved, errorMessage = session:Save()
    if not saved then
        self:RefreshLevelUI("新 Part 资源创建失败：" .. tostring(errorMessage))
        return false
    end

    local part = PartDefinition.New({
        id = id,
        name = partName,
        localVoxelPath = path,
        transform = {
            position = { x = 0, y = 0, z = 0 },
            rotation = { yawSteps = 0, pitchSteps = 0, rollSteps = 0 },
            scale = { x = 1, y = 1, z = 1 },
        },
        transformCapabilities = { move = true, rotate = true, scale = false },
        behaviorModes = {},
        behaviors = {},
    })
    local added, addError = self.levelDocument:AddPart(part)
    if not added then
        self:RefreshLevelUI("新 Part 加入关卡失败：" .. tostring(addError))
        return false
    end
    self.selectedPartId = id
    self:SyncTransformGrid(part)
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    local pathRebuilt, pathError = self:RefreshPathRuntime()
    if not pathRebuilt then
        self:RefreshLevelUI(tostring(pathError))
        return false
    end
    self:RefreshLevelUI("已新建空 Part：" .. partName)
    return true
end

function LevelEditor:AllocateStillObjectId(baseName)
    local base = SanitizePartId(baseName)
    local index = 1
    local id = "still_" .. base
    while self.levelDocument:HasId(id) do
        index = index + 1
        id = "still_" .. base .. "_" .. tostring(index)
    end
    return id
end

function LevelEditor:CreateStillObject()
    local displayName = "新静物"
    local id = self:AllocateStillObjectId(displayName)
    local object = StillObject.New({ id = id })
    object:SetName(displayName)
    object:SetParentId(self.selectedPartId or self.selectedStillObjectId)
    local added, addError = self.levelDocument:AddStillObject(object)
    if not added then
        self:RefreshLevelUI(tostring(addError))
        return false
    end
    self:SelectStillObject(id)
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已新建静物")
    return true
end

function LevelEditor:DuplicateSelectedPart()
    local source = self:GetSelectedPart()
    if not source then
        return false
    end
    local sourceSession, sourceError = PartEditSession.Open(self.partRenderer.grid, source)
    if not sourceSession then
        self:RefreshLevelUI("无法读取源 Part：" .. tostring(sourceError))
        return false
    end

    local name = self:AllocateCopyName(source.name)
    local id = self:AllocatePartId(name)
    local path = "parts/" .. id .. ".json"
    local cloneSession = PartEditSession.New(self.partRenderer.grid, {
        id = id,
        name = name,
        path = path,
    })
    cloneSession.document:LoadTable(sourceSession.document:CloneTable())
    local saved, saveError = cloneSession:Save()
    if not saved then
        self:RefreshLevelUI("副本体素资源保存失败：" .. tostring(saveError))
        return false
    end

    local copy = PartDefinition.New(source:ToTable())
    copy.id = id
    copy.name = name
    copy.localVoxelPath = path
    self:SyncTransformGrid(source)
    self.transformGrid.hexQ = self.transformGrid.hexQ + self.transformGrid.snapStep
    copy:SetPosition(self:GetSnappedWorldPosition(
        self.transformGrid.hexQ,
        self.transformGrid.hexR,
        self.transformGrid.layer
    ))
    local added, addError = self.levelDocument:AddPart(copy)
    if not added then
        self:RefreshLevelUI("副本加入关卡失败：" .. tostring(addError))
        return false
    end
    self.selectedPartId = id
    self:SyncTransformGrid(copy)
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已复制 Part：" .. name)
    return true
end

function LevelEditor:DeleteSelectedPart()
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local removed, errorMessage = self.levelDocument:RemovePart(part.id)
    if not removed then
        self:RefreshLevelUI("删除 Part 失败：" .. tostring(errorMessage))
        return false
    end
    local parts = self.levelDocument:GetParts()
    self.selectedPartId = parts[1] and parts[1].id or nil
    local selected = self:GetSelectedPart()
    if selected then
        self:SyncTransformGrid(selected)
    end
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    local pathRebuilt, pathError = self:RefreshPathRuntime()
    if not pathRebuilt then
        self:RefreshLevelUI(tostring(pathError))
        return false
    end
    if self.ui then
        if self.ui.levelInspector then
            self.ui.levelInspector.selectedPathCandidateId = nil
        end
        self.ui:Refresh()
    end
    self:RefreshLevelUI("已从关卡移除 Part：" .. part.name .. "（局部资源保留）")
    return true
end

function LevelEditor:ConfirmDeleteSelectedObject()
    local still = self:GetSelectedStillObject()
    if still then
        UI.Modal.Confirm({
            title = "移除静物",
            message = "确定移除静物吗？",
            confirmText = "移除",
            cancelText = "取消",
            onConfirm = function() self:DeleteSelectedStillObject() end,
        })
    elseif self:GetSelectedPart() then
        self:DeleteSelectedPartPrompt()
    end
end

function LevelEditor:DeleteSelectedPartPrompt()
    local part = self:GetSelectedPart()
    if not part then
        return
    end
    UI.Modal.Confirm({
        title = "从关卡移除 Part",
        message = "确定移除选中 Part 吗？局部体素 JSON 会保留。",
        confirmText = "移除",
        cancelText = "取消",
        onConfirm = function() self:DeleteSelectedPart() end,
    })
end

function LevelEditor:DeleteSelectedStillObject()
    local object = self:GetSelectedStillObject()
    if not object then
        return false
    end
    local removed, errorMessage = self.levelDocument:RemoveStillObject(object.id)
    if not removed then
        self:RefreshLevelUI(tostring(errorMessage))
        return false
    end
    self:ClearSelection()
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已移除静物")
    return true
end

function LevelEditor:RebuildAfterStillEdit(status)
    self.levelDocument.dirty = true
    local object = self:GetSelectedStillObject()
    local root = object and self.partRenderer:GetRoot(object.id)
    if root and object then
        self.partRenderer:ApplyStillTransform(root, object)
    end
    self:RefreshLevelUI(status)
    return true
end

function LevelEditor:SetSelectedStillName(value)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetName(value) then
        return false
    end
    return self:RebuildAfterStillEdit("已更新静物名称")
end

function LevelEditor:SetSelectedStillParent(parentId)
    local object = self:GetSelectedStillObject()
    if not object then
        return false
    end
    if parentId == "" then
        parentId = nil
    end
    local root = self.partRenderer:GetRoot(object.id)
    local worldPosition = root and root.worldPosition or nil
    local ok, err = self.levelDocument:SetParent(object.id, parentId)
    if not ok then
        self:RefreshLevelUI(tostring(err))
        return false
    end
    if parentId == nil and worldPosition then
        object:SetPosition({ x = worldPosition.x, y = worldPosition.y, z = worldPosition.z })
    end
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已更新静物父级")
    return true
end

function LevelEditor:SetSelectedStillCoordinate(axis, value)
    local object = self:GetSelectedStillObject()
    local number = tonumber(value)
    if not object or not number then
        return false
    end
    local position = {
        x = object.transform.position.x,
        y = object.transform.position.y,
        z = object.transform.position.z,
    }
    position[axis] = number
    object:SetPosition(position)
    return self:RebuildAfterStillEdit("已更新静物坐标")
end

function LevelEditor:SetSelectedStillYaw(value)
    local object = self:GetSelectedStillObject()
    local number = tonumber(value)
    if not object or not number then
        return false
    end
    object:SetRotation({ x = 0, y = number, z = 0 })
    return self:RebuildAfterStillEdit("已更新静物朝向")
end

function LevelEditor:SetSelectedStillScale(value)
    local object = self:GetSelectedStillObject()
    local number = tonumber(value)
    if not object or not object:SetScale(number) then
        return false
    end
    return self:RebuildAfterStillEdit("已更新静物缩放")
end

function LevelEditor:SetSelectedStillModelId(modelId)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetModelId(modelId) then
        return false
    end
    self.levelDocument.dirty = true
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI(modelId == "" and "已解绑静物模型" or ("已绑定静物模型：" .. modelId))
    return true
end

function LevelEditor:SetSelectedStillParam(path, value)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetParam(path, value) then
        return false
    end
    self.levelDocument.dirty = true
    if not self.partRenderer:ApplyStillLooks(object) then
        local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
        if not rebuilt then
            self:RefreshLevelUI(tostring(rebuildError))
            return false
        end
    end
    self:RefreshLevelUI("已更新静物外观")
    return true
end

function LevelEditor:SetSelectedStillDriver(driverId, value)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetDriver(driverId, value) then
        return false
    end
    self.levelDocument.dirty = true
    if not self.partRenderer:ApplyStillDrivers(object) then
        local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
        if not rebuilt then
            self:RefreshLevelUI(tostring(rebuildError))
            return false
        end
    end
    -- 拖滑条时不要 Refresh 整个 Inspector，否则控件会被重建。
    if self.ui then
        self.ui:SetStatus(string.format("已更新静物 %s = %.2f", driverId, object:GetDriver(driverId)))
    end
    return true
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
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
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
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
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
    local ok, errorMessage = self:ApplyPartTransformAndRefresh(part)
    if not ok then
        return false, errorMessage
    end
    self:RefreshLevelUI(string.format(
        "%s Yaw：%d（%d°）",
        part.name,
        part.transform.rotation.yawSteps,
        part.transform.rotation.yawSteps * 60
    ))
    return true
end

function LevelEditor:SetSelectedPivotMode(mode)
    local part = self:GetSelectedPart()
    if not part or not part:SetPivotMode(mode) then
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已更新 Pivot Mode")
    return true
end

function LevelEditor:SetSelectedPivotCoordinate(axis, value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local pivotCell = part:GetPivotCell() or { hexQ = 0, hexR = 0, sector = 0, layer = 0 }
    if part:GetPivotMode() ~= "cell_center" then
        part:SetPivotMode("cell_center")
    end
    local numeric = tonumber(value)
    if not numeric then
        self:RefreshLevelUI("Pivot 坐标必须是数字")
        return false
    end
    local cell = {
        hexQ = pivotCell.hexQ,
        hexR = pivotCell.hexR,
        sector = pivotCell.sector,
        layer = pivotCell.layer,
    }
    if axis == "hexQ" or axis == "hexR" or axis == "layer" then
        cell[axis] = SnapToStep(numeric, 0.5)
    elseif axis == "sector" then
        cell.sector = math.floor(numeric)
    else
        return false
    end
    local _, candidate = self.partRenderer.grid:GetPivotCellCenter({
        hexQ = cell.hexQ,
        hexR = cell.hexR,
        sector = cell.sector,
        layer = math.max(0, cell.layer),
    })
    if candidate.sector < 0 or candidate.sector > 5 or candidate.layer < 0 then
        self:RefreshLevelUI("Pivot Cell 非法：Q/R/Layer 0.5 步进，Sector 0..5")
        return false
    end
    if not part:SetPivotCell(candidate) then
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
    end
    local pivotPosition = self.partRenderer:GetPivotPosition(part)
    self:RefreshLevelUI(string.format(
        "Pivot Cell Q=%.1f R=%.1f S=%d L=%.1f  -> 中心 (%.3f, %.3f, %.3f)",
        candidate.hexQ,
        candidate.hexR,
        candidate.sector,
        candidate.layer,
        pivotPosition.x,
        pivotPosition.y,
        pivotPosition.z
    ))
    return true
end

function LevelEditor:SetSelectedPartName(name)
    local part = self:GetSelectedPart()
    if not part or not part:SetName(name) then
        self:RefreshLevelUI("Part 名称不能为空")
        return false
    end
    self.levelDocument.dirty = true
    self:RefreshLevelUI("已更新 Part 名称")
    return true
end

function LevelEditor:SetSelectedParent(parentId)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local parent = parentId and self.levelDocument:GetPart(parentId) or nil
    local changed, errorMessage = self.levelDocument:SetParent(part.id, parent and parent.id or nil)
    if not changed then
        self:RefreshLevelUI("设置父级失败：" .. tostring(errorMessage))
        return false
    end
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:RefreshPathRuntime()
    self:RefreshLevelUI(parent and ("已将 " .. part.name .. " 移入 " .. parent.name) or "已将 Part 移到 LevelRoot")
    return true
end

function LevelEditor:SetSelectedScale(value)
    local part = self:GetSelectedPart()
    if not part or not part:SetScale(value) then
        self:RefreshLevelUI("当前 Part 不允许使用该均匀缩放值")
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI(string.format("%s Scale：%.2f", part.name, part.transform.scale.x))
    return true
end

function LevelEditor:SetSelectedBehaviorMode(mode, enabled)
    local part = self:GetSelectedPart()
    if not part or not part:SetBehaviorMode(mode, enabled) then
        return false
    end
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已更新 " .. part.name .. " 行为模式")
    return true
end

function LevelEditor:SetSelectedMoverAxis(axis, enabled)
    local part = self:GetSelectedPart()
    if not part or not part:HasBehavior("mover") then
        self:RefreshLevelUI("当前 Part 未启用 Mover")
        return false
    end
    if not part:SetMoverAxis(axis, enabled) then
        self:RefreshLevelUI("Mover 至少要保留一条 Q / R / Layer 轴")
        return false
    end
    self.levelDocument.dirty = true
    self:RefreshLevelUI(string.format(
        "已更新 %s Mover 轴：Q=%s R=%s Layer=%s",
        part.name,
        tostring(part.behaviors.mover.axes.q),
        tostring(part.behaviors.mover.axes.r),
        tostring(part.behaviors.mover.axes.layer)
    ))
    return true
end

function LevelEditor:SetSelectedStillInteraction(mode, enabled)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetInteraction(mode, enabled) then
        self:RefreshLevelUI("静物只能挂交互组件")
        return false
    end
    self.levelDocument.dirty = true
    self:RefreshLevelUI("已更新静物交互")
    return true
end

function LevelEditor:SetSelectedStillTriggerId(value)
    local object = self:GetSelectedStillObject()
    if not object or not object:SetTriggerId(value) then
        self:RefreshLevelUI("当前静物未启用 Triggerable")
        return false
    end
    self.levelDocument.dirty = true
    self:RefreshLevelUI("已更新静物 Trigger ID")
    return true
end

function LevelEditor:SetSelectedTriggerId(value)
    local part = self:GetSelectedPart()
    if not part or not part:SetTriggerId(value) then
        self:RefreshLevelUI("当前 Part 未启用 Triggerable")
        return false
    end
    self.levelDocument.dirty = true
    self:RefreshLevelUI("已更新 Trigger ID")
    return true
end

function LevelEditor:ApplyCurrentAtmosphere()
    LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
    return true
end

function LevelEditor:SetAtmosphereLightGroup(value)
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.lightGroup = value
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新 LightGroup：" .. tostring(value))
    return true
end

function LevelEditor:SetAtmosphereTonemap(value)
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.tonemap = LookApplier.NormalizeTonemap(value, atmosphere.tonemap)
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新 Tonemap：" .. tostring(atmosphere.tonemap))
    return true
end

function LevelEditor:SetAtmosphereFogColor(hex)
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.fog.color = LookApplier.NormalizeHex(hex, atmosphere.fog.color)
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新雾色")
    return true
end

function LevelEditor:SetAtmosphereFogNumber(field, value)
    if field ~= "start" and field ~= "finish" and field ~= "density" then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("雾参数必须是数字")
        return false
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.fog[field] = number
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新雾参数")
    return true
end

function LevelEditor:SetAtmosphereBloomEnabled(enabled)
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.bloom.enabled = enabled == true
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI(enabled and "已开启 Bloom" or "已关闭 Bloom")
    return true
end

function LevelEditor:SetAtmosphereBloomNumber(field, value)
    if field ~= "threshold" and field ~= "intensity" then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("Bloom 参数必须是数字")
        return false
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.bloom[field] = number
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新 Bloom")
    return true
end

function LevelEditor:SetAtmosphereVignetteEnabled(enabled)
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.vignette.enabled = enabled == true
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI(enabled and "已开启 Vignette" or "已关闭 Vignette")
    return true
end

function LevelEditor:SetAtmosphereVignetteIntensity(value)
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("Vignette 强度必须是数字")
        return false
    end
    local atmosphere = LookApplier.CopyAtmosphere(self.levelDocument.atmosphere)
    atmosphere.vignette.intensity = number
    self.levelDocument.atmosphere = LookApplier.CopyAtmosphere(atmosphere)
    self.levelDocument.dirty = true
    self:ApplyCurrentAtmosphere()
    self:RefreshLevelUI("已更新 Vignette")
    return true
end

function LevelEditor:RebuildSelectedPartLook()
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    self.levelDocument.dirty = true
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI("Look 重建失败：" .. tostring(rebuildError))
        return false
    end
    self:RefreshLevelUI("已更新 " .. part.name .. " Look")
    return true
end

function LevelEditor:SetSelectedPartLookShader(shader)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.shader = LookApplier.NormalizeShader(shader)
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookColor(field, hex)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    if field ~= "colorNeg" and field ~= "colorMid" and field ~= "colorPos" then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look[field] = LookApplier.NormalizeHex(hex, look[field])
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookAxis(axis, value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    if axis ~= "x" and axis ~= "y" and axis ~= "z" then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("光照轴必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.lightAxis[axis] = number
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookAOEnabled(enabled)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.aoEnabled = enabled == true
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookAOColor(hex)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.aoColor = LookApplier.NormalizeHex(hex, look.aoColor)
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookAOSmooth(value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("AO 平滑度必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.aoSmooth = math.max(0.0, number) * 1.0
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookAOBlend(value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("AO Blend 必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.aoBlend = math.max(0.0, math.min(1.0, number)) * 1.0
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookEmissionColor(hex)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.emissionColor = LookApplier.NormalizeHex(hex, look.emissionColor)
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookEmissionStrength(value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("Hover 强度必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.emissionStrength = math.max(0.0, number) * 1.0
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookFogColor(hex)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.fogColor = LookApplier.NormalizeHex(hex, look.fogColor)
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookFogUp(axis, value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    if axis ~= "x" and axis ~= "y" and axis ~= "z" then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("高度雾轴向必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look.fogUp[axis] = number
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SetSelectedPartLookFogNumber(field, value)
    local part = self:GetSelectedPart()
    if not part then
        return false
    end
    if field ~= "fogHeightA" and field ~= "fogHeightB" then
        return false
    end
    local number = tonumber(value)
    if not number then
        self:RefreshLevelUI("高度雾高度必须是数字")
        return false
    end
    local look = LookApplier.CopyPartLook(part.look)
    look[field] = number * 1.0
    part:SetLook(look)
    return self:RebuildSelectedPartLook()
end

function LevelEditor:SelectPart(partId)
    if not self.levelDocument:GetPart(partId) then
        return false
    end
    self.selectedPartId = partId
    self.selectedStillObjectId = nil
    self:SyncTransformGrid(self:GetSelectedPart())
    self:RefreshLevelUI("已选择 Part：" .. self:GetSelectedPart().name)
    if self.ui and self.ui.ShowInspectorForSelection then
        self.ui:ShowInspectorForSelection()
    end
    return true
end

function LevelEditor:SelectStillObject(objectId)
    local object = self.levelDocument:GetStillObject(objectId)
    if not object then
        return false
    end
    self.selectedStillObjectId = objectId
    self.selectedPartId = nil
    self:RefreshLevelUI("已选择静物：" .. object.name)
    if self.ui and self.ui.ShowInspectorForSelection then
        self.ui:ShowInspectorForSelection()
    end
    return true
end

function LevelEditor:FindPathNodeAtScreenPoint(screenX, screenY, radius)
    if not self.pathRuntime then
        return nil
    end
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    local ray = self.camera:GetScreenRay(screenX / width, screenY / height)
    local candidates = self.pathRuntime:FindNodeCandidatesAtRay(ray)
    if candidates[1] then
        return candidates[1].record
    end

    local best = nil
    local bestDistance = math.huge
    for _, record in ipairs(self.pathRuntime:GetNodes()) do
        if record.worldPoint then
            local offset = record.worldPoint - ray.origin
            local projection = offset:DotProduct(ray.direction)
            if projection >= 0 then
                local closest = ray.origin + ray.direction * projection
                local distance = (record.worldPoint - closest):Length()
                if distance < bestDistance and distance <= (radius or 0.5) then
                    best = record
                    bestDistance = distance
                end
            end
        end
    end
    return best
end

function LevelEditor:UpdatePathNodeHover()
    self.pathHoveredNodeKey = nil
    if not self.pathRuntime or not self.pathPickMode then
        return
    end
    local mouse = input:GetMousePosition()
    local best = self:FindPathNodeAtScreenPoint(mouse.x, mouse.y)
    self.pathHoveredNodeKey = best and best.key or nil
end

function LevelEditor:BeginPathPick(mode)
    if mode ~= "from" and mode ~= "to" and mode ~= "spawn" then
        return false
    end
    self.pathPickMode = mode
    self.pathHoveredNodeKey = nil
    local message = mode == "from" and "请点击场景中的 PathNode 作为起点"
        or mode == "to" and "请点击场景中的 PathNode 作为终点"
        or "请点击场景中的 PathNode 作为出生点"
    self:RefreshLevelUI(message)
    return true
end

function LevelEditor:CancelPathPick()
    self.pathPickMode = nil
    self.pathHoveredNodeKey = nil
    self:RefreshLevelUI("已取消路径节点拾取")
end

function LevelEditor:GetPathPickState()
    return {
        mode = self.pathPickMode,
        fromKey = self.pathPickedFromKey,
        toKey = self.pathPickedToKey,
    }
end

function LevelEditor:TryPickPathNode(screenX, screenY)
    if self.mode ~= "level" or not self.pathPickMode or not self.pathRuntime then
        return false
    end
    local best = self:FindPathNodeAtScreenPoint(screenX, screenY)
    if not best then
        self:RefreshLevelUI("没有命中 PathNode，请点击绿色节点球体或对应体素面")
        return false
    end
    if self.pathPickMode == "from" then
        self.pathPickedFromKey = best.key
        self.pathPickMode = nil
        self:RefreshLevelUI("已选择起点：" .. best.key)
    elseif self.pathPickMode == "to" then
        self.pathPickedToKey = best.key
        self.pathPickMode = nil
        self:RefreshLevelUI("已选择终点：" .. best.key)
    else
        if not best.node.walkable then
            self:RefreshLevelUI("出生点必须是可行走 PathNode")
            return false
        end
        local changed, errorMessage = self.levelDocument:SetSpawnNodeKey(best.key)
        if not changed then
            self:RefreshLevelUI("设置出生点失败：" .. tostring(errorMessage))
            return false
        end
        self.pathPickMode = nil
        self.pathHoveredNodeKey = nil
        self:RefreshLevelUI("已设置出生点：" .. best.key)
    end
    if self.ui then
        self.ui:RefreshPathCandidatePicker()
        self.ui:RefreshSpawnPicker()
    end
    return true
end

function LevelEditor:GetPathNodeOptions()
    local options = {}
    if not self.pathRuntime then
        return options
    end
    for _, record in ipairs(self.pathRuntime:GetNodes()) do
        options[#options + 1] = {
            value = record.key,
            label = record.key .. " [" .. record.node.face .. "]",
        }
    end
    return options
end

function LevelEditor:GetSpawnNodeKey()
    return self.levelDocument:GetSpawnNodeKey()
end

function LevelEditor:SetSpawnNodeFromUI(nodeKey)
    if nodeKey == nil or nodeKey == "" then
        return self:ClearSpawnNode()
    end
    if not self.pathRuntime or not self.pathRuntime:GetNode(nodeKey) then
        self:RefreshLevelUI("出生点必须是有效的可走 PathNode")
        return false
    end
    local changed, errorMessage = self.levelDocument:SetSpawnNodeKey(nodeKey)
    if not changed then
        self:RefreshLevelUI("设置出生点失败：" .. tostring(errorMessage))
        return false
    end
    self:RefreshLevelUI("已设置出生点：" .. nodeKey)
    return true
end

function LevelEditor:ClearSpawnNode()
    if not self.levelDocument:GetSpawnNodeKey() then
        return true
    end
    self.levelDocument:SetSpawnNodeKey(nil)
    self.pathPickMode = nil
    self.pathHoveredNodeKey = nil
    if self.ui then
        self.ui:RefreshSpawnPicker()
    end
    self:RefreshLevelUI("已清空出生点")
    return true
end

function LevelEditor:GetPathCandidateOptions()
    local options = {}
    for _, candidate in ipairs(self.levelDocument:GetPathCandidates()) do
        options[#options + 1] = {
            value = candidate.id,
            label = candidate.id .. "  " .. candidate.direction,
        }
    end
    return options
end

local function SplitPathNodeKey(key)
    if type(key) ~= "string" then
        return nil, nil
    end
    local separator = key:find(":", 1, true)
    if not separator then
        return nil, nil
    end
    return key:sub(1, separator - 1), key:sub(separator + 1)
end

function LevelEditor:AddPathCandidateFromUI(fromKey, toKey, direction)
    fromKey = fromKey or self.pathPickedFromKey
    toKey = toKey or self.pathPickedToKey
    local fromPartId, fromNodeId = SplitPathNodeKey(fromKey)
    local toPartId, toNodeId = SplitPathNodeKey(toKey)
    if not fromPartId or not toPartId then
        return false, "请选择有效的起点和终点节点"
    end
    local index = 1
    local id = "candidate_" .. tostring(index)
    while self.levelDocument:HasPathCandidate(id) do
        index = index + 1
        id = "candidate_" .. tostring(index)
    end
    local added, errorMessage = self.levelDocument:AddPathCandidate({
        id = id,
        from = { partId = fromPartId, nodeId = fromNodeId },
        to = { partId = toPartId, nodeId = toNodeId },
        kind = "visual_candidate",
        direction = direction or "bidirectional",
        enabled = true,
    })
    if not added then
        return false, errorMessage
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        return false, rebuildError
    end
    self.pathHoveredNodeKey = nil
    self.pathPickMode = nil
    self.pathPickedFromKey = nil
    self.pathPickedToKey = nil
    self:RefreshLevelUI("已创建跨 Part 路径候选：" .. id)
    return true, id
end

function LevelEditor:RemovePathCandidateFromUI(candidateId)
    local removed, errorMessage = self.levelDocument:RemovePathCandidate(candidateId)
    if not removed then
        return false, errorMessage
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        return false, rebuildError
    end
    self:RefreshLevelUI("已删除路径候选：" .. candidateId)
    return true
end

function LevelEditor:RefreshPathRuntime()
    if not self.pathRuntime then
        return false, "PathRuntime is not available"
    end
    local rebuilt, errorMessage = self.pathRuntime:Rebuild()
    if not rebuilt then
        return false, errorMessage
    end
    local spawnNodeKey = self.levelDocument:GetSpawnNodeKey()
    if spawnNodeKey and not self.pathRuntime:GetNode(spawnNodeKey) then
        self.levelDocument:ClearSpawnNodeIf(spawnNodeKey)
        if self.ui then
            self.ui:SetStatus("出生点节点已失效，已自动清空，请重新配置")
        end
    end
    return true
end

function LevelEditor:RefreshPathRuntimeAfterPartEdit()
    return self:RefreshPathRuntime()
end

function LevelEditor:ApplyPartTransformAndRefresh(part)
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    local rebuilt, errorMessage = self:RefreshPathRuntime()
    if not rebuilt then
        self:RefreshLevelUI("路径刷新失败：" .. tostring(errorMessage))
        return false, errorMessage
    end
    return true
end

function LevelEditor:RefreshLevelUI(status)
    if self.ui then
        self.ui:Refresh()
        self.ui:SetStatus(status or "Level View")
    end
end

function LevelEditor:OpenSelectedPart()
    if self:GetSelectedStillObject() then
        self:RefreshLevelUI("静物不能打开体素编辑器")
        return false
    end
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
    self.overlayRenderer:EnterVoxelMode()
    self.mode = "part"
    self.partEditor = VoxelSandbox.New(
        self.scene,
        self.cameraNode,
        self.camera,
        self.edgeLength,
        self.voxelHeight,
        session,
        self.overlayRenderer,
        part
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
    local saved, errorMessage = self.partEditor:SaveDocument()
    if not saved then
        return false, errorMessage
    end
    self:EnterLevelMode()
    self:RefreshPathRuntimeAfterPartEdit()
    return true
end

function LevelEditor:StartGamePreview()
    if self.mode ~= "level" then
        return false
    end
    local spawnNodeKey = self.levelDocument:GetSpawnNodeKey()
    if not spawnNodeKey or not self.pathRuntime:GetNode(spawnNodeKey) then
        self:RefreshLevelUI("无法启动 Preview：必须先配置有效的出生点")
        return false
    end
    local preview = GamePreview.New(
        self.levelDocument,
        self.edgeLength,
        self.voxelHeight
    )
    local started, errorMessage = preview:Start()
    if not started then
        self:RefreshLevelUI("无法启动 Preview：" .. tostring(errorMessage))
        return false
    end
    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
    self.overlayRenderer:ClearTransformGizmo()
    self.overlayRenderer:ClearPathNodeGizmos()
    self.overlayRenderer:ClearVoxelGizmos()
    self.gamePreview = preview
    self.mode = "preview"
    print("Level Editor: entered game preview")
    return true
end

function LevelEditor:StopGamePreview()
    if self.mode ~= "preview" then
        return false
    end
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

-- 用户系统剪切板，不是 VoxelSandbox 的项目体素复制缓冲。
function LevelEditor:CopyTextToUserClipboard(text)
    if type(text) ~= "string" or text == "" then
        return false, "clipboard text is empty"
    end
    if not ui then
        return false, "engine UI clipboard is unavailable"
    end
    ui.useSystemClipboard = true
    ui:SetClipboardText(text)
    local copied = ui:GetClipboardText()
    if copied ~= text then
        return false, "system clipboard rejected the export"
    end
    return true
end

function LevelEditor:ExportInlineLevelToUserClipboard()
    local json, errorMessage = self.levelDocument:ExportInlineJson(self.partRenderer.grid)
    if not json then
        self:RefreshLevelUI("关卡导出失败：" .. tostring(errorMessage))
        return false
    end
    local copied, copyError = self:CopyTextToUserClipboard(json)
    if not copied then
        self:RefreshLevelUI("无法复制到用户剪切板：" .. tostring(copyError))
        return false
    end
    print(string.format(
        "Level export: copied inline JSON to user clipboard chars=%d parts=%d",
        #json,
        #self.levelDocument:GetParts()
    ))
    self:RefreshLevelUI("已复制内联关卡 JSON 到用户剪切板")
    return true
end

function LevelEditor:ImportInlineLevelJson(json)
    if self.mode ~= "level" then
        self:RefreshLevelUI("请先回到 Level View 再导入关卡")
        return false
    end
    if type(json) ~= "string" or json == "" then
        self:RefreshLevelUI("导入失败：请先把关卡 JSON 粘贴到输入框")
        return false
    end
    local imported, errorMessage = self.levelDocument:ImportInlineJson(json, self.partRenderer.grid)
    if not imported then
        self:RefreshLevelUI("关卡导入失败：" .. tostring(errorMessage))
        return false
    end

    self.selectedPartId = nil
    self.pathPickMode = nil
    self.pathPickedFromKey = nil
    self.pathPickedToKey = nil
    self.pathHoveredNodeKey = nil
    self:ResetEditorCamera()
    LookApplier.ApplyAtmosphere(self.scene, self.levelDocument.atmosphere)
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI("关卡已导入，但显示重建失败：" .. tostring(rebuildError))
        return false
    end
    local parts = self.levelDocument:GetParts()
    self.selectedPartId = parts[1] and parts[1].id or nil
    local selectedPart = self:GetSelectedPart()
    if selectedPart then
        self:SyncTransformGrid(selectedPart)
    end
    local pathRebuilt, pathError = self:RefreshPathRuntime()
    if not pathRebuilt then
        self:RefreshLevelUI("关卡已导入，但路径重建失败：" .. tostring(pathError))
        return false
    end
    print(string.format(
        "Level import: loaded inline JSON parts=%d",
        #parts
    ))
    self:RefreshLevelUI("已导入关卡：" .. self.levelDocument.name)
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
    local ok, errorMessage = self:ApplyPartTransformAndRefresh(part)
    if not ok then
        return false, errorMessage
    end
    self:RefreshLevelUI(string.format(
        "%s Yaw：%d（%d°）",
        part.name,
        part.transform.rotation.yawSteps,
        part.transform.rotation.yawSteps * 60
    ))
    return true
end

function LevelEditor:Refresh(timeStep)
    timeStep = timeStep or 0.0
    if ScreenColorPicker.Update() then
        return
    end
    if self.mode == "level" then
        self:HandleEditorCameraInput()
        self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
        self.overlayRenderer:SyncCamera()
        if self.pathRuntime then
            self.pathRuntime:EvaluateCandidates()
        end
        self:UpdatePathNodeHover()
        if input:GetMouseButtonPress(MOUSEB_LEFT) and not UI.IsPointerOverUI() then
            local mouse = input:GetMousePosition()
            if self:TryPickPathNode(mouse.x, mouse.y) then
                return
            end
        end
        local root = self.partRenderer:GetRoot(self.selectedStillObjectId or self.selectedPartId)
        local minPoint, maxPoint = self.partRenderer:GetLocalBounds(self.selectedStillObjectId or self.selectedPartId)
        local pivotPosition = self.partRenderer:GetPivotWorldPosition(self.selectedStillObjectId or self.selectedPartId)
        self.overlayRenderer:DrawSelection(root, minPoint, maxPoint, pivotPosition)
        self.overlayRenderer:DrawLevelHexGrid(self.partRenderer.grid, self.levelDocument, 0, 6)
        self.overlayRenderer:DrawLevelPathNodes(
            self.pathRuntime,
            self.pathPickMode and self.pathHoveredNodeKey or nil,
            self.pathPickedFromKey,
            self.pathPickedToKey
        )
        self.overlayRenderer:DrawPathConnectionCandidates(
            self.pathRuntime,
            self.ui and self.ui.levelInspector and self.ui.levelInspector.selectedPathCandidateId or nil
        )
    elseif self.partEditor then
        self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
        self.overlayRenderer:SyncCamera(
            self.overlayViewManager:GetEditorCameraNode(),
            self.overlayViewManager:GetEditorCamera()
        )
        self.partEditor:Refresh()
    elseif self.mode == "preview" then
        if input:GetKeyPress(KEY_ESCAPE) then
            self:StopGamePreview()
        elseif self.gamePreview then
            self.gamePreview:Update(timeStep)
        end
    end
end

function LevelEditor:Stop()
    if self.gamePreview then
        self.gamePreview:Stop()
        self.gamePreview = nil
    end
    if self.partEditor then
        self.partEditor:Stop()
        self.partEditor = nil
    end
    if self.ui then
        self.ui:Destroy()
        self.ui = nil
    end
    self.partRenderer:Clear()
    if self.evaluationCameraNode then
        self.evaluationCameraNode:Remove()
        self.evaluationCameraNode = nil
        self.evaluationCamera = nil
    end
    self.pathRuntime = nil
    self.overlayViewManager:Stop()
    self.overlayRenderer:Stop()
end

return LevelEditor
