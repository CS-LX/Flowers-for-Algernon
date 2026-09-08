-- BGM 薄封装。
-- 只负责：逻辑 id、单轨播放、crossfade、音量。
-- 不认识选关 / 章节 / 关卡；由那些调用方 Register 并 Play。

local Bgm = {}

local DEFAULT_FADE = 1.0

---@class BgmPlayOptions
---@field fade number|nil
---@field loop boolean|nil
---@field volume number|nil

---@class BgmStopOptions
---@field fade number|nil

---@class BgmChannel
---@field name string
---@field node Node|nil
---@field source SoundSource|nil
---@field id string|nil
---@field path string|nil
---@field envelope number
---@field envelopeFrom number
---@field envelopeTo number
---@field fadeElapsed number
---@field fadeDuration number
---@field trackGain number
---@field loop boolean
---@field active boolean

---@type Scene|nil
local scene_ = nil
---@type Node|nil
local root_ = nil
---@type BgmChannel|nil
local primary_ = nil
---@type BgmChannel|nil
local secondary_ = nil
---@type table<string, string>
local tracks_ = {}
local musicVolume_ = 1.0
local muted_ = false
local paused_ = false
local alive_ = false
local subscribed_ = false
---@type string|nil
local currentId_ = nil

local function Clamp01(value)
    local number = tonumber(value)
    if number == nil then
        return 0.0
    end
    if number < 0.0 then
        return 0.0
    end
    if number > 1.0 then
        return 1.0
    end
    return number
end

local function NormalizeId(id)
    if type(id) ~= "string" then
        return ""
    end
    return id
end

local function LooksLikePath(id)
    if id == "" then
        return false
    end
    if id:find("/", 1, true) or id:find("\\", 1, true) then
        return true
    end
    local lower = id:lower()
    return lower:sub(-4) == ".ogg"
        or lower:sub(-4) == ".wav"
        or lower:sub(-4) == ".mp3"
end

local function ResolvePath(id)
    local registered = tracks_[id]
    if type(registered) == "string" and registered ~= "" then
        return registered
    end
    if LooksLikePath(id) then
        return id
    end
    return nil
end

local function BusGain()
    if muted_ then
        return 0.0
    end
    return musicVolume_
end

local function ApplyGain(channel)
    if not channel or not channel.source then
        return
    end
    local gain = channel.envelope * channel.trackGain * BusGain()
    channel.source:SetGain(gain)
end

local function ApplyAllGains()
    ApplyGain(primary_)
    ApplyGain(secondary_)
end

---@param channel BgmChannel
local function HaltChannel(channel)
    if channel.source and channel.active then
        channel.source:StopImmediate()
    end
    channel.id = nil
    channel.path = nil
    channel.envelope = 0.0
    channel.envelopeFrom = 0.0
    channel.envelopeTo = 0.0
    channel.fadeElapsed = 0.0
    channel.fadeDuration = 0.0
    channel.trackGain = 1.0
    channel.loop = true
    channel.active = false
end

---@param channel BgmChannel
---@param to number
---@param duration number
local function StartFade(channel, to, duration)
    local fadeDuration = tonumber(duration) or 0.0
    if fadeDuration < 0.0 then
        fadeDuration = 0.0
    end
    channel.envelopeFrom = channel.envelope
    channel.envelopeTo = to
    channel.fadeElapsed = 0.0
    channel.fadeDuration = fadeDuration
    if fadeDuration <= 0.0 then
        channel.envelope = to
        ApplyGain(channel)
        if to <= 0.0 then
            HaltChannel(channel)
        end
    end
end

---@param channel BgmChannel
---@param dt number
local function StepFade(channel, dt)
    if not channel.active then
        return
    end
    if channel.fadeDuration <= 0.0 then
        return
    end
    local elapsed = channel.fadeElapsed + dt
    channel.fadeElapsed = elapsed
    local t = elapsed / channel.fadeDuration
    if t >= 1.0 then
        channel.envelope = channel.envelopeTo
        channel.fadeDuration = 0.0
        ApplyGain(channel)
        if channel.envelopeTo <= 0.0 then
            HaltChannel(channel)
        end
        return
    end
    channel.envelope = channel.envelopeFrom + (channel.envelopeTo - channel.envelopeFrom) * t
    ApplyGain(channel)
