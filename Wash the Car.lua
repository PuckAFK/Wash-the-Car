--[[
    PuckAFK | Wash the Car | Smart Autofarm v1.2
    Place 70733580049633
    Audited against the supplied 2026-10-19 .rbxl and network log.

    Smart tycoon purchases, legitimate client-side dirt erasing, native-format
    spray batching, free bonuses, player upgrades, offline claim and smooth travel.
    v1.2: dynamic named upgrade/decor pad recognition, placeholder filtering,
    richer multi-zone purchase planning, better purchase touch recovery.
    v1.1: dirt-progress scoring, real brush size, end-game ROI weighting,
    first-slot unlock planning, high-payout / quick-tip target selection, and
    performance-aware scanning.
    Robux products and premium pads are intentionally excluded.

    PuckUI's built-in Configs tab persists controls when executor file APIs exist.
    Script has not been live-tested. Server-side acceptance may vary.
]]

if game.PlaceId ~= 70733580049633 then
    warn('[PuckAFK Wash] Unsupported place: ' .. tostring(game.PlaceId))
    return
end

local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local WS = game:GetService('Workspace')
local CollectionService = game:GetService('CollectionService')
local TweenService = game:GetService('TweenService')
local RunService = game:GetService('RunService')
local HttpService = game:GetService('HttpService')
local LP = Players.LocalPlayer
if not LP then return end

local env = (type(getgenv) == 'function' and getgenv()) or _G
if env.__PUCKAFK_WASH_THE_CAR and type(env.__PUCKAFK_WASH_THE_CAR.Unload) == 'function' then
    pcall(env.__PUCKAFK_WASH_THE_CAR.Unload)
end

local alive = true
local startedAt = os.clock()
local settings = {
    master = true, wash = true, purchases = true, personal = true,
    bonuses = true, offline = true, zones = true, decorations = true,
    tweenSpeed = 125, washInterval = 0.14, batchSize = 16,
    reservePercent = 3, distance = 16, useNoclip = true,
    smartSpending = true, autoRecover = true, antiAfk = true,
    purchaseUpgrades = true, purchaseStations = true, ignorePlaceholders = true,
    washPrioritization = true, fastTips = true, wealthyZonePriority = true,
}
local state = {
    status = 'Starting', plot = nil, target = nil, currentTween = nil,
    lastWash = 0, lastBuy = 0, lastPlotScan = 0,
    sprays = 0, cleaningPasses = 0, bought = 0, failed = 0,
    bonuses = 0, lastBonus = 0, lastCash = 0, lastCashChange = os.clock(),
    targetSince = 0, lastAction = os.clock(), moveToken = 0,
    lastOffline = 0, vehicleCheck = 0, lastShop = 0,
    lastIncomeSample = os.clock(), cashAtSample = 0, incomePerMinute = 0,
    lastVehicleScan = 0, scanCache = nil, lastPurchaseScan = 0, purchaseCache = {},
    foundPurchasePads = 0, availablePurchasePads = 0, lastPurchaseName = 'None',
}
local cleanCursor = setmetatable({}, {__mode = 'k'})
local faceBlocked = setmetatable({}, {__mode = 'k'})
local buttonBackoff = setmetatable({}, {__mode = 'k'})
local vehicleBackoff = setmetatable({}, {__mode = 'k'})
local vehicleProgress = setmetatable({}, {__mode = 'k'})
local connections = {}
local travelCollisions = {}
local travelActive = false
local ui, window, statusLabel, detailLabel

local function status(msg)
    state.status = msg
end
local function try(label, func)
    local ok, result = pcall(func)
    if not ok then
        state.failed += 1
        warn('[PuckAFK Wash][' .. tostring(label) .. '] ' .. tostring(result))
        return nil
    end
    return result
end
local function waitActive(t)
    local limit = os.clock() + math.max(0, t or 0)
    while alive and os.clock() < limit do
        task.wait(math.min(0.08, limit - os.clock()))
    end
    return alive
end
local function addConnection(c)
    if c then table.insert(connections, c) end
    return c
end
local function character()
    local c = LP.Character
    local root = c and c:FindFirstChild('HumanoidRootPart')
    local hum = c and c:FindFirstChildOfClass('Humanoid')
    if c and root and hum and hum.Health > 0 then return c, root, hum end
end
local function cash()
    local cashData = LP:FindFirstChild('CashData')
    local value = cashData and cashData:FindFirstChild('Cash')
    return value and value.Value or 0
