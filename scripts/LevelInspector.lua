-- 关卡级 Inspector。
-- 负责路径候选、出生点和编辑器相机；不绘制 Part Transform / Behavior。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"

local LevelInspector = {}
LevelInspector.__index = LevelInspector

function LevelInspector.New(editor)
    local self = setmetatable({}, LevelInspector)
    self.editor = editor
    self.selectedPathCandidateId = nil
    self.scroll = nil
    self.pathCandidateFromPickButton = nil
    self.pathCandidateToPickButton = nil
    self.pathCandidateCancelPickButton = nil
    self.pathCandidateClearFromButton = nil
    self.pathCandidateClearToButton = nil
    self.pathCandidateFromDropdown = nil
    self.pathCandidateToDropdown = nil
    self.pathCandidateDirectionDropdown = nil
    self.pathCandidateAddButton = nil
    self.pathCandidateList = nil
    self.pathCandidateRemoveButton = nil
    self.pathCandidateDropdown = nil
    self.pathCandidateStatusLabel = nil
    self.spawnNodeDropdown = nil
    self.spawnClearButton = nil
    self.spawnPickButton = nil
    self.cameraLabel = nil
    self.previewButton = nil
    self.saveButton = nil
    self.exportButton = nil
    self.importButton = nil
    self.lightGroupDropdown = nil
    self.fogColorPicker = nil
    self.fogStartField = nil
    self.fogFinishField = nil
    self.fogDensityField = nil
    self.heightFogToggle = nil
    self.bloomToggle = nil
    self.bloomThresholdField = nil
    self.bloomIntensityField = nil
    self.vignetteToggle = nil
    self.vignetteIntensityField = nil
    return self
end

