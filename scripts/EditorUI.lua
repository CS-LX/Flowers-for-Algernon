-- 三棱柱体素编辑器 Yoga UI。
-- 只负责构建面板、保存控件引用、转发用户命令；不读取或修改 Document/Grid/SceneNode。

local UI = require("urhox-libs/UI")
local IconToolPalette = require "IconToolPalette"

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
    local toolPalette = IconToolPalette.New({
        activeToolId = "edit",
        activeModes = {
            edit = "place",
            selection = "select",
            transform = "copy",
            view = "grid",
            document = "undo",
        },
        tools = {
            { id = "edit", icon = "brush", modes = {
                { id = "place", label = "笔刷", icon = "brush" },
                { id = "erase", label = "擦除", icon = "erase" },
                { id = "fill", label = "填充", icon = "fill" },
                { id = "picker", label = "吸管", icon = "picker" },
                { id = "path_node", label = "挂载节点", icon = "path" },
                { id = "delete_node", label = "删除节点", icon = "delete" },
            } },
            { id = "selection", icon = "select", modes = {
                { id = "select", label = "单选", icon = "select" },
                { id = "box", label = "框选", icon = "box_select" },
                { id = "connected", label = "连通选择", icon = "connected" },
                { id = "same_material", label = "同材质选择", icon = "same_material" },
                { id = "layer", label = "当前层", icon = "layer" },
                { id = "surface", label = "表面", icon = "surface" },
                { id = "select_all", label = "全选", icon = "select_all" },
                { id = "clear", label = "清空选择", icon = "clear" },
            } },
            { id = "transform", icon = "copy", modes = {
                { id = "copy", label = "复制", icon = "copy" },
                { id = "paste", label = "粘贴", icon = "paste" },
                { id = "delete_selection", label = "删除选中", icon = "delete" },
                { id = "rotate", label = "旋转", icon = "rotate" },
                { id = "mirror", label = "镜像", icon = "mirror" },
                { id = "move_left", label = "向左移动", icon = "move" },
                { id = "move_right", label = "向右移动", icon = "move" },
                { id = "move_up", label = "上移一层", icon = "move" },
            } },
            { id = "view", icon = "grid", modes = {
                { id = "grid", label = "网格", icon = "grid" },
                { id = "axes", label = "轴向", icon = "move" },
                { id = "projection", label = "投影", icon = "projection" },
            } },
            { id = "document", icon = "undo", modes = {
                { id = "undo", label = "撤销", icon = "undo" },
                { id = "redo", label = "重做", icon = "redo" },
                { id = "save", label = "保存", icon = "save" },
                { id = "load", label = "加载", icon = "load" },
            } },
        },
        onSelect = function(toolId, modeId)
            if toolId == "edit" then
                if modeId == "path_node" then
                    editor:SetPathNodeTool(true, false)
                elseif modeId == "delete_node" then
                    editor:SetPathNodeTool(true, true)
                else
                    editor:SetTool(modeId)
                end
            elseif toolId == "selection" then
                if modeId == "connected" then editor:SelectConnected()
                elseif modeId == "same_material" then editor:SelectSameMaterial()
                elseif modeId == "layer" then editor:SelectLayer()
                elseif modeId == "surface" then editor:SelectSurface()
                elseif modeId == "select_all" then editor:SelectAll()
                elseif modeId == "clear" then editor:ClearSelection()
                else editor:SetTool(modeId) end
            elseif toolId == "transform" then
                if modeId == "copy" then editor:CopySelection()
                elseif modeId == "paste" then editor:PasteAtHover()
                elseif modeId == "delete_selection" then editor:DeleteSelection()
                elseif modeId == "rotate" then editor:RotateSelection()
                elseif modeId == "mirror" then editor:MirrorSelection()
                elseif modeId == "move_left" then editor:MoveSelection(-1, 0, 0)
                elseif modeId == "move_right" then editor:MoveSelection(1, 0, 0)
                elseif modeId == "move_up" then editor:MoveSelection(0, 0, 1) end
            elseif toolId == "view" then
                if modeId == "grid" then editor:ToggleGrid()
                elseif modeId == "axes" then editor:ToggleAxes()
                elseif modeId == "projection" then editor:ToggleProjection() end
            elseif toolId == "document" then
                if modeId == "undo" then editor:Undo()
                elseif modeId == "redo" then editor:Redo()
                elseif modeId == "save" then editor:SaveDocument()
                elseif modeId == "load" then editor:LoadDocument() end
            end
        end,
    })
    editor.toolPalette = toolPalette

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
                    UI.Button {
                        text = "← 返回关卡",
                        height = 28,
                        fontSize = 11,
                        variant = "secondary",
                        visible = editor.onBackToLevel ~= nil,
                        onClick = function()
                            if editor.onBackToLevel then editor.onBackToLevel() end
                        end,
                    },
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
                position = "absolute", top = 52, left = 8, width = 62,
                pointerEvents = "auto",
                children = { toolPalette:Build() },
            },
            UI.Panel {
                position = "absolute", top = 52, right = 8, width = 224, padding = 10, gap = 6,
                backgroundColor = PANEL_COLOR, borderColor = BORDER_COLOR, borderWidth = 1, borderRadius = 5,
                children = {
                    UI.Label { text = "检查器", fontSize = 11, fontWeight = "bold", fontColor = TEXT_COLOR },
                    UI.Label { text = "选择状态", fontSize = 10, fontColor = MUTED_COLOR },
                    editor.selectionLabel,
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
