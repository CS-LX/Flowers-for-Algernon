-- 一次性音效。挂在当前关卡 Scene 上，小池叠播。不碰 BGM。

local Sfx = {}
Sfx.__index = Sfx

Sfx.MODAL_CLICK = "audio/sfx/sfx_modal_click.mp3"
Sfx.TYPE_RESEARCHER = "audio/sfx/sfx_typewriter_researcher.mp3"
Sfx.TYPE_CHARLIE = "audio/sfx/sfx_typewriter_charlie.mp3"

local POOL = 8

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
