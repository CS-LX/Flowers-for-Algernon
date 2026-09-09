-- 选关 stencil RT 右下角预览。只画 MenuPrism 的 mask RT，不拦截点击。

local Widget = require("urhox-libs/UI/Core/Widget")

---@class MenuRtPreview : Widget
---@field texture Texture2D|nil
---@field nvgImage integer
---@field nvgCtx any
---@overload fun(props?: table): MenuRtPreview
local MenuRtPreview = Widget:Extend("MenuRtPreview")

local PREVIEW_HEIGHT = 160

function MenuRtPreview:Init(props)
    props = props or {}
    props.position = props.position or "absolute"
    props.right = props.right or 16
    props.bottom = props.bottom or 16
    props.width = props.width or PREVIEW_HEIGHT
    props.height = props.height or PREVIEW_HEIGHT
    props.pointerEvents = "none"
    props.borderRadius = 0
    rawset(self, "texture", nil)
    rawset(self, "nvgImage", 0)
    rawset(self, "nvgCtx", nil)
    Widget.Init(self, props)
end

function MenuRtPreview:ReleaseImage()
    if self.nvgImage and self.nvgImage > 0 and self.nvgCtx and nvgDeleteVideo then
        nvgDeleteVideo(self.nvgCtx, self.nvgImage)
    end
    rawset(self, "nvgImage", 0)
    rawset(self, "nvgCtx", nil)
end

function MenuRtPreview:SyncSize()
    local texture = self.texture
    if not texture then
        return
    end
    local width = texture:GetWidth()
    local height = texture:GetHeight()
    if not width or width <= 0 or not height or height <= 0 then
        return
    end
    local previewHeight = PREVIEW_HEIGHT
    local previewWidth = math.floor(previewHeight * width / height + 0.5)
    if previewWidth < 8 then
        previewWidth = 8
    end
    self:SetStyle({
        width = previewWidth,
        height = previewHeight,
    })
end

function MenuRtPreview:SetTexture(texture)
    if self.texture == texture then
        self:SyncSize()
        return
    end
    self:ReleaseImage()
    rawset(self, "texture", texture)
    self:SyncSize()
end

function MenuRtPreview:EnsureImage(nvg)
    if not self.texture or not nvgCreateVideo then
        return 0
    end
    if self.nvgImage > 0 and self.nvgCtx == nvg then
        return self.nvgImage
    end
    self:ReleaseImage()
    local handle = nvgCreateVideo(nvg, self.texture)
    if not handle or handle <= 0 then
        print("MenuRtPreview: nvgCreateVideo failed")
        return 0
    end
    rawset(self, "nvgImage", handle)
    rawset(self, "nvgCtx", nvg)
    return handle
end

function MenuRtPreview:Render(nvg)
    self:SyncSize()
    local handle = self:EnsureImage(nvg)
    if handle <= 0 then
        return
    end
    local layout = self:GetAbsoluteLayout()
    local paint = nvgImagePattern(nvg, layout.x, layout.y, layout.w, layout.h, 0, handle, 1.0)
    nvgBeginPath(nvg)
    nvgRect(nvg, layout.x, layout.y, layout.w, layout.h)
    nvgFillPaint(nvg, paint)
    nvgFill(nvg)
end

function MenuRtPreview:Destroy()
    self:ReleaseImage()
    rawset(self, "texture", nil)
    Widget.Destroy(self)
end

function MenuRtPreview:IsStateful()
    return true
end

return MenuRtPreview
