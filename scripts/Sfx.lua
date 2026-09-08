-- 一次性音效。关卡 Scene 上用实例池；菜单/退出按钮用全局一次性源。
-- 不碰 BGM。

local Sfx = {}
Sfx.__index = Sfx

Sfx.MODAL_CLICK = "audio/sfx/sfx_modal_click.mp3"
Sfx.TYPE_RESEARCHER = "audio/sfx/sfx_typewriter_researcher.mp3"
Sfx.TYPE_CHARLIE = "audio/sfx/sfx_typewriter_charlie.mp3"

local POOL = 8
---@type Node|nil
local uiNode = nil
---@type SoundSource|nil
local uiSource = nil

function Sfx.BindUiScene(scene)
    if not scene then
        return nil
    end
    if uiNode and uiSource and uiNode.scene == scene then
        return uiSource
    end
    if uiNode then
        uiNode:Remove()
        uiNode = nil
        uiSource = nil
    end
    uiNode = scene:CreateChild("UiSfx")
    local source = uiNode:CreateComponent("SoundSource")
    if not source then
        print("Sfx: failed to create ui SoundSource")
        uiNode = nil
        return nil
    end
    source:SetSoundType(SOUND_EFFECT)
    uiSource = source
    print("Sfx: bound ui source")
    return uiSource
end

local function EnsureUiSource()
    if uiSource then
        return uiSource
    end
    print("Sfx: ui source missing")
    return nil
end

function Sfx.PlayUi(path)
    path = path or Sfx.MODAL_CLICK
    local source = EnsureUiSource()
    if not source then
        return false
    end
    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("Sfx: missing " .. path)
        return false
    end
    sound:SetLooped(false)
    source:Play(sound, sound:GetFrequency(), 1.0)
    return true
end

function Sfx.PlayModalClick()
    return Sfx.PlayUi(Sfx.MODAL_CLICK)
end

---@param scene Scene
function Sfx.New(scene)
    local self = setmetatable({}, Sfx)
    self.scene = scene
    self.root = scene:CreateChild("Sfx")
    ---@type SoundSource[]
    self.sources = {}
    self.nextIndex = 1
    for i = 1, POOL do
        local node = self.root:CreateChild("Sfx" .. tostring(i))
        local source = node:CreateComponent("SoundSource")
        source:SetSoundType(SOUND_EFFECT)
        self.sources[i] = source
    end
    return self
end

function Sfx:Play(path)
    if not path or not self.sources[self.nextIndex] then
        return false
    end
    local sound = cache:GetResource("Sound", path)
    if not sound then
        print("Sfx: missing " .. path)
        return false
    end
    sound:SetLooped(false)
    local source = self.sources[self.nextIndex]
    local nextIndex = self.nextIndex + 1
    if nextIndex > #self.sources then
        nextIndex = 1
    end
    self.nextIndex = nextIndex
    source:Play(sound, sound:GetFrequency(), 1.0)
    return true
end

function Sfx:Destroy()
    if self.sources then
        for i = 1, #self.sources do
            self.sources[i]:Stop()
        end
    end
    self.sources = {}
    if self.root then
        self.root:Remove()
        self.root = nil
    end
    self.scene = nil
end

return Sfx
