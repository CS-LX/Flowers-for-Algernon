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

local function ValidateCandidateData(data)
    if type(data) ~= "table" then
        return false, "path connection candidate must be a table"
    end
    if type(data.id) ~= "string" or data.id == "" then
        return false, "path connection candidate id is required"
    end
    if not PathConnectionCandidate.IsValidReference(data.from)
        or not PathConnectionCandidate.IsValidReference(data.to) then
        return false, "path connection candidate has invalid endpoint"
    end
    if data.kind ~= nil and not VALID_KINDS[data.kind] then
        return false, "unsupported path connection candidate kind"
    end
    if data.direction ~= nil and not VALID_DIRECTIONS[data.direction] then
        return false, "unsupported path connection candidate direction"
    end
    return true
end

function PathConnectionCandidate.IsValidReference(reference)
    return type(reference) == "table"
        and type(reference.partId) == "string"
        and reference.partId ~= ""
        and type(reference.nodeId) == "string"
        and reference.nodeId ~= ""
end

function PathConnectionCandidate.New(data)
    local valid, errorMessage = ValidateCandidateData(data)
    if not valid then
        return nil, errorMessage
    end
    local self = setmetatable({}, PathConnectionCandidate)
    self.id = data.id
    self.from = CopyReference(data.from)
    self.to = CopyReference(data.to)
    self.kind = data.kind or PathConnectionCandidate.KIND_VISUAL
    self.direction = data.direction or PathConnectionCandidate.DIRECTION_BIDIRECTIONAL
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
    local valid, errorMessage = ValidateCandidateData(data)
    if not valid then
        return nil, errorMessage
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
