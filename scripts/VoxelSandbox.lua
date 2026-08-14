-- 三棱柱体素地编编辑器。
-- 文档数据、网格拓扑、工具命令、相机和渲染节点分离。

local UI = require("urhox-libs/UI")
local TriPrismGrid = require "TriPrismGrid"
local EditorContext = require "EditorContext"
local PendingEdit = require "PendingEdit"
local VoxelBrush = require "VoxelBrush"
local Modifier = require "Modifier"
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
    self.pendingEdit = PendingEdit.New(self.document)
    self.history = VoxelHistory.New(self.document, function()
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
    self.selectedCells = {}
    self.voxelNodes = {}
    self.clipboard = {}
    self.dragActive = false
    self.dragChanges = {}
    self.dragChangeKeys = {}
    self.lastMouseX = 0
    self.lastMouseY = 0
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
    self.toolLabel = UI.Label { text = "工具：笔刷", fontSize = 13, fontColor = { 150, 205, 255, 255 } }
    self.layerLabel = UI.Label { text = "层：0", fontSize = 13, fontColor = { 210, 220, 235, 255 } }
    self.projectionLabel = UI.Label { text = "投影：正交", fontSize = 13, fontColor = { 210, 220, 235, 255 } }
    self.statusLabel = UI.Label { text = "", fontSize = 12, fontColor = { 185, 195, 212, 255 } }
    self.selectionLabel = UI.Label { text = "选择：0 个", fontSize = 12, fontColor = { 255, 220, 150, 255 } }

    local function toolButton(text, tool, variant)
        return UI.Button { text = text, variant = variant or "secondary", height = 30, fontSize = 12, onClick = function() self:SetTool(tool) end }
    end

    local root = UI.Panel {
        width = "100%", height = "100%", pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 10, left = 10, right = 10, height = 46,
                paddingHorizontal = 14, flexDirection = "row", alignItems = "center", gap = 16,
                backgroundColor = { 18, 24, 35, 238 }, borderColor = { 100, 150, 210, 90 }, borderWidth = 1, borderRadius = 8,
                children = { title, self.toolLabel, self.layerLabel, self.projectionLabel },
            },
            UI.Panel {
                position = "absolute", top = 66, left = 10, width = 190, padding = 9, gap = 6,
                backgroundColor = { 18, 24, 35, 238 }, borderColor = { 100, 150, 210, 90 }, borderWidth = 1, borderRadius = 8,
                children = {
                    UI.Label { text = "工具", fontSize = 13, fontWeight = "bold", fontColor = { 220, 230, 245, 255 } },
                    UI.Panel { flexDirection = "row", gap = 5, children = { toolButton("笔刷", "place", "primary"), toolButton("擦除", "erase", "danger") } },
                    UI.Panel { flexDirection = "row", gap = 5, children = { toolButton("选择", "select"), toolButton("框选", "box") } },
                    UI.Panel { flexDirection = "row", gap = 5, children = { toolButton("填充", "fill"), toolButton("吸管", "picker") } },
                    UI.Label { text = "层级", fontSize = 12, fontColor = { 185, 195, 212, 255 } },
                    UI.Panel {
                        flexDirection = "row", gap = 5,
                        children = {
                            UI.Button { text = "−", width = 38, height = 28, fontSize = 15, variant = "secondary", onClick = function() self:SetLayer(self.activeLayer - 1) end },
                            UI.Button { text = "+", width = 38, height = 28, fontSize = 15, variant = "secondary", onClick = function() self:SetLayer(self.activeLayer + 1) end },
                            UI.Button { text = "投影", height = 28, fontSize = 11, variant = "secondary", onClick = function() self:ToggleProjection() end },
                        },
                    },
                    UI.Label { text = "文档", fontSize = 12, fontColor = { 185, 195, 212, 255 } },
                    UI.Panel {
                        flexDirection = "row", gap = 5,
                        children = {
                            UI.Button { text = "撤销", height = 28, fontSize = 11, variant = "secondary", onClick = function() self.history:Undo() end },
                            UI.Button { text = "重做", height = 28, fontSize = 11, variant = "secondary", onClick = function() self.history:Redo() end },
                            UI.Button { text = "保存", height = 28, fontSize = 11, variant = "success", onClick = function() self:SaveDocument() end },
                            UI.Button { text = "加载", height = 28, fontSize = 11, variant = "secondary", onClick = function() self:LoadDocument() end },
                        },
                    },
                },
            },
            UI.Panel {
                position = "absolute", top = 66, right = 10, width = 210, padding = 10, gap = 6,
                backgroundColor = { 18, 24, 35, 238 }, borderColor = { 100, 150, 210, 90 }, borderWidth = 1, borderRadius = 8,
                children = {
                    UI.Label { text = "选择与变换", fontSize = 13, fontWeight = "bold", fontColor = { 220, 230, 245, 255 } },
                    self.selectionLabel,
                    UI.Panel { flexDirection = "row", gap = 5, children = {
                        UI.Button { text = "复制", height = 30, fontSize = 11, variant = "secondary", onClick = function() self:CopySelection() end },
                        UI.Button { text = "粘贴", height = 30, fontSize = 11, variant = "primary", onClick = function() self:PasteAtHover() end },
                        UI.Button { text = "镜像", height = 30, fontSize = 11, variant = "secondary", onClick = function() self:MirrorSelection() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 5, children = {
                        UI.Button { text = "旋转", height = 30, fontSize = 11, variant = "secondary", onClick = function() self:RotateSelection() end },
                        UI.Button { text = "←", width = 30, height = 30, fontSize = 14, variant = "secondary", onClick = function() self:MoveSelection(-1, 0, 0) end },
                        UI.Button { text = "→", width = 30, height = 30, fontSize = 14, variant = "secondary", onClick = function() self:MoveSelection(1, 0, 0) end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 5, children = {
                        UI.Button { text = "↑", width = 30, height = 30, fontSize = 14, variant = "secondary", onClick = function() self:MoveSelection(0, 1, 0) end },
                        UI.Button { text = "↓", width = 30, height = 30, fontSize = 14, variant = "secondary", onClick = function() self:MoveSelection(0, -1, 0) end },
                        UI.Button { text = "升层", height = 30, fontSize = 11, variant = "secondary", onClick = function() self:MoveSelection(0, 0, 1) end },
                    } },
                },
            },
            UI.Panel {
                position = "absolute", left = 10, bottom = 10, paddingHorizontal = 12, paddingVertical = 8,
                backgroundColor = { 18, 24, 35, 225 }, borderColor = { 100, 150, 210, 70 }, borderWidth = 1, borderRadius = 7,
                children = { self.statusLabel },
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
        return
    end
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
    self.selectedCells = {}
    local center = self.hoverCell
    for _, cell in pairs(self.document.cells) do
        if cell.layer == center.layer and math.abs(cell.hexQ - center.hexQ) <= 2 and math.abs(cell.hexR - center.hexR) <= 2 then
            self.selectedCells[CellKey(self.grid, cell)] = CopyCell(cell)
        end
    end
    self:UpdateSelectionLabel()
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
    self.selectedCells = {}
    if self.hoverExisting then
        local key = CellKey(self.grid, self.hoverExisting)
        self.selectedCells[key] = CopyCell(self.hoverExisting)
    end
    self:UpdateSelectionLabel()
end

function VoxelSandbox:PickMaterial()
    if self.hoverExisting then
        self.activeMaterial = self.hoverExisting.material or 1
        self:SetTool("place")
        self.statusLabel:SetText("已吸取材质 " .. tostring(self.activeMaterial))
    end
end

function VoxelSandbox:DeleteHover()
    if self.hoverExisting then
        self.history:Execute({ self:MakeChange(self.hoverExisting, nil) }, "Delete")
        self.selectedCells = {}
        self:UpdateSelectionLabel()
    end
end

function VoxelSandbox:ApplySelectionTransform(transform)
    local changes = {}
    local destinations = {}
    for _, cell in pairs(self.selectedCells) do
        local after = transform(CopyCell(cell))
        local key = CellKey(self.grid, after)
        if destinations[key] or (self.document:Get(after) and not self.selectedCells[CellKey(self.grid, after)]) then
            self.statusLabel:SetText("变换失败：目标位置已被占用")
            return
        end
        destinations[key] = true
        changes[#changes + 1] = self:MakeChange(cell, nil)
        changes[#changes + 1] = self:MakeChange(nil, after)
    end
    if self.history:Execute(changes, "Selection Transform") then
        self.selectedCells = {}
        for _, change in ipairs(changes) do
            if change.after then
                self.selectedCells[CellKey(self.grid, change.after)] = CopyCell(change.after)
            end
        end
        self:UpdateSelectionLabel()
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
    for _, cell in pairs(self.selectedCells) do
        minQ = math.min(minQ, cell.hexQ)
        minR = math.min(minR, cell.hexR)
        minLayer = math.min(minLayer, cell.layer)
    end
    if minQ == math.huge then return end
    for _, cell in pairs(self.selectedCells) do
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
    if UI.IsPointerOverUI() then return end
    local leftPress = input:GetMouseButtonPress(MOUSEB_LEFT)
    local leftDown = input:GetMouseButtonDown(MOUSEB_LEFT)
    local leftRelease = input:GetMouseButtonRelease(MOUSEB_LEFT)

    if self.tool == "select" and leftPress then self:SelectHover() return end
    if self.tool == "box" and leftPress then self:HandleBoxSelection() return end
    if self.tool == "picker" and leftPress then self:PickMaterial() return end
    if self.tool == "fill" and leftPress then self:FloodFill() return end

    if self.tool == "place" or self.tool == "erase" then
        if leftPress then
            self.dragActive = self.modifier:Begin()
        end
        if self.dragActive and leftDown then
            self.modifier:Update(0.016)
        end
        if self.dragActive and leftRelease then
            self.modifier:End(true)
            self.dragActive = false
        end
    end
end

function VoxelSandbox:HandleCameraInput()
    local mouse = input:GetMousePosition()
    local dx = mouse.x - self.lastMouseX
    local dy = mouse.y - self.lastMouseY
    self.lastMouseX = mouse.x
    self.lastMouseY = mouse.y
    if UI.IsPointerOverUI() then return end

    if input:GetMouseButtonDown(MOUSEB_RIGHT) then
        self.cameraYaw = self.cameraYaw + dx * 0.35
        self.cameraPitch = Clamp(self.cameraPitch + dy * 0.25, 8.0, 82.0)
    elseif input:GetMouseButtonDown(MOUSEB_MIDDLE) then
        local rotation = Quaternion(self.cameraYaw, Vector3.UP)
        local right = rotation * Vector3(1, 0, 0)
        local forward = rotation * Vector3(0, 0, 1)
        local scale = self.cameraDistance * 0.0025
        self.cameraFocus = self.cameraFocus - right * dx * scale + forward * dy * scale
    end

    local wheel = input:GetMouseMoveWheel()
    if wheel ~= 0 then
        if self.projection == "orthographic" then
            self.orthoSize = Clamp(self.orthoSize - wheel * 0.45, 2.0, 30.0)
        else
            self.cameraDistance = Clamp(self.cameraDistance - wheel * 0.5, 3.0, 40.0)
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

function VoxelSandbox:DrawGrid()
    local y = self.activeLayer * self.voxelHeight + 0.012
    local color = Color(0.20, 0.42, 0.62, 0.48)
    for r = -4, 4 do
        for q = -4, 4 do
            local vertices = self.grid:GetHexVertices(q, r, self.activeLayer * self.voxelHeight + 0.012)
            for index = 1, 6 do
                local nextIndex = index % 6 + 1
                self.debugRenderer:AddLine(vertices[index], vertices[nextIndex], color, false)
            end
        end
    end
end

function VoxelSandbox:DrawTriangle(cell, color, yOffset)
    if not cell then return end
    local vertices = self.grid:GetTriangleVertices(cell, yOffset)
    self.debugRenderer:AddLine(vertices[1], vertices[2], color, false)
    self.debugRenderer:AddLine(vertices[2], vertices[3], color, false)
    self.debugRenderer:AddLine(vertices[3], vertices[1], color, false)
    self.debugRenderer:AddCross(self.grid:GetCellCenter(cell), 0.15, color, false)
end

function VoxelSandbox:DrawDebug()
    self:DrawGrid()
    if self.hoverCell then
        local occupied = self.document:Get(self.hoverCell)
        local color = occupied and Color(1.0, 0.25, 0.25, 1.0) or Color(0.25, 1.0, 0.55, 1.0)
        self:DrawTriangle(self.hoverCell, color, 0.025)
    end
    for _, cell in pairs(self.selectedCells) do
        self:DrawTriangle(cell, Color(1.0, 0.92, 0.25, 1.0), 0.05)
    end
    if self.modifier then
        for _, change in ipairs(self.pendingEdit:GetChanges()) do
            if change.after then
                self:DrawTriangle(change.after, Color(0.25, 1.0, 0.55, 0.7), 0.07)
            end
        end
    end
end

function VoxelSandbox:UpdateDocumentStatus()
    local dirty = self.document.dirty and "*" or ""
    self.statusLabel:SetText("体素：" .. tostring(self.document:Count()) .. "  " .. dirty .. "JSON文档　左键编辑　右键旋转　中键平移　滚轮缩放")
end

function VoxelSandbox:UpdateSelectionLabel()
    local count = 0
    for _ in pairs(self.selectedCells) do count = count + 1 end
    self.selectionLabel:SetText("选择：" .. tostring(count) .. " 个")
end

function VoxelSandbox:SaveDocument()
    local ok, message = self.document:Save()
    self.statusLabel:SetText(ok and "已保存 tri_voxel_sandbox.json" or ("保存失败：" .. tostring(message)))
end

function VoxelSandbox:LoadDocument()
    local ok, message = self.document:Load()
    if ok then
        self.history:Clear()
        self.selectedCells = {}
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
