-- 三棱柱连续笔刷。
-- 参考 Goxel 的 last_pos 插值原则：快速拖动时按固定步长补齐路径，避免断笔。
-- Brush 只产生 PendingEdit，不直接写文档或创建场景节点。

local VoxelBrush = {}
VoxelBrush.__index = VoxelBrush

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

local function CellDistance(a, b)
    local dq = math.abs(a.hexQ - b.hexQ)
    local dr = math.abs(a.hexR - b.hexR)
    local ds = math.abs(a.sector - b.sector)
    local dl = math.abs(a.layer - b.layer)
    return math.max(dq, dr, math.ceil(ds / 2), dl)
end

function VoxelBrush.New(grid, document, pendingEdit)
    local self = setmetatable({}, VoxelBrush)
    self.grid = grid
    self.document = document
    self.pendingEdit = pendingEdit
    self.mode = "place"
    self.activeMaterial = 1
    self.lastCell = nil
    self.started = false
    return self
end

function VoxelBrush:SetMode(mode)
    self.mode = mode or "place"
end

function VoxelBrush:SetMaterial(material)
    self.activeMaterial = material or 1
end

function VoxelBrush:Activate(context)
    context.tool = self
end

function VoxelBrush:Begin(context)
    self.pendingEdit:Begin()
    self.lastCell = nil
    self.started = true
    self:Update(context)
end

function VoxelBrush:CellAtStep(startCell, endCell, step, count)
    local t = count <= 1 and 1.0 or step / count
    local cell = {
        hexQ = math.floor(startCell.hexQ + (endCell.hexQ - startCell.hexQ) * t + 0.5),
        hexR = math.floor(startCell.hexR + (endCell.hexR - startCell.hexR) * t + 0.5),
        sector = math.floor(startCell.sector + (endCell.sector - startCell.sector) * t + 0.5) % 6,
        layer = math.floor(startCell.layer + (endCell.layer - startCell.layer) * t + 0.5),
        rotation = 0,
        material = self.activeMaterial,
    }
    return self.grid:NormalizeCell(cell)
end

function VoxelBrush:ApplyCell(cell)
    if not cell then
        return
    end
    local normalized = self.grid:NormalizeCell(cell)
    local before = self.document:Get(normalized)
    local after = nil
    local changed = false
    if self.mode == "place" then
        if not before then
            normalized.material = self.activeMaterial
            after = normalized
            changed = true
        end
    elseif self.mode == "erase" then
        if before then
            changed = true
        end
    elseif self.mode == "paint" then
        if before and before.material ~= self.activeMaterial then
            after = CopyCell(before)
            after.material = self.activeMaterial
            changed = true
        end
    end
    if changed then
        self.pendingEdit:SetChange(normalized, before, after)
    end
end

function VoxelBrush:Update(context)
    if not self.started or not context.cursorCell then
        return
    end
    local current = self.grid:NormalizeCell(context.cursorCell)
    if not self.lastCell then
        self:ApplyCell(current)
        self.lastCell = current
        return
    end

    local distance = CellDistance(self.lastCell, current)
    local steps = math.max(1, distance * 2)
    for step = 1, steps do
        self:ApplyCell(self:CellAtStep(self.lastCell, current, step, steps))
    end
    self.lastCell = current
end

function VoxelBrush:Preview(context)
    context.isPreviewing = self.pendingEdit:Count() > 0
end

function VoxelBrush:Execute(context)
    self:Update(context)
    self:Preview(context)
end

function VoxelBrush:End(context)
    self:Preview(context)
end

function VoxelBrush:Commit(context)
    self.started = false
    self.lastCell = nil
end

function VoxelBrush:Abort(context)
    self.pendingEdit:Revert()
    self.started = false
    self.lastCell = nil
    context.isPreviewing = false
end

function VoxelBrush:Deactivate(context)
    if self.started then
        self:Abort(context)
    end
    if context.tool == self then
        context.tool = nil
    end
end

return VoxelBrush
