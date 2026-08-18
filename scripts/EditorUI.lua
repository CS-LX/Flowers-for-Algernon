-- 三棱柱体素编辑器 Yoga UI。
-- 只负责构建面板、保存控件引用、转发用户命令；不读取或修改 Document/Grid/SceneNode。

local UI = require("urhox-libs/UI")

local EditorUI = {}
EditorUI.__index = EditorUI

local PANEL_COLOR = { 24, 29, 38, 242 }
local BORDER_COLOR = { 71, 85, 105, 170 }
local MUTED_COLOR = { 100, 116, 139, 255 }
local TEXT_COLOR = { 226, 232, 240, 255 }

function EditorUI.New(editor)
    local self = setmetatable({}, EditorUI)
    self.editor = editor
    self.root = nil
    return self
end

function EditorUI:Build()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    local editor = self.editor
    local function toolButton(text, tool, variant)
        return UI.Button {
            text = text,
            variant = variant or "secondary",
            height = 30,
            fontSize = 12,
            onClick = function()
                editor:SetTool(tool)
            end,
        }
    end

    local title = UI.Label {
        text = "TRI-PRISM VOXEL EDITOR",
        fontSize = 17,
        fontWeight = "bold",
        fontColor = { 240, 245, 255, 255 },
    }
    editor.toolLabel = UI.Label {
        text = "工具：笔刷",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = TEXT_COLOR,
    }
    editor.layerLabel = UI.Label {
        text = "层：0",
        fontSize = 12,
        fontColor = { 148, 163, 184, 255 },
    }
    editor.projectionLabel = UI.Label {
        text = "投影：正交",
        fontSize = 12,
        fontColor = { 148, 163, 184, 255 },
    }
    editor.viewLabel = UI.Label {
        text = "LMB 编辑  ·  RMB 旋转  ·  MMB 平移  ·  Wheel 缩放",
        fontSize = 11,
        fontColor = MUTED_COLOR,
    }
    editor.statusLabel = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = { 148, 163, 184, 255 },
    }
    editor.selectionLabel = UI.Label {
        text = "选择：0 个",
        fontSize = 12,
        fontColor = { 190, 225, 255, 255 },
    }

    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8, right = 8, height = 38,
                paddingHorizontal = 12, flexDirection = "row", alignItems = "center", gap = 18,
                backgroundColor = { 24, 29, 38, 245 }, borderColor = BORDER_COLOR, borderWidth = 1, borderRadius = 5,
                children = {
                    title,
                    UI.Label { text = "文件", fontSize = 11, fontColor = MUTED_COLOR },
                    UI.Label { text = "编辑", fontSize = 11, fontColor = MUTED_COLOR },
                    UI.Label { text = "视图", fontSize = 11, fontColor = MUTED_COLOR },
                    UI.Label { text = "工具", fontSize = 11, fontColor = MUTED_COLOR },
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    editor.toolLabel, editor.layerLabel, editor.projectionLabel,
                },
            },
            UI.Panel {
                position = "absolute", top = 52, left = 8, width = 172, padding = 8, gap = 5,
                backgroundColor = PANEL_COLOR, borderColor = BORDER_COLOR, borderWidth = 1, borderRadius = 5,
                children = {
                    UI.Label { text = "工具箱", fontSize = 11, fontWeight = "bold", fontColor = TEXT_COLOR },
                    UI.Label { text = "编辑", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        toolButton("笔刷", "place", "primary"), toolButton("擦除", "erase", "danger"),
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        toolButton("单选", "select"), toolButton("框选", "box"),
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        toolButton("填充", "fill"), toolButton("吸管", "picker"),
                    } },
                    UI.Label { text = "选择扩展", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "连通", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:SelectConnected() end },
                        UI.Button { text = "同材质", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:SelectSameMaterial() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "当前层", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:SelectLayer() end },
                        UI.Button { text = "表面", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:SelectSurface() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "全选", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:SelectAll() end },
                        UI.Button { text = "清空", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:ClearSelection() end },
                    } },
                    UI.Label { text = "图层", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "−", width = 32, height = 27, fontSize = 14, variant = "secondary", onClick = function() editor:SetLayer(editor.activeLayer - 1) end },
                        UI.Button { text = "+", width = 32, height = 27, fontSize = 14, variant = "secondary", onClick = function() editor:SetLayer(editor.activeLayer + 1) end },
                        UI.Button { text = "投影", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleProjection() end },
                    } },
                    UI.Label { text = "文档", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "撤销", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:Undo() end },
                        UI.Button { text = "重做", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:Redo() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "保存", flexGrow = 1, height = 27, fontSize = 10, variant = "success", onClick = function() editor:SaveDocument() end },
                        UI.Button { text = "加载", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:LoadDocument() end },
                    } },
                },
            },
            UI.Panel {
                position = "absolute", top = 52, right = 8, width = 224, padding = 10, gap = 6,
                backgroundColor = PANEL_COLOR, borderColor = BORDER_COLOR, borderWidth = 1, borderRadius = 5,
                children = {
                    UI.Label { text = "检查器", fontSize = 11, fontWeight = "bold", fontColor = TEXT_COLOR },
                    UI.Label { text = "选择状态", fontSize = 10, fontColor = MUTED_COLOR },
                    editor.selectionLabel,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "复制", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:CopySelection() end },
                        UI.Button { text = "粘贴", flexGrow = 1, height = 28, fontSize = 10, variant = "primary", onClick = function() editor:PasteAtHover() end },
                        UI.Button { text = "删除选中", flexGrow = 1, height = 28, fontSize = 10, variant = "danger", onClick = function() editor:DeleteSelection() end },
                    } },
                    UI.Label { text = "变换", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "旋转", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:RotateSelection() end },
                        UI.Button { text = "镜像", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:MirrorSelection() end },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "←", flexGrow = 1, height = 28, fontSize = 13, variant = "secondary", onClick = function() editor:MoveSelection(-1, 0, 0) end },
                        UI.Button { text = "→", flexGrow = 1, height = 28, fontSize = 13, variant = "secondary", onClick = function() editor:MoveSelection(1, 0, 0) end },
                        UI.Button { text = "↑层", flexGrow = 1, height = 28, fontSize = 10, variant = "secondary", onClick = function() editor:MoveSelection(0, 0, 1) end },
                    } },
                    UI.Label { text = "视图", fontSize = 10, fontColor = MUTED_COLOR },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "网格", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleGrid() end },
                        UI.Button { text = "轴向", flexGrow = 1, height = 27, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleAxes() end },
                    } },
                },
            },
            UI.Panel {
                position = "absolute", left = 8, right = 8, bottom = 8, height = 30,
                paddingHorizontal = 10, flexDirection = "row", alignItems = "center",
                backgroundColor = { 24, 29, 38, 238 }, borderColor = BORDER_COLOR, borderWidth = 1, borderRadius = 5,
                children = { editor.statusLabel, UI.Panel { flexGrow = 1 }, editor.viewLabel },
            },
        },
    }
    UI.SetRoot(self.root)
end

function EditorUI:Destroy()
    self.root = nil
    UI.Shutdown()
end

return EditorUI
