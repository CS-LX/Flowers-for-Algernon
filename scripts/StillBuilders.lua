-- 基础几何静物 builder。
-- 每个静物只创建一个 StaticModel，并统一使用 still_object_base.shader。

local LookApplier = require "LookApplier"

local StillBuilders = {}

local function AddShape(parent, name, geometry)
    local node = parent:CreateChild(name)
    local model = node:CreateComponent("StaticModel")
    model.model = geometry:ToModel()
    return node, model
end

local function BuildCube(parent)
    return AddShape(parent, "Cube", BoxGeometry(0.38, 0.38, 0.38))
end

local function BuildCapsule(parent)
    return AddShape(parent, "Capsule", CapsuleGeometry(0.13, 0.42, 8, 8, 1))
end

local function BuildCylinder(parent)
    return AddShape(parent, "Cylinder", CylinderGeometry(0.16, 0.16, 0.42, 8, 1, false))
end

local function BuildTriPrism(parent)
    return AddShape(parent, "TriPrism", CylinderGeometry(0.24, 0.24, 0.42, 3, 1, false))
end

local BUILDERS = {
    still_cube = BuildCube,
    still_capsule = BuildCapsule,
    still_cylinder = BuildCylinder,
    still_tri_prism = BuildTriPrism,
}

function StillBuilders.Build(builderId, parent)
    local builder = BUILDERS[builderId]
    if not builder then
        print("StillBuilders: unknown builder " .. tostring(builderId))
        return nil
    end
    local node, model = builder(parent)
    print(string.format("StillBuilders: built %s", builderId))
    return {
        node = node,
        model = model,
        localBounds = model.boundingBox,
    }
end

return StillBuilders
