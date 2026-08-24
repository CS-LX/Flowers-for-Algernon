-- 固定 Runtime 相机姿态工具。
-- 仅服务 Game Preview 与 PathRuntime 评估；不服务 Level/Part 编辑器自由相机。

local FixedGameCamera = {}

function FixedGameCamera.GetWorldPosition(config)
    local target = Vector3(config.target.x, config.target.y, config.target.z)
    local pitch = math.rad(config.pitch)
    local distance = config.orthoSize * 1.5
    local yaw = math.rad(30.0)
    local horizontal = math.cos(pitch) * distance
    return target, target + Vector3(
        math.sin(yaw) * horizontal,
        math.sin(pitch) * distance,
        -math.cos(yaw) * horizontal
    )
end

function FixedGameCamera.Create(scene, name, config)
    local target, position = FixedGameCamera.GetWorldPosition(config)
    local node = scene:CreateChild(name)
    node.position = position
    node:LookAt(target)
    local camera = node:CreateComponent("Camera")
    camera.orthographic = true
    camera.orthoSize = config.orthoSize
    camera.nearClip = config.nearClip
    camera.farClip = config.farClip
    return node, camera
end

return FixedGameCamera
