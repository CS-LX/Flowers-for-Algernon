-- 拖拽中的临时编辑结果。
-- 只保存 before/after，不直接修改 EditorDocument；取消时直接丢弃。

local PendingEdit = {}
PendingEdit.__index = PendingEdit

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

function PendingEdit.New(document)
    local self = setmetatable({}, PendingEdit)
    self.document = document
    self.changes = {}
    self.order = {}
    self.active = false
    return self
end

function PendingEdit:Begin()
    self.changes = {}
    self.order = {}
    self.active = true
end

function PendingEdit:SetChange(cell, before, after)
    if not cell then
        return false
    end
    local key = self.document.grid:CellKey(cell)
    if self.changes[key] then
        return false
    end
    self.changes[key] = {
        key = key,
        before = CopyCell(before),
        after = CopyCell(after),
    }
    self.order[#self.order + 1] = key
    return true
end

function PendingEdit:Has(key)
    return self.changes[key] ~= nil
end

function PendingEdit:GetChange(key)
    return self.changes[key]
end

function PendingEdit:GetChanges()
    local result = {}
    for _, key in ipairs(self.order) do
        result[#result + 1] = self.changes[key]
    end
    return result
end

function PendingEdit:Count()
    return #self.order
end

function PendingEdit:Clear()
    self.changes = {}
    self.order = {}
    self.active = false
end

function PendingEdit:Revert()
    self:Clear()
end

return PendingEdit