end

---@param name string
---@return BgmChannel
local function MakeChannel(name)
    ---@type BgmChannel
    local channel = {
        name = name,
        node = nil,
        source = nil,
        id = nil,
        path = nil,
        envelope = 0.0,
        envelopeFrom = 0.0,
        envelopeTo = 0.0,
        fadeElapsed = 0.0,
        fadeDuration = 0.0,
        trackGain = 1.0,
        loop = true,
        active = false,
    }
    return channel
end

---@param channel BgmChannel
local function BindChannel(channel)
    if not root_ then
        return false
    end
    local node = root_:CreateChild(channel.name)
    local source = node:CreateComponent("SoundSource")
    if not source then
        print("Bgm: failed to create SoundSource for " .. channel.name)
        return false
    end
    source:SetSoundType(SOUND_MUSIC)
    source:SetGain(0.0)
    channel.node = node
    channel.source = source
    return true
end

local function EnsureReady()
    if alive_ and scene_ and primary_ and secondary_ then
        return true
    end
    return Bgm.Init()
end

---@param eventType string
---@param eventData UpdateEventData
local function HandleBgmUpdate(eventType, eventData)
    Bgm.Update(eventData:GetFloat("TimeStep"))
end

function Bgm.Init()
    if alive_ and scene_ and primary_ and secondary_ then
        return true
    end
    scene_ = Scene()
    root_ = scene_:CreateChild("BgmRoot")
    primary_ = MakeChannel("BgmPrimary")
    secondary_ = MakeChannel("BgmSecondary")
    if not BindChannel(primary_) or not BindChannel(secondary_) then
        Bgm.Shutdown()
        return false
    end
    alive_ = true
    paused_ = false
    audio:Play()
    audio:SetMasterGain(SOUND_MUSIC, 1.0)
    if audio:IsSoundTypePaused(SOUND_MUSIC) then
        audio:ResumeSoundType(SOUND_MUSIC)
    end
    if not subscribed_ then
        SubscribeToEvent("Update", HandleBgmUpdate)
        subscribed_ = true
    end
    print("Bgm: init")
    return true
end

function Bgm.Shutdown()
    if primary_ then
        HaltChannel(primary_)
    end
    if secondary_ then
        HaltChannel(secondary_)
    end
    currentId_ = nil
    paused_ = false
    alive_ = false
    primary_ = nil
    secondary_ = nil
    root_ = nil
    if scene_ then
        scene_:Dispose()
        scene_ = nil
    end
    print("Bgm: shutdown")
end

function Bgm.Register(id, path)
    id = NormalizeId(id)
    if id == "" or type(path) ~= "string" or path == "" then
        print("Bgm: register ignored, empty id or path")
        return false
    end
    tracks_[id] = path
    print(string.format("Bgm: register id=%s path=%s", id, path))
    return true
end

function Bgm.Unregister(id)
    id = NormalizeId(id)
    if id == "" then
        return
    end
    tracks_[id] = nil
end

function Bgm.GetPath(id)
    id = NormalizeId(id)
    if id == "" then
        return nil
    end
    return tracks_[id]
end

function Bgm.SetVolume(volume)
    musicVolume_ = Clamp01(volume)
    ApplyAllGains()
    print(string.format("Bgm: volume=%.2f", musicVolume_))
end

function Bgm.GetVolume()
    return musicVolume_
end

function Bgm.SetMuted(muted)
    muted_ = muted == true
    ApplyAllGains()
    print(string.format("Bgm: muted=%s", tostring(muted_)))
end

function Bgm.IsMuted()
    return muted_
end

function Bgm.Pause()
    if paused_ then
        return
    end
    paused_ = true
    audio:PauseSoundType(SOUND_MUSIC)
    print("Bgm: pause")
end

function Bgm.Resume()
    if not paused_ then
        return
    end
    paused_ = false
    audio:ResumeSoundType(SOUND_MUSIC)
    print("Bgm: resume")
end

function Bgm.IsPaused()
    return paused_
end

function Bgm.CurrentId()
    return currentId_
end

function Bgm.IsPlaying()
    if primary_ and primary_.active then
        return true
    end
    if secondary_ and secondary_.active then
        return true
    end
    return false
end

