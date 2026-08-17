-- 三棱柱体素地编编辑器。
-- 文档数据、网格拓扑、工具命令、相机和渲染节点分离。

local UI = require("urhox-libs/UI")
local TriPrismGrid = require "TriPrismGrid"
local EditorContext = require "EditorContext"
local PendingEdit = require "PendingEdit"
local VoxelBrush = require "VoxelBrush"
local Modifier = require "Modifier"
local Selection = require "Selection"
local ViewportRenderer = require "ViewportRenderer"
local VoxelDocument = require "VoxelDocument"
local VoxelHistory = require "VoxelHistory"
local VoxelRenderer = require "VoxelRenderer"

local VoxelSandbox = {}
---@class VoxelSandbox
VoxelSandbox.__index = VoxelSandbox

local SQRT3 = math.sqrt(3.0)
local MAX_FILL = 256

local function Clamp(value, low, high)
    return math.max(low, math.min(high, value))
end

local function CopyCell(cell)
    if not cell then return nil end
    return {
        hexQ = cell.hexQ,
        hexR = cell.hexR,
        sector = cell.sector,
        layer = cell.layer,
        rotation = cell.rotation,
        material = cell.material,
    }
end

local function CellKey(grid, cell)
    return grid:CellKey(cell)
end

local COLORS = {
    Color(0.95, 0.29, 0.33, 1.0),
    Color(0.98, 0.58, 0.20, 1.0),
    Color(0.95, 0.87, 0.22, 1.0),
    Color(0.35, 0.78, 0.38, 1.0),
    Color(0.24, 0.65, 0.92, 1.0),
    Color(0.62, 0.38, 0.88, 1.0),
}

function VoxelSandbox.New(scene, cameraNode, camera, debugRenderer, edgeLength, voxelHeight)
    local self = setmetatable({}, VoxelSandbox)
    self.scene = scene
    self.cameraNode = cameraNode
    self.camera = camera
    self.debugRenderer = debugRenderer
    self.grid = TriPrismGrid.New(edgeLength, voxelHeight)
    self.document = VoxelDocument.New(self.grid)
    self.context = EditorContext.New(self.grid, self.document)
    self.selection = Selection.New(self.grid, self.document, function()
        self:UpdateSelectionLabel()
    end)
    self.viewportRenderer = ViewportRenderer.New(self.debugRenderer, self.grid, self.document, self.selection)
    self.context.selection = self.selection
    self.pendingEdit = PendingEdit.New(self.document)
    self.history = VoxelHistory.New(self.document, function()
        self.selection:SetCells(self.selection:ToArray())
        self:RebuildDocumentScene()
        self:UpdateDocumentStatus()
    end)
    self.brush = VoxelBrush.New(self.grid, self.document, self.pendingEdit)
    self.modifier = Modifier.New(self.document, self.history, self.context, self.pendingEdit, function()
        self:UpdateDocumentStatus()
    end)
    self.modifier:SetBrush(self.brush)
    self.modifier:Activate()
    self.edgeLength = edgeLength
    self.voxelHeight = voxelHeight
    self.tool = "place"
    self.activeLayer = 0
    self.activeMaterial = 1
    self.hoverCell = nil
    self.hoverExisting = nil
    self.selectedCells = self.selection.cells
    self.voxelNodes = {}
    self.clipboard = {}
    self.dragActive = false
    self.dragChanges = {}
    self.dragChangeKeys = {}
    self.cameraFocus = Vector3(0, 0, 0)
    self.cameraYaw = 0.0
    self.cameraPitch = 30.0
    self.cameraDistance = 15.0
    self.projection = "orthographic"
    self.orthoSize = 10.0
    self.fov = 45.0
    self.context.activeLayer = self.activeLayer
    self.context.activeMaterial = self.activeMaterial
    self.context.projection = self.projection
    self.toolLabel = nil
    self.layerLabel = nil
    self.projectionLabel = nil
    self.viewLabel = nil
    self.statusLabel = nil
    self.selectionLabel = nil
    return self
end

function VoxelSandbox:Start()
    input.mouseMode = MM_ABSOLUTE
    input.mouseVisible = true
    self:CreateUI()
    self:CreateInitialDocument()
    self:UpdateCamera()
    self:UpdateDocumentStatus()
    print("Tri-prism voxel editor started with packed triangular tiling")
end

