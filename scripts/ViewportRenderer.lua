-- 体素编辑器辅助显示状态。
-- 所有网格、Hover、命中面、选区和 PendingEdit 绘制统一由 OverlayRenderer 承担。
-- 本模块只保存 UI 可切换的显示选项，不直接调用 DebugRenderer。

local ViewportRenderer = {}
ViewportRenderer.__index = ViewportRenderer

function ViewportRenderer.New(_, grid, document, selection)
    local self = setmetatable({}, ViewportRenderer)
    self.grid = grid
    self.document = document
    self.selection = selection
    self.showGrid = true
    self.showAxes = true
    self.showHitFace = true
    self.gridRadius = 5
    return self
end

return ViewportRenderer