function LevelInspector:Build()
    local editor = self.editor
    self.pathCandidateFromPickButton = UI.Button {
        text = "拾取起点",
        height = 27, fontSize = 10, variant = "secondary",
        onClick = function() editor:BeginPathPick("from") end,
    }
    self.pathCandidateToPickButton = UI.Button {
        text = "拾取终点",
        height = 27, fontSize = 10, variant = "secondary",
        onClick = function() editor:BeginPathPick("to") end,
    }
    self.pathCandidateCancelPickButton = UI.Button {
        text = "取消拾取",
        height = 27, fontSize = 10, variant = "secondary",
        onClick = function() editor:CancelPathPick() end,
    }
    self.pathCandidateClearFromButton = UI.Button {
        text = "清除起点",
        height = 27, fontSize = 10, variant = "secondary",
        onClick = function()
            editor.pathPickedFromKey = nil
            editor.pathPickMode = nil
            self:RefreshPathCandidatePicker()
            editor:RefreshLevelUI("已清除候选连接起点")
        end,
    }
    self.pathCandidateClearToButton = UI.Button {
        text = "清除终点",
        height = 27, fontSize = 10, variant = "secondary",
        onClick = function()
            editor.pathPickedToKey = nil
            editor.pathPickMode = nil
            self:RefreshPathCandidatePicker()
            editor:RefreshLevelUI("已清除候选连接终点")
        end,
    }
    self.pathCandidateFromDropdown = UI.Dropdown {
        options = {}, value = "", placeholder = "起点节点", height = 26, fontSize = 10,
    }
    self.pathCandidateToDropdown = UI.Dropdown {
        options = {}, value = "", placeholder = "终点节点", height = 26, fontSize = 10,
    }
    self.pathCandidateDirectionDropdown = UI.Dropdown {
        options = {
            { value = "bidirectional", label = "双向" },
            { value = "from_to", label = "起点 → 终点" },
            { value = "to_from", label = "终点 → 起点" },
        },
        value = "bidirectional", height = 26, fontSize = 10,
    }
    self.pathCandidateAddButton = UI.Button {
        text = "添加候选连接", height = 27, fontSize = 10, variant = "secondary",
        onClick = function()
            local ok, result = editor:AddPathCandidateFromUI(
                self.pathCandidateFromDropdown:GetValue(),
                self.pathCandidateToDropdown:GetValue(),
                self.pathCandidateDirectionDropdown:GetValue()
            )
            if ok then
                self.selectedPathCandidateId = nil
                self.pathCandidateDropdown:SetValue("")
                self.pathCandidateFromDropdown:SetValue("")
                self.pathCandidateToDropdown:SetValue("")
                self.pathCandidateStatusLabel:SetText("已添加：" .. result)
                self:Refresh()
            else
                self.pathCandidateStatusLabel:SetText("添加失败：" .. tostring(result))
            end
        end,
    }
    self.pathCandidateList = UI.List {
        items = {}, variant = "dense", selectable = true, showDividers = true,
        height = 120, flexShrink = 1,
        onItemClick = function(_, item)
            self.selectedPathCandidateId = item.id
            self.pathCandidateStatusLabel:SetText(tostring(item.secondary or item.text or item.id))
        end,
    }
    self.pathCandidateRemoveButton = UI.Button {
        text = "删除选中候选", height = 27, fontSize = 10, variant = "danger",
        onClick = function()
            local candidateId = self.selectedPathCandidateId or self.pathCandidateDropdown:GetValue()
            if not candidateId or candidateId == "" then
                self.pathCandidateStatusLabel:SetText("请先选择候选")
                return
            end
            local ok, result = editor:RemovePathCandidateFromUI(candidateId)
            if ok then
                self.selectedPathCandidateId = nil
                self.pathCandidateDropdown:SetValue("")
                self.pathCandidateStatusLabel:SetText("已删除：" .. candidateId)
                self:Refresh()
            else
                self.pathCandidateStatusLabel:SetText("删除失败：" .. tostring(result))
            end
        end,
    }
    self.pathCandidateDropdown = UI.Dropdown {
        options = {}, value = "", placeholder = "已有候选", height = 26, fontSize = 10,
    }
    self.pathCandidateStatusLabel = UI.Label {
        text = "仅通过 UI 配置，不需编辑 JSON",
        fontSize = 9,
        fontColor = Shared.MUTED,
        whiteSpace = "normal",
    }
    self.spawnNodeDropdown = UI.Dropdown {
        options = {}, value = "", placeholder = "选择出生 PathNode", height = 26, fontSize = 10,
        onChange = function(_, value) editor:SetSpawnNodeFromUI(value) end,
    }
    self.spawnClearButton = UI.Button {
        text = "清空出生点", height = 26, fontSize = 10, variant = "secondary",
        onClick = function() editor:ClearSpawnNode() end,
    }
    self.spawnPickButton = UI.Button {
        text = "拾取出生点", height = 26, fontSize = 10, variant = "primary",
        onClick = function() editor:BeginPathPick("spawn") end,
    }
    self.cameraLabel = UI.Label { text = "", fontSize = 10, fontColor = { 173, 214, 255, 255 } }
    self.previewButton = UI.Button {
        text = "游戏预览",
        height = 30,
        fontSize = 11,
        variant = "primary",
        onClick = function()
            editor:StartGamePreview()
        end,
    }
    self.saveButton = UI.Button {
        text = "保存关卡",
        height = 30,
        fontSize = 11,
        variant = "success",
        onClick = function()
            editor:SaveLevel()
        end,
    }
    self.exportButton = UI.Button {
        text = "导出 JSON 到用户剪切板",
        height = 30,
        fontSize = 11,
        variant = "secondary",
        onClick = function()
            editor:ExportInlineLevelToUserClipboard()
        end,
    }
    self.importButton = UI.Button {
        text = "从用户剪切板导入 JSON",
        height = 30,
        fontSize = 11,
        variant = "secondary",
        onClick = function()
            local jsonField = UI.TextField {
                placeholder = "在此 Ctrl+V 粘贴导出的关卡 JSON",
                height = 92,
                fontSize = 11,
            }
            local modal = UI.Modal {
                title = "导入关卡 JSON",
                size = "lg",
                closeOnOverlay = false,
            }
            modal:AddContent(UI.Label {
                text = "WASM 不能直接读取用户系统剪切板。请把导出的 JSON 粘贴到下面，再导入。未导出的当前关卡会被替换。",
                fontSize = 11,
                fontColor = Shared.MUTED,
                whiteSpace = "normal",
            })
            modal:AddContent(jsonField)
            local footer = UI.Panel {
                flexDirection = "row",
                justifyContent = "flex-end",
                gap = 10,
                width = "100%",
            }
            footer:AddChild(UI.Button {
                text = "取消",
                variant = "secondary",
                onClick = function()
                    modal:Close()
                end,
            })
            footer:AddChild(UI.Button {
                text = "导入",
                variant = "primary",
                onClick = function()
                    local json = jsonField:GetValue()
                    modal:Close()
                    editor:ImportInlineLevelJson(json)
                end,
            })
            modal:SetFooter(footer)
            modal:Open()
        end,
    }
    self.lightGroupDropdown = UI.Dropdown {
        options = {
            { value = "LightGroup/Daytime.xml", label = "Daytime" },
            { value = "LightGroup/Dusk.xml", label = "Dusk" },
            { value = "LightGroup/Sandstorm.xml", label = "Sandstorm" },
            { value = "LightGroup/Night.xml", label = "Night" },
            { value = "LightGroup/Midnight.xml", label = "Midnight" },
            { value = "LightGroup/DarkNight.xml", label = "DarkNight" },
            { value = "LightGroup/BloodNight.xml", label = "BloodNight" },
        },
        value = "LightGroup/Daytime.xml",
        height = 26,
        fontSize = 10,
        onChange = function(_, value) editor:SetAtmosphereLightGroup(value) end,
    }
    self.fogColorPicker = Shared.ColorField {
        color = "#C9C2B4",
        onClose = function(picker)
            editor:SetAtmosphereFogColor(picker:GetHex())
        end,
    }
    self.fogStartField = UI.TextField {
        value = "8",
        placeholder = "Start",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereFogNumber("start", value) end,
        onBlur = function(field) editor:SetAtmosphereFogNumber("start", field:GetValue()) end,
    }
    self.fogFinishField = UI.TextField {
        value = "42",
        placeholder = "Finish",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereFogNumber("finish", value) end,
        onBlur = function(field) editor:SetAtmosphereFogNumber("finish", field:GetValue()) end,
    }
    self.fogDensityField = UI.TextField {
        value = "0.85",
        placeholder = "Density",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereFogNumber("density", value) end,
        onBlur = function(field) editor:SetAtmosphereFogNumber("density", field:GetValue()) end,
    }
    self.heightFogToggle = UI.Checkbox {
        checked = false,
        label = "Height Fog",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetAtmosphereHeightFog(checked) end,
    }
    self.bloomToggle = UI.Checkbox {
        checked = false,
        label = "Bloom",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetAtmosphereBloomEnabled(checked) end,
    }
    self.bloomThresholdField = UI.TextField {
        value = "1.1",
        placeholder = "Threshold",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereBloomNumber("threshold", value) end,
        onBlur = function(field) editor:SetAtmosphereBloomNumber("threshold", field:GetValue()) end,
    }
    self.bloomIntensityField = UI.TextField {
        value = "0.15",
        placeholder = "Intensity",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereBloomNumber("intensity", value) end,
        onBlur = function(field) editor:SetAtmosphereBloomNumber("intensity", field:GetValue()) end,
    }
    self.vignetteToggle = UI.Checkbox {
        checked = false,
        label = "Vignette",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetAtmosphereVignetteEnabled(checked) end,
    }
    self.vignetteIntensityField = UI.TextField {
        value = "0.08",
        placeholder = "Intensity",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetAtmosphereVignetteIntensity(value) end,
        onBlur = function(field) editor:SetAtmosphereVignetteIntensity(field:GetValue()) end,
    }

    self.scroll = UI.ScrollView {
        width = "100%",
        height = "100%",
        padding = 0,
        gap = 0,
        flexGrow = 1,
        flexShrink = 1,
        flexBasis = 0,
        scrollY = true,
        scrollX = false,
        showScrollbar = true,
        scrollbarInteractive = true,
        bounces = false,
        backgroundColor = Shared.PANEL,
        children = {
            Shared.ComponentHeader("⌁", "Path Candidates"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label {
                        text = "跨 Part 面候选仅进入固定相机评估，不等于已连通。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    UI.Label { text = "起点 / 终点", fontSize = 9, fontColor = Shared.MUTED },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.pathCandidateFromPickButton,
                        self.pathCandidateToPickButton,
                        self.pathCandidateCancelPickButton,
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.pathCandidateClearFromButton,
                        self.pathCandidateClearToButton,
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.pathCandidateFromDropdown } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.pathCandidateToDropdown } },
                    } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.pathCandidateDirectionDropdown,
                        self.pathCandidateAddButton,
                    } },
                    self.pathCandidateList,
                    self.pathCandidateDropdown,
                    self.pathCandidateRemoveButton,
                    self.pathCandidateStatusLabel,
                },
            },
            Shared.ComponentHeader("⌂", "Preview Spawn"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label {
                        text = "出生点是 Preview 的必选项；删除对应节点后会自动清空。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    self.spawnNodeDropdown,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        self.spawnPickButton,
                        self.spawnClearButton,
                    } },
                },
            },
            Shared.ComponentHeader("◉", "Editor Preview Camera"),
            UI.Panel {
                padding = 8,
                gap = 5,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    self.cameraLabel,
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Button { text = "投影", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:ToggleEditorProjection() end },
                        UI.Button { text = "聚焦", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:FocusSelectedPart() end },
                        UI.Button { text = "重置", flexGrow = 1, height = 26, fontSize = 10, variant = "secondary", onClick = function() editor:ResetEditorCamera(); editor:RefreshLevelUI("已恢复固定 30° 正交编辑基准") end },
                    } },
                    UI.Label { text = "RMB 旋转 · MMB 平移 · Wheel 缩放", fontSize = 9, fontColor = Shared.MUTED },
                },
            },
            Shared.ComponentHeader("☁", "Atmosphere"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label {
                        text = "覆盖 LightGroup 的 Zone，不新建 Zone。AutoExposure 固定关闭。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                    Shared.FieldRow("LightGroup", self.lightGroupDropdown),
                    Shared.FieldRow("Fog Color", self.fogColorPicker),
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.fogStartField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.fogFinishField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.fogDensityField } },
                    } },
                    self.heightFogToggle,
                    UI.Panel { flexDirection = "row", gap = 8, children = { self.bloomToggle, self.vignetteToggle } },
                    UI.Panel { flexDirection = "row", gap = 4, children = {
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.bloomThresholdField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.bloomIntensityField } },
                        UI.Panel { flexGrow = 1, flexShrink = 1, children = { self.vignetteIntensityField } },
                    } },
                },
            },
            UI.Panel {
                padding = 10,
                gap = 6,
                children = {
                    self.previewButton,
                    self.saveButton,
                    self.exportButton,
                    self.importButton,
                },
            },
        },
    }
    Shared.BindSlowWheel(self.scroll)
    return self.scroll
