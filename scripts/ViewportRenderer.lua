-- Part 编辑器辅助显示选项。
-- 实际绘制统一由 LevelEditorOverlayRenderer 完成。

local PartEditorDisplayOptions = {}
PartEditorDisplayOptions.__index = PartEditorDisplayOptions

function PartEditorDisplayOptions.New()
    local self = setmetatable({}, PartEditorDisplayOptions)
    self.showGrid = true
    self.showAxes = true
    self.showHitFace = true
    self.gridRadius = 5
    return self
end

return PartEditorDisplayOptions
