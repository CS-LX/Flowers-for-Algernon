-- 屏幕颜色拾取。
-- 进入拾取模式后，下一次左键只记下鼠标位置；等本帧画完再读像素，然后自动退出。
-- 不能在 Update 里立刻截屏：WebGL backbuffer 这时通常已经被清成黑。

local UI = require("urhox-libs/UI")
local PaintScreenColorPicker = require("urhox-libs.Paint.ScreenColorPicker")

local ScreenColorPicker = {}

---@type fun(hex: string)|nil
local onPicked_ = nil
---@type fun()|nil
local onCancel_ = nil
local waitingRelease_ = false
local pendingX_ = nil
local pendingY_ = nil
local hintRegistered_ = false

local function ChannelToByte(value)
    local number = tonumber(value) or 0
    if number > 1 then
        return math.floor(math.max(0, math.min(255, number)) + 0.5)
    end
    return math.floor(math.max(0, math.min(1, number)) * 255.0 + 0.5)
end

local function HexFromColor(color)
    if not color then
        return nil
    end
    return string.format(
        "#%02X%02X%02X",
        ChannelToByte(color.r),
        ChannelToByte(color.g),
        ChannelToByte(color.b)
    )
end

local function EnsureHint()
    if hintRegistered_ then
        return
    end
    UI.RegisterGlobalComponent("ScreenColorPickerHint", {
        Render = function(_, nvg)
            if not onPicked_ or pendingX_ ~= nil then
                return
            end
            local width = UI.GetWidth() or 800
            local chipW = 260
            local chipH = 32
            local x = (width - chipW) * 0.5
            local y = 16
            nvgBeginPath(nvg)
            nvgRoundedRect(nvg, x, y, chipW, chipH, 8)
            nvgFillColor(nvg, nvgRGBA(12, 16, 24, 210))
            nvgFill(nvg)
            nvgFontFace(nvg, "sans")
            nvgFontSize(nvg, 13)
            nvgFillColor(nvg, nvgRGBA(240, 245, 255, 255))
            nvgTextAlign(nvg, NVG_ALIGN_CENTER_VISUAL + NVG_ALIGN_MIDDLE)
            nvgText(nvg, x + chipW * 0.5, y + chipH * 0.5, "点击画面拾取颜色    Esc 取消")
        end,
    })
    hintRegistered_ = true
end

function ScreenColorPicker.IsActive()
    return onPicked_ ~= nil
end

function ScreenColorPicker.Cancel()
    local cancel = onCancel_
    onPicked_ = nil
    onCancel_ = nil
    waitingRelease_ = false
    pendingX_ = nil
    pendingY_ = nil
    if cancel then
        cancel()
    end
end

local function Finish(hex)
    local picked = onPicked_
    onPicked_ = nil
    onCancel_ = nil
    waitingRelease_ = false
    pendingX_ = nil
    pendingY_ = nil
    if picked and hex then
        picked(hex)
    end
end

local function SampleHex(mouseX, mouseY)
    local color = PaintScreenColorPicker.Pick(mouseX, mouseY)
    local hex = HexFromColor(color)
    if hex == "#000000" then
        local flipped = PaintScreenColorPicker.Pick(mouseX, mouseY, { flipY = true })
        local flippedHex = HexFromColor(flipped)
        if flippedHex and flippedHex ~= "#000000" then
            print(string.format(
                "ScreenColorPicker: used flipY mouse=(%d,%d) hex=%s",
                mouseX,
                mouseY,
                flippedHex
            ))
            return flippedHex
        end
    end
    if hex then
        print(string.format(
            "ScreenColorPicker: mouse=(%d,%d) hex=%s r=%.3f g=%.3f b=%.3f",
            mouseX,
            mouseY,
            hex,
            tonumber(color and color.r) or 0,
            tonumber(color and color.g) or 0,
            tonumber(color and color.b) or 0
        ))
        return hex
    end
    print(string.format("ScreenColorPicker: Pick failed mouse=(%d,%d)", mouseX, mouseY))
    return nil
end

function ScreenColorPicker.CaptureIfPending()
    if pendingX_ == nil or pendingY_ == nil then
        return
    end
    local mouseX = pendingX_
    local mouseY = pendingY_
    pendingX_ = nil
    pendingY_ = nil
    Finish(SampleHex(mouseX, mouseY))
end

function ScreenColorPicker.Begin(onPicked, onCancel)
    ScreenColorPicker.Cancel()
    if type(onPicked) ~= "function" then
        return false
    end
    EnsureHint()
    onPicked_ = onPicked
    if type(onCancel) == "function" then
        onCancel_ = onCancel
    else
        onCancel_ = nil
    end
    waitingRelease_ = input:GetMouseButtonDown(MOUSEB_LEFT)
    pendingX_ = nil
    pendingY_ = nil
    return true
end

function ScreenColorPicker.Update()
    if not ScreenColorPicker.IsActive() then
        return false
    end
    if input:GetKeyPress(KEY_ESCAPE) then
        ScreenColorPicker.Cancel()
        return true
    end
    if waitingRelease_ then
        if not input:GetMouseButtonDown(MOUSEB_LEFT) then
            waitingRelease_ = false
        end
        return true
    end
    if pendingX_ ~= nil then
        return true
    end
    if input:GetMouseButtonPress(MOUSEB_LEFT) then
        local mouse = input:GetMousePosition()
        pendingX_ = math.floor(mouse.x + 0.5)
        pendingY_ = math.floor(mouse.y + 0.5)
        return true
    end
    return true
end

return ScreenColorPicker
