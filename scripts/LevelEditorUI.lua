-- Level View 的 Yoga UI。
-- 左侧 Object Tree，右侧 Inspector 拆成关卡 / Part 两个 Tab。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"
local LevelInspector = require "LevelInspector"
local PartInspector = require "PartInspector"
local StillObjectInspector = require "StillObjectInspector"

local LevelEditorUI = {}
LevelEditorUI.__index = LevelEditorUI

function LevelEditorUI.New(editor)
    local self = setmetatable({}, LevelEditorUI)
    self.editor = editor
    self.root = nil
    self.levelInspector = LevelInspector.New(editor)
    self.partInspector = PartInspector.New(editor)
    self.stillInspector = StillObjectInspector.New(editor)
    self.inspectorTabs = nil
    self.tree = nil
    self.titleLabel = nil
    self.statusLabel = nil
    self.createButton = nil
    self.createStillButton = nil
    self.duplicateButton = nil
    self.deleteButton = nil
    return self
end

function LevelEditorUI:Build()
    UI.Init({
        theme = "default-dark",
        fonts = { { name = "sans", path = "Fonts/MiSans-Regular.ttf" } },
        scale = UI.Scale.DEFAULT,
    })

    local editor = self.editor
    self.titleLabel = UI.Label {
        text = "LEVEL OBJECT TREE",
        fontSize = 17,
        fontWeight = "bold",
        fontColor = Shared.TEXT,
    }
    self.statusLabel = UI.Label {
        text = "",
        fontSize = 11,
        fontColor = Shared.MUTED,
    }
    self.tree = UI.Tree {
        nodes = {},
        size = "sm",
        height = "100%",
        flexGrow = 1,
        flexShrink = 1,
        showLines = true,
        defaultExpandAll = false,
        selectedBgColor = Shared.COMPONENT_ACCENT,
        onSelect = function(_, _, node)
            if node and node.id then
                editor:SelectObject(node.id)
            end
        end,
    }
    self.createButton = UI.Button {
        text = "+ 新建 Part",
        height = 30,
        fontSize = 11,
        variant = "primary",
        onClick = function() editor:CreateEmptyPart() end,
    }
    self.createStillButton = UI.Button {
        text = "+ 新建静物",
        height = 28,
        fontSize = 11,
        variant = "secondary",
        onClick = function() editor:CreateStillObject() end,
    }
    self.duplicateButton = UI.Button {
        text = "复制",
        flexGrow = 1,
        height = 28,
        fontSize = 10,
        variant = "secondary",
        onClick = function() editor:DuplicateSelectedObject() end,
    }
    self.deleteButton = UI.Button {
        text = "删除",
        flexGrow = 1,
        height = 28,
        fontSize = 10,
        variant = "danger",
        onClick = function()
            editor:ConfirmDeleteSelectedObject()
        end,
    }

    local levelContent = self.levelInspector:Build()
    local partContent = self.partInspector:Build()
    local stillContent = self.stillInspector:Build()
    self.inspectorTabs = UI.Tabs {
        tabs = {
            { id = "level", label = "关卡" },
            { id = "part", label = "Part" },
            { id = "still", label = "静物" },
        },
        activeTab = "level",
        variant = "enclosed",
        tabHeight = 32,
        fontSize = 12,
        width = "100%",
        height = "100%",
        backgroundColor = Shared.PANEL,
        onChange = function(_, tabId)
            if tabId == "part" and not editor:GetSelectedPart() then
                editor:RefreshLevelUI("未选择 Part，Part Inspector 为空")
            elseif tabId == "still" and not editor:GetSelectedStillObject() then
                editor:RefreshLevelUI("未选择静物，静物 Inspector 为空")
            end
        end,
    }
    self.inspectorTabs:SetTabContent("level", levelContent)
    self.inspectorTabs:SetTabContent("part", partContent)
    self.inspectorTabs:SetTabContent("still", stillContent)

    self.root = UI.Panel {
        width = "100%",
        height = "100%",
        pointerEvents = "box-none",
        children = {
            UI.Panel {
                position = "absolute", top = 8, left = 8, right = 8, height = 40,
                paddingHorizontal = 12, flexDirection = "row", alignItems = "center", gap = 16,
                backgroundColor = Shared.PANEL, borderColor = Shared.BORDER, borderWidth = 1, borderRadius = 6,
                children = {
                    self.titleLabel,
                    UI.Label { text = "关卡总装 / 固定 30° 正交视图", fontSize = 11, fontColor = Shared.MUTED },
                    UI.Panel { flexGrow = 1, flexShrink = 1 },
                    UI.Label { text = "F9：UI 检查器", fontSize = 10, fontColor = Shared.MUTED },
                },
            },
            UI.Panel {
                position = "absolute", top = 56, left = 8, width = 210, bottom = 44,
                padding = 10, gap = 8,
                backgroundColor = Shared.PANEL, borderColor = Shared.BORDER, borderWidth = 1, borderRadius = 6,
                children = {
                    UI.Label { text = "OBJECT TREE", fontSize = 11, fontWeight = "bold", fontColor = Shared.TEXT },
                    UI.Label { text = "LevelRoot", fontSize = 12, fontWeight = "bold", fontColor = { 180, 201, 226, 255 } },
                    self.tree,
                    self.createButton,
                    self.createStillButton,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.duplicateButton,
                        self.deleteButton,
                    } },
                    UI.Divider { thickness = 1, color = Shared.BORDER, spacing = 2 },
                    UI.Label { text = "选择 Part 后可在右侧 Part Tab 编辑属性。", fontSize = 10, fontColor = Shared.MUTED, whiteSpace = "normal" },
                },
            },
            UI.Panel {
                position = "absolute", top = 56, right = 8, width = 300, bottom = 44,
                backgroundColor = Shared.PANEL, borderColor = Shared.BORDER, borderWidth = 1, borderRadius = 3,
                overflow = "hidden",
                children = {
                    self.inspectorTabs,
                },
            },
            UI.Panel {
                position = "absolute", left = 8, right = 8, bottom = 8, height = 28,
                paddingHorizontal = 10, flexDirection = "row", alignItems = "center",
                backgroundColor = Shared.PANEL, borderColor = Shared.BORDER, borderWidth = 1, borderRadius = 5,
                children = {
                    self.statusLabel,
                    UI.Panel { flexGrow = 1 },
                    UI.Label { text = "关卡 Tab 配置路径与预览；Part Tab 编辑选中物件。", fontSize = 10, fontColor = Shared.MUTED },
                },
            },
        },
    }
    UI.SetRoot(self.root, true)
    self:Refresh()