end

function LevelInspector:Refresh()
    local editor = self.editor
    local candidateItems = {}
    for _, candidate in ipairs(editor.levelDocument:GetPathCandidates()) do
        local status = "未评估"
        local reason = ""
        for _, record in ipairs(editor.pathRuntime:GetCandidateRecords()) do
            if record.id == candidate.id then
                status = record.status
                reason = record.reason or ""
                break
            end
        end
        candidateItems[#candidateItems + 1] = {
            id = candidate.id,
            text = candidate.id,
            secondary = candidate.from.partId .. ":" .. candidate.from.nodeId .. "  →  " .. candidate.to.partId .. ":" .. candidate.to.nodeId .. "  [" .. status .. "] " .. reason,
        }
    end
    self.pathCandidateList:SetItems(candidateItems)
    self.pathCandidateFromDropdown:SetOptions(editor:GetPathNodeOptions())
    self.pathCandidateToDropdown:SetOptions(editor:GetPathNodeOptions())
    self.pathCandidateFromDropdown:SetValue(editor.pathPickedFromKey or "")
    self.pathCandidateToDropdown:SetValue(editor.pathPickedToKey or "")
    self.pathCandidateDropdown:SetOptions(editor:GetPathCandidateOptions())
    self.spawnNodeDropdown:SetOptions(editor:GetPathNodeOptions())
    self.spawnNodeDropdown.props.value = editor:GetSpawnNodeKey() or ""
    self:SetCameraState(editor.editorCamera)
    local atmosphere = editor.levelDocument.atmosphere
    self.lightGroupDropdown.props.value = atmosphere.lightGroup
    self.fogColorPicker:SetHex(atmosphere.fog.color)
    self.fogStartField:SetValue(tostring(atmosphere.fog.start))
    self.fogFinishField:SetValue(tostring(atmosphere.fog.finish))
    self.fogDensityField:SetValue(tostring(atmosphere.fog.density))
    self.heightFogToggle:SetChecked(atmosphere.fog.heightFog == true)
    self.bloomToggle:SetChecked(atmosphere.bloom.enabled == true)
    self.bloomThresholdField:SetValue(tostring(atmosphere.bloom.threshold))
    self.bloomIntensityField:SetValue(tostring(atmosphere.bloom.intensity))
    self.vignetteToggle:SetChecked(atmosphere.vignette.enabled == true)
    self.vignetteIntensityField:SetValue(tostring(atmosphere.vignette.intensity))
end

function LevelInspector:RefreshSpawnPicker()
    self.spawnNodeDropdown:SetOptions(self.editor:GetPathNodeOptions())
    self.spawnNodeDropdown.props.value = self.editor:GetSpawnNodeKey() or ""
end

function LevelInspector:RefreshPathCandidatePicker()
    self.pathCandidateFromDropdown:SetValue(self.editor.pathPickedFromKey or "")
    self.pathCandidateToDropdown:SetValue(self.editor.pathPickedToKey or "")
end

function LevelInspector:SetCameraState(camera)
    self.cameraLabel:SetText(string.format(
        "%s  Yaw %.0f°  Pitch %.0f°  Zoom %.1f",
        camera.projection == "orthographic" and "正交" or "透视",
        camera.yaw,
        camera.pitch,
        camera.projection == "orthographic" and camera.orthoSize or camera.distance
    ))
end

return LevelInspector
