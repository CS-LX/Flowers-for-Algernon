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
---@field stillSceneDrag table|nil
---@field mode string
---@field partEditor table|nil
---@field overlayViewManager table
---@field overlayRenderer table
---@field ui table|nil
---@field transformGrid table
---@field editorCamera table
---@field candidateFillJob table|nil
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
    ---@type table|nil
    self.stillSceneDrag = nil
    self.mode = "level"
    self.partEditor = nil
    self.gamePreview = nil
    self.ui = nil
    ---@type table|nil
    self.candidateFillJob = nil
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
    if self.stillSceneDrag and self.stillSceneDrag.started then
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
    local baseName, _ = GetCopyBaseName(sourceName)
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
            for _, object in ipairs(self.levelDocument:GetStillObjects()) do
                if object.name == candidate then
                    exists = true
                    break
                end
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

function LevelEditor:DuplicateSelectedStillObject()
    local source = self:GetSelectedStillObject()
    if not source then
        return false
    end
    local name = self:AllocateCopyName(source.name)
    local id = self:AllocateStillObjectId(name)
    local data = source:ToTable()
    data.id = id
    data.name = name
    local copy = StillObject.New(data)
    copy:SetName(name)
    local offset = self.edgeLength or 1.0
    copy:SetPosition({
        x = source.transform.position.x + offset,
        y = source.transform.position.y,
        z = source.transform.position.z,
    })
    local added, addError = self.levelDocument:AddStillObject(copy)
    if not added then
        self:RefreshLevelUI("副本加入关卡失败：" .. tostring(addError))
        return false
    end
    local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
    if not rebuilt then
        self:RefreshLevelUI(tostring(rebuildError))
        return false
    end
    self:SelectStillObject(id)
    self:RefreshLevelUI("已复制静物：" .. name)
    print(string.format(
        "Level Editor: duplicated still %s -> %s parent=%s",
        source.id,
        id,
        tostring(copy.parentId)
    ))
    return true
end

function LevelEditor:DuplicateSelectedObject()
    if self:GetSelectedStillObject() then
        return self:DuplicateSelectedStillObject()
    end
    if self:GetSelectedPart() then
        return self:DuplicateSelectedPart()
    end
    self:RefreshLevelUI("未选择可复制对象")
    return false
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