function VoxelSandbox:CreateInitialDocument()
    local initial = {
        { hexQ = 0, hexR = 0, sector = 0, layer = 0, rotation = 0, material = 1 },
        { hexQ = 0, hexR = 0, sector = 1, layer = 0, rotation = 0, material = 2 },
        { hexQ = 0, hexR = 0, sector = 2, layer = 0, rotation = 0, material = 3 },
        { hexQ = 0, hexR = 0, sector = 3, layer = 0, rotation = 0, material = 4 },
        { hexQ = 0, hexR = 0, sector = 4, layer = 0, rotation = 0, material = 5 },
        { hexQ = 0, hexR = 0, sector = 5, layer = 0, rotation = 0, material = 6 },
        { hexQ = 1, hexR = 0, sector = 3, layer = 0, rotation = 0, material = 2 },
        { hexQ = 0, hexR = 1, sector = 4, layer = 0, rotation = 0, material = 3 },
        { hexQ = 0, hexR = 0, sector = 0, layer = 1, rotation = 0, material = 2 },
    }
    for _, cell in ipairs(initial) do
        self.document:Set(cell)
    end
    self.document.dirty = false
    self:RebuildDocumentScene()
end

function VoxelSandbox:ColorForMaterial(material)
    return COLORS[((material or 1) - 1) % #COLORS + 1]
end

function VoxelSandbox:CreateVoxelNode(cell)
    local position, rotation = self.grid:GetVoxelTransform(cell)
    local node = VoxelRenderer.CreateVoxel(self.scene, position, self:ColorForMaterial(cell.material), {
        edgeLength = self.edgeLength,
        height = self.voxelHeight,
        rotation = rotation,
        name = "Voxel_" .. CellKey(self.grid, cell),
    })
    self.voxelNodes[CellKey(self.grid, cell)] = node
end

function VoxelSandbox:RebuildDocumentScene()
    for _, node in pairs(self.voxelNodes) do
        node:Remove()
    end
    self.voxelNodes = {}
    self.document:ForEach(function(cell)
        self:CreateVoxelNode(cell)
    end)
end

function VoxelSandbox:CreateUI()
    UI.Init({
        theme = "dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    local title = UI.Label { text = "TRI-PRISM VOXEL EDITOR", fontSize = 17, fontWeight = "bold", fontColor = { 240, 245, 255, 255 } }
    self.toolLabel = UI.Label { text = "工具  笔刷", fontSize = 14, fontWeight = "bold", fontColor = { 226, 232, 240, 255 } }
    self.layerLabel = UI.Label { text = "层  0", fontSize = 12, fontColor = { 148, 163, 184, 255 } }
    self.projectionLabel = UI.Label { text = "正交", fontSize = 12, fontColor = { 148, 163, 184, 255 } }
    self.viewLabel = UI.Label { text = "透视视图  ·  LMB 编辑  ·  RMB 旋转  ·  MMB 平移  ·  Wheel 缩放", fontSize = 11, fontColor = { 100, 116, 139, 255 } }
    self.statusLabel = UI.Label { text = "", fontSize = 11, fontColor = { 148, 163, 184, 255 } }
    self.selectionLabel = UI.Label { text = "选择：0 个", fontSize = 12, fontColor = { 255, 220, 150, 255 } }

    local function toolButton(text, tool, variant)
        return UI.Button { text = text, variant = variant or "secondary", height = 30, fontSize = 12, onClick = function() self:SetTool(tool) end }
    end

    local root = UI.Panel {
        width = "100%", height = "100%", pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8, right = 8, height = 38,
                paddingHorizontal = 12, flexDirection = "row", alignItems = "center", gap = 18,
                backgroundColor = { 24, 29, 38, 245 }, borderColor = { 71, 85, 105, 190 }, borderWidth = 1, borderRadius = 5,
                children = {
                    title,
                    UI.Label { text = "文件", fontSize = 11, fontColor = { 148, 163, 184, 255 } },
                    UI.Label { text = "编辑", fontSize = 11, fontColor = { 148, 163, 184, 255 } },
                    UI.Label { text = "视图", fontSize = 11, fontColor = { 148, 163, 184, 255 } },
                    UI.Label { text = "工具", fontSize = 11, fontColor = { 148, 163, 184, 255 } },
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    self.toolLabel, self.layerLabel, self.projectionLabel,
                },
            },
            UI.Panel {
                position = "absolute", top = 52, left = 8, width = 164, padding = 8, gap = 5,
                backgroundColor = { 24, 29, 38, 242 }, borderColor = { 71, 85, 105, 170 }, borderWidth = 1, borderRadius = 5,
                children = {
                    UI.Label { text = "工具箱", fontSize = 11, fontWeight = "bold", fontColor = { 226, 232, 240, 255 } },
                    UI.Label { text = "编辑", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    UI.Panel { flexDirection = "row", gap = 4, children = { toolButton("笔刷", "place", "primary"), toolButton("擦除", "erase", "danger") } },
                    UI.Panel { flexDirection = "row", gap = 4, children = { toolButton("选择", "select"), toolButton("框选", "box") } },
                    UI.Panel { flexDirection = "row", gap = 4, children = { toolButton("填充", "fill"), toolButton("吸管", "picker") } },
                    UI.Label { text = "图层", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button { text = "−", width = 32, height = 27, fontSize = 14, variant = "secondary", onClick = function() self:SetLayer(self.activeLayer - 1) end },
                            UI.Button { text = "+", width = 32, height = 27, fontSize = 14, variant = "secondary", onClick = function() self:SetLayer(self.activeLayer + 1) end },
                            UI.Button { text = "投影", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self:ToggleProjection() end },
                        },
                    },
                    UI.Label { text = "文档", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button { text = "撤销", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self.history:Undo() end },
                            UI.Button { text = "重做", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self.history:Redo() end },
                        },
                    },
                    UI.Panel {
                        flexDirection = "row", gap = 4,
                        children = {
                            UI.Button { text = "保存", flexGrow = 1, height = 27, fontSize = 10, variant = "success", onClick = function() self:SaveDocument() end },
                            UI.Button { text = "加载", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self:LoadDocument() end },
                        },
                    },
                },
            },
            UI.Panel {
                position = "absolute", top = 52, right = 8, width = 224, padding = 10, gap = 6,
                backgroundColor = { 24, 29, 38, 242 }, borderColor = { 71, 85, 105, 170 }, borderWidth = 1, borderRadius = 5,
                children = {
                    UI.Label { text = "检查器", fontSize = 11, fontWeight = "bold", fontColor = { 226, 232, 240, 255 } },
                    UI.Label { text = "选择状态", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    self.selectionLabel,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "复制", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() self:CopySelection() end },
                        UI.Button { text = "粘贴", flexGrow = 1, height = 28, fontSize = 10, variant = "primary", onClick = function() self:PasteAtHover() end },
                        UI.Button { text = "删除选中", flexGrow = 1, height = 28, fontSize = 10, variant = "danger", onClick = function() self:DeleteSelection() end },
                    } },
                    UI.Label { text = "变换", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "旋转", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() self:RotateSelection() end },
                        UI.Button { text = "镜像", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() self:MirrorSelection() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "←", flexGrow = 1, height = 28, fontSize = 13, variant = "secondary", onClick = function() self:MoveSelection(-1, 0, 0) end },
                        UI.Button { text = "→", flexGrow = 1, height = 28, fontSize = 13, variant = "secondary", onClick = function() self:MoveSelection(1, 0, 0) end },
                        UI.Button { text = "↑层", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() self:MoveSelection(0, 0, 1) end },
                    } },
                    UI.Label { text = "视图", fontSize = 10, fontColor = { 100, 116, 139, 255 } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "网格", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self.viewportRenderer.showGrid = not self.viewportRenderer.showGrid end },
                        UI.Button { text = "轴向", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() self.viewportRenderer.showAxes = not self.viewportRenderer.showAxes end },
                    } },
                },
            },
            UI.Panel {
                position = "absolute", left = 8, right = 8, bottom = 8, height = 30,
                paddingHorizontal = 10, flexDirection = "row", alignItems = "center",
                backgroundColor = { 24, 29, 38, 238 }, borderColor = { 71, 85, 105, 150 }, borderWidth = 1, borderRadius = 5,
                children = { self.statusLabel, UI.Panel { flexGrow = 1 }, self.viewLabel },
            },
        },
    }
    self.uiRoot = root
    UI.SetRoot(root)
