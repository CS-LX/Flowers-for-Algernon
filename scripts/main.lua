-- 实验入口。当前切到 ColorTruthLab，隔离真实 RGB / 雾 / HDR / tonemap。
-- 关卡编辑器入口留在 main；实验稳定前不切回。

local ColorTruthLab = require "ColorTruthLab"

function Start()
    ColorTruthLab.Start()
end

function Stop()
    ColorTruthLab.Stop()
end