function LevelEditor:SetSelectedMoverLimit(name, value)
    local part = self:GetSelectedPart()
    if not part or not part:HasBehavior("mover") then
        self:RefreshLevelUI("当前 Part 未启用 Mover")
        return false
    end
    if not part:SetMoverLimit(name, value) then
        self:RefreshLevelUI("Mover 上下限只能是数字，留空表示不限制")
        return false
    end
    self.levelDocument.dirty = true
    local shown = part.behaviors.mover[name]
    self:RefreshLevelUI(string.format(
        "已更新 %s Mover %s=%s",
        part.name,
        name,
        shown == nil and "不限制" or tostring(shown)
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

function LevelEditor:GetScreenRay(screenX, screenY)
    local width = math.max(1, graphics:GetWidth())
    local height = math.max(1, graphics:GetHeight())
    return self.camera:GetScreenRay(screenX / width, screenY / height)
end

function LevelEditor:IsSelectedStillHit(ray)
    local object = self:GetSelectedStillObject()
    if not object then
        return false
    end
    local distance = self.partRenderer:RaycastStillObject(object.id, ray)
    return distance ~= nil
end

function LevelEditor:BeginStillSceneDrag()
    if self.mode ~= "level" or UI.IsPointerOverUI() or self.pathPickMode then
        return false
    end
    if not input:GetMouseButtonPress(MOUSEB_LEFT) then
        return false
    end
    local object = self:GetSelectedStillObject()
    if not object then
        return false
    end
    local mouse = input:GetMousePosition()
    local ray = self:GetScreenRay(mouse.x, mouse.y)
    if not self:IsSelectedStillHit(ray) then
        return false
    end
    self.stillSceneDrag = {
        objectId = object.id,
        started = false,
        originX = mouse.x,
        originY = mouse.y,
        lastParentId = object.parentId,
        lastCellKey = nil,
    }
    print("Level Editor: still scene drag begin " .. object.id)
    return true
end

function LevelEditor:GetEmptyGridTop(ray)
    local grid = self.partRenderer.grid
    -- 未打到体素时，按 layer 0 空三棱柱的上表面中心吸附。
    local plane = Plane(Vector3.UP, Vector3(0, grid.voxelHeight, 0))
    local distance = ray:HitDistance(plane)
    if not distance or distance < 0 or distance == M_INFINITY then
        return nil
    end
    local worldPoint = ray.origin + ray.direction * distance
    local cell = grid:WorldToCell(worldPoint, 0)
    if not cell then
        return nil
    end
    return {
        cell = cell,
        worldTop = grid:GetCellTopCenter(cell),
    }
end

function LevelEditor:WorldToStillLocal(object, worldPoint)
    local parentNode = self.partRenderer:GetParentNode(object.parentId)
    if not parentNode or parentNode == self.scene then
        return {
            x = worldPoint.x,
            y = worldPoint.y,
            z = worldPoint.z,
        }
    end
    local localPoint = parentNode.worldTransform:Inverse() * worldPoint
    return {
        x = localPoint.x,
        y = localPoint.y,
        z = localPoint.z,
    }
end

function LevelEditor:ApplyStillSnap(object, parentId, worldPoint, cellKey)
    local currentParent = object.parentId
    if parentId ~= currentParent then
        local ok, err = self.levelDocument:SetParent(object.id, parentId)
        if not ok then
            print("Level Editor: still parent rejected " .. tostring(err))
            return false
        end
        local rebuilt, rebuildError = self.partRenderer:Rebuild(self.levelDocument)
        if not rebuilt then
            self:RefreshLevelUI(tostring(rebuildError))
            return false
        end
        local pathRebuilt, pathError = self:RefreshPathRuntime()
        if not pathRebuilt then
            self:RefreshLevelUI("路径刷新失败：" .. tostring(pathError))
            return false
        end
    end
    object:SetPosition(self:WorldToStillLocal(object, worldPoint))
    self.levelDocument.dirty = true
    local root = self.partRenderer:GetRoot(object.id)
    if root then
        self.partRenderer:ApplyStillTransform(root, object)
    end
    if self.stillSceneDrag then
        self.stillSceneDrag.lastParentId = object.parentId
        self.stillSceneDrag.lastCellKey = cellKey
    end
    return true
end

function LevelEditor:UpdateStillSceneDrag()
    local drag = self.stillSceneDrag
    if not drag then
        return false
    end
    if not input:GetMouseButtonDown(MOUSEB_LEFT) then
        self:EndStillSceneDrag()
        return true
    end
    local mouse = input:GetMousePosition()
    if not drag.started then
        local dx = mouse.x - drag.originX
        local dy = mouse.y - drag.originY
        if (dx * dx + dy * dy) < 16 then
            return true
        end
        drag.started = true
        print("Level Editor: still scene drag started " .. drag.objectId)
    end
    local object = self.levelDocument:GetStillObject(drag.objectId)
    if not object then
        self.stillSceneDrag = nil
        return false
    end
    local ray = self:GetScreenRay(mouse.x, mouse.y)
    local voxelHit = self.partRenderer:RaycastVoxel(ray)
    local parentId = nil
    local worldPoint = nil
    local cellKey = nil
    if voxelHit then
        parentId = voxelHit.partId
        worldPoint = voxelHit.worldTop
        cellKey = voxelHit.partId .. ":" .. self.partRenderer.grid:CellKey(voxelHit.cell)
    else
        local empty = self:GetEmptyGridTop(ray)
        if not empty then
            return true
        end
        worldPoint = empty.worldTop
        cellKey = "world:" .. self.partRenderer.grid:CellKey(empty.cell)
    end
    if cellKey == drag.lastCellKey and parentId == drag.lastParentId then
        return true
    end
    self:ApplyStillSnap(object, parentId, worldPoint, cellKey)
    local parentPart = parentId and self.levelDocument:GetPart(parentId) or nil
    local parentName = parentPart and parentPart.name or "世界网格"
    if self.ui then
        self.ui:SetStatus(string.format("静物吸附：%s → %s", object.name, parentName))
    end
    return true
end

function LevelEditor:EndStillSceneDrag()
    local drag = self.stillSceneDrag
    if not drag then
        return
    end
    self.stillSceneDrag = nil
    local object = self.levelDocument:GetStillObject(drag.objectId)
    if drag.started and object then
        self:RefreshLevelUI(string.format(
            "静物已吸附：%s  parent=%s",
            object.name,
            object.parentId or "世界"
        ))
        print(string.format(
            "Level Editor: still scene drag end id=%s parent=%s pos=(%.3f, %.3f, %.3f)",
            object.id,
            tostring(object.parentId),
            object.transform.position.x,
            object.transform.position.y,
            object.transform.position.z
        ))
    end
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

function LevelEditor:GetPartOptions()
    local options = {}
    for _, part in ipairs(self.levelDocument:GetParts()) do
        options[#options + 1] = {
            value = part.id,
            label = part.name .. "  (" .. part.id .. ")",
        }
    end
    return options
end

function LevelEditor:ClearAllPathCandidatesFromUI()
    if self.candidateFillJob and self.candidateFillJob.thread then
        return false, "正在填充候选，请先取消"
    end
    local count = self.levelDocument:ClearPathCandidates()
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        return false, rebuildError
    end
    self:RefreshLevelUI("已删除全部路径候选：" .. tostring(count))
    if self.ui and self.ui.levelInspector then
        self.ui.levelInspector:Refresh()
    end
    return true, count
end

function LevelEditor:ConfirmClearAllPathCandidates()
    if self.candidateFillJob and self.candidateFillJob.thread then
        self:RefreshLevelUI("正在填充候选，请先取消")
        return
    end
    local count = #self.levelDocument:GetPathCandidates()
    UI.Modal.Confirm({
        title = "删除所有候选路径",
        message = count == 0 and "当前没有候选路径。" or ("确定删除全部 " .. tostring(count) .. " 条候选路径？"),
        confirmText = "删除全部",
        cancelText = "取消",
        onConfirm = function()
            if count == 0 then
                return
            end
            self:ClearAllPathCandidatesFromUI()
        end,
    })
end

local function CandidateLayer(record)
    local node = record and record.node
    if not node then
        return nil
    end
    local cell = node.voxelCell
    if not cell then
        return nil
    end
    return math.floor(cell.layer or 0)
end

function LevelEditor:ApplyPartYawPreview(part, yawSteps)
    local normalized = ((math.floor(yawSteps) % 6) + 6) % 6
    if not part:SetYawSteps(normalized) then
        part.transform.rotation.yawSteps = normalized
        if part:HasBehavior(PartDefinition.MODE_ROTATOR) then
            part.behaviors.rotator.state = normalized
        end
    end
    local root = self.partRenderer:GetRoot(part.id)
    if root then
        self.partRenderer:ApplyTransform(root, part)
    end
    if self.pathRuntime then
        self.pathRuntime:UpdateNodeSpatialData()
    end
end

function LevelEditor:RestorePartYaw(part, yawSteps)
    self:ApplyPartYawPreview(part, yawSteps)
    self:RefreshPathRuntime()
end

function LevelEditor:RestoreFillYaw(job)
    if not job or not job.originalYaws then
        self:RefreshPathRuntime()
        return
    end
    for partId, yaw in pairs(job.originalYaws) do
        local part = self.levelDocument:GetPart(partId)
        if part then
            self:ApplyPartYawPreview(part, yaw)
        end
    end
    self:RefreshPathRuntime()
end

function LevelEditor:CancelCandidateFillJob(restore)
    local job = self.candidateFillJob
    if not job then
        return
    end
    job.cancelled = true
    if restore ~= false then
        self:RestoreFillYaw(job)
    end
    local modal = job.modal
    self.candidateFillJob = nil
    if modal then
        modal.onClose_ = nil
        modal:Close()
    end
end

function LevelEditor:FinishCandidateFillJob()
    local job = self.candidateFillJob
    if not job then
        return
    end
    self:RestoreFillYaw(job)
    if job.statusLabel then
        job.statusLabel:SetText(string.format(
            "完成：检查 %d，新增 %d，跳过已有 %d",
            job.checked or 0,
            job.added or 0,
            job.skipped or 0
        ))
    end
    if job.progress then
        job.progress:SetValue(1)
    end
    self:RefreshLevelUI(string.format(
        "候选填充完成：新增 %d / 检查 %d",
        job.added or 0,
        job.checked or 0
    ))
    if self.ui and self.ui.levelInspector then
        self.ui.levelInspector:Refresh()
    end
    self.candidateFillJob = nil
end

function LevelEditor:UpdateCandidateFillDialog(job)
    if not job then
        return
    end
    local total = job.total
    if total <= 0 then
        total = 1
    end
    if job.progress then
        job.progress:SetValue(job.done / total)
    end
    if job.statusLabel then
        job.statusLabel:SetText(string.format(
            "%s  检查 %d/%d  新增 %d",
            job.progressText or "填充中",
            job.done or 0,
            job.total or 0,
            job.added or 0
        ))
    end
end

function LevelEditor:UpdateCandidateFillJob()
    local job = self.candidateFillJob
    if not job or not job.thread then
        return
    end
    if job.cancelled then
        self:CancelCandidateFillJob(true)
        return
    end
    local ok, result = coroutine.resume(job.thread)
    if not ok then
        print("LevelEditor: candidate fill failed: " .. tostring(result))
        if job.statusLabel then
            job.statusLabel:SetText("填充失败：" .. tostring(result))
        end
        self:CancelCandidateFillJob(true)
        return
    end
    if coroutine.status(job.thread) == "dead" then
        self:FinishCandidateFillJob()
        return
    end
    self:UpdateCandidateFillDialog(job)
end

local FILL_MODE_WITHIN = "within"
local FILL_MODE_BETWEEN = "between"

function LevelEditor:IsRotatorPart(part)
    return part ~= nil and part:HasBehavior(PartDefinition.MODE_ROTATOR)
end

function LevelEditor:CanFillBetweenParts(left, right)
    if not left or not right or left.id == right.id then
        return false
    end
    -- rotator+rotator、rotator+静态、两静态。mover 不参与。
    if left:HasBehavior(PartDefinition.MODE_MOVER) or right:HasBehavior(PartDefinition.MODE_MOVER) then
        return false
    end
    return true
end

function LevelEditor:CollectPartYawStates(part)
    if self:IsRotatorPart(part) then
        return { 0, 1, 2, 3, 4, 5 }
    end
    return { part.transform.rotation.yawSteps }
end

function LevelEditor:TryAddFillCandidate(job, fromRecord, toRecord)
    job.checked = job.checked + 1
    local a = fromRecord.partId .. ":" .. fromRecord.localNodeId
    local b = toRecord.partId .. ":" .. toRecord.localNodeId
    local pairKey = a < b and (a .. "|" .. b) or (b .. "|" .. a)
    if job.seenPairs[pairKey] then
        return
    end
    if self.levelDocument:HasPathCandidateBetween(
        fromRecord.partId,
        fromRecord.localNodeId,
        toRecord.partId,
        toRecord.localNodeId
    ) then
        job.seenPairs[pairKey] = true
        job.skipped = job.skipped + 1
        return
    end
    local status = self.pathRuntime:EvaluateNodePair(fromRecord, toRecord, job.worldFaces)
    if status ~= "accepted" then
        return
    end
    job.seenPairs[pairKey] = true
    local added = self.levelDocument:AddPathCandidate({
        id = self.levelDocument:AllocatePathCandidateId(),
        from = { partId = fromRecord.partId, nodeId = fromRecord.localNodeId },
        to = { partId = toRecord.partId, nodeId = toRecord.localNodeId },
        kind = "visual_candidate",
        direction = "bidirectional",
        enabled = true,
    })
    if added then
        job.added = job.added + 1
    end
end

function LevelEditor:NodesForPart(partId)
    local result = {}
    for _, record in ipairs(self.pathRuntime:GetNodes()) do
        if record.partId == partId and record.node and record.node.walkable then
            result[#result + 1] = record
        end
    end
    return result
end

function LevelEditor:StartWithinPartFill(partId)
    local part = self.levelDocument:GetPart(partId)
    if not part then
        return false, "请选择 Part"
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        return false, rebuildError
    end
    local job = self.candidateFillJob
    job.mode = FILL_MODE_WITHIN
    job.originalYaws = { [part.id] = part.transform.rotation.yawSteps }
    job.cancelled = false
    job.checked = 0
    job.added = 0
    job.skipped = 0
    job.done = 0
    job.total = 1
    job.seenPairs = {}
    job.progressText = "单 Part 跨层"
    local BATCH = 16
    local yaws = self:CollectPartYawStates(part)
    job.thread = coroutine.create(function()
        local nodes = self:NodesForPart(part.id)
        local pairCount = 0
        for i = 1, #nodes - 1 do
            for j = i + 1, #nodes do
                pairCount = pairCount + 1
            end
        end
        job.total = math.max(1, pairCount * #yaws)
        print(string.format(
            "LevelEditor: within-part fill part=%s nodes=%d pairs=%d yaws=%d",
            part.id,
            #nodes,
            pairCount,
            #yaws
        ))
        local processed = 0
        for yawIndex, yaw in ipairs(yaws) do
            if job.cancelled then
                return
            end
            job.progressText = string.format("单 Part 跨层  Yaw %d/%d", yawIndex, #yaws)
            self:ApplyPartYawPreview(part, yaw)
            job.worldFaces = self.pathRuntime:CollectWorldFaces()
            for i = 1, #nodes - 1 do
                local source = nodes[i]
                local sourceLayer = CandidateLayer(source)
                for j = i + 1, #nodes do
                    if job.cancelled then
                        return
                    end
                    local target = nodes[j]
                    processed = processed + 1
                    job.done = processed
                    local targetLayer = CandidateLayer(target)
                    if sourceLayer ~= nil and targetLayer ~= nil and sourceLayer ~= targetLayer then
                        self:TryAddFillCandidate(job, source, target)
                    else
                        job.checked = job.checked + 1
                    end
                    if processed % BATCH == 0 then
                        coroutine.yield()
                    end
                end
            end
            coroutine.yield()
        end
    end)
    print("LevelEditor: start within-part fill " .. part.id)
    self:UpdateCandidateFillJob()
    return true
end

function LevelEditor:StartBetweenPartsFill(leftId, rightId)
    local left = self.levelDocument:GetPart(leftId)
    local right = self.levelDocument:GetPart(rightId)
    if not left or not right then
        return false, "请选择两个 Part"
    end
    if left.id == right.id then
        return false, "两个 Part 不能相同"
    end
    if not self:CanFillBetweenParts(left, right) then
        return false, "只允许 rotator+rotator、rotator+静态、两静态"
    end
    local rebuilt, rebuildError = self:RefreshPathRuntime()
    if not rebuilt then
        return false, rebuildError
    end
    local job = self.candidateFillJob
    job.mode = FILL_MODE_BETWEEN
    job.originalYaws = {
        [left.id] = left.transform.rotation.yawSteps,
        [right.id] = right.transform.rotation.yawSteps,
    }
    job.cancelled = false
    job.checked = 0
    job.added = 0
    job.skipped = 0
    job.done = 0
    job.total = 1
    job.seenPairs = {}
    job.progressText = "两 Part"
    local BATCH = 16
    local leftYaws = self:CollectPartYawStates(left)
    local rightYaws = self:CollectPartYawStates(right)
    job.thread = coroutine.create(function()
        local leftNodes = self:NodesForPart(left.id)
        local rightNodes = self:NodesForPart(right.id)
        local pairCount = #leftNodes * #rightNodes
        job.total = math.max(1, pairCount * #leftYaws * #rightYaws)
        print(string.format(
            "LevelEditor: between-part fill %s(%d) x %s(%d) yaw=%dx%d",
            left.id,
            #leftNodes,
            right.id,
            #rightNodes,
            #leftYaws,
            #rightYaws
        ))
        local processed = 0
        for _, leftYaw in ipairs(leftYaws) do
            if job.cancelled then
                return
            end
            self:ApplyPartYawPreview(left, leftYaw)
            for _, rightYaw in ipairs(rightYaws) do
                if job.cancelled then
                    return
                end
                self:ApplyPartYawPreview(right, rightYaw)
                job.progressText = string.format(
                    "两 Part  Yaw %d/%d × %d/%d",
                    leftYaw + 1,
                    6,
                    rightYaw + 1,
                    6
                )
                job.worldFaces = self.pathRuntime:CollectWorldFaces()
                for _, source in ipairs(leftNodes) do
                    for _, target in ipairs(rightNodes) do
                        if job.cancelled then
                            return
                        end
                        processed = processed + 1
                        job.done = processed
                        self:TryAddFillCandidate(job, source, target)
                        if processed % BATCH == 0 then
                            coroutine.yield()
                        end
                    end
                end
                coroutine.yield()
            end
        end
    end)
    print("LevelEditor: start between-part fill " .. left.id .. " / " .. right.id)
    self:UpdateCandidateFillJob()
    return true
end

function LevelEditor:StartCandidateFill(mode, firstId, secondId)
    if self.candidateFillJob and self.candidateFillJob.thread then
        return false, "已有填充任务在跑"
    end
    if not self.pathRuntime then
        return false, "PathRuntime is not available"
    end
    if not self.candidateFillJob then
        self.candidateFillJob = {}
    end
    if mode == FILL_MODE_BETWEEN then
        return self:StartBetweenPartsFill(firstId, secondId)
    end
    return self:StartWithinPartFill(firstId)
end

function LevelEditor:OpenCandidateFillDialog()
    if self.candidateFillJob and self.candidateFillJob.thread then
        if self.candidateFillJob.modal then
            self.candidateFillJob.modal:Open()
        end
        return
    end
    local partOptions = self:GetPartOptions()
    local modeDropdown = UI.Dropdown {
        options = {
            { value = FILL_MODE_WITHIN, label = "单 Part 跨层" },
            { value = FILL_MODE_BETWEEN, label = "两 Part 六向" },
        },
        value = FILL_MODE_WITHIN,
        height = 28,
        fontSize = 11,
    }
    local firstDropdown = UI.Dropdown {
        options = partOptions,
        value = self.selectedPartId or "",
        placeholder = "选择 Part",
        height = 28,
        fontSize = 11,
    }
    local secondDropdown = UI.Dropdown {
        options = partOptions,
        value = "",
        placeholder = "第二个 Part",
        height = 28,
        fontSize = 11,
    }
    secondDropdown:SetVisible(false)
    local hintLabel = UI.Label {
        text = "单 Part：不同 layer 的点对，且必须通过摄像机投影校验。rotator 扫 6 档 Yaw。",
        fontSize = 10,
        whiteSpace = "normal",
    }
    local progress = UI.ProgressBar {
        value = 0,
        max = 1,
        height = 10,
        showLabel = false,
    }
    local statusLabel = UI.Label {
        text = "选择模式和 Part 后开始。",
        fontSize = 10,
        whiteSpace = "normal",
    }
    local startButton = nil
    local modal = UI.Modal {
        title = "填充候选路径",
        size = "sm",
        closeOnOverlay = false,
        closeOnEscape = false,
        onClose = function()
            local job = self.candidateFillJob
            if job and job.thread and not job.cancelled then
                self:CancelCandidateFillJob(true)
            end
        end,
    }
    local function SyncMode()
        local mode = modeDropdown:GetValue()
        local between = mode == FILL_MODE_BETWEEN
        secondDropdown:SetVisible(between)
        if between then
            hintLabel:SetText("两 Part：rotator 走 6 档 Yaw，静态保持当前朝向。通过摄像机投影校验才写入。")
        else
            hintLabel:SetText("单 Part：不同 layer 的点对，且必须通过摄像机投影校验。rotator 扫 6 档 Yaw。")
        end
    end
    modeDropdown.props.onChange = function()
        SyncMode()
    end
    startButton = UI.Button {
        text = "开始填充",
        height = 30,
        fontSize = 11,
        variant = "primary",
        onClick = function()
            local mode = modeDropdown:GetValue()
            local ok, errorMessage = self:StartCandidateFill(
                mode,
                firstDropdown:GetValue(),
                secondDropdown:GetValue()
            )
            if not ok then
                statusLabel:SetText("无法开始：" .. tostring(errorMessage))
                return
            end
            modeDropdown:SetDisabled(true)
            firstDropdown:SetDisabled(true)
            secondDropdown:SetDisabled(true)
            startButton:SetDisabled(true)
            statusLabel:SetText("填充中…")
        end,
    }
    modal:AddContent(modeDropdown)
    modal:AddContent(firstDropdown)
    modal:AddContent(secondDropdown)
    modal:AddContent(hintLabel)
    modal:AddContent(progress)
    modal:AddContent(statusLabel)
    modal:AddContent(startButton)
    modal:Open()
    self.candidateFillJob = {
        modal = modal,
        progress = progress,
        statusLabel = statusLabel,
        modeDropdown = modeDropdown,
        firstDropdown = firstDropdown,
        secondDropdown = secondDropdown,
        startButton = startButton,
    }
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
    self.stillSceneDrag = nil
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
        part,
        self.levelDocument
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
        self:UpdateCandidateFillJob()
        self:HandleEditorCameraInput()
        self.overlayViewManager:SyncCamera(self.cameraNode, self.camera)
        self.overlayRenderer:SyncCamera()
        local filling = self.candidateFillJob and self.candidateFillJob.thread
        if self.pathRuntime and not filling then
            self.pathRuntime:EvaluateCandidates()
        end
        self:UpdatePathNodeHover()
        if filling then
            -- 填充期间不拾取、不拖拽，避免打断协程。
        elseif self.stillSceneDrag then
            self:UpdateStillSceneDrag()
        elseif not UI.IsPointerOverUI() and input:GetMouseButtonPress(MOUSEB_LEFT) then
            if not self:BeginStillSceneDrag() then
                local mouse = input:GetMousePosition()
                if self:TryPickPathNode(mouse.x, mouse.y) then
                    return
                end
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
        if input:GetKeyPress(KEY_ESCAPE) then
            self:BackToLevel()
        end
    elseif self.mode == "preview" then
        if input:GetKeyPress(KEY_ESCAPE) then
            self:StopGamePreview()
        elseif self.gamePreview then
            self.gamePreview:Update(timeStep)
        end
    end
end

function LevelEditor:Stop()
    if self.candidateFillJob then
        self:CancelCandidateFillJob(true)
    end
    self.stillSceneDrag = nil
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
