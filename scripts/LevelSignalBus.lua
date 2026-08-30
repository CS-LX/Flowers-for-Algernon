-- 关卡内 keyed pub/sub 框架。
-- 对齐 MessagePipe：按 channel id 分发，不跨关卡；Dispose 清空全部订阅。
-- 信号值只允许 -1 / 0 / +1。本模块不接线门、过关或 Part。

local LevelSignalBus = {}
LevelSignalBus.__index = LevelSignalBus

LevelSignalBus.NEGATIVE = -1
LevelSignalBus.NEUTRAL = 0
LevelSignalBus.POSITIVE = 1
-- 预留通道名，供关卡过关应用订阅；框架本身不自动 Publish。
LevelSignalBus.FINISH_ID = "level.finish"

local function NormalizeId(channelId)
    if type(channelId) ~= "string" then
        return ""
    end
    return channelId
end

function LevelSignalBus.NormalizeValue(value)
    local number = tonumber(value)
    if number == nil then
        return nil
    end
    if number > 0 then
        return LevelSignalBus.POSITIVE
    end
    if number < 0 then
        return LevelSignalBus.NEGATIVE
    end
    return LevelSignalBus.NEUTRAL
end

function LevelSignalBus.New()
    local self = setmetatable({}, LevelSignalBus)
    self.channels = {}
    self.nextHandle = 1
    self.alive = true
    self.lastValues = {}
    return self
end

function LevelSignalBus:IsAlive()
    return self.alive == true
end

function LevelSignalBus:GetLast(channelId)
    channelId = NormalizeId(channelId)
    if channelId == "" then
        return nil
    end
    return self.lastValues[channelId]
end

function LevelSignalBus:Subscribe(channelId, listener)
    if not self.alive then
        return nil
    end
    channelId = NormalizeId(channelId)
    if channelId == "" or type(listener) ~= "function" then
        return nil
    end
    local handle = self.nextHandle
    self.nextHandle = self.nextHandle + 1
    local channel = self.channels[channelId]
    if not channel then
        channel = {}
        self.channels[channelId] = channel
    end
    channel[handle] = listener
    print(string.format("LevelSignalBus: subscribe id=%s handle=%d", channelId, handle))
    return handle
end

function LevelSignalBus:Unsubscribe(channelId, handle)
    channelId = NormalizeId(channelId)
    local channel = self.channels[channelId]
    if not channel or handle == nil then
        return
    end
    channel[handle] = nil
end

function LevelSignalBus:Publish(channelId, value, source)
    if not self.alive then
        return false, "signal bus disposed"
    end
    channelId = NormalizeId(channelId)
    if channelId == "" then
        return false, "empty signal id"
    end
    local signal = LevelSignalBus.NormalizeValue(value)
    if signal == nil then
        return false, "invalid signal value"
    end
    self.lastValues[channelId] = signal
    local payload = {
        id = channelId,
        value = signal,
        source = source or {},
    }
    print(string.format(
        "LevelSignalBus: publish id=%s value=%d source=%s",
        channelId,
        signal,
        tostring(payload.source.kind or payload.source.id or "")
    ))
    local channel = self.channels[channelId]
    if not channel then
        return true
    end
    local snapshot = {}
    for handle, listener in pairs(channel) do
        snapshot[#snapshot + 1] = { handle = handle, listener = listener }
    end
    for _, item in ipairs(snapshot) do
        if channel[item.handle] == item.listener then
            item.listener(payload)
        end
    end
    return true
end

function LevelSignalBus:Dispose()
    print("LevelSignalBus: dispose")
    self.alive = false
    self.channels = {}
    self.lastValues = {}
end

return LevelSignalBus