end

function LevelEditorUI:Refresh()
    self.tree:SetNodes(self.editor.levelDocument:GetTreeNodes())
    self.tree:ExpandAll()
    self.levelInspector:Refresh()
    self.partInspector:Refresh()
    self.stillInspector:Refresh()

    local part = self.editor:GetSelectedPart()
    local still = self.editor:GetSelectedStillObject()
    local hasObject = part ~= nil or still ~= nil
    self.duplicateButton:SetDisabled(not hasObject)
    self.deleteButton:SetDisabled(not hasObject)
end

function LevelEditorUI:ShowInspectorForSelection()
    if not self.inspectorTabs then
        return
    end
    if self.editor:GetSelectedStillObject() then
        self.inspectorTabs:SetActiveTab("still")
    elseif self.editor:GetSelectedPart() then
        self.inspectorTabs:SetActiveTab("part")
    end
end

function LevelEditorUI:RefreshSpawnPicker()
    self.levelInspector:RefreshSpawnPicker()
end

function LevelEditorUI:RefreshPathCandidatePicker()
    self.levelInspector:RefreshPathCandidatePicker()
end

function LevelEditorUI:SetCameraState(camera)
    self.levelInspector:SetCameraState(camera)
end

function LevelEditorUI:SetStatus(text)
    self.statusLabel:SetText(text)
end

function LevelEditorUI:Destroy()
    if self.root then
        if UI.GetRoot() == self.root then
            UI.SetRoot(nil, true)
        else
            self.root:Destroy()
        end
        self.root = nil
    end
end

return LevelEditorUI