end

function VoxelSandbox:SetTool(tool)
    self.tool = tool
    local names = { place = "笔刷", erase = "擦除", select = "选择", box = "框选", fill = "填充", picker = "吸管" }
    self.context.tool = self.tool
    self.context.activeLayer = self.activeLayer
    self.context.activeMaterial = self.activeMaterial
    self.brush:SetMode(tool == "erase" and "erase" or "place")
    if self.modifier then
        self.modifier:SetMode(tool == "erase" and "erase" or "place")
    end
    self.toolLabel:SetText("工具：" .. (names[tool] or tool))
    if self.modifier and self.context.isDragging then
        self.modifier:Abort()
    end
    self.dragActive = false
end

function VoxelSandbox:SetLayer(layer)
    self.activeLayer = Clamp(layer, 0, 16)
    self.context.activeLayer = self.activeLayer
    self.layerLabel:SetText("层：" .. tostring(self.activeLayer))
end

function VoxelSandbox:ToggleProjection()
    self.projection = self.projection == "orthographic" and "perspective" or "orthographic"
    self.context.projection = self.projection
    self.camera.orthographic = self.projection == "orthographic"
    self.projectionLabel:SetText(self.projection == "orthographic" and "投影：正交" or "投影：透视")
    self:UpdateCamera()
