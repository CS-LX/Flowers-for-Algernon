-- 静物 Inspector。
-- 名称、父级、局部坐标，以及当前模型 sidecar 声明的字段 / driver。

local UI = require("urhox-libs/UI")
local Shared = require "InspectorShared"
local StillModelCatalog = require "StillModelCatalog"
local LookApplier = require "LookApplier"

local StillObjectInspector = {}
StillObjectInspector.__index = StillObjectInspector

function StillObjectInspector.New(editor)
    local self = setmetatable({}, StillObjectInspector)
    self.editor = editor
    self.scroll = nil
    self.selectionLabel = nil
    self.nameField = nil
    self.parentDropdown = nil
    self.posXField = nil
    self.posYField = nil
    self.posZField = nil
    self.rotYField = nil
    self.scaleField = nil
    self.modelLabel = nil
    ---@type Dropdown|nil
    self.modelDropdown = nil
    ---@type TextField|nil
    self.fogHeightAField = nil
    ---@type TextField|nil
    self.fogHeightBField = nil
    ---@type TextField|nil
    self.gradeSaturationField = nil
    ---@type TextField|nil
    self.gradeValueField = nil
    ---@type TextField|nil
    self.gradeContrastField = nil
    ---@type TextField|nil
    self.gradeHazeField = nil
    ---@type Widget|nil
    self.lookPanel = nil
    ---@type Widget|nil
    self.driverPanel = nil
    self.triggerableToggle = nil
    self.triggerIdField = nil
    self.interactionLabel = nil
    return self
end

function StillObjectInspector:Build()
    local editor = self.editor
    self.selectionLabel = UI.Label {
        text = "未选择静物",
        fontSize = 14,
        fontWeight = "bold",
        fontColor = Shared.TEXT,
    }
    self.nameField = UI.TextField {
        value = "",
        placeholder = "静物名称",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillName(value) end,
    }
    self.parentDropdown = UI.Dropdown {
        options = {},
        value = "",
        placeholder = "父级",
        height = 28,
        fontSize = 11,
        onChange = function(_, value) editor:SetSelectedStillParent(value == "" and nil or value) end,
    }
    self.posXField = UI.TextField {
        value = "0", placeholder = "X", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("x", value) end,
    }
    self.posYField = UI.TextField {
        value = "0", placeholder = "Y", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("y", value) end,
    }
    self.posZField = UI.TextField {
        value = "0", placeholder = "Z", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillCoordinate("z", value) end,
    }
    self.rotYField = UI.TextField {
        value = "0", placeholder = "Yaw", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillYaw(value) end,
    }
    self.scaleField = UI.TextField {
        value = "1.0", placeholder = "Scale", height = 28, fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillScale(value) end,
    }
    self.modelLabel = UI.Label {
        text = "占位模型：Box",
        fontSize = 10,
        fontColor = Shared.MUTED,
        whiteSpace = "normal",
    }
    self.modelDropdown = UI.Dropdown {
        options = StillModelCatalog.Options(),
        value = "",
        placeholder = "静物模型",
        height = 28,
        fontSize = 11,
        onChange = function(_, value) editor:SetSelectedStillModelId(value) end,
    }
    Shared.BindSlowDropdownWheel(self.modelDropdown)
    self.tintSlotId = "wall"
    local function TintPath(fieldName)
        return "slots." .. (self.tintSlotId or "wall") .. "." .. fieldName
    end
    self.fogHeightAField = UI.TextField {
        value = "8.00",
        placeholder = "起始",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("fogHeightA"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("fogHeightA"), field:GetValue()) end,
    }
    self.fogHeightBField = UI.TextField {
        value = "0.00",
        placeholder = "终止",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("fogHeightB"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("fogHeightB"), field:GetValue()) end,
    }
    self.gradeSaturationField = UI.TextField {
        value = "0.55",
        placeholder = "饱和",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("gradeSaturation"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("gradeSaturation"), field:GetValue()) end,
    }
    self.gradeValueField = UI.TextField {
        value = "1.08",
        placeholder = "明度",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("gradeValue"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("gradeValue"), field:GetValue()) end,
    }
    self.gradeContrastField = UI.TextField {
        value = "0.72",
        placeholder = "对比",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("gradeContrast"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("gradeContrast"), field:GetValue()) end,
    }
    self.gradeHazeField = UI.TextField {
        value = "0.22",
        placeholder = "霾",
        height = 26,
        fontSize = 10,
        onSubmit = function(_, value) editor:SetSelectedStillParam(TintPath("gradeHaze"), value) end,
        onBlur = function(field) editor:SetSelectedStillParam(TintPath("gradeHaze"), field:GetValue()) end,
    }
    self.lookPanel = UI.Panel {
        width = "100%",
        gap = 4,
        children = {},
    }
    self.driverPanel = UI.Panel {
        width = "100%",
        gap = 4,
        children = {},
    }
    self.triggerableToggle = UI.Checkbox {
        checked = false,
        label = "Triggerable",
        size = 16,
        height = 24,
        fontSize = 10,
        onChange = function(_, checked) editor:SetSelectedStillInteraction("triggerable", checked) end,
    }
    self.triggerIdField = UI.TextField {
        value = "",
        placeholder = "Trigger ID",
        height = 28,
        fontSize = 11,
        onSubmit = function(_, value) editor:SetSelectedStillTriggerId(value) end,
    }
    self.interactionLabel = UI.Label {
        text = "Inspector 只配置 Trigger ID。开火条件写在静物辅助脚本里；门是进入且 open≥0.95。",
        fontSize = 9,
        fontColor = Shared.MUTED,
        whiteSpace = "normal",
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
            UI.Panel {
                padding = 8,
                gap = 5,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    self.selectionLabel,
                    Shared.FieldRow("Name", self.nameField),
                    Shared.FieldRow("Parent", self.parentDropdown),
                },
            },
            Shared.ComponentHeader("◈", "Local Transform"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    UI.Label { text = "不吸附网格，坐标是父节点局部米制。", fontSize = 9, fontColor = Shared.MUTED, whiteSpace = "normal" },
                    UI.Panel { flexDirection = "row", alignItems = "center", gap = 6, children = {
                        UI.Label { text = "Position", width = 62, fontSize = 10, fontColor = Shared.MUTED },
                        UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, flexDirection = "row", gap = 3, children = {
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posXField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posYField } },
                            UI.Panel { flexGrow = 1, flexShrink = 1, minWidth = 0, children = { self.posZField } },
                        } },
                    } },
                    Shared.FieldRow("Yaw", self.rotYField),
                    Shared.FieldRow("Scale", self.scaleField),
                },
            },
            Shared.ComponentHeader("⌁", "Interaction"),
            UI.Panel {
                padding = 8,
                gap = 4,
                borderBottomWidth = 1,
                borderBottomColor = Shared.BORDER,
                children = {
                    self.triggerableToggle,
                    Shared.FieldRow("Trigger ID", self.triggerIdField),
                    self.interactionLabel,
                },
            },
            Shared.ComponentHeader("▣", "Presentation"),
            UI.Panel {
                padding = 8,
                gap = 4,
                children = {
                    Shared.FieldRow("Model", self.modelDropdown),
                    self.modelLabel,
                    self.lookPanel,
                    self.driverPanel,
                    UI.Label {
                        text = "静物没有体素、PathNode 和机关。自己不会移动，只跟随父级 Transform。换模型会保留旧模型覆盖。",
                        fontSize = 9,
                        fontColor = Shared.MUTED,
                        whiteSpace = "normal",
                    },
                },
            },
            Shared.ColorPopupSpacer(),
        },
    }
    Shared.BindSlowWheel(self.scroll)
    return self.scroll