end
local function money(n)
    n = tonumber(n) or 0
    if n < 1000 then return tostring(math.floor(n)) end
    local suffix = {'k','M','B','T','Qd','Qn','Sx','Sp','Oc','No','De','Ud','Dd','Td','Qt','Qnd','Sxd','Spd','Ocd'}
    local tier = math.clamp(math.floor(math.log10(math.max(n, 1)) / 3), 1, #suffix)
    return string.format('%.2f%s', n / 10^(tier*3), suffix[tier])
end
local function ownPlot()
    if state.plot and state.plot.Parent and state.plot:GetAttribute('OwnerUserId') == LP.UserId then
        return state.plot
    end
    local plots = WS:FindFirstChild('Plots')
    if plots then
        for _, p in ipairs(plots:GetChildren()) do
            if p:GetAttribute('OwnerUserId') == LP.UserId then
                state.plot = p
                return p
            end
        end
    end
    state.plot = nil
end
local function isOwnVehicle(model, plot)
    if not model or not model:IsA('Model') or not plot or not model:IsDescendantOf(plot) then return false end
    local node = model
    while node and node ~= plot do
        if node:GetAttribute('WashOpen') ~= nil then
            local uid = node:GetAttribute('OwnerUserId')
            return node:GetAttribute('WashOpen') == true and (uid == nil or uid == LP.UserId)
        end
        node = node.Parent
    end
    return false
end
local function vehicleOf(part, plot)
    local node = part and part.Parent
    while node and node ~= plot do
        if node:IsA('Model') and node:GetAttribute('WashOpen') ~= nil then
            if isOwnVehicle(node, plot) then return node end
            return nil
        end
        node = node.Parent
    end
end
local function isEnabledPart(part)
    return part and part:IsA('BasePart') and part:IsDescendantOf(WS)
       and part.Transparency < 0.98 and part.CanTouch
end
local function paidAncestor(inst)
    local p = inst
    while p and p ~= WS do
        local name = string.lower(p.Name)
        if name:find('robux', 1, true) or name:find('premium', 1, true)
            or name:find('x2cash', 1, true) or name:find('gamepass', 1, true)
            or name:find('devproduct', 1, true) or name:find('productstand', 1, true)
            or name:find('paid', 1, true) then return true end
        p = p.Parent
    end
    return false
end
local function cancelTravel()
    state.moveToken += 1
    local t = state.currentTween
    state.currentTween = nil
    if t then pcall(function() t:Cancel() end) end
    travelActive = false
    for part, old in pairs(travelCollisions) do
        if part.Parent then pcall(function() part.CanCollide = old end) end
        travelCollisions[part] = nil
    end
end
addConnection(RunService.Stepped:Connect(function()
    if not alive or not travelActive or not settings.useNoclip then return end
    local c = LP.Character
    if not c then return end
    for _, part in ipairs(c:GetDescendants()) do
        if part:IsA('BasePart') then
            if travelCollisions[part] == nil then travelCollisions[part] = part.CanCollide end
            part.CanCollide = false
        end
    end
end))
local function tweenTo(point, lookAt, maxTime)
    local c, root, hum = character()
    if not root then return false end
    if typeof(point) ~= 'Vector3' then return false end
    cancelTravel()
    local token = state.moveToken
    local dist = (root.Position - point).Magnitude
    if dist < 3.3 then return true end
    local direction = lookAt and Vector3.new(lookAt.X - point.X, 0, lookAt.Z - point.Z)
    if not direction or direction.Magnitude < 0.01 then direction = root.CFrame.LookVector end
    local goal = CFrame.lookAt(point, point + direction.Unit)
    local duration = math.clamp(dist / math.max(tonumber(settings.tweenSpeed) or 100, 20), 0.08, maxTime or 18)
    local activeTween = TweenService:Create(root, TweenInfo.new(duration, Enum.EasingStyle.Linear), {CFrame = goal})
    state.currentTween = activeTween
    travelActive = true
    local finish = false
    local completed = activeTween.Completed:Connect(function() finish = true end)
    activeTween:Play()
    local stopAt = os.clock() + duration + 1.6
    while alive and state.moveToken == token and not finish and os.clock() < stopAt do
        local _, nowRoot = character()
        if nowRoot ~= root or not root.Parent then break end
        task.wait(0.04)
    end
    completed:Disconnect()
    if state.currentTween == activeTween then state.currentTween = nil end
    pcall(function() activeTween:Cancel() end)
    travelActive = false
    for part, old in pairs(travelCollisions) do
        if part.Parent then pcall(function() part.CanCollide = old end) end
        travelCollisions[part] = nil
    end
    local _, newRoot = character()
    return alive and state.moveToken == token and newRoot and (newRoot.Position - point).Magnitude < 7
end

local Wash = RS:WaitForChild('Wash', 20)
local WashEvent = Wash and Wash:FindFirstChild('WashEvent')
local CleanableManager = Wash and try('wash-module', function() return require(Wash:WaitForChild('CleanableManager', 15)) end)
local PowerWashConfig = Wash and try('wash-config', function() return require(Wash:WaitForChild('PowerWashConfig', 15)) end)
local DirtSurface = Wash and try('surface-module', function() return require(Wash:WaitForChild('DirtSurface', 15)) end)
local BrushUpgradeConfig = try('brush-config', function() return require(RS:WaitForChild('BrushUpgradeConfig', 15)) end)
local CarPrices = try('car-prices', function() return require((RS:WaitForChild('Cars', 15)):WaitForChild('CarPrices',15)) end)
local PurchaseTargets = try('purchase-targets', function() return require(RS:WaitForChild('PurchaseTargets', 15)) end)
local UpgradesConfig = try('upgrade-config', function() return require(RS:WaitForChild('UpgradesConfig', 15)) end)
local UpgradeRemote = RS:FindFirstChild('UpgradeRemote')
local OfflineClaim = RS:FindFirstChild('OfflineClaim')
local bonusFolder = RS:FindFirstChild('BonusBillboard')
local bonusHit = bonusFolder and bonusFolder:FindFirstChild('Hit')
local bonusSpawn = bonusFolder and bonusFolder:FindFirstChild('Spawn')
local PuckUI = try('PuckUI', function()
    return loadstring(game:HttpGet('https://raw.githubusercontent.com/PuckAFK/Puck-Loader/refs/heads/main/ui/PuckUI.lua'))()
end)
if not PuckUI then
    warn('[PuckAFK Wash] UI could not load; refusing to start without Unload controls.')
    alive = false
    cancelTravel()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    return
end

local directions = {
    Front = {Vector3.new(0,0,-1), Vector3.new(1,0,0), Vector3.new(0,1,0), 'X','Y'},
    Back = {Vector3.new(0,0,1), Vector3.new(-1,0,0), Vector3.new(0,1,0), 'X','Y'},
    Left = {Vector3.new(-1,0,0), Vector3.new(0,0,-1), Vector3.new(0,1,0), 'Z','Y'},
    Right = {Vector3.new(1,0,0), Vector3.new(0,0,1), Vector3.new(0,1,0), 'Z','Y'},
    Top = {Vector3.new(0,1,0), Vector3.new(1,0,0), Vector3.new(0,0,-1), 'X','Z'},
    Bottom = {Vector3.new(0,-1,0), Vector3.new(1,0,0), Vector3.new(0,0,1), 'X','Z'},
}
local function facesOf(part)
    local raw = part:GetAttribute('CleanFaces')
    if type(raw) ~= 'string' or #raw == 0 then return PowerWashConfig and PowerWashConfig.DefaultFaces or {'Front','Back','Left','Right','Top','Bottom'} end
    local list = {}
    for name in raw:gmatch('[^,%s]+') do
        if directions[name] then table.insert(list, name) end
    end
    return list
end
local function doneFace(part, face)
    local done = part:GetAttribute('DoneFaces')
    return type(done) == 'string' and (',' .. done .. ','):find(','..face..',', 1, true) ~= nil
end
local function pendingFaces(part)
    local count = 0
    for _, face in ipairs(facesOf(part)) do
        if not doneFace(part, face) then count += 1 end
    end
    return count
end
-- The normal WashClient keeps editable dirt surfaces in DirtSurface.active.
-- Read that live surface state instead of assuming every dirty face is still 0%.
local function surfaceProgress()
    local map = {}
    if DirtSurface and type(DirtSurface.active) == 'table' then
        for surface in pairs(DirtSurface.active) do
            if type(surface) == 'table' and typeof(surface.part) == 'Instance'
               and type(surface.faceName) == 'string' then
                local faces = map[surface.part]
                if not faces then faces = {}; map[surface.part] = faces end
                faces[surface.faceName] = math.clamp(tonumber(surface.progress) or 0, 0, 1)
            end
        end
    end
    return map
end

local function vehiclePay(model)
    local pay = tonumber(model:GetAttribute('WashPay'))
    if (not pay or pay <= 0) and CarPrices and type(CarPrices.getWashPay) == 'function' then
        pay = CarPrices.getWashPay(model)
    end
    pay = pay or 0
    local mult = tonumber(model:GetAttribute('PayMultiplier')) or 1
    local bonus = tonumber(model:GetAttribute('BonusMultiplier')) or 1
    return math.max(0,pay*math.max(mult,1)*math.max(bonus,1))
end

local function chooseVehicle(plot)
    local _, root = character()
    if not root then return end
    local cars = {}
    local progress = surfaceProgress()
    for _, part in ipairs(CollectionService:GetTagged('Cleanable')) do
        if part:IsA('BasePart') and part:IsDescendantOf(plot) then
            local model = vehicleOf(part, plot)
            if model and (vehicleBackoff[model] or 0) < os.clock() then
                local count = pendingFaces(part)
                if count > 0 then
                    local data = cars[model]
                    if not data then
                        data = {model = model, parts = {}, faces = 0, equivalentFaces = 0,
                                nearest = math.huge, pay = vehiclePay(model), progress = progress,
                                liveProgress = 0, seen = 0, partsAmount = 0}
                        cars[model] = data
                    end
                    data.faces += count
                    data.nearest = math.min(data.nearest, (part.Position-root.Position).Magnitude)
                    data.partsAmount += 1
                    local liveFaces = progress[part]
                    for _, face in ipairs(facesOf(part)) do
                        if not doneFace(part,face) then
                            local done = liveFaces and liveFaces[face] or 0
                            data.equivalentFaces += math.max(0.08, 1-done)
                            data.liveProgress += done
                            data.seen += 1
                        end
                    end
                    table.insert(data.parts, part)
                end
            end
        end
    end
    local best, bestScore
    for _, data in pairs(cars) do
        local estimatedEffort = math.max(data.equivalentFaces, 0.6)
        local travelSeconds = math.max(0,data.nearest - 34)/math.max(settings.tweenSpeed,20)
        local payoutRank = math.log10(math.max(data.pay,1))
        local score = (payoutRank*11 + 13) / (1 + estimatedEffort*0.045 + travelSeconds*.45)
        if settings.washPrioritization then
            score += math.min(24, data.liveProgress / math.max(data.seen,1) * 24)
        end
        local started = tonumber(data.model:GetAttribute('WashStartTime'))
        -- Finishing quickly matters for tips, but do not chase expired vehicles endlessly.
        if settings.fastTips and started and started > 0 then
            local age = math.max(0,os.time()-started)
            if age < 18 then score += 14
            elseif age < 40 then score += 6 end
        end
        if settings.wealthyZonePriority then
            score += payoutRank * 2
        end
        if not best or score > bestScore then best, bestScore = data, score end
    end
    if best then
        table.sort(best.parts, function(a,b)
            local function partValue(p)
                local f = progress[p]
                local sum = 0
                if f then for _, n in pairs(f) do sum += n end end
                return sum*8 - (p.Position-root.Position).Magnitude*.1
            end
            return partValue(a) > partValue(b)
        end)
    end
    return best
end

local function geometry(part, face)
    local d = directions[face]
    if not d then return end
    local s = part.Size
    local localNormal, axisU, axisV = d[1], d[2], d[3]
    local extent = Vector3.new(s.X/2, s.Y/2, s.Z/2)
    local abs = localNormal:Abs()
    local depth = extent:Dot(abs)
    local lengthU = (axisU:Abs()):Dot(s)
    local lengthV = (axisV:Abs()):Dot(s)
    return localNormal, axisU, axisV, depth, lengthU, lengthV
end
local function faceRay(part, face, index)
    local n, u, v, depth, lenU, lenV = geometry(part, face)
    if not n then return end
    local spacing = 2.5
    local cols = math.clamp(math.ceil(lenU / spacing), 1, 32)
    local rows = math.clamp(math.ceil(lenV / spacing), 1, 32)
    local total = cols * rows
    local offset = (index - 1) % total
    local x = offset % cols
    local y = math.floor(offset / cols)
    -- Rotate sampling start on alternate sweeps to find dirty texture patches.
    local localOrigin = n * depth + u * (((x+0.5)/cols-0.5)*lenU*0.90)
                          + v * (((y+0.5)/rows-0.5)*lenV*0.90)
    local worldNormal = part.CFrame:VectorToWorldSpace(n)
    local facePoint = part.CFrame:PointToWorldSpace(localOrigin)
    local origin = facePoint + worldNormal * 4
    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Include
    params.FilterDescendantsInstances = {part}
    local hit = WS:Raycast(origin, -worldNormal * 8, params)
    if not hit or hit.Instance ~= part then return nil, total, facePoint, worldNormal end
    return hit, total, facePoint, worldNormal
end
local function ensureNear(part, face)
    local _, root = character()
    if not root then return false end
    local n, _, _, depth = geometry(part, face)
    if not n then return false end
    local worldNormal = part.CFrame:VectorToWorldSpace(n)
    local faceCenter = part.Position + worldNormal * depth
    local near = faceCenter + worldNormal * math.clamp(settings.distance, 9, 23)
    if face == 'Bottom' then
        near = part.Position + part.CFrame.RightVector * 10 + Vector3.new(0,-2,0)
    end
    if (root.Position - faceCenter).Magnitude > 31 then
        status('Moving to ' .. face .. ' surface')
        if not tweenTo(near, faceCenter, 25) then return false end
        waitActive(0.5)
    end
    local _, current = character()
    return current ~= nil and (current.Position - faceCenter).Magnitude < 42
end
local function validSprayPart(part, model, plot)
    return alive and part.Parent and model.Parent and model:IsDescendantOf(plot)
        and model:GetAttribute('WashOpen') == true and part:IsDescendantOf(model)
end
local function brushSize()
    local width = PowerWashConfig and tonumber(PowerWashConfig.BrushWidth) or 3
    local pcScale = PowerWashConfig and tonumber(PowerWashConfig.BrushWidthPCScale) or .6
    local level = BrushUpgradeConfig and BrushUpgradeConfig.levelOf and BrushUpgradeConfig.levelOf(LP) or 1
    local factor = BrushUpgradeConfig and BrushUpgradeConfig.scaleFor and BrushUpgradeConfig.scaleFor(level) or 1
    return math.clamp(width * pcScale * factor, .7, 9)
end

local function sprayBatch(part, face, model, plot)
    if not WashEvent then return false end
    if not validSprayPart(part,model,plot) or doneFace(part,face) then return false end
    if not ensureNear(part, face) then return false end
    local cursorMap = cleanCursor[part] or {}
    cleanCursor[part] = cursorMap
    local startIndex = cursorMap[face] or 1
    local records, attempts, maxPoints = {}, 0, math.clamp(math.floor(settings.batchSize), 1, 30)
    local span = brushSize()
    local _, faceAxis = geometry(part, face)
    local sweepAxis = part.CFrame:VectorToWorldSpace(faceAxis)
    local swept = 0
    local lastTotal = 0
    while attempts < maxPoints and alive and validSprayPart(part,model,plot) do
        local hit, total = faceRay(part, face, startIndex + swept)
        lastTotal = total or lastTotal
        swept += 1
        if hit then
            local p, primary, faceList
            if CleanableManager and type(CleanableManager.eraseAt) == 'function' then
                local okay, a, b, c = pcall(CleanableManager.eraseAt, hit, sweepAxis, span, math.max(0.7,span*0.9))
                if okay then p,primary,faceList = a,b,c end
            end
            -- The native sprayer sends one record per affected face.
            if p and type(faceList) == 'table' then
                for _, f in ipairs(faceList) do
                    if #records < 30 then table.insert(records, {p=p, f=f, pos=hit.Position}) end
                end
            else
                -- Local surface data might not have streamed in yet. Wait for real
                -- DirtSurface loading rather than guessing and flooding invalid events.
                if not CleanableManager then
                    if #records < 30 then table.insert(records, {p=part, f=face, pos=hit.Position}) end
                end
            end
        end
        attempts += 1
        if lastTotal > 0 and swept >= lastTotal then break end
    end
    cursorMap[face] = startIndex + swept
    if #records == 0 then
        faceBlocked[part] = faceBlocked[part] or {}
        faceBlocked[part][face] = os.clock() + 5
        return false
    end
    local now = os.clock()
    if now - state.lastWash < settings.washInterval then waitActive(settings.washInterval - (now-state.lastWash)) end
    if not alive then return false end
    state.lastWash = os.clock()
    -- Shape and cadence match the observed WashNet.fire('reportSpray', batch, upVector).
    local ok = pcall(WashEvent.FireServer, WashEvent, 'reportSpray', records, sweepAxis)
    if ok then
        state.sprays += 1
        state.lastAction = os.clock()
        status('Cleaning ' .. model.Name .. ' • ' .. face)
        return true
    end
    return false
end
local function doWash(plot)
    if not settings.wash or not WashEvent then return false end
    local picked = chooseVehicle(plot)
    if not picked then return false end
    local model = picked.model
    state.target = model
    -- Verify whole-vehicle progress. Repeated sends without new completed faces
    -- must eventually yield to another vehicle rather than looping forever.
    local record = vehicleProgress[model]
    local now = os.clock()
    if not record then
        record = {lastFaces = picked.faces, lastWork = picked.equivalentFaces, lastChange = now}
        vehicleProgress[model] = record
    elseif picked.faces < record.lastFaces or picked.equivalentFaces < (record.lastWork or math.huge) - 0.015 then
        record.lastFaces = picked.faces
        record.lastWork = picked.equivalentFaces
        record.lastChange = now
    elseif now - record.lastChange > 38 then
        vehicleBackoff[model] = now + 13
        record.lastChange = now
        status('Rechecking stalled vehicle: ' .. model.Name)
        return false
    end
    local didSomething = false
    local stampLimit = 6  -- re-evaluate purchases & bonuses regularly
    local fired = 0
    for _, part in ipairs(picked.parts) do
        if not alive or not settings.master or not settings.wash then break end
        local order = facesOf(part)
        local liveFaces = (picked.progress or {})[part] or {}
        table.sort(order,function(a,b)
            return (liveFaces[a] or 0) > (liveFaces[b] or 0)
        end)
        for _, face in ipairs(order) do
            if not alive or fired >= stampLimit then break end
            if not doneFace(part,face) and ((faceBlocked[part] or {})[face] or 0) < os.clock() then
                if sprayBatch(part,face,model,plot) then
                    fired += 1
                    didSomething = true
                end
            end
        end
        if fired >= stampLimit then break end
    end
    if didSomething then
        state.cleaningPasses += 1
    else
        vehicleBackoff[model] = os.clock()+4
    end
    return didSomething
end

-- Purchase discovery, verified against the 2026-10-19 extended place dump.
-- The earlier script only recognized models ending in "Button". Other zones
-- actually use models named HeliUpgrade_Foam, HeliUpgrade_Water, etc. Some
-- future-ring/space buttons are only attribute stubs (zero physical children).
-- Never attempt to purchase a stub: it does not have an Activate touch part.
local slotGroups = {
    Slots = 1, HeliSlots = 2, BoatSlots = 3, PlaneSlots = 4, SpaceSlots = 5,
    Ring6Slots = 6, Ring5Slots = 7, Ring4Slots = 8, Ring3Slots = 9,
    SaturnSlots = 10, HubSlots = 11,
}
local function padIdentity(pad, slot, groupName)
    local label = string.lower(pad.Name)
    if label:sub(1,1) == '_' or label:find('bought',1,true)
        or label:find('product',1,true) or label:find('shop',1,true)
        or label:find('pass',1,true) then return end
    if slot.Name == 'Zone' or slot.Name == 'Floor' or groupName == 'HubSlots' then
        return 'Zone', nil
    end
    if label:find('decor',1,true) then return 'Decoration', nil end
    if label:find('upgrade',1,true) then
        local equipment = label:match('upgrade[_%-](.+)') or label:match('upgrade(.+)')
        return 'Equipment', equipment
    end
    if label == 'button' or label:find('unlock',1,true)
        or label:find('station',1,true) then return 'Station', nil end
    -- A game update may add new name formats. Accept only direct children
    -- with their own replicated Price attribute and active touch component.
    return 'Equipment', nil
end
local function livePad(pad)
    if not (pad and (pad:IsA('Model') or pad:IsA('Folder'))) then return end
    if paidAncestor(pad) or pad:GetAttribute('Locked') == true then return end
    local price = pad:GetAttribute('Price')
    if type(price) ~= 'number' or price ~= price or price == math.huge
        or price < 0 then return end
    local act = pad:FindFirstChild('Activate')
    if not isEnabledPart(act) then return end
    return act, price
end
local function slotReady(slot, pad, groupName)
    if groupName == 'Slots' then
        local stage = tonumber(pad:GetAttribute('Stage'))
        local level = tonumber(slot:GetAttribute('Level')) or
            (slot:GetAttribute('Active') and 1 or 0)
        if pad.Name == 'UpgradeButton' and (not stage or stage ~= level + 1) then return false end
        if pad.Name == 'DecorButton' and level < 1 then return false end
    else
        -- Station upgrades require that their station be unlocked first.
        -- Future zones may place decorative pads under the area itself.
        local label = string.lower(pad.Name)
        if label:find('upgrade',1,true) and tonumber(slot.Name) then
            if slot:GetAttribute('Active') ~= true then return false end
        end
    end
    return true
end
local upgradeBoost = {
    foam = 39, dryer = 31, goldconveyor = 26,
    water = 15, waterfront = 15, waterback = 15,
    brushes = 13, brushtop = 13, brushsidel = 12, brushsider = 12,
}
local function purchaseCandidates(plot)
    local available = {}
    local haveCash = cash()
    local _, root = character()
    if not root then return available end
    local originalBayPads
    if PurchaseTargets and type(PurchaseTargets.collect) == 'function' then
        local ok, targets = pcall(PurchaseTargets.collect, plot)
        if ok and type(targets) == 'table' and next(targets) then
            originalBayPads = targets
        end
    end
    local discovered = 0
    -- Iterate known live plot slot folders. Never scan ReplicatedStorage's
    -- PlotLodStorage: its objects are templates and cannot be purchased.
    for groupName, area in pairs(slotGroups) do
        local group = plot:FindFirstChild(groupName)
        if group then
            for _, slot in ipairs(group:GetChildren()) do
                if slot:IsA('Model') or slot:IsA('Folder') then
                    for _, pad in ipairs(slot:GetChildren()) do
                        if pad:IsA('Model') or pad:IsA('Folder') then
                            local act, price = livePad(pad)
                            if act then
                                discovered += 1
                                local kind, equipment = padIdentity(pad,slot,groupName)
                                if kind and (buttonBackoff[pad] or 0) <= os.clock()
                                  and (groupName ~= 'Slots' or not originalBayPads or originalBayPads[pad])
                                  and slotReady(slot,pad,groupName)
                                  and (kind ~= 'Decoration' or settings.decorations)
                                  and (kind ~= 'Zone' or settings.zones)
                                  and (kind ~= 'Equipment' or settings.purchaseUpgrades)
                                  and (kind ~= 'Station' or settings.purchaseStations)
                                  and price <= haveCash then
                                    local dist = (root.Position - act.Position).Magnitude
                                    local isFirstStation = kind == 'Station' and slot.Name == '1'
                                    local score
                                    if kind == 'Zone' then score = 170
                                    elseif kind == 'Station' then score = isFirstStation and 150 or 116
                                    elseif kind == 'Equipment' then score = 100
                                    else score = 69 end
                                    if kind == 'Equipment' then
                                        if equipment and upgradeBoost[equipment] then
                                            score += upgradeBoost[equipment]
                                        elseif groupName == 'Slots' then
                                            local stage = tonumber(pad:GetAttribute('Stage'))
                                            local boost = ({[3]=39,[8]=31,[9]=26,[2]=13,[4]=12,[5]=12,[6]=15,[7]=15})
                                            score += boost[stage] or 10
                                        else score += 10 end
                                    elseif kind == 'Decoration' then
                                        if area >= 2 then score += 25 end
                                        if slot:GetAttribute('Active') == true then score += 7 end
                                    end
                                    score += math.min(area * 3.5, 33)
                                    if settings.smartSpending then
                                        -- A small preference for closer/cheaper pads, after important
                                        -- unlocks and payout multipliers are identified.
                                        score -= math.min(22, dist/math.max(40,settings.tweenSpeed)*3)
                                        score -= math.min(18, math.log10(math.max(price,1))*0.6)
                                    else
                                        score -= math.log10(math.max(price,1))*3
                                    end
                                    local reserve = (kind == 'Zone' or isFirstStation) and 0
                                        or math.min(15, settings.reservePercent)
                                    if haveCash >= price * (1 + reserve/100) then
                                        table.insert(available, {
                                            pad = pad, act = act, group = groupName,
                                            kind = kind, equipment = equipment, price = price,
                                            score = score, distance = dist,
                                            label = groupName .. '/' .. slot.Name .. '/' .. pad.Name,
                                        })
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end
    state.foundPurchasePads = discovered
    state.availablePurchasePads = #available
    table.sort(available,function(a,b)
        if a.score == b.score then return a.price < b.price end
        return a.score > b.score
    end)
    return available
end
local function buyPad(target)
    local pad, act = target.pad, target.act
    if not alive or not settings.master or not settings.purchases then return false end
    if not (pad and pad.Parent and livePad(pad) and isEnabledPart(act)) then return false end
    if cash() < target.price then return false end
    local plot = ownPlot()
    if not plot or not pad:IsDescendantOf(plot) then return false end
    state.lastPurchaseName = target.label
    status('Buying '..target.label..' • '..money(target.price))
    local beforeCash = cash()
    local slot = pad.Parent
    local beforeLevel = slot:GetAttribute('Level')
    local beforeActive = slot:GetAttribute('Active')
    local beforeStage = pad:GetAttribute('Stage')
    local beforePrice = pad:GetAttribute('Price')
    local beforeParent = pad.Parent
    local beforeLocked = pad:GetAttribute('Locked')
    local function confirmed()
        if not pad.Parent or pad.Parent ~= beforeParent then return true end
        if not act.Parent or not isEnabledPart(act) then return true end
        if slot:GetAttribute('Level') ~= beforeLevel or slot:GetAttribute('Active') ~= beforeActive
            or pad:GetAttribute('Stage') ~= beforeStage or pad:GetAttribute('Locked') ~= beforeLocked
            or pad:GetAttribute('Price') ~= beforePrice then return true end
        if target.price > 0 and cash() <= beforeCash - target.price * 0.85 then return true end
        return false
    end
    local _, currentRoot = character()
    if not currentRoot then return false end
    local point = act.Position + Vector3.new(0, math.max(2.5, act.Size.Y/2 + 2.7), 0)
    local dist = (currentRoot.Position - point).Magnitude
    if dist > 3.8 then
        if not tweenTo(point, act.Position, 30) or not alive or not settings.master then
            buttonBackoff[pad] = os.clock() + 9
            return false
        end
    end
    -- Let the character settle on the purchase pad before any executor touch
    -- fallback.  This is also usable without firetouchinterest.
    waitActive(0.26)
    if not confirmed() and alive and settings.master and type(firetouchinterest) == 'function' then
        local _, root = character()
        if root and (root.Position - act.Position).Magnitude < 10 then
            pcall(firetouchinterest,root,act,0)
            task.wait(0.1)
            pcall(firetouchinterest,root,act,1)
        end
    end
    local deadline = os.clock() + 1.6
    while alive and settings.master and not confirmed() and os.clock() < deadline do
        task.wait(0.1)
    end
    if confirmed() then
        state.bought += 1
        state.lastBuy = os.clock()
        state.lastAction = os.clock()
        buttonBackoff[pad] = os.clock() + 2.7
        status('Purchased '..target.label)
        return true
    end
    -- Persistent backoff avoids looping at an inaccessible or server-locked pad.
    buttonBackoff[pad] = os.clock() + 11
    state.failed += 1
    status('Purchase not confirmed: '..target.label)
    return false
end

local nextUpgrade = 0
local function buyPersonal(plot)
    if not settings.personal or not UpgradesConfig or not UpgradeRemote or os.clock()<nextUpgrade then return false end
    local options = {}
    local currentCash = cash()
    local weights = {Income=98,Tips=89,SpongeSize=57,WalkSpeed=15}
    for _,id in ipairs({'Income','Tips','SpongeSize','WalkSpeed'}) do
        local lv = UpgradesConfig.levelOf(id,LP)
        local price = UpgradesConfig.priceFor(id,lv,LP)
        if type(price)=='number' and price>0 and price<=currentCash then
            local item = UpgradesConfig.get(id)
            local current = UpgradesConfig.valueFor(id,lv)
            local after = UpgradesConfig.valueFor(id,lv+1)
            local delta = tonumber(after) and tonumber(current) and current>0 and (after/current - 1) or 0
            local reserve = (settings.smartSpending and 1 + settings.reservePercent/100 or 1)
            -- Do not spend an entire zone-unlock bankroll on personal stats.
            -- Early inexpensive upgrades remain accessible.
            local budgetLimit = math.max(5000, currentCash * 0.12)
            if currentCash >= price*reserve and price <= budgetLimit then
                local score = weights[id] + math.max(0,delta)*100 - math.log10(math.max(price,1))*4
                if id=='SpongeSize' and settings.wash then score += 12 end
                -- Tween movement means the in-game WalkSpeed stat is comparatively weak.
                if id=='WalkSpeed' and settings.useNoclip then score -= 16 end
                table.insert(options, {id=id, level=lv, price=price, score=score})
            end
        end
    end
    table.sort(options, function(a,b) return a.score>b.score end)
    if #options == 0 then return false end
    -- More than one remote per half-second is unnecessary and makes rejection noisy.
    nextUpgrade = os.clock()+0.65
    local pick = options[1]
    local success, accepted = pcall(UpgradeRemote.InvokeServer, UpgradeRemote, 'Buy', pick.id)
    if success and accepted then
        state.bought += 1
        state.lastAction = os.clock()
        status('Upgraded '..pick.id)
        return true
    end
    nextUpgrade = os.clock()+4
    return false
end

local seenBonuses = {}
if bonusSpawn and bonusHit then
    addConnection(bonusSpawn.OnClientEvent:Connect(function(vehicle, id, amount, lifetime, tier, paid)
        if not alive or not settings.bonuses or paid then return end
        if typeof(vehicle) ~= 'Instance' or type(id) ~= 'string' then return end
        local plot = ownPlot()
        if not plot or not vehicle:IsDescendantOf(plot) or not isOwnVehicle(vehicle,plot) then return end
        if seenBonuses[id] then return end
        seenBonuses[id] = os.clock()
        task.spawn(function()
            if alive and settings.bonuses and os.clock() - state.lastBonus >= .18 then
                state.lastBonus = os.clock()
                local success = pcall(bonusHit.FireServer,bonusHit,id)
                if success then
                    state.bonuses += 1 -- outgoing free-claim attempts (server success not confirmed)
                    state.lastAction = os.clock()
                end
            end
        end)
    end))
end
-- Keep idle sessions active without sending additional game remotes.
local virtualUser = game:GetService('VirtualUser')
addConnection(LP.Idled:Connect(function()
    if alive and settings.antiAfk and settings.master then
        pcall(function()
            virtualUser:CaptureController()
            virtualUser:ClickButton2(Vector2.zero)
        end)
    end
end))
local function claimOffline()
    if not settings.offline or not OfflineClaim then return false end
    local value = tonumber(LP:GetAttribute('OfflinePending')) or 0
    if value <= 0 or os.clock() - state.lastOffline < 12 then return false end
    state.lastOffline = os.clock()
    if pcall(OfflineClaim.FireServer, OfflineClaim, 'x1') then
        status('Claiming offline earnings')
        return true
    end
    return false
end
local function unload()
    if not alive then return end
    alive = false
    settings.master = false
    cancelTravel()
    for _, c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(connections)
    if window then pcall(function() window:Destroy() end) end
    if env.__PUCKAFK_WASH_THE_CAR and env.__PUCKAFK_WASH_THE_CAR.Unload == unload then
        env.__PUCKAFK_WASH_THE_CAR = nil
    end
end
env.__PUCKAFK_WASH_THE_CAR = {Unload=unload, State=state, Settings=settings}

window = PuckUI:CreateWindow({
    Name='PuckAFK | Wash the Car', Title='PuckAFK | Wash the Car',
    GuiName='PuckAFK_WashTheCar', ConfigId='Wash_The_Car_70733580049633',
    Width=495, Height=480,
})
window:SetCloseCallback(unload)
local farm = window:CreateTab('Autofarm')
farm:CreateSection('Smart progression')
farm:CreateToggle({Name='Smart Autofarm',CurrentValue=settings.master,Callback=function(v) settings.master=v; if not v then cancelTravel() end end})
farm:CreateToggle({Name='Wash Vehicles',CurrentValue=settings.wash,Callback=function(v) settings.wash=v end})
farm:CreateToggle({Name='Smart Wash Targeting',CurrentValue=settings.washPrioritization,Callback=function(v) settings.washPrioritization=v end})
farm:CreateToggle({Name='Buy Tycoon Equipment & Stations',CurrentValue=settings.purchases,Callback=function(v) settings.purchases=v end})
farm:CreateToggle({Name='Auto Player Upgrades',CurrentValue=settings.personal,Callback=function(v) settings.personal=v end})
farm:CreateSection('Live activity')
statusLabel = farm:CreateLabel('Starting...')
detailLabel = farm:CreateLabel('Waiting for plot')
local options = window:CreateTab('Progression')
options:CreateSection('Expansion')
options:CreateToggle({Name='Unlock New Zones',CurrentValue=settings.zones,Callback=function(v) settings.zones=v end})
options:CreateToggle({Name='Buy Decorations',CurrentValue=settings.decorations,Callback=function(v) settings.decorations=v end})
options:CreateToggle({Name='Buy Station Upgrades',CurrentValue=settings.purchaseUpgrades,Callback=function(v) settings.purchaseUpgrades=v end})
options:CreateToggle({Name='Buy New Stations',CurrentValue=settings.purchaseStations,Callback=function(v) settings.purchaseStations=v end})
options:CreateToggle({Name='Smart Spending Priority',CurrentValue=settings.smartSpending,Callback=function(v) settings.smartSpending=v end})
options:CreateToggle({Name='Prioritize High-Earning Zones',CurrentValue=settings.wealthyZonePriority,Callback=function(v) settings.wealthyZonePriority=v end})
options:CreateToggle({Name='Favor Quick Tips',CurrentValue=settings.fastTips,Callback=function(v) settings.fastTips=v end})
options:CreateSlider({Name='Cash Reserve',Range={0,20},Increment=1,CurrentValue=settings.reservePercent,Suffix='%',Callback=function(v) settings.reservePercent=v end})
options:CreateSection('Free income')
options:CreateToggle({Name='Collect Free Bonuses',CurrentValue=settings.bonuses,Callback=function(v) settings.bonuses=v end})
options:CreateToggle({Name='Claim Offline Earnings (1x)',CurrentValue=settings.offline,Callback=function(v) settings.offline=v end})
local advanced = window:CreateTab('Settings')
advanced:CreateSection('Movement & washing')
advanced:CreateSlider({Name='Tween Speed',Range={40,250},Increment=5,CurrentValue=settings.tweenSpeed,Suffix=' studs/s',Callback=function(v) settings.tweenSpeed=v end})
advanced:CreateSlider({Name='Spray Delay',Range={0.12,0.40},Increment=0.01,CurrentValue=settings.washInterval,Suffix='s',Callback=function(v) settings.washInterval=v end})
advanced:CreateSlider({Name='Wash Batch Size',Range={4,25},Increment=1,CurrentValue=settings.batchSize,Callback=function(v) settings.batchSize=v end})
advanced:CreateSlider({Name='Washing Distance',Range={10,22},Increment=1,CurrentValue=settings.distance,Suffix=' studs',Callback=function(v) settings.distance=v end})
advanced:CreateToggle({Name='Noclip During Tween Only',CurrentValue=settings.useNoclip,Callback=function(v) settings.useNoclip=v end})
advanced:CreateToggle({Name='Automatic Stall Recovery',CurrentValue=settings.autoRecover,Callback=function(v) settings.autoRecover=v end})
advanced:CreateToggle({Name='Anti AFK',CurrentValue=settings.antiAfk,Callback=function(v) settings.antiAfk=v end})
advanced:CreateSection('Controls')
advanced:CreateButton({Name='Unload Script',Callback=unload})

-- Single serialized planner. No independent purchase/movement loops may compete.
task.spawn(function()
    local previousPlot = nil
    local lastUi = 0
    while alive do
        local ok, errorText = pcall(function()
            if os.clock() - lastUi > .6 then
                lastUi = os.clock()
                if statusLabel then statusLabel:Set(state.status) end
                if detailLabel then detailLabel:Set('Cash '..money(cash())..' | '..state.bought..' buys | '..state.sprays..' sprays | '..state.bonuses..' bonuses | '..state.availablePurchasePads..' buyable') end
            end
            local nowCash = cash()
            if nowCash ~= state.lastCash then
                state.lastCash, state.lastCashChange = nowCash, os.clock()
            end
            if not settings.master then status('Paused'); task.wait(.25); return end
            local plot = ownPlot()
            if not plot then status('Waiting for your plot'); task.wait(.65); return end
            if previousPlot ~= plot then
                previousPlot = plot
                buttonBackoff = setmetatable({}, {__mode='k'})
                vehicleBackoff = setmetatable({}, {__mode='k'})
                cancelTravel()
            end
            local _, root = character()
            if not root then status('Respawning'); task.wait(.5); return end
            claimOffline()
            -- Buy active, affordable machinery before personal upgrades so a
            -- continuously affordable Income upgrade cannot starve station buys.
            if settings.purchases then
                local candidates = purchaseCandidates(plot)
                if #candidates>0 and buyPad(candidates[1]) then task.wait(.2); return end
            end
            if settings.personal and buyPersonal(plot) then task.wait(.22); return end
            if settings.wash and doWash(plot) then task.wait(.06); return end
            if settings.autoRecover and os.clock() - state.lastAction > 25 then
                -- Discard transient target backoffs and revisit stations when stream-in finishes.
                vehicleBackoff = setmetatable({}, {__mode='k'})
                faceBlocked = setmetatable({}, {__mode='k'})
                state.lastAction = os.clock()
                status('Rechecking plot & vehicle state')
            else
                status('Waiting for new vehicles or affordable upgrades')
            end
            task.wait(.55)
        end)
        if not ok then
            state.failed += 1
            warn('[PuckAFK Wash][controller] '..tostring(errorText))
            status('Recovering from controller error')
            waitActive(0.8)
        else
            task.wait(.03)
        end
    end
end)

PuckUI:Notify({Title='Wash the Car v1.2',Content='New upgrade pad names supported, smarter purchasing, and late-zone placeholder filtering.',Duration=5})