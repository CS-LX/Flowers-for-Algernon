-- 把 StillModelCatalog 资产绑到 Scene Node。
-- 关卡数据仍由 StillObject 持有；这里只派生显示和 driver。

local LookApplier = require "LookApplier"
local StillModelCatalog = require "StillModelCatalog"

---@class StillRuntimeEntry
---@field node Node
---@field model AnimatedModel|StaticModel
---@field asset table
---@field slotMaterials table<string, Material>
---@field boneNodes table<string, Node|nil>
---@field animCtrl AnimationController|nil
---@field animationName string|nil
---@field animationLength number

local StillObjectRuntime = {}

---@type Material|nil
local hiddenMaterial_ = nil

local function ClampDriver(driver, value)
    local number = tonumber(value) or driver.min
    if number < driver.min then
        number = driver.min
    elseif number > driver.max then
        number = driver.max
    end
    return number * 1.0
end

local function Compare(op, left, right)
    if op == ">=" then
        return left >= right
    end
    if op == "<" then
        return left < right
    end
    if op == "<=" then
        return left <= right
    end
    if op == "==" then
        return left == right
    end
    if op == "~=" then
        return left ~= right
    end
    return left > right
end

local function FindBoneNode(model, boneName)
    if not model or boneName == "" then
        return nil
    end
    local skeleton = model:GetSkeleton()
    if not skeleton then
        return nil
    end
    local named = skeleton:GetBone(boneName)
    if named and named.node then
        return named.node
    end
    for index = 0, skeleton:GetNumBones() - 1 do
        local bone = skeleton:GetBone(index)
        if bone and bone.node and bone.name == boneName then
            return bone.node
        end
    end
    return nil
end

local function HiddenMaterial()
    if hiddenMaterial_ then
        return hiddenMaterial_
    end
    local material = Material:new()
    material:SetTechnique(0, cache:GetResource("Technique", "Techniques/PBR/PBRNoTextureAlpha.xml"))
    material:SetShaderParameter("MatDiffColor", Variant(Color(0, 0, 0, 0)))
    local technique = material:GetTechnique(0)
    if technique then
        local pass = nil
        if technique:HasPass("alpha") then
            pass = technique:GetPass("alpha")
        elseif technique:HasPass("base") then
            pass = technique:GetPass("base")
        end
        if pass then
            pass:SetBlendMode(BLEND_ALPHA)
            pass:SetDepthWrite(false)
        end
    end
    hiddenMaterial_ = material
    return material
end

local function CreateSlotMaterial(slot, look)
    if slot.shader == LookApplier.SHADER_STILL_OBJECT_UNLIT then
        return LookApplier.CreateStillObjectUnlitMaterial(look)
    end
    return LookApplier.CreateStillObjectBaseMaterial(look)
end

local function SlotVisible(slot, drivers)
    local rule = slot.visibleWhen
    if not rule then
        return true
    end
    local value = tonumber(drivers[rule.driver]) or 0.0
    return Compare(rule.op, value, rule.value)
end

function StillObjectRuntime.ApplyVisibility(entry, object)
    if not entry or not entry.model or not entry.asset then
        return
    end
    local drivers = object:GetDriverState()
    local geoCount = entry.model:GetNumGeometries()
    for _, slot in ipairs(entry.asset.slots) do
        if slot.index >= 0 and slot.index < geoCount then
            local visible = SlotVisible(slot, drivers)
            if visible then
                entry.model:SetMaterial(slot.index, entry.slotMaterials[slot.id])
            else
                entry.model:SetMaterial(slot.index, HiddenMaterial())
            end
            if slot.visibleWhen then
                print(string.format(
                    "StillObjectRuntime: slot %s visible=%s driver=%s",
                    slot.id,
                    tostring(visible),
                    tostring(drivers[slot.visibleWhen.driver])
                ))
            end
        end
    end
end

