-- 角色视觉跟随：站在当前 PathNode 上的 Walker，随 Part 的视觉 Transform 贴合。
-- 不关心 rotator / mover；机关拖动和演出缓动共用这一层。
-- 走路中的 Walker 不贴合，避免把路径插值拉回节点。

local RiderFollow = {}
RiderFollow.__index = RiderFollow

---@class RiderFollow
---@field levelDocument table
---@field partRenderer table
---@field player table|nil
---@field algernon table|nil

function RiderFollow.New(levelDocument, partRenderer)
    local self = setmetatable({}, RiderFollow)
    self.levelDocument = levelDocument
    self.partRenderer = partRenderer
    ---@type table|nil
    self.player = nil
    ---@type table|nil
    self.algernon = nil
    return self
end

function RiderFollow:Bind(player, algernon)
    self.player = player
    self.algernon = algernon
end

function RiderFollow:IsEnabledWalker(walker)
    if not walker then
        return false
    end
    if walker.IsEnabled and not walker:IsEnabled() then
        return false
    end
    return true
end

function RiderFollow:IsOnPart(walker, part)
    if not self:IsEnabledWalker(walker) or not part then
        return false
    end
    local partId = walker:GetCurrentPartId()
    if not partId then
        return false
    end
    return partId == part.id
        or self.levelDocument:IsDescendant(partId, part.id)
end

function RiderFollow:IsWalkingOnPart(walker, part)
    return self:IsEnabledWalker(walker)
        and walker.IsWalking
        and walker:IsWalking()
        and self:IsOnPart(walker, part)
end

function RiderFollow:FollowWalker(walker)
    if not self:IsEnabledWalker(walker) then
        return false
    end
    if walker.IsWalking and walker:IsWalking() then
        return false
    end
    if not walker.FollowCurrentNodeVisual then
        return false
    end
    return walker:FollowCurrentNodeVisual(self.partRenderer)
end

--- 所有未在走路的角色贴到当前 PathNode 视觉位置。
function RiderFollow:Sync()
    local followed = false
    if self:FollowWalker(self.player) then
        followed = true
    end
    if self:FollowWalker(self.algernon) then
        followed = true
    end
    return followed
end

--- 只贴站在该 Part（含子孙）上的角色。机关拖动用这个，避免动 A 时把 B 上的人拉一下。
function RiderFollow:SyncOnPart(part)
    if not part then
        return false
    end
    local followed = false
    if self:IsOnPart(self.player, part) and self:FollowWalker(self.player) then
        followed = true
    end
    if self:IsOnPart(self.algernon, part) and self:FollowWalker(self.algernon) then
        followed = true
    end
    return followed
end

function RiderFollow:LockPlayer(locked)
    if self.player and self.player.SetMechanismLocked then
        self.player:SetMechanismLocked(locked)
    end
end

return RiderFollow
