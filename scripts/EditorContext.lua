-- Vengi 风格的编辑上下文。
-- 输入、命中、选择和投影状态集中在这里，工具不直接读取 UI 或场景节点。

local EditorContext = {}
EditorContext.__index = EditorContext

function EditorContext.New(grid, document)
    local self = setmetatable({}, EditorContext)
    self.grid = grid
    self.document = document
    self.tool = nil
    self.modifier = nil
    self.ray = nil
    self.hit = nil
    self.hitCell = nil
    self.hitFace = nil
    self.hitNormal = nil
    self.placementCell = nil
    self.cursorCell = nil
    self.activeLayer = 0
    self.activeMaterial = 1
    self.gridResolution = 1
    self.lockedDirection = nil
    self.selection = {}
    self.projection = "orthographic"
    self.isDragging = false
    self.isPreviewing = false
    self.pointerOverUI = false
    self.mousePosition = Vector2(0, 0)
    self.now = 0.0
    return self
end

function EditorContext:UpdateHit(ray, hit)
    self.ray = ray
    self.hit = hit
    self.hitCell = hit and hit.cell or nil
    self.hitFace = hit and hit.face or nil
    self.hitNormal = hit and hit.normal or nil
    self.placementCell = hit and hit.placementCell or nil
    self.cursorCell = self.placementCell or self.hitCell
end

return EditorContext
