-- 阿尔吉侬表现层。
-- 用 Algernon 模型资产，不进入关卡静物树；世界位姿由 Walker 驱动。
-- 演出可改 Presentation 节点的 local transform，不离开 Path Graph。

local StillObject = require "StillObject"
local StillObjectRuntime = require "StillObjectRuntime"

local AlgernonView = {}
AlgernonView.__index = AlgernonView

local function CopyEuler(value)
    value = value or {}
    return {
        x = value.x or 0,
        y = value.y or 0,
        z = value.z or 0,
    }
end

function AlgernonView.New(scene)
    local self = setmetatable({}, AlgernonView)
    self.scene = scene
    self.node = scene:CreateChild("AlgernonActor")
    self.presentation = self.node:CreateChild("AlgernonPresentation")
    self.dummyObject = StillObject.New({
        id = "algernon_actor",
        name = "阿尔吉侬",
        modelId = "algernon",
    })
    self.runtime = StillObjectRuntime.Bind(self.presentation, self.dummyObject)
    self.localPosition = { x = 0, y = 0, z = 0 }
    self.localRotation = { x = 0, y = 0, z = 0 }
    self.localScale = { x = 1, y = 1, z = 1 }
    self:ApplyLocalTransform()
    self.node.enabled = false
    print("AlgernonView: created")
    return self
end

function AlgernonView:ApplyLocalTransform()
    if not self.presentation then
        return
    end
    local position = self.localPosition
    local rotation = self.localRotation
    local scale = self.localScale
    self.presentation.position = Vector3(position.x, position.y, position.z)
    self.presentation.rotation = Quaternion(rotation.y or 0, Vector3.UP)
        * Quaternion(rotation.x or 0, Vector3.RIGHT)
        * Quaternion(rotation.z or 0, Vector3.FORWARD)
    self.presentation.scale = Vector3(scale.x, scale.y, scale.z)
end

---@param transform table
---@return boolean
function AlgernonView:SetLocalTransform(transform)
    if type(transform) ~= "table" then
        return false
    end
    if transform.position then
        self.localPosition = {
            x = transform.position.x or 0,
            y = transform.position.y or 0,
            z = transform.position.z or 0,
        }
    end
    if transform.rotation then
        self.localRotation = CopyEuler(transform.rotation)
    end
    if transform.scale then
        if type(transform.scale) == "number" then
            local value = transform.scale
            self.localScale = { x = value, y = value, z = value }
        else
            self.localScale = {
                x = transform.scale.x or 1,
                y = transform.scale.y or 1,
                z = transform.scale.z or 1,
            }
        end
    end
    self:ApplyLocalTransform()
    return true
end

function AlgernonView:GetLocalTransform()
    return {
        position = {
            x = self.localPosition.x,
            y = self.localPosition.y,
            z = self.localPosition.z,
        },
        rotation = CopyEuler(self.localRotation),
        scale = {
            x = self.localScale.x,
            y = self.localScale.y,
            z = self.localScale.z,
        },
    }
end

function AlgernonView:Apply(position, rotation)
    if not self.node then
        return
    end
    self.node.position = position
    self.node.rotation = rotation
end

function AlgernonView:SetVisible(visible)
    if not self.node then
        return false
    end
    self.node.enabled = visible ~= false
    return true
end

function AlgernonView:Destroy()
    if self.node then
        self.node:Remove()
        self.node = nil
        self.presentation = nil
        self.runtime = nil
    end
end

return AlgernonView
