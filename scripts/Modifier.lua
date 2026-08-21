-- Vengi 风格工具协调器。
-- Modifier 管理生命周期；Brush 生成变化；History 只在 Commit 时接收一个完整命令。

local Modifier = {}
Modifier.__index = Modifier

function Modifier.New(document, history, context, pendingEdit, onPreviewChanged)
    local self = setmetatable({}, Modifier)
    self.document = document
    self.history = history
    self.context = context
    self.pendingEdit = pendingEdit
    self.onPreviewChanged = onPreviewChanged
    self.brush = nil
    self.mode = "place"
    self.active = false
    return self
end

function Modifier:SetBrush(brush)
    if self.brush and self.active then
        self.brush:Deactivate(self.context)
    end
    self.brush = brush
    if self.active and self.brush then
        self.brush:SetMode(self.mode)
        self.brush:Activate(self.context)
    end
end

function Modifier:SetMode(mode)
    self.mode = mode or "place"
    if self.brush then
        self.brush:SetMode(self.mode)
    end
end

function Modifier:Activate()
    self.active = true
    self.context.modifier = self
    if self.brush then
        self.brush:SetMode(self.mode)
        self.brush:Activate(self.context)
    end
end

function Modifier:Begin()
    if not self.active or not self.brush or self.context.isDragging then
        return false
    end
    self.context.isDragging = true
    self.brush:Begin(self.context)
    self:NotifyPreview()
    return true
end

function Modifier:Update(dt)
    if not self.active or not self.brush or not self.context.isDragging then
        return
    end
    self.context.now = self.context.now + (dt or 0)
    self.brush:Execute(self.context)
    self:NotifyPreview()
end

function Modifier:End(commit)
    if not self.context.isDragging or not self.brush then
        return false
    end
    self.brush:End(self.context)
    if commit == false then
        self:Abort()
    else
        self:Commit()
    end
    return true
end

function Modifier:Commit()
    local changes = self.pendingEdit:GetChanges()
    if #changes > 0 then
        self.history:Execute(changes, self.mode == "erase" and "Erase Brush" or "Place Brush")
    end
    self.pendingEdit:Clear()
    self.brush:Commit(self.context)
    self.context.isDragging = false
    self.context.isPreviewing = false
    self:NotifyPreview()
end

function Modifier:Abort()
    self.pendingEdit:Revert()
    self.brush:Abort(self.context)
    self.context.isDragging = false
    self.context.isPreviewing = false
    self:NotifyPreview()
end

function Modifier:Deactivate()
    if self.context.isDragging then
        self:Abort()
    end
    if self.brush then
        self.brush:Deactivate(self.context)
    end
    self.active = false
    self.context.modifier = nil
end

function Modifier:NotifyPreview()
    if self.onPreviewChanged then
        self.onPreviewChanged(self.pendingEdit:GetChanges())
    end
end

return Modifier