end

function VoxelSandbox:ScreenRay()
    local mouse = input:GetMousePosition()
    local width = graphics:GetWidth()
    local height = graphics:GetHeight()
    return self.camera:GetScreenRay(mouse.x / width, mouse.y / height)
end

function VoxelSandbox:ScreenToWorldOnLayer()
    local ray = self:ScreenRay()
    if math.abs(ray.direction.y) < 0.001 then return nil end
    local planeY = self.activeLayer * self.voxelHeight
    local distance = (planeY - ray.origin.y) / ray.direction.y
    if distance < 0 then return nil end
    return ray.origin + ray.direction * distance
end

function VoxelSandbox:FindExistingCellOnRay()
    local ray = self:ScreenRay()
    return self.grid:Raycast(ray, self.document)
end

function VoxelSandbox:RefreshHover()
    local hit = self:FindExistingCellOnRay()
    self.context:UpdateHit(self:ScreenRay(), hit)
    self.hoverExisting = hit and hit.cell or nil
    if self.tool == "select" or self.tool == "erase" or self.tool == "picker" then
        self.hoverCell = self.hoverExisting
        self.context.cursorCell = self.hoverCell
        self.selection:SetHighlightedCell(self.hoverExisting)
        return
    end
    self.selection:SetHighlightedCell(nil)
    if hit and hit.placementCell then
        self.hoverCell = hit.placementCell
        return
    end
    local point = self:ScreenToWorldOnLayer()
    if point then
        self.hoverCell = self.grid:WorldToCell(point, self.activeLayer)
    else
        self.hoverCell = nil
    end
    self.context.cursorCell = self.hoverCell
end

function VoxelSandbox:MakeChange(before, after)
    return { before = CopyCell(before), after = CopyCell(after) }
end

