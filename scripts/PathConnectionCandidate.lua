-- Level 级路径连接候选值对象。
-- 候选只引用 Part 内的局部 PathNode，不表示当前已经连通。
-- 视觉评估和有效边生成由后续 PathRuntime 负责。

local PathConnectionCandidate = {}
PathConnectionCandidate.__index = PathConnectionCandidate

PathConnectionCandidate.KIND_VISUAL = "visual_candidate"
PathConnectionCandidate.DIRECTION_BIDIRECTIONAL = "bidirectional"
PathConnectionCandidate.DIRECTION_FROM_TO = "from_to"
PathConnectionCandidate.DIRECTION_TO_FROM = "to_from"

local VALID_KINDS = {
    visual_candidate = true,
}

local VALID_DIRECTIONS = {
    bidirectional = true,
    from_to = true,
    to_from = true,
}

local function CopyReference(reference)
    return {
        partId = reference.partId,
        nodeId = reference.nodeId,
    }
end

function PathConnectionCandidate.IsValidReference(reference)
    return type(reference) == "table"
        and type(reference.partId) == "string"
        and reference.partId ~= ""
        and type(reference.nodeId) == "string"
        and reference.nodeId ~= ""
end

function PathConnectionCandidate.New(data)
    data = data or {}
    local self = setmetatable({}, PathConnectionCandidate)
    self.id = data.id or "path_candidate"
    self.from = CopyReference(data.from or {})
    self.to = CopyReference(data.to or {})
    self.kind = VALID_KINDS[data.kind] and data.kind or PathConnectionCandidate.KIND_VISUAL
    self.direction = VALID_DIRECTIONS[data.direction]
        and data.direction
        or PathConnectionCandidate.DIRECTION_BIDIRECTIONAL
    self.enabled = data.enabled ~= false
    return self
end

function PathConnectionCandidate:ToTable()
    return {
        id = self.id,
        from = CopyReference(self.from),
        to = CopyReference(self.to),
        kind = self.kind,
        direction = self.direction,
        enabled = self.enabled,
    }
end

function PathConnectionCandidate.FromTable(data)
    if type(data) ~= "table" or type(data.id) ~= "string" or data.id == "" then
        return nil, "invalid path connection candidate"
    end
    if not PathConnectionCandidate.IsValidReference(data.from)
        or not PathConnectionCandidate.IsValidReference(data.to) then
        return nil, "path connection candidate has invalid endpoint"
    end
    if data.kind ~= nil and not VALID_KINDS[data.kind] then
        return nil, "unsupported path connection candidate kind"
    end
    if data.direction ~= nil and not VALID_DIRECTIONS[data.direction] then
        return nil, "unsupported path connection candidate direction"
    end
    return PathConnectionCandidate.New(data)
end

function PathConnectionCandidate:GetEndpoint(side)
    if side == "from" then
        return self.from
    end
    if side == "to" then
        return self.to
    end
    return nil
end

function PathConnectionCandidate:GetEndpointKey(side)
    local endpoint = self:GetEndpoint(side)
    if not endpoint then
        return nil
    end
    return endpoint.partId .. ":" .. endpoint.nodeId
end

return PathConnectionCandidate
