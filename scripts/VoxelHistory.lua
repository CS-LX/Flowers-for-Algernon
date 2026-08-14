-- 体素文档命令历史。
-- 所有编辑操作先形成变更，再一次性提交；拖拽笔刷作为一个 BatchCommand。

local VoxelHistory = {}
VoxelHistory.__index = VoxelHistory

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

local function ApplyChange(document, change, forward)
    local value = forward and change.after or change.before
    local target = forward and change.before or change.after
    if value then
        document:Set(value)
    elseif forward and target then
        document:Remove(target)
    elseif not forward and target then
        document:Set(target)
    end
end

function VoxelHistory.New(document, onChanged)
    local self = setmetatable({}, VoxelHistory)
    self.document = document
    self.onChanged = onChanged
    self.undoStack = {}
    self.redoStack = {}
    return self
end

function VoxelHistory:Notify()
    if self.onChanged then
        self.onChanged()
    end
end

function VoxelHistory:Execute(changes, label)
    if not changes or #changes == 0 then
        return false
    end

    local command = {
        label = label or "Edit",
        changes = {},
    }
    for _, change in ipairs(changes) do
        command.changes[#command.changes + 1] = {
            before = CopyCell(change.before),
            after = CopyCell(change.after),
        }
    end

    for _, change in ipairs(command.changes) do
        ApplyChange(self.document, change, true)
    end
    self.undoStack[#self.undoStack + 1] = command
    self.redoStack = {}
    self:Notify()
    return true
end

function VoxelHistory:Undo()
    local command = self.undoStack[#self.undoStack]
    if not command then
        return false
    end

    for index = #command.changes, 1, -1 do
        ApplyChange(self.document, command.changes[index], false)
    end
    self.undoStack[#self.undoStack] = nil
    self.redoStack[#self.redoStack + 1] = command
    self:Notify()
    return true
end

function VoxelHistory:Redo()
    local command = self.redoStack[#self.redoStack]
    if not command then
        return false
    end

    for _, change in ipairs(command.changes) do
        ApplyChange(self.document, change, true)
    end
    self.redoStack[#self.redoStack] = nil
    self.undoStack[#self.undoStack + 1] = command
    self:Notify()
    return true
end

function VoxelHistory:CanUndo()
    return #self.undoStack > 0
end

function VoxelHistory:CanRedo()
    return #self.redoStack > 0
end

function VoxelHistory:Clear()
    self.undoStack = {}
    self.redoStack = {}
end

return VoxelHistory
