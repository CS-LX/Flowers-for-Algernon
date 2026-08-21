-- 三棱柱选择集与选择策略。
--
-- 参考边界：
-- Vengi：选择模式作为策略（Single/Box/Connected/SameMaterial/Surface）。
-- Goxel：Replace/Add/Subtract 三种合并语义，拖拽结束后才提交选择。
-- VoxelShop：正式选择、hover 高亮、临时框选范围、临时变换互相分离。
--
-- 本模块不处理鼠标，不修改文档，也不创建场景节点。

local Selection = {}
Selection.__index = Selection

local MAX_CONNECTED_CELLS = 4096

local function CopyCell(cell)
    if not cell then
        return nil
    end
    return {
        hexQ = cell.hexQ,
        hexR = cell.hexR,
        sector = cell.sector,
        layer = cell.layer,
        rotation = cell.rotation,
        material = cell.material,
    }
end

local function HexDistance(a, b)
    local dq = a.hexQ - b.hexQ
    local dr = a.hexR - b.hexR
    return math.max(math.abs(dq), math.abs(dr), math.abs(dq + dr))
end

function Selection.New(grid, document, onChanged)
    local self = setmetatable({}, Selection)
    self.grid = grid
    self.document = document
    self.onChanged = onChanged
    self.cells = {}
    self.previewCells = {}
    self.previewBounds = nil
    return self
end

function Selection:Notify()
    if self.onChanged then
        self.onChanged(self)
    end
end

function Selection:ClearPreview()
    self.previewCells = {}
    self.previewBounds = nil
end

function Selection:GetPreviewCells()
    local result = {}
    for key, cell in pairs(self.previewCells) do
        result[key] = CopyCell(cell)
    end
    return result
end

function Selection:GetPreviewBounds()
    return CopyCell(self.previewBounds and self.previewBounds.first),
        CopyCell(self.previewBounds and self.previewBounds.second)
end

function Selection:SetCells(cells)
    self.cells = self.cells or {}
    for key in pairs(self.cells) do
        self.cells[key] = nil
    end
    for _, cell in ipairs(cells or {}) do
        local existing = self.document:Get(cell)
        if existing then
            self.cells[self.grid:CellKey(existing)] = CopyCell(existing)
        end
    end
    self:ClearPreview()
    self:Notify()
end

function Selection:Clear()
    self.cells = self.cells or {}
    for key in pairs(self.cells) do
        self.cells[key] = nil
    end
    self:ClearPreview()
    self:Notify()
end

function Selection:Count()
    local count = 0
    for _ in pairs(self.cells) do
        count = count + 1
    end
    return count
end

function Selection:Contains(cell)
    return cell and self.cells[self.grid:CellKey(cell)] ~= nil
end

function Selection:GetCells()
    local result = {}
    for key, cell in pairs(self.cells) do
        result[key] = CopyCell(cell)
    end
    return result
end

function Selection:ToArray()
    local result = {}
    for _, cell in pairs(self.cells) do
        result[#result + 1] = CopyCell(cell)
    end
    return result
end

function Selection:Merge(candidates, mode)
    mode = mode or "replace"
    if mode == "replace" then
        self:Clear()
    end
    for _, cell in ipairs(candidates or {}) do
        local normalized = self.grid:NormalizeCell(cell)
        local existing = self.document:Get(normalized)
        if existing then
            local key = self.grid:CellKey(existing)
            if mode == "subtract" then
                self.cells[key] = nil
            else
                self.cells[key] = CopyCell(existing)
            end
        end
    end
    self:ClearPreview()
    self:Notify()
end

function Selection:Preview(candidates, bounds)
    self.previewCells = {}
    for _, cell in ipairs(candidates or {}) do
        local existing = self.document:Get(cell)
        if existing then
            self.previewCells[self.grid:CellKey(existing)] = CopyCell(existing)
        end
    end
    self.previewBounds = bounds
    self:Notify()
end

function Selection:Single(cell)
    local existing = self.document:Get(cell)
    if not existing then
        return {}
    end
    return { CopyCell(existing) }
end

function Selection:Layer(layer)
    local result = {}
    self.document:ForEach(function(cell)
        if cell.layer == layer then
            result[#result + 1] = CopyCell(cell)
        end
    end)
    return result
end

function Selection:SameMaterial(seedCell, sameLayerOnly)
    local seed = self.document:Get(seedCell)
    if not seed then
        return {}
    end
    local result = {}
    self.document:ForEach(function(cell)
        local layerMatches = not sameLayerOnly or cell.layer == seed.layer
        if layerMatches and cell.material == seed.material then
            result[#result + 1] = CopyCell(cell)
        end
    end)
    return result
end

function Selection:Box(firstCell, secondCell)
    if not firstCell or not secondCell then
        return {}, nil
    end
    local first = self.grid:NormalizeCell(firstCell)
    local second = self.grid:NormalizeCell(secondCell)
    local minQ = math.min(first.hexQ, second.hexQ)
    local maxQ = math.max(first.hexQ, second.hexQ)
    local minR = math.min(first.hexR, second.hexR)
    local maxR = math.max(first.hexR, second.hexR)
    local minLayer = math.min(first.layer, second.layer)
    local maxLayer = math.max(first.layer, second.layer)
    local maxRadius = HexDistance(first, second)
    local result = {}

    self.document:ForEach(function(cell)
        local insideAxialBounds = cell.hexQ >= minQ and cell.hexQ <= maxQ
            and cell.hexR >= minR and cell.hexR <= maxR
            and cell.layer >= minLayer and cell.layer <= maxLayer
        local insideHexRadius = HexDistance(first, cell) <= maxRadius
        if insideAxialBounds and insideHexRadius then
            result[#result + 1] = CopyCell(cell)
        end
    end)

    return result, {
        first = CopyCell(first),
        second = CopyCell(second),
        minLayer = minLayer,
        maxLayer = maxLayer,
    }
end

function Selection:Connected(seedCell, sameMaterial)
    local seed = self.document:Get(seedCell)
    if not seed then
        return {}
    end

    local result = {}
    local queue = { CopyCell(seed) }
    local visited = {}
    local index = 1
    while queue[index] and #result < MAX_CONNECTED_CELLS do
        local cell = queue[index]
        index = index + 1
        local key = self.grid:CellKey(cell)
        if not visited[key] then
            visited[key] = true
            local existing = self.document:Get(cell)
            if existing and (not sameMaterial or existing.material == seed.material) then
                result[#result + 1] = CopyCell(existing)
                for face = 1, self.grid.faceCount do
                    local neighbor = self.grid:GetFaceNeighbor(existing, face)
                    if neighbor and neighbor.layer >= 0 then
                        queue[#queue + 1] = neighbor
                    end
                end
            end
        end
    end
    return result
end

function Selection:Surface()
    local result = {}
    self.document:ForEach(function(cell)
        local exposed = false
        for face = 1, self.grid.faceCount do
            local neighbor = self.grid:GetFaceNeighbor(cell, face)
            if not neighbor or neighbor.layer < 0 or not self.document:Get(neighbor) then
                exposed = true
                break
            end
        end
        if exposed then
            result[#result + 1] = CopyCell(cell)
        end
    end)
    return result
end

return Selection
