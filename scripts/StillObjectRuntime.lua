-- 把 StillModelCatalog 资产绑到 Scene Node。
-- 关卡数据仍由 StillObject 持有；这里只派生显示和 driver。

local LookApplier = require "LookApplier"
local StillModelCatalog = require "StillModelCatalog"
local StillBuilders = require "StillBuilders"

---@class StillRuntimeEntry
---@field node Node
---@field model AnimatedModel|StaticModel|nil
---@field asset table
---@field slotMaterials table<string, Material>
---@field partNodes table<string, Node[]>|nil
---@field localBounds BoundingBox|nil
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
    if slot.shader == LookApplier.SHADER_STILL_OBJECT_MESH_TINT_FOG then
        return LookApplier.CreateStillObjectMeshTintFogMaterial(look)
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
    if not entry or not entry.asset then
        return
    end
    local drivers = object:GetDriverState()
    if entry.model then
        local geoCount = entry.model:GetNumGeometries()
        for _, slot in ipairs(entry.asset.slots) do
            if slot.index >= 0 and slot.index < geoCount then
                local visible = SlotVisible(slot, drivers)
                if visible then
                    entry.model:SetMaterial(slot.index, entry.slotMaterials[slot.id])
                else
                    entry.model:SetMaterial(slot.index, HiddenMaterial())
                end
            end
        end
    elseif entry.partNodes then
        for _, slot in ipairs(entry.asset.slots) do
            local visible = SlotVisible(slot, drivers)
            for _, node in ipairs(entry.partNodes[slot.id] or {}) do
                node.enabled = visible
            end
        end
    end
end

function StillObjectRuntime.ApplyLooks(entry, object)
    if not entry or not entry.asset then
        return
    end
    local overrides = object:GetActiveParams()
    entry.slotMaterials = {}
    if entry.model then
        local geoCount = entry.model:GetNumGeometries()
        for _, slot in ipairs(entry.asset.slots) do
            if slot.index >= 0 and slot.index < geoCount then
                local look = StillModelCatalog.SlotLook(entry.asset, slot, overrides)
                entry.slotMaterials[slot.id] = CreateSlotMaterial(slot, look)
            end
        end
    elseif entry.partNodes then
        for _, slot in ipairs(entry.asset.slots) do
            local look = StillModelCatalog.SlotLook(entry.asset, slot, overrides)
            local material = CreateSlotMaterial(slot, look)
            entry.slotMaterials[slot.id] = material
            for _, node in ipairs(entry.partNodes[slot.id] or {}) do
                local model = node:GetComponent("StaticModel")
                if model then
                    model:SetMaterial(material)
                end
            end
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

---@param parent Node
---@param object StillObject
---@return StillRuntimeEntry|nil
function StillObjectRuntime.Bind(parent, object)
    local asset = StillModelCatalog.Get(object.modelId)
    if not asset then
        print("StillObjectRuntime: unknown modelId " .. tostring(object and object.modelId))
        return nil
    end

    local node = parent:CreateChild("StillModel_" .. object.id)
    local rotation = asset.rootRotation
    node.rotation = Quaternion(rotation.x, Vector3.RIGHT)
        * Quaternion(rotation.y, Vector3.UP)
        * Quaternion(rotation.z, Vector3.FORWARD)
    local offset = asset.rootOffset
    node.position = Vector3(offset.x, offset.y, offset.z)
    local scale = asset.rootScale or { x = 1, y = 1, z = 1 }
    node.scale = Vector3(scale.x, scale.y, scale.z)

    ---@type AnimatedModel|StaticModel|nil
    local model = nil
    ---@type BoundingBox|nil
    local modelSpaceBounds = nil
    if asset.modelPath ~= "" then
        local resource = cache:GetResource("Model", asset.modelPath)
        if not resource then
            print("StillObjectRuntime: missing model " .. asset.modelPath)
            return nil
        end
        if asset.component == "AnimatedModel" then
            model = node:CreateComponent("AnimatedModel")
        else
            model = node:CreateComponent("StaticModel")
        end
        model:SetModel(resource)
        modelSpaceBounds = resource.boundingBox
    elseif asset.builder ~= "" then
        local built = StillBuilders.Build(asset.builder, node)
        if not built then
            print("StillObjectRuntime: builder failed " .. asset.builder)
            return nil
        end
        model = built.model
        modelSpaceBounds = built.localBounds
    else
        print("StillObjectRuntime: asset has neither modelPath nor builder " .. asset.id)
        return nil
    end
    if asset.bounds then
        modelSpaceBounds = BoundingBox(
            Vector3(asset.bounds.min.x, asset.bounds.min.y, asset.bounds.min.z),
            Vector3(asset.bounds.max.x, asset.bounds.max.y, asset.bounds.max.z)
        )
    end

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
    ---@type BoundingBox|nil
    entry.localBounds = nil

    if model and asset.component == "AnimatedModel" then
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
    -- 选中/触发箱在静物根节点空间。用静止姿态盒子乘上模型节点局部变换，
    -- 避免门的 90° 旋转、开门骨骼和丁达尔光把盒子撑成横躺长方体。
    if modelSpaceBounds then
        entry.localBounds = modelSpaceBounds:Transformed(node.transform)
        print(string.format(
            "StillObjectRuntime: bounds %s min=(%.3f, %.3f, %.3f) max=(%.3f, %.3f, %.3f)",
            asset.id,
            entry.localBounds.min.x,
            entry.localBounds.min.y,
            entry.localBounds.min.z,
            entry.localBounds.max.x,
            entry.localBounds.max.y,
            entry.localBounds.max.z
        ))
    end
    local geometryCount = model and model:GetNumGeometries() or 0
    print(string.format(
        "StillObjectRuntime: bound %s geos=%d drivers=%d builder=%s",
        asset.id,
        geometryCount,
        #asset.drivers,
        tostring(asset.builder ~= "")
    ))
    return entry
end

return StillObjectRuntime