---@param channel BgmChannel
---@param id string
---@param path string
---@param loop boolean
---@param trackGain number
---@param fade number
---@return boolean
local function StartChannel(channel, id, path, loop, trackGain, fade)
    if not channel.source then
        return false
    end
    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("Bgm: missing sound path=" .. path)
        return false
    end
    sound:SetLooped(loop)
    channel.id = id
    channel.path = path
    channel.loop = loop
    channel.trackGain = Clamp01(trackGain)
    channel.active = true
    channel.envelope = 0.0
    channel.source:Play(sound, 0, 0.0)
    ApplyGain(channel)
    StartFade(channel, 1.0, fade)
    print(string.format(
        "Bgm: start channel=%s id=%s fade=%.2f loop=%s",
        channel.name,
        id,
        fade,
        tostring(loop)
    ))
    return true
end

---@param id string
---@param options BgmPlayOptions|nil
---@return boolean
function Bgm.Play(id, options)
    if not EnsureReady() or not primary_ or not secondary_ then
        return false
    end
    id = NormalizeId(id)
    if id == "" then
        print("Bgm: play ignored, empty id")
        return false
    end
    local path = ResolvePath(id)
    if not path then
        print("Bgm: play missing id=" .. id)
        return false
    end
    options = options or {}
    local fade = tonumber(options.fade)
    if fade == nil then
        fade = DEFAULT_FADE
    end
    if fade < 0.0 then
        fade = 0.0
    end
    local loop = options.loop
    if loop == nil then
        loop = true
    else
        loop = loop == true
    end
    local trackGain = 1.0
    if options.volume ~= nil then
        trackGain = Clamp01(options.volume)
    end

    if primary_.active and primary_.id == id then
        primary_.loop = loop
        primary_.trackGain = trackGain
        if primary_.envelopeTo < 1.0 or not primary_.active then
            StartFade(primary_, 1.0, fade)
        else
            ApplyGain(primary_)
        end
        currentId_ = id
        print(string.format("Bgm: already current id=%s", id))
        return true
    end

    if secondary_.active then
        HaltChannel(secondary_)
    end

    if primary_.active then
        local outgoing = primary_
        local incoming = secondary_
        primary_ = incoming
        secondary_ = outgoing
        StartFade(secondary_, 0.0, fade)
        local started = StartChannel(primary_, id, path, loop, trackGain, fade)
        if not started then
            primary_ = outgoing
            secondary_ = incoming
            currentId_ = primary_.id
            return false
        end
        currentId_ = id
        print(string.format("Bgm: crossfade to id=%s fade=%.2f", id, fade))
        return true
    end

    local started = StartChannel(primary_, id, path, loop, trackGain, fade)
    if not started then
        return false
    end
    currentId_ = id
    return true
end

---@param id string
---@param fade number|nil
---@param options BgmPlayOptions|nil
---@return boolean
function Bgm.Crossfade(id, fade, options)
    ---@type BgmPlayOptions
    local playOptions = {}
    if options then
        playOptions.fade = options.fade
        playOptions.loop = options.loop
        playOptions.volume = options.volume
    end
    if fade ~= nil then
        playOptions.fade = fade
    elseif playOptions.fade == nil then
        playOptions.fade = DEFAULT_FADE
    end
    return Bgm.Play(id, playOptions)
end

---@param options BgmStopOptions|nil
function Bgm.Stop(options)
    if not primary_ and not secondary_ then
        currentId_ = nil
        return
    end
    options = options or {}
    local fade = tonumber(options.fade)
    if fade == nil then
        fade = DEFAULT_FADE
    end
    if fade < 0.0 then
        fade = 0.0
    end
    currentId_ = nil
    if primary_ and primary_.active then
        StartFade(primary_, 0.0, fade)
    end
    if secondary_ and secondary_.active then
        StartFade(secondary_, 0.0, fade)
    end
    print(string.format("Bgm: stop fade=%.2f", fade))
end

---@param dt number
function Bgm.Update(dt)
    if not alive_ or paused_ then
        return
    end
    local step = tonumber(dt) or 0.0
    if step < 0.0 then
        step = 0.0
    end
    if primary_ then
        StepFade(primary_, step)
    end
    if secondary_ then
        StepFade(secondary_, step)
    end
end

Bgm.DEFAULT_FADE = DEFAULT_FADE

return Bgm