end

function StillObjectInspector:Clear()
    self.selectionLabel:SetText("未选择静物")
    self.nameField:SetValue("")
    self.parentDropdown:SetOptions({ { value = "", label = "LevelRoot" } })
    self.parentDropdown.props.value = ""
    self.posXField:SetValue("")
    self.posYField:SetValue("")
    self.posZField:SetValue("")
    self.rotYField:SetValue("")
    self.scaleField:SetValue("")
    self.modelLabel:SetText("占位模型：Box")
    if self.modelDropdown then
        self.modelDropdown:SetOptions(StillModelCatalog.Options())
        self.modelDropdown.props.value = ""
    end
    if self.lookPanel then
        self.lookPanel:ClearChildren()
    end
    if self.fogHeightAField then
        self.fogHeightAField:SetValue("")
    end
    if self.fogHeightBField then
        self.fogHeightBField:SetValue("")
    end
    if self.driverPanel then
        self.driverPanel:ClearChildren()
    end
    self.triggerableToggle:SetChecked(false)
    self.triggerIdField:SetValue("")
    self.triggerIdField:SetDisabled(true)
end

function StillObjectInspector:Refresh()
    local editor = self.editor
    local object = editor:GetSelectedStillObject()
    if not object then
        self:Clear()
        return
    end
    local parentOptions = { { value = "", label = "LevelRoot" } }
    for _, part in ipairs(editor.levelDocument:GetParts()) do
        if not editor.levelDocument:IsDescendant(part.id, object.id) then
            parentOptions[#parentOptions + 1] = { value = part.id, label = "[Part] " .. part.name }
        end
    end
    for _, still in ipairs(editor.levelDocument:GetStillObjects()) do
        if still.id ~= object.id and not editor.levelDocument:IsDescendant(still.id, object.id) then
            parentOptions[#parentOptions + 1] = { value = still.id, label = "[Still] " .. still.name }
        end
    end
    self.parentDropdown:SetOptions(parentOptions)
    self.parentDropdown.props.value = object.parentId or ""
    self.selectionLabel:SetText(object.name .. "  [" .. object.id .. "]")
    self.nameField:SetValue(object.name)
    local position = object.transform.position
    local rotation = object.transform.rotation
    local scale = object.transform.scale
    self.posXField:SetValue(string.format("%.3f", position.x))
    self.posYField:SetValue(string.format("%.3f", position.y))
    self.posZField:SetValue(string.format("%.3f", position.z))
    self.rotYField:SetValue(string.format("%.1f", rotation.y or 0))
    self.scaleField:SetValue(string.format("%.2f", scale.x))
    local asset = object:GetAsset()
    if self.modelDropdown then
        self.modelDropdown:SetOptions(StillModelCatalog.Options())
        self.modelDropdown.props.value = object.modelId or ""
    end
    if asset then
        local detail = asset.modelPath ~= "" and asset.modelPath or ("builder:" .. tostring(asset.builder))
        self.modelLabel:SetText("资产：" .. asset.label .. "  " .. detail)
    elseif object:HasModel() then
        self.modelLabel:SetText("模型：" .. object.modelPath)
    else
        self.modelLabel:SetText("占位模型：Box（尚未绑定资产）")
    end
    self:RefreshLooks(object, asset)
    self:RefreshDrivers(object, asset)
    local hasTrigger = object:HasBehavior("triggerable")
    self.triggerableToggle:SetChecked(hasTrigger)
    self.triggerIdField:SetDisabled(not hasTrigger)
    self.triggerIdField:SetValue(hasTrigger and object.behaviors.triggerable.triggerId or "")
end

function StillObjectInspector:RefreshLooks(object, asset)
    if not self.lookPanel then
        return
    end
    self.lookPanel:ClearChildren()
    if not asset or #asset.inspect == 0 then
        return
    end
    local editor = self.editor
    local overrides = object:GetActiveParams()
    for _, field in ipairs(asset.inspect) do
        local current = StillModelCatalog.ResolveParam(asset, overrides, field.path)
        local picker = Shared.ColorField {
            color = current or "#FFFFFF",
            onClose = function(widget)
                editor:SetSelectedStillParam(field.path, widget:GetHex())
            end,
        }
        picker:SetHex(current or "#FFFFFF")
        self.lookPanel:AddChild(Shared.FieldRow(field.label, picker))
    end
    local tintSlot = nil
    for _, slot in ipairs(asset.slots or {}) do
        if slot.shader == LookApplier.SHADER_STILL_OBJECT_MESH_TINT_FOG then
            tintSlot = slot
            break
        end
    end
    self.tintSlotId = tintSlot and tintSlot.id or "wall"
    if tintSlot and self.fogHeightAField and self.fogHeightBField then
        local prefix = "slots." .. tintSlot.id .. "."
        local heightA = tonumber(StillModelCatalog.ResolveParam(asset, overrides, prefix .. "fogHeightA")) or 8.0
        local heightB = tonumber(StillModelCatalog.ResolveParam(asset, overrides, prefix .. "fogHeightB")) or 0.0
        self.fogHeightAField:SetValue(string.format("%.2f", heightA))
        self.fogHeightBField:SetValue(string.format("%.2f", heightB))
        self.lookPanel:AddChild(Shared.FieldRow("雾起始", self.fogHeightAField))
        self.lookPanel:AddChild(Shared.FieldRow("雾终止", self.fogHeightBField))
        local function GradeValue(path, fallback)
            return tonumber(StillModelCatalog.ResolveParam(asset, overrides, path)) or fallback
        end
        if self.gradeSaturationField then
            self.gradeSaturationField:SetValue(string.format("%.2f", GradeValue(prefix .. "gradeSaturation", 0.55)))
            self.lookPanel:AddChild(Shared.FieldRow("饱和", self.gradeSaturationField))
        end
        if self.gradeValueField then
            self.gradeValueField:SetValue(string.format("%.2f", GradeValue(prefix .. "gradeValue", 1.08)))
            self.lookPanel:AddChild(Shared.FieldRow("明度", self.gradeValueField))
        end
        if self.gradeContrastField then
            self.gradeContrastField:SetValue(string.format("%.2f", GradeValue(prefix .. "gradeContrast", 0.72)))
            self.lookPanel:AddChild(Shared.FieldRow("对比", self.gradeContrastField))
        end
        if self.gradeHazeField then
            self.gradeHazeField:SetValue(string.format("%.2f", GradeValue(prefix .. "gradeHaze", 0.22)))
            self.lookPanel:AddChild(Shared.FieldRow("霾", self.gradeHazeField))
        end
    end
end

function StillObjectInspector:RefreshDrivers(object, asset)
    if not self.driverPanel then
        return
    end
    self.driverPanel:ClearChildren()
    if not asset or #asset.drivers == 0 then
        return
    end
    local editor = self.editor
    for _, driver in ipairs(asset.drivers) do
        local value = object:GetDriver(driver.id)
        local slider = UI.Slider {
            value = value,
            min = driver.min,
            max = driver.max,
            step = 0.01,
            width = "100%",
            onChange = function(_, amount)
                editor:SetSelectedStillDriver(driver.id, amount)
            end,
        }
        self.driverPanel:AddChild(Shared.FieldRow(driver.label, slider))
    end
end

return StillObjectInspector
