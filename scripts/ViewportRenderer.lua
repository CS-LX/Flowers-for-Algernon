-- 三棱柱编辑器视口绘制层。
-- 只消费 grid/document/selection/context，不修改任何 model 状态。
-- 视觉层级参考 Vengi Viewport/Gizmo、Goxel selection mask、VoxelShop outline。

local ViewportRenderer = {}
ViewportRenderer.__index = ViewportRenderer

local function AddLoop(debugRenderer, vertices, color, depthTest)
    for index = 1, #vertices do
        local nextIndex = index % #vertices + 1
        debugRenderer:AddLine(vertices[index], vertices[nextIndex], color, depthTest)
    end
end

local function ScaleFace(vertices, cellCenter, scale)
    local result = {}
    for index, vertex in ipairs(vertices) do
        result[index] = cellCenter + (vertex - cellCenter) * scale
    end
    return result
end

local function DrawFace(debugRenderer, vertices, color, depthTest)
    if #vertices == 3 then
        debugRenderer:AddTriangle(vertices[1], vertices[2], vertices[3], color, depthTest)
    else
        debugRenderer:AddPolygon(vertices[1], vertices[2], vertices[3], vertices[4], color, depthTest)
    end
end

function ViewportRenderer.New(debugRenderer, grid, document, selection)
    local self = setmetatable({}, ViewportRenderer)
    self.debugRenderer = debugRenderer
    -- 编辑器 overlay 必须保持稳定浅色；线抗锯齿会把边缘与深色场景混合，
    -- 在斜视角下表现为黑线，因此这里使用清晰的不透明像素线。
    self.debugRenderer:SetLineAntiAlias(false)
    self.grid = grid
    self.document = document
    self.selection = selection
    self.showGrid = true
    self.showAxes = true
    self.showHitFace = true
    self.gridRadius = 5
    return self
end

function ViewportRenderer:DrawGrid(activeLayer)
    if not self.showGrid then
        return
    end
    local y = activeLayer * self.grid.voxelHeight + 0.035
    local gridColor = Color(0.78, 0.86, 0.96, 1.0)
    local triangleColor = Color(0.68, 0.79, 0.92, 1.0)
    for hexR = -self.gridRadius, self.gridRadius do
        for hexQ = -self.gridRadius, self.gridRadius do
            local vertices = self.grid:GetHexVertices(hexQ, hexR, y)
            AddLoop(self.debugRenderer, vertices, gridColor, false)
            for sector = 0, 5 do
                local cell = {
                    hexQ = hexQ,
                    hexR = hexR,
                    sector = sector,
                    layer = activeLayer,
                }
                local triangle = self.grid:GetTriangleVertices(cell, 0.035)
                self.debugRenderer:AddLine(triangle[1], triangle[2], triangleColor, false)
                self.debugRenderer:AddLine(triangle[1], triangle[3], triangleColor, false)
            end
        end
    end
end

function ViewportRenderer:DrawCellOutline(cell, color, depthTest, widthScale)
    if not cell then
        return
    end
    local faces = self.grid:GetCellFaces(cell)
    for _, face in ipairs(faces) do
        AddLoop(self.debugRenderer, face.vertices, color, depthTest)
    end
    local center = self.grid:GetCellCenter(cell)
    self.debugRenderer:AddCross(center, 0.12 * (widthScale or 1.0), color, depthTest)
end

function ViewportRenderer:DrawCellFace(cell, faceIndex, color, depthTest)
    if not cell or not faceIndex then
        return
    end
    local faces = self.grid:GetCellFaces(cell)
    for _, face in ipairs(faces) do
        if face.index == faceIndex then
            local vertices = face.vertices
            if #vertices == 3 then
                self.debugRenderer:AddTriangle(vertices[1], vertices[2], vertices[3], color, depthTest)
            else
                self.debugRenderer:AddPolygon(vertices[1], vertices[2], vertices[3], vertices[4], color, depthTest)
            end
            AddLoop(self.debugRenderer, vertices, color, depthTest)
            return
        end
    end
end

function ViewportRenderer:DrawSelected(selectionCells)
    local fillColor = Color(0.82, 0.92, 1.0, 0.42)
    local topFillColor = Color(0.92, 0.98, 1.0, 0.56)
    local outerColor = Color(0.42, 0.78, 1.0, 1.0)
    local innerColor = Color(0.94, 0.99, 1.0, 1.0)

    for _, cell in pairs(selectionCells or {}) do
        local cellCenter = self.grid:GetCellCenter(cell)
        cellCenter.y = cellCenter.y + self.grid.voxelHeight * 0.5
        for _, face in ipairs(self.grid:GetCellFaces(cell)) do
            local neighbor = self.grid:GetFaceNeighbor(cell, face.index)
            local neighborSelected = neighbor and selectionCells[self.grid:CellKey(neighbor)] ~= nil
            if not neighborSelected then
                local outerVertices = ScaleFace(face.vertices, cellCenter, 1.035)
                local innerVertices = ScaleFace(face.vertices, cellCenter, 1.012)
                DrawFace(
                    self.debugRenderer,
                    outerVertices,
                    face.kind == "top" and topFillColor or fillColor,
                    false
                )
                AddLoop(self.debugRenderer, outerVertices, outerColor, false)
                AddLoop(self.debugRenderer, innerVertices, innerColor, false)
            end
        end
    end
end

function ViewportRenderer:DrawHover(cell, occupied)
    if not cell then
        return
    end
    local color = occupied and Color(1.0, 0.34, 0.16, 1.0) or Color(0.12, 0.92, 0.95, 1.0)
    self:DrawCellOutline(cell, color, false, 1.15)
end

function ViewportRenderer:DrawPreview(changes)
    for _, change in ipairs(changes or {}) do
        if change.after then
            self:DrawCellOutline(change.after, Color(0.18, 1.0, 0.48, 0.88), false, 1.0)
        elseif change.before then
            self:DrawCellOutline(change.before, Color(1.0, 0.24, 0.20, 0.78), false, 1.0)
        end
    end
end

function ViewportRenderer:DrawHitFace(hit)
    if self.showHitFace and hit and hit.cell and hit.face then
        self:DrawCellFace(hit.cell, hit.face, Color(0.95, 0.98, 1.0, 0.72), false)
    end
end

function ViewportRenderer:DrawAxes(origin, scale)
    if not self.showAxes then
        return
    end
    local size = scale or 1.0
    local x = origin + Vector3(size, 0, 0)
    local y = origin + Vector3(0, size, 0)
    local z = origin + Vector3(0, 0, size)
    self.debugRenderer:AddLine(origin, x, Color(0.92, 0.20, 0.20, 0.95), false)
    self.debugRenderer:AddLine(origin, y, Color(0.25, 0.90, 0.35, 0.95), false)
    self.debugRenderer:AddLine(origin, z, Color(0.25, 0.50, 1.0, 0.95), false)
    self.debugRenderer:AddCross(origin, 0.08, Color(0.95, 0.95, 0.95, 0.95), false)
end

function ViewportRenderer:Draw(context, activeLayer, pendingChanges)
    self:DrawGrid(activeLayer)
    self:DrawAxes(Vector3(0, activeLayer * self.grid.voxelHeight + 0.02, 0), 0.7)
    self:DrawHitFace(context.hit)
    self:DrawHover(context.cursorCell, context.cursorCell and self.document:Get(context.cursorCell) ~= nil)
    self:DrawSelected(self.selection:GetCells())
    self:DrawPreview(pendingChanges)
end

return ViewportRenderer
