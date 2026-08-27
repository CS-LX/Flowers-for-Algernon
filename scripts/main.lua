-- 实验入口。当前切到 VoxelLookLab，隔离体素 + Surface Shader。
-- 关卡编辑器入口已冻结在 main checkpoint；实验稳定前不切回。

local VoxelLookLab = require "VoxelLookLab"

function Start()
    VoxelLookLab.Start()
end

function Stop()
    VoxelLookLab.Stop()
end
