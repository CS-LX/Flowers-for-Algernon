-- 机关手感。只读写云配置，不持有 Scene / HUD。
-- 旋转模式：orbit 环绕（关卡默认），pan 平移（选关棱柱）。

local ControlSettings = {}

local CLOUD_KEY = "player_controls"
local DIRTY_FLUSH_DELAY = 0.6
local DEFAULT_SENSITIVITY = 1.0
local MIN_SENSITIVITY = 0.25
local MAX_SENSITIVITY = 2.0
local MODE_ORBIT = "orbit"
local MODE_PAN = "pan"

local rotateMode = MODE_ORBIT
local sensitivity = DEFAULT_SENSITIVITY
local calibrated = false
local loaded = false
local loadStarted = false
---@type fun()[]
local loadCallbacks = {}
local dirty = false
local saving = false
local pendingSave = false
local flushDelay = 0.0
local saveGeneration = 0

local function ClampSensitivity(value)
    local number = tonumber(value)
    if not number then
        return DEFAULT_SENSITIVITY
    end
    if number < MIN_SENSITIVITY then
        return MIN_SENSITIVITY
    end
    if number > MAX_SENSITIVITY then
        return MAX_SENSITIVITY
    end
    return number
end

local function NormalizeMode(value)
    if value == MODE_PAN then
        return MODE_PAN
    end
    return MODE_ORBIT
end

local function CloudAvailable()
    return clientCloud ~= nil and type(clientCloud.Set) == "function" and type(clientCloud.Get) == "function"
end

local function Snapshot()
    return {
        rotateMode = rotateMode,
        sensitivity = sensitivity,
        calibrated = calibrated == true,
    }
end

local function FinishLoad()
    loaded = true
    local callbacks = loadCallbacks
    loadCallbacks = {}
    for i = 1, #callbacks do
        callbacks[i]()
    end
end

local function MarkDirty()
    dirty = true
    flushDelay = DIRTY_FLUSH_DELAY
end

function ControlSettings.Save(reason)
    flushDelay = 0.0
    if not dirty then
        return false
    end
    if saving then
        pendingSave = true
        return true
    end
    if not CloudAvailable() then
        print("ControlSettings: cloud unavailable, keep local " .. tostring(reason))
        return false
    end
    dirty = false
    saving = true
    pendingSave = false
    saveGeneration = saveGeneration + 1
    local generation = saveGeneration
    local payload = Snapshot()
    clientCloud:Set(CLOUD_KEY, payload, {
        ok = function()
            if generation == saveGeneration then
                saving = false
                print("ControlSettings: saved " .. tostring(reason))
                if pendingSave or dirty then
                    pendingSave = false
                    dirty = true
                    ControlSettings.Save("retry")
                end
            end
        end,
        error = function(code, message)
            if generation == saveGeneration then
                saving = false
                dirty = true
                print(string.format(
                    "ControlSettings: save failed reason=%s code=%s message=%s",
                    tostring(code),
                    tostring(message)
                ))
            end
        end,
    })
    return true
end

function ControlSettings.Load(onLoaded)
    if type(onLoaded) == "function" then
        loadCallbacks[#loadCallbacks + 1] = onLoaded
    end
    if loaded then
        FinishLoad()
        return
    end
    if loadStarted then
        return
    end
    loadStarted = true
    if not CloudAvailable() then
        print("ControlSettings: cloud unavailable, defaults")
        FinishLoad()
        return
    end
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            local payload = values and values[CLOUD_KEY]
            if type(payload) == "table" then
                rotateMode = NormalizeMode(payload.rotateMode)
                sensitivity = ClampSensitivity(payload.sensitivity)
                calibrated = payload.calibrated == true
            end
            print(string.format(
                "ControlSettings: loaded mode=%s sensitivity=%.2f calibrated=%s",
                rotateMode,
                sensitivity,
                tostring(calibrated)
            ))
            FinishLoad()
        end,
        error = function(code, message)
            print(string.format(
                "ControlSettings: load failed code=%s message=%s",
                tostring(code),
                tostring(message)
            ))
            FinishLoad()
        end,
    })
end

function ControlSettings.SetRotateMode(mode, persist)
    rotateMode = NormalizeMode(mode)
    if persist then
        MarkDirty()
    end
    return rotateMode
end

function ControlSettings.SetSensitivity(value, persist)
    sensitivity = ClampSensitivity(value)
    if persist then
        MarkDirty()
    end
    return sensitivity
end

function ControlSettings.SetCalibrated(value, persist)
    calibrated = value == true
    if persist then
        MarkDirty()
        ControlSettings.Save("calibrated")
    end
    return calibrated
end

function ControlSettings.RotateMode()
    return rotateMode
end

function ControlSettings.IsPanRotate()
    return rotateMode == MODE_PAN
end

function ControlSettings.Sensitivity()
    return sensitivity
end

function ControlSettings.RotateSensitivity()
    return sensitivity
end

function ControlSettings.MoveSensitivity()
    return sensitivity
end

function ControlSettings.HasCalibrated()
    return calibrated == true
end

function ControlSettings.SliderValue()
    return (sensitivity - MIN_SENSITIVITY) / (MAX_SENSITIVITY - MIN_SENSITIVITY)
end

function ControlSettings.SetFromSlider(sliderValue, persist)
    local t = tonumber(sliderValue) or 0.5
    if t < 0.0 then
        t = 0.0
    end
    if t > 1.0 then
        t = 1.0
    end
    return ControlSettings.SetSensitivity(
        MIN_SENSITIVITY + t * (MAX_SENSITIVITY - MIN_SENSITIVITY),
        persist
    )
end

function ControlSettings.PanDegreesPerPixel()
    return 0.35 * sensitivity
end

function ControlSettings.LayerPixelsToStep()
    return 0.012 * sensitivity
end

function ControlSettings.Update(timeStep)
    if not dirty or saving then
        return
    end
    if flushDelay <= 0.0 then
        return
    end
    local nextDelay = flushDelay - timeStep
    if nextDelay > 0.0 then
        flushDelay = nextDelay
        return
    end
    ControlSettings.Save("idle")
end

function ControlSettings.IsLoaded()
    return loaded
end

ControlSettings.MODE_ORBIT = MODE_ORBIT
ControlSettings.MODE_PAN = MODE_PAN
ControlSettings.MIN_SENSITIVITY = MIN_SENSITIVITY
ControlSettings.MAX_SENSITIVITY = MAX_SENSITIVITY

return ControlSettings