function VoxelSandbox:AddBrushChange(cell)
    if not cell then return end
    local normalized = self.grid:NormalizeCell(cell)
    local key = CellKey(self.grid, normalized)
    if self.dragChangeKeys[key] then return end
    local existing = self.document:Get(normalized)
    if self.tool == "place" and not existing then
        normalized.material = self.activeMaterial
        self.dragChanges[#self.dragChanges + 1] = self:MakeChange(nil, normalized)
        self.dragChangeKeys[key] = true
    elseif self.tool == "erase" and existing then
        self.dragChanges[#self.dragChanges + 1] = self:MakeChange(existing, nil)
        self.dragChangeKeys[key] = true
    end
end

function VoxelSandbox:CommitDrag()
    if #self.dragChanges > 0 then
        self.history:Execute(self.dragChanges, self.tool == "erase" and "Erase Brush" or "Place Brush")
    end
    self.dragChanges = {}
    self.dragChangeKeys = {}
    self.dragActive = false
end

function VoxelSandbox:BeginDrag()
    self.dragActive = true
    self.dragChanges = {}
    self.dragChangeKeys = {}
    self:AddBrushChange(self.hoverCell)
end

function VoxelSandbox:HandleBoxSelection()
    if not self.hoverCell then return end
    local candidates, bounds = self.selection:Box(self.hoverCell, self.hoverCell)
    self.selection:Preview(candidates, bounds)
    self.selection:Merge(candidates, "replace")
end

function VoxelSandbox:FloodFill()
    local start = self.hoverCell
    if not start then return end
    local changes = {}
    local queue = { self.grid:NormalizeCell(start) }
    local visited = {}
    local index = 1
    while queue[index] and #changes < MAX_FILL do
        local cell = queue[index]
        index = index + 1
        local key = CellKey(self.grid, cell)
        if not visited[key] then
            visited[key] = true
            if not self.document:Get(cell) then
                cell.material = self.activeMaterial
                changes[#changes + 1] = self:MakeChange(nil, cell)
                for face = 3, 5 do
                    local neighbor = self.grid:GetFaceNeighbor(cell, face)
                    if neighbor then queue[#queue + 1] = neighbor end
                end
            end
        end
    end
    self.history:Execute(changes, "Fill")
end

function VoxelSandbox:SelectHover()
    local candidates = self.selection:Single(self.hoverExisting)
    self.selection:Merge(candidates, "replace")
end

function VoxelSandbox:PickMaterial()
    if self.hoverExisting then
        self.activeMaterial = self.hoverExisting.material or 1
        self:SetTool("place")
        self.statusLabel:SetText("已吸取材质 " .. tostring(self.activeMaterial))
    end
end

function VoxelSandbox:DeleteSelection()
    local changes = {}
    for _, cell in pairs(self.selection:GetCells()) do
        local existing = self.document:Get(cell)
        if existing then
            changes[#changes + 1] = self:MakeChange(existing, nil)
        end
    end
    if self.history:Execute(changes, "Delete Selection") then
        self.selection:Clear()
    end
end

function VoxelSandbox:ApplySelectionTransform(transform)
    local sourceCells = self.selection:GetCells()
    local changes = {}
    local destinations = {}
    local afterCells = {}
    for _, cell in pairs(sourceCells) do
        local after = transform(CopyCell(cell))
        local key = CellKey(self.grid, after)
        if destinations[key] or (self.document:Get(after) and not sourceCells[CellKey(self.grid, after)]) then
            self.statusLabel:SetText("变换失败：目标位置已被占用")
            return
        end
        destinations[key] = true
        afterCells[#afterCells + 1] = after
        changes[#changes + 1] = self:MakeChange(cell, nil)
        changes[#changes + 1] = self:MakeChange(nil, after)
    end
    if self.history:Execute(changes, "Selection Transform") then
        self.selection:SetCells(afterCells)
    end
end

function VoxelSandbox:MoveSelection(di, dj, dl)
    self:ApplySelectionTransform(function(cell)
        cell.hexQ = cell.hexQ + di
        cell.hexR = cell.hexR + dj
        cell.layer = cell.layer + dl
        return cell
    end)
end

function VoxelSandbox:RotateSelection()
    self:ApplySelectionTransform(function(cell)
        return self.grid:TransformCell(cell, { kind = "rotate", steps = 1 })
    end)
end

function VoxelSandbox:MirrorSelection()
    self:ApplySelectionTransform(function(cell)
        return self.grid:TransformCell(cell, { kind = "mirror", axis = "q" })
    end)
end

function VoxelSandbox:CopySelection()
    self.clipboard = {}
    local minQ, minR, minLayer = math.huge, math.huge, math.huge
    for _, cell in pairs(self.selection:GetCells()) do
        minQ = math.min(minQ, cell.hexQ)
        minR = math.min(minR, cell.hexR)
        minLayer = math.min(minLayer, cell.layer)
    end
    if minQ == math.huge then return end
    for _, cell in pairs(self.selection:GetCells()) do
        local copy = CopyCell(cell)
        copy.hexQ = copy.hexQ - minQ
        copy.hexR = copy.hexR - minR
        copy.layer = copy.layer - minLayer
        self.clipboard[#self.clipboard + 1] = copy
    end
    self.statusLabel:SetText("已复制 " .. tostring(#self.clipboard) .. " 个体素")
end

function VoxelSandbox:PasteAtHover()
    if #self.clipboard == 0 or not self.hoverCell then return end
    local changes = {}
    for _, source in ipairs(self.clipboard) do
        local cell = CopyCell(source)
        cell.hexQ = cell.hexQ + self.hoverCell.hexQ
        cell.hexR = cell.hexR + self.hoverCell.hexR
        cell.layer = cell.layer + self.hoverCell.layer
        if not self.document:Get(cell) then
            changes[#changes + 1] = self:MakeChange(nil, cell)
        end
    end
    self.history:Execute(changes, "Paste")
end

function VoxelSandbox:HandlePointer()
    local pointerOverUI = UI.IsPointerOverUI()
    local leftPress = input:GetMouseButtonPress(MOUSEB_LEFT)
    local leftDown = input:GetMouseButtonDown(MOUSEB_LEFT)

    -- 拖拽事务不能只依赖单帧 Release 事件。鼠标松开或进入 UI 后，
    -- 都要结束当前笔刷，否则 PendingEdit 会一直悬空而不会写入文档。
    if self.dragActive and (not leftDown or pointerOverUI) then
        self.modifier:End(true)
        self.dragActive = false
    end
    if pointerOverUI then
        return
    end

    if self.tool == "select" and leftPress then self:SelectHover() return end
    if self.tool == "box" and leftPress then self:HandleBoxSelection() return end
    if self.tool == "picker" and leftPress then self:PickMaterial() return end
    if self.tool == "fill" and leftPress then self:FloodFill() return end

    if self.tool == "place" or self.tool == "erase" then
        if leftPress and not self.dragActive then
            self.dragActive = self.modifier:Begin()
        end
        if self.dragActive and leftDown then
            self.modifier:Update(0.016)
        end
    end
end

function VoxelSandbox:HandleCameraInput()
    local mouseMove = input:GetMouseMove()
    if UI.IsPointerOverUI() then return end

    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        self.cameraYaw = self.cameraYaw + mouseMove.x * 0.22
        self.cameraPitch = Clamp(self.cameraPitch + mouseMove.y * 0.18, 8.0, 82.0)
    elseif input:GetMouseButtonDown(MOUSEB_MIDDLE) then
        local cameraRotation = self.cameraNode.worldRotation
        local screenRight = cameraRotation * Vector3.RIGHT
        local screenUp = cameraRotation * Vector3.UP
        local worldPerPixel
        if self.projection == "orthographic" then
            worldPerPixel = self.orthoSize / math.max(1, graphics:GetHeight())
        else
            worldPerPixel = self.cameraDistance * 0.0015
        end
        self.cameraFocus = self.cameraFocus
            - screenRight * mouseMove.x * worldPerPixel
            + screenUp * mouseMove.y * worldPerPixel
    end

    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 then
        local wheelDirection = wheel > 0 and 1.0 or -1.0
        local zoomFactor = wheelDirection > 0 and 0.90 or (1.0 / 0.90)
        if self.projection == "orthographic" then
            self.orthoSize = Clamp(self.orthoSize * zoomFactor, 2.0, 30.0)
        else
            self.cameraDistance = Clamp(self.cameraDistance * zoomFactor, 3.0, 40.0)
        end
    end
end

function VoxelSandbox:UpdateCamera()
    local yaw = math.rad(self.cameraYaw)
    local pitch = math.rad(self.cameraPitch)
    local horizontal = math.cos(pitch) * self.cameraDistance
    local offset = Vector3(math.sin(yaw) * horizontal, math.sin(pitch) * self.cameraDistance, -math.cos(yaw) * horizontal)
    self.cameraNode.position = self.cameraFocus + offset
    self.cameraNode:LookAt(self.cameraFocus)
    self.camera.orthographic = self.projection == "orthographic"
    self.camera.orthoSize = self.orthoSize
    self.camera.fov = self.fov
end

function VoxelSandbox:DrawDebug()
    self.viewportRenderer:Draw(
        self.context,
        self.activeLayer,
        self.pendingEdit:GetChanges()
    )
end

function VoxelSandbox:UpdateDocumentStatus()
    local dirty = self.document.dirty and "*" or ""
    self.statusLabel:SetText("体素：" .. tostring(self.document:Count()) .. "  " .. dirty .. "JSON文档　左键编辑　右键旋转　中键平移　滚轮缩放")
end

function VoxelSandbox:UpdateSelectionLabel()
    self.selectionLabel:SetText("选择：" .. tostring(self.selection:Count()) .. " 个")
end

function VoxelSandbox:SaveDocument()
    local ok, message = self.document:Save()
    self.statusLabel:SetText(ok and "已保存 tri_voxel_sandbox.json" or ("保存失败：" .. tostring(message)))
end

function VoxelSandbox:LoadDocument()
    local ok, message = self.document:Load()
    if ok then
        self.history:Clear()
        self.selection:Clear()
        self:RebuildDocumentScene()
        self:UpdateSelectionLabel()
        self.statusLabel:SetText("已加载 tri_voxel_sandbox.json")
    else
        self.statusLabel:SetText("加载失败：" .. tostring(message))
    end
end

function VoxelSandbox:Refresh()
    self:RefreshHover()
    self:HandlePointer()
    self:HandleCameraInput()
    self:UpdateCamera()
    self:DrawDebug()
end

function VoxelSandbox:Stop()
    if self.modifier then
        self.modifier:Deactivate()
    end
    UI.Shutdown()
end

return VoxelSandbox
