-- BGM 曲目路径。只查表，不播。credits 曲未登记。

local BgmTracks = {}

local TRACKS = {
    menu = "audio/Chained Story (Menu).mp3",
    chapter1 = "audio/Writing the future (CH1).mp3",
    chapter2 = "audio/Brittle Rille (CH2).mp3",
    chapter3 = "audio/Piece of Quiet (CH3).mp3",
    chapter4 = "audio/Eschatology (CH4_2).mp3",
    chapter5 = "audio/添い寝 (CH5).mp3",
    credits = "audio/Yume no Naka Naraba (credits).mp3",
}

BgmTracks.FADE = 1.0

function BgmTracks.Path(id)
    if type(id) ~= "string" then
        return nil
    end
    return TRACKS[id]
end

function BgmTracks.ChapterPath(chapter)
    local number = tonumber(chapter)
    if not number then
        return nil
    end
    return TRACKS["chapter" .. tostring(math.floor(number + 0.5))]
end

function BgmTracks.MenuPath()
    return TRACKS.menu
end

function BgmTracks.CreditsPath()
    return TRACKS.credits
end

return BgmTracks