function StillObjectRuntime.ApplyLooks(entry, object)
    if not entry or not entry.model or not entry.asset then
        return
    end
    local overrides = object:GetActiveParams()
    entry.slotMaterials = {}
    local geoCount = entry.model:GetNumGeometries()
    for _, slot in ipairs(entry.asset.slots) do
        if slot.index >= 0 and slot.index < geoCount then
            local look = StillModelCatalog.SlotLook(entry.asset, slot, overrides)
            entry.slotMaterials[slot.id] = CreateSlotMaterial(slot, look)
        end
    end
    StillObjectRuntime.ApplyVisibility(entry, object)
end

function StillObjectRuntime.ApplyDrivers(entry, object)
    if not entry or not entry.asset then
        return
    end
    for _, driver in ipairs(entry.asset.drivers) do
        local value = ClampDriver(driver, object:GetDriver(driver.id))
        if driver.type == "animationTime" and entry.animCtrl and entry.animationName then
            entry.animCtrl:SetTime(entry.animationName, value * entry.animationLength)
        else
            local boneNode = entry.boneNodes[driver.id]
            if boneNode then
                local distance = driver.distance * value
                if driver.axis == "X" then
                    boneNode.position = Vector3(distance, 0, 0)
                elseif driver.axis == "Z" then
                    boneNode.position = Vector3(0, 0, distance)
                else
                    boneNode.position = Vector3(0, distance, 0)
                end
            end
        end
    end
    StillObjectRuntime.ApplyVisibility(entry, object)
end

function StillObjectRuntime.Bind(parent, object)
    local asset = StillModelCatalog.Get(object.modelId)
    if not asset then
        print("StillObjectRuntime: unknown modelId " .. tostring(object and object.modelId))
        return nil
    end
    local resource = cache:GetResource("Model", asset.modelPath)
    if not resource then
        print("StillObjectRuntime: missing model " .. asset.modelPath)
        return nil
    end

    local node = parent:CreateChild("StillModel_" .. object.id)
    local rotation = asset.rootRotation
    node.rotation = Quaternion(rotation.x, Vector3.RIGHT)
        * Quaternion(rotation.y, Vector3.UP)
        * Quaternion(rotation.z, Vector3.FORWARD)
    local offset = asset.rootOffset
    node.position = Vector3(offset.x, offset.y, offset.z)

    ---@type AnimatedModel|StaticModel
    local model
    if asset.component == "AnimatedModel" then
        model = node:CreateComponent("AnimatedModel")
    else
        model = node:CreateComponent("StaticModel")
    end
    model:SetModel(resource)

    local entry = {
        node = node,
        model = model,
        asset = asset,
        slotMaterials = {},
        boneNodes = {},
        animCtrl = nil,
        animationName = nil,
        animationLength = 1.0,
    }

    if asset.component == "AnimatedModel" then
        ---@cast model AnimatedModel
        for _, driver in ipairs(asset.drivers) do
            if driver.type == "boneTranslate" and driver.bone ~= "" then
                entry.boneNodes[driver.id] = FindBoneNode(model, driver.bone)
            elseif driver.type == "animationTime" and driver.animation ~= "" and fileSystem:FileExists(driver.animation) then
                entry.animCtrl = node:CreateComponent("AnimationController")
                entry.animationName = driver.animation
                local animation = cache:GetResource("Animation", driver.animation)
                entry.animationLength = animation and animation.length or 1.0
                if entry.animCtrl then
                    entry.animCtrl:Play(driver.animation, 0, false, 0)
                    entry.animCtrl:SetSpeed(driver.animation, 0)
                    entry.animCtrl:SetTime(driver.animation, 0)
                end
            end
        end
    end

    StillObjectRuntime.ApplyLooks(entry, object)
    StillObjectRuntime.ApplyDrivers(entry, object)
    print(string.format(
        "StillObjectRuntime: bound %s geos=%d drivers=%d",
        asset.id,
        model:GetNumGeometries(),
        #asset.drivers
    ))
    return entry
end

return StillObjectRuntime
