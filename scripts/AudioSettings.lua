-- 玩家音量。只读写云配置并设置 Audio MasterGain。
-- 不持有 SoundSource，也不引用菜单或关卡。

local AudioSettings = {}

local CLOUD_KEY = "player_settings"
local DIRTY_FLUSH_DELAY = 0.6
local DEFAULT_VOLUME = 1.0

local bgmVolume = DEFAULT_VOLUME
local sfxVolume = DEFAULT_VOLUME
local loaded = false
local loadStarted = false
---@type fun()[]
local loadCallbacks = {}
local dirty = false
local saving = false
local pendingSave = false
local flushDelay = 0.0
local saveGeneration = 0

local function Clamp01(value)
    local number = tonumber(value)
    if not number then
        return DEFAULT_VOLUME
    end
    if number < 0.0 then
        return 0.0
    end
    if number > 1.0 then
        return 1.0
    end
    return number
end

local function CloudAvailable()
    return clientCloud ~= nil and type(clientCloud.Set) == "function" and type(clientCloud.Get) == "function"
end

local function Snapshot()
    return {
        bgmVolume = bgmVolume,
        sfxVolume = sfxVolume,
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

function AudioSettings.Apply()
    if not audio then
        return false
    end
    audio:SetMasterGain(SOUND_MUSIC, bgmVolume)
    audio:SetMasterGain(SOUND_EFFECT, sfxVolume)
    return true
end

function AudioSettings.Save(reason)
    flushDelay = 0.0
    if not dirty then
        return false
    end
    if saving then
        pendingSave = true
        return true
    end
    if not CloudAvailable() then
        print("AudioSettings: cloud unavailable, keep local " .. tostring(reason))
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
                print("AudioSettings: saved " .. tostring(reason))
                if pendingSave or dirty then
                    pendingSave = false
                    dirty = true
                    AudioSettings.Save("retry")
                end
            end
        end,
        error = function(code, message)
            if generation == saveGeneration then
                saving = false
                dirty = true
                print(string.format(
                    "AudioSettings: save failed reason=%s code=%s message=%s",
                    tostring(reason),
                    tostring(code),
                    tostring(message)
                ))
            end
        end,
    })
    return true
end

function AudioSettings.Load(onLoaded)
    if type(onLoaded) == "function" then
        loadCallbacks[#loadCallbacks + 1] = onLoaded
    end
    if loaded then
        AudioSettings.Apply()
        FinishLoad()
        return
    end
    if loadStarted then
        return
    end
    loadStarted = true
    if not CloudAvailable() then
        print("AudioSettings: cloud unavailable, default volumes")
        AudioSettings.Apply()
        FinishLoad()
        return
    end
    clientCloud:Get(CLOUD_KEY, {
        ok = function(values)
            local payload = values and values[CLOUD_KEY]
            if type(payload) == "table" then
                bgmVolume = Clamp01(payload.bgmVolume)
                sfxVolume = Clamp01(payload.sfxVolume)
            end
            print(string.format(
                "AudioSettings: loaded bgm=%.2f sfx=%.2f",
                bgmVolume,
                sfxVolume
            ))
            AudioSettings.Apply()
            FinishLoad()
        end,
        error = function(code, message)
            print(string.format(
                "AudioSettings: load failed code=%s message=%s",
                tostring(code),
                tostring(message)
            ))
            AudioSettings.Apply()
            FinishLoad()
        end,
    })
end

function AudioSettings.SetBgmVolume(value, persist)
    bgmVolume = Clamp01(value)
    AudioSettings.Apply()
    if persist then
        MarkDirty()
    end
    return bgmVolume
end

function AudioSettings.SetSfxVolume(value, persist)
    sfxVolume = Clamp01(value)
    AudioSettings.Apply()
    if persist then
        MarkDirty()
    end
    return sfxVolume
end

function AudioSettings.BgmVolume()
    return bgmVolume
end

function AudioSettings.SfxVolume()
    return sfxVolume
end

function AudioSettings.Update(timeStep)
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
    AudioSettings.Save("idle")
end

function AudioSettings.IsLoaded()
    return loaded
end

return AudioSettings
