
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

local LocalPlayer = Players.LocalPlayer

-- State
local aimbotEnabled = true
local silentAimEnabled = false
local wallbangEnabled = false
local alwaysHitEnabled = false
local antiAimEnabled = false
local speedHackEnabled = false
local speedHackValue = 2
local setSpeedHack
local autoShootEnabled = true
local noRecoilEnabled = false
local noSpreadEnabled = false
local noclipEnabled = false
local flyEnabled = false
local flyBodyVel = nil
local flyBodyGyro = nil
local visCheckEnabled = true
local savedTeleportPos = nil
local emoteAnimationId = "71617211320246"
local silentAimKey = Enum.KeyCode.T
local aimbotTargetHead = true
local aimbotTargetBody = false
local aimbotTargetLegs = false
local espNameEnabled = false
local espGlowEnabled = false
local espOutlinesEnabled = false
local espSkeletonEnabled = false
local espBoxEnabled = false
local fovRadius = 60
local cameraFov = 75
local aimbotSmoothness = 0.3
local autoShootCooldown = 0.12
local lastShotTime = 0
local nameColor = Color3.fromRGB(255, 255, 255)
local glowColor = Color3.fromRGB(255, 70, 70)

local colorPresets = {
    Color3.fromRGB(255, 255, 255),
    Color3.fromRGB(255, 80, 80),
    Color3.fromRGB(80, 255, 80),
    Color3.fromRGB(80, 150, 255),
    Color3.fromRGB(255, 255, 80),
    Color3.fromRGB(255, 80, 255),
    Color3.fromRGB(80, 255, 255),
    Color3.fromRGB(255, 150, 80),
    Color3.fromRGB(180, 80, 255),
}

local nameColorIdx = 1
local glowColorIdx = 2
local outlinesColor = Color3.fromRGB(255, 255, 255)
local outlinesColorIdx = 1
local skeletonColor = Color3.fromRGB(80, 255, 80)
local skeletonColorIdx = 3
local espBoxColor = Color3.fromRGB(255, 255, 255)
local espBoxColorIdx = 1

local gui
local panel
local toggleBtnRef = nil
local flyToggleUpdate = nil
local noclipToggleUpdate = nil
local speedToggleUpdate = nil
local fovCircle
local mouseMoveConn
local mouseUpConn
local rainbowConn
local open = true
local aimSmoothCF

-- silent aim keybind state
local listeningForKey = false
local keybindBtnRef = nil

-- auto shoot keybind state
local autoShootKey = Enum.KeyCode.Y
local listeningAutoKey = false
local autoKeyBtnRef = nil

-- drag state (panel)
local panelDragging = false
local panelDragStart = Vector2.new()
local panelPosStart = Vector2.new()
local panelOpenPos = Vector2.new()

-- ESP connection tracking (prevents RenderStepped leaks)
local espConns = {} -- [player] = { tag = conn, glow = conn, outlines = conn, skeleton = conn, box = conn }
local espCharConns = {} -- [player] = CharacterAdded connection
local espSkeleDrawings = {} -- [player] = { {line = Drawing, a = part, b = part}, ... }
local espBoxDrawings = {} -- [player] = Drawing

local function cleanupESP(player)
    if espConns[player] then
        if espConns[player].tag then espConns[player].tag:Disconnect() end
        if espConns[player].glow then espConns[player].glow:Disconnect() end
        if espConns[player].outlines then espConns[player].outlines:Disconnect() end
        if espConns[player].skeleton then espConns[player].skeleton:Disconnect() end
        if espConns[player].box then espConns[player].box:Disconnect() end
        espConns[player] = nil
    end
    if espCharConns[player] then
        espCharConns[player]:Disconnect()
        espCharConns[player] = nil
    end
    if espSkeleDrawings[player] then
        for _, d in ipairs(espSkeleDrawings[player]) do d.line:Remove() end
        espSkeleDrawings[player] = nil
    end
    if espBoxDrawings[player] then
        espBoxDrawings[player]:Remove()
        espBoxDrawings[player] = nil
    end
    if player.Character then
        local t = player.Character:FindFirstChild("ESPTag")
        if t then t:Destroy() end
        local g = player.Character:FindFirstChild("ESPGlow")
        if g then g:Destroy() end
        local o = player.Character:FindFirstChild("ESPOutlines")
        if o then o:Destroy() end
        local s = player.Character:FindFirstChild("ESPSkeleton")
        if s then s:Destroy() end
        local b = player.Character:FindFirstChild("ESPBox")
        if b then b:Destroy() end
    end
end

-- Create FOV circle
local function createFOV()
    if fovCircle then
        return
    end
    local ok, circle = pcall(Drawing.new, "Circle")
    if not ok then return end
    fovCircle = circle
    fovCircle.Radius = fovRadius
    fovCircle.Thickness = 2
    fovCircle.Color = Color3.fromRGB(0, 255, 0)
    fovCircle.Transparency = 0.7
    fovCircle.Filled = false
    fovCircle.Visible = aimbotEnabled
end

local function removeFOV()
    if fovCircle then
        fovCircle:Remove()
        fovCircle = nil
    end
end

-- Line-of-sight check
local function hasLOS(targetPart)
    if not targetPart then
        return false
    end
    if not LocalPlayer or not LocalPlayer.Character then return false end
    local cam = workspace.CurrentCamera
    if not cam then return false end
    local origin = cam.CFrame.Position
    local direction = (targetPart.Position - origin).Unit * 1000

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Blacklist
    params.FilterDescendantsInstances = {LocalPlayer.Character}

    local result = workspace:Raycast(origin, direction, params)
    return result and result.Instance and result.Instance:IsDescendantOf(targetPart.Parent)
end

-- ESP: nametag (name + distance)
local function createESPTag(char, player)
    if not char then return end
    local head = char:FindFirstChild("Head")
    if not head then return end
    if char:FindFirstChild("ESPTag") then return end

    local tag = Instance.new("BillboardGui")
    tag.Name = "ESPTag"
    tag.Size = UDim2.new(0, 120, 0, 28)
    tag.StudsOffset = Vector3.new(0, 2.5, 0)
    tag.AlwaysOnTop = true
    tag.Parent = head

    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "Name"
    nameLabel.Size = UDim2.new(1, 0, 0.5, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.Text = player.Name
    nameLabel.TextColor3 = nameColor
    nameLabel.TextStrokeTransparency = 0.3
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 13
    nameLabel.TextXAlignment = Enum.TextXAlignment.Center
    nameLabel.Parent = tag

    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Distance"
    distLabel.Position = UDim2.new(0, 0, 0.5, 0)
    distLabel.Size = UDim2.new(1, 0, 0.5, 0)
    distLabel.BackgroundTransparency = 1
    distLabel.TextColor3 = nameColor
    distLabel.Font = Enum.Font.Gotham
    distLabel.TextSize = 10
    distLabel.TextStrokeTransparency = 0.3
    distLabel.TextXAlignment = Enum.TextXAlignment.Center
    distLabel.Parent = tag

    local conn = RunService.RenderStepped:Connect(function()
        if not espNameEnabled then tag.Enabled = false return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not root or not cam then tag.Enabled = false return end
        local distance = math.floor((root.Position - cam.CFrame.Position).Magnitude)
        distLabel.Text = tostring(distance) .. "m"
        tag.Enabled = distance <= 300
    end)

    if not espConns[player] then espConns[player] = {} end
    if espConns[player].tag then espConns[player].tag:Disconnect() end
    espConns[player].tag = conn
end

-- ESP: wallhack glow
local function createESPGlow(char, player)
    if not char then return end
    if char:FindFirstChild("ESPGlow") then return end

    local hl = Instance.new("Highlight")
    hl.Name = "ESPGlow"
    hl.FillColor = glowColor
    hl.FillTransparency = 0.45
    hl.OutlineTransparency = 1
    hl.Parent = char

    local conn = RunService.RenderStepped:Connect(function()
        if not espGlowEnabled then hl.Enabled = false return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not root or not cam then hl.Enabled = false return end
        local distance = (root.Position - cam.CFrame.Position).Magnitude
        hl.Enabled = distance <= 300
    end)

    if not espConns[player] then espConns[player] = {} end
    if espConns[player].glow then espConns[player].glow:Disconnect() end
    espConns[player].glow = conn
end

-- ESP: outlines only (no fill)
local function createESPOutlines(char, player)
    if not char then return end
    if char:FindFirstChild("ESPOutlines") then return end

    local hl = Instance.new("Highlight")
    hl.Name = "ESPOutlines"
    hl.FillColor = outlinesColor
    hl.FillTransparency = 1
    hl.OutlineColor = outlinesColor
    hl.OutlineTransparency = 0
    hl.Parent = char

    local conn = RunService.RenderStepped:Connect(function()
        if not espOutlinesEnabled then hl.Enabled = false return end
        local root = char:FindFirstChild("HumanoidRootPart")
        local cam = workspace.CurrentCamera
        if not root or not cam then hl.Enabled = false return end
        local distance = (root.Position - cam.CFrame.Position).Magnitude
        hl.Enabled = distance <= 300
    end)

    if not espConns[player] then espConns[player] = {} end
    if espConns[player].outlines then espConns[player].outlines:Disconnect() end
    espConns[player].outlines = conn
end

-- ESP: skeleton (single-pass build, proximity fallback for any model)
local function getVisualPos(p)
    if p:IsA("MeshPart") and p.Offset then
        return (p.CFrame * CFrame.new(p.Offset)).Position
    end
    return p.Position
end

local function createESPSkeleton(char, player)
    -- Guards
    if not char then return end
    if char:FindFirstChild("ESPSkeleton") then return end
    if not Drawing then return end

    -- Verify Drawing is functional before committing
    local ok, testLine = pcall(Drawing.new, "Line")
    if not ok then return end
    testLine:Remove()

    -- Tag the character so we don't double-register
    local tag = Instance.new("Folder")
    tag.Name = "ESPSkeleton"
    tag.Parent = char

    -- Only look up known parts by exact name — never scan all descendants
    local function getPart(name)
        local p = char:FindFirstChild(name)
        return (p and p:IsA("BasePart")) and p or nil
    end

    -- Build line list, deduplicating by unordered pair key
    local lines = {}
    local used  = {}

    local function addLine(a, b)
        if not a or not b then return end
        local ka, kb = a.Name, b.Name
        local key = (ka < kb) and (ka .. "|" .. kb) or (kb .. "|" .. ka)
        if used[key] then return end
        used[key] = true

        local ln        = Drawing.new("Line")
        ln.Thickness    = 2
        ln.Color        = skeletonColor
        ln.Visible      = false

        table.insert(lines, { line = ln, a = a, b = b })
    end

    -- ── R15 connections ──────────────────────────────────────────────────────
    -- Spine
    addLine(getPart("Head"),            getPart("UpperTorso"))
    addLine(getPart("UpperTorso"),      getPart("LowerTorso"))

    -- Left arm
    addLine(getPart("UpperTorso"),      getPart("LeftUpperArm"))
    addLine(getPart("LeftUpperArm"),    getPart("LeftLowerArm"))
    addLine(getPart("LeftLowerArm"),    getPart("LeftHand"))

    -- Right arm
    addLine(getPart("UpperTorso"),      getPart("RightUpperArm"))
    addLine(getPart("RightUpperArm"),   getPart("RightLowerArm"))
    addLine(getPart("RightLowerArm"),   getPart("RightHand"))

    -- Left leg
    addLine(getPart("LowerTorso"),      getPart("LeftUpperLeg"))
    addLine(getPart("LeftUpperLeg"),    getPart("LeftLowerLeg"))
    addLine(getPart("LeftLowerLeg"),    getPart("LeftFoot"))

    -- Right leg
    addLine(getPart("LowerTorso"),      getPart("RightUpperLeg"))
    addLine(getPart("RightUpperLeg"),   getPart("RightLowerLeg"))
    addLine(getPart("RightLowerLeg"),   getPart("RightFoot"))

    -- ── R6 fallback (addLine no-ops on nil, so safe to always call) ──────────
    -- HumanoidRootPart intentionally omitted — it overlaps Torso/LowerTorso
    -- and produces a near-zero stub that looks like a floating artefact
    addLine(getPart("Head"),        getPart("Torso"))
    addLine(getPart("Torso"),       getPart("Left Arm"))
    addLine(getPart("Torso"),       getPart("Right Arm"))
    addLine(getPart("Torso"),       getPart("Left Leg"))
    addLine(getPart("Torso"),       getPart("Right Leg"))

    -- Nothing to draw (unsupported rig or all nil)
    if #lines == 0 then
        tag:Destroy()
        return
    end

    -- Remove any previous drawings for this player
    if espSkeleDrawings[player] then
        for _, d in ipairs(espSkeleDrawings[player]) do
            d.line:Remove()
        end
    end
    espSkeleDrawings[player] = lines

    -- ── Per-frame update ─────────────────────────────────────────────────────
    local conn = RunService.RenderStepped:Connect(function()
        -- Hide all and bail when the feature is toggled off
        if not espSkeletonEnabled then
            for _, d in ipairs(lines) do
                d.line.Visible = false
            end
            return
        end

        local cam = workspace.CurrentCamera
        if not cam then
            for _, d in ipairs(lines) do
                d.line.Visible = false
            end
            return
        end

        for _, d in ipairs(lines) do
            -- Part has been removed from the workspace (death / respawn)
            if not d.a or not d.b or not d.a.Parent or not d.b.Parent then
                d.line.Visible = false
                continue
            end

            -- WorldToViewportPoint: coords are in full-screen space, which is
            -- exactly what the Drawing library uses.  WorldToScreenPoint is
            -- offset by the CoreGui inset (~36 px) and causes the "floating"
            -- artefact where lines sit above the character.
            local aScr, aVis = cam:WorldToViewportPoint(d.a.Position)
            local bScr, bVis = cam:WorldToViewportPoint(d.b.Position)

            if aVis and bVis and aScr.Z > 0 and bScr.Z > 0 then
                d.line.From    = Vector2.new(aScr.X, aScr.Y)
                d.line.To      = Vector2.new(bScr.X, bScr.Y)
                d.line.Visible = true
            else
                d.line.Visible = false
            end
        end
    end)

    -- ── Connection bookkeeping ────────────────────────────────────────────────
    if not espConns[player] then
        espConns[player] = {}
    end

    if espConns[player].skeleton then
        espConns[player].skeleton:Disconnect()
    end

    espConns[player].skeleton = conn
end

-- ESP: 2D boxes (root-centered)
local function createESPBox(char, player)
    if not char then return end
    if char:FindFirstChild("ESPBox") then return end
    if not Drawing then return end

    Instance.new("Folder", char).Name = "ESPBox"

    local ok, square = pcall(Drawing.new, "Square")
    if not ok then return end
    square.Thickness = 2
    square.Color = espBoxColor
    square.Filled = false
    square.Visible = false

    if espBoxDrawings[player] then
        espBoxDrawings[player]:Remove()
    end
    espBoxDrawings[player] = square

    local conn = RunService.RenderStepped:Connect(function()
        if not espBoxEnabled then
            square.Visible = false
            return
        end

        local cam = workspace.CurrentCamera
        if not cam or not char.Parent then
            square.Visible = false
            return
        end

        local root = char:FindFirstChild("HumanoidRootPart")
            or char:FindFirstChild("Torso")
            or char:FindFirstChild("LowerTorso")
        local head = char:FindFirstChild("Head")
        if not root or not head then
            square.Visible = false
            return
        end

        -- Fix 1: root is at waist; subtract ~3 studs to estimate feet
        local feetPos = root.Position - Vector3.new(0, 3, 0)
        local headTop = head.Position  + Vector3.new(0, 0.6, 0)

        local topVP = cam:WorldToViewportPoint(headTop)
        local botVP = cam:WorldToViewportPoint(feetPos)

        -- Fix 2: hide if either point is behind the camera (Z <= 0)
        if topVP.Z <= 0 or botVP.Z <= 0 then
            square.Visible = false
            return
        end

        -- Fix 3: use min/max instead of assuming which is higher on screen
        local minY   = math.min(topVP.Y, botVP.Y)
        local maxY   = math.max(topVP.Y, botVP.Y)
        local height = maxY - minY

        if height < 4 then
            square.Visible = false
            return
        end

        local width   = height * 0.65
        local centerX = (topVP.X + botVP.X) * 0.5

        square.Position = Vector2.new(centerX - width * 0.5, minY)
        square.Size     = Vector2.new(width, height)
        square.Color    = espBoxColor
        square.Visible  = true
    end)

    if not espConns[player] then espConns[player] = {} end
    if espConns[player].box then espConns[player].box:Disconnect() end
    espConns[player].box = conn
end

-- Apply ESP features to a player (persists on respawn)
local function setupESP(player)
    local function apply(char)
        if not char then return end
        if espNameEnabled then createESPTag(char, player) end
        if espGlowEnabled then createESPGlow(char, player) end
        if espOutlinesEnabled then createESPOutlines(char, player) end
        if espSkeletonEnabled then createESPSkeleton(char, player) end
        if espBoxEnabled then createESPBox(char, player) end
    end

    if player.Character then
        apply(player.Character)
    end

    if espCharConns[player] then espCharConns[player]:Disconnect() end
    espCharConns[player] = player.CharacterAdded:Connect(function(char)
        task.wait(1)
        apply(char)
    end)
end

-- Clear all ESP features
local function clearAllESP()
    for _, p in ipairs(Players:GetPlayers()) do
        cleanupESP(p)
    end
end

-- Update existing ESP colors
local function updateNameColor()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local tag = p.Character:FindFirstChild("ESPTag")
            if tag then
                local nameL = tag:FindFirstChild("Name")
                local distL = tag:FindFirstChild("Distance")
                if nameL then nameL.TextColor3 = nameColor end
                if distL then distL.TextColor3 = nameColor end
            end
        end
    end
end

local function updateGlowColor()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local glow = p.Character:FindFirstChild("ESPGlow")
            if glow then glow.FillColor = glowColor end
        end
    end
end

local function cycleNameColor()
    nameColorIdx = nameColorIdx % #colorPresets + 1
    nameColor = colorPresets[nameColorIdx]
    updateNameColor()
end

local function cycleGlowColor()
    glowColorIdx = glowColorIdx % #colorPresets + 1
    glowColor = colorPresets[glowColorIdx]
    updateGlowColor()
end

local function updateOutlinesColor()
    for _, p in ipairs(Players:GetPlayers()) do
        if p.Character then
            local outlines = p.Character:FindFirstChild("ESPOutlines")
            if outlines then
                outlines.FillColor = outlinesColor
                outlines.OutlineColor = outlinesColor
            end
        end
    end
end

local function cycleOutlinesColor()
    outlinesColorIdx = outlinesColorIdx % #colorPresets + 1
    outlinesColor = colorPresets[outlinesColorIdx]
    updateOutlinesColor()
end

local function updateSkeletonColor()
    for _, p in ipairs(Players:GetPlayers()) do
        if espSkeleDrawings[p] then
            for _, d in ipairs(espSkeleDrawings[p]) do
                d.line.Color = skeletonColor
            end
        end
    end
end

local function cycleSkeletonColor()
    skeletonColorIdx = skeletonColorIdx % #colorPresets + 1
    skeletonColor = colorPresets[skeletonColorIdx]
    updateSkeletonColor()
end

local function updateBoxColor()
    for _, p in ipairs(Players:GetPlayers()) do
        if espBoxDrawings[p] then espBoxDrawings[p].Color = espBoxColor end
    end
end

local function cycleBoxColor()
    espBoxColorIdx = espBoxColorIdx % #colorPresets + 1
    espBoxColor = colorPresets[espBoxColorIdx]
    updateBoxColor()
end

-- Aimbot core loop
local function startAimbotLoop()
    RunService.RenderStepped:Connect(function()
        local cam = workspace.CurrentCamera
        if not cam then return end

        local aimbotActive = aimbotEnabled
        local silentActive = silentAimEnabled
        local autoActive = autoShootEnabled

        if not aimbotActive and not silentActive and not autoActive then
            if fovCircle then fovCircle.Visible = false end
            aimSmoothCF = nil
            return
        end

        local vp = cam.ViewportSize
        local center = Vector2.new(vp.X / 2, vp.Y / 2)

        -- FOV circle (only for visible aimbot)
        if aimbotActive then
            if not fovCircle then createFOV() end
            fovCircle.Position = center
            fovCircle.Visible = true
        else
            if fovCircle then fovCircle.Visible = false end
        end

        -- collect candidate part names from enabled toggles
        local candidates = {}
        if aimbotTargetHead then candidates[1] = "Head" end
        if aimbotTargetBody then
            candidates[#candidates + 1] = "HumanoidRootPart"
            candidates[#candidates + 1] = "UpperTorso"
            candidates[#candidates + 1] = "LowerTorso"
            candidates[#candidates + 1] = "Torso"
        end
        if aimbotTargetLegs then
            candidates[#candidates + 1] = "LeftUpperLeg"
            candidates[#candidates + 1] = "RightUpperLeg"
            candidates[#candidates + 1] = "LeftLowerLeg"
            candidates[#candidates + 1] = "RightLowerLeg"
            candidates[#candidates + 1] = "Left Leg"
            candidates[#candidates + 1] = "Right Leg"
        end

        -- find closest visible target part inside FOV
        local targetPart = nil
        local shortest = math.huge

        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and p.Character then
                local humanoid = p.Character:FindFirstChild("Humanoid")
                if not humanoid or humanoid.Health <= 0 then continue end
                if LocalPlayer.Team and p.Team and p.Team == LocalPlayer.Team then continue end
                for _, partName in ipairs(candidates) do
                    local part = p.Character:FindFirstChild(partName)
                    if part then
                        local screenPos, onScreen = cam:WorldToScreenPoint(part.Position)
                        if onScreen then
                            local d = (Vector2.new(screenPos.X, screenPos.Y) - center).Magnitude
                            if d < fovRadius and d < shortest and (wallbangEnabled or not visCheckEnabled or hasLOS(part)) then
                                shortest = d
                                targetPart = part
                            end
                        end
                    end
                end
            end
        end

        if targetPart and targetPart.Parent then
            local targetCF = CFrame.new(cam.CFrame.Position, targetPart.Position)
            -- smooth target
            if aimbotSmoothness > 0 then
                if not aimSmoothCF then aimSmoothCF = targetCF end
                aimSmoothCF = aimSmoothCF:Lerp(targetCF, 1 - aimbotSmoothness)
                targetCF = aimSmoothCF
            else
                aimSmoothCF = nil
            end
            -- aimbot (smooth snap)
            if aimbotActive then
                cam.CFrame = targetCF
            end
            -- silent aim (redirect camera while mouse is held)
            if silentActive and UserInputService:IsKeyDown(silentAimKey) then
                cam.CFrame = targetCF
            end
            -- auto-shoot
            if autoActive then
                local now = tick()
                if now - lastShotTime >= autoShootCooldown then
                    if silentActive then cam.CFrame = targetCF end
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
                    VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
                    lastShotTime = now
                end
            end
        else
            aimSmoothCF = nil
        end

        -- no recoil
        if noRecoilEnabled and LocalPlayer.Character then
            local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
            if tool then
                for _, v in ipairs(tool:GetDescendants()) do
                    if v:IsA("NumberValue") and (v.Name:lower():find("recoil") or v.Name:lower():find("bloom") or v.Name:lower():find("spread")) then
                        v.Value = 0
                    end
                end
            end
            for _, v in ipairs(LocalPlayer.Character:GetDescendants()) do
                if v:IsA("NumberValue") and (v.Name:lower():find("recoil") or v.Name:lower():find("camerashake")) then
                    v.Value = 0
                end
            end
        end

        -- no spread
        if noSpreadEnabled and LocalPlayer.Character then
            local tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
            if tool then
                for _, v in ipairs(tool:GetDescendants()) do
                    if v:IsA("NumberValue") and (v.Name:lower():find("spread") or v.Name:lower():find("bloom") or v.Name:lower():find("accuracy")) then
                        v.Value = 0
                    end
                end
            end
        end
    end)
end

-- Noclip loop: disable collision on local character while enabled
local function startNoclipLoop()
    RunService.Stepped:Connect(function()
        if not noclipEnabled or not LocalPlayer.Character then return end
        for _, part in ipairs(LocalPlayer.Character:GetDescendants()) do
            if part:IsA("BasePart") then
                part.CanCollide = false
            end
        end
    end)
end

-- Fly loop: WASD + Space/LeftCtrl, oriented to camera
local function clearFly()
    if flyBodyVel then pcall(function() flyBodyVel:Destroy() end) end
    if flyBodyGyro then pcall(function() flyBodyGyro:Destroy() end) end
    flyBodyVel = nil
    flyBodyGyro = nil
end

local function startFlyLoop()
    RunService.RenderStepped:Connect(function()
        if not flyEnabled then return end
        local char = LocalPlayer.Character
        if not char then return end
        local root = char:FindFirstChild("HumanoidRootPart")
        if not root then return end

        -- (re)create movers (handles respawn)
        local valid = flyBodyVel and flyBodyGyro and pcall(function() return flyBodyVel.Parent == root end)
        if not valid then
            clearFly()
            flyBodyVel = Instance.new("BodyVelocity")
            flyBodyVel.MaxForce = Vector3.new(1e5, 1e5, 1e5)
            flyBodyVel.Velocity = Vector3.new()
            flyBodyVel.Parent = root
            flyBodyGyro = Instance.new("BodyGyro")
            flyBodyGyro.MaxTorque = Vector3.new(1e5, 1e5, 1e5)
            flyBodyGyro.P = 9e4
            flyBodyGyro.Parent = root
        end

        local cam = workspace.CurrentCamera
        if not cam then return end
        flyBodyGyro.CFrame = cam.CFrame

        local dir = Vector3.new()
        local forward = cam.CFrame.LookVector
        local right = cam.CFrame.RightVector
        if UserInputService:IsKeyDown(Enum.KeyCode.W) then dir = dir + forward end
        if UserInputService:IsKeyDown(Enum.KeyCode.S) then dir = dir - forward end
        if UserInputService:IsKeyDown(Enum.KeyCode.A) then dir = dir - right end
        if UserInputService:IsKeyDown(Enum.KeyCode.D) then dir = dir + right end
        if UserInputService:IsKeyDown(Enum.KeyCode.Space) then dir = dir + Vector3.new(0, 1, 0) end
        if UserInputService:IsKeyDown(Enum.KeyCode.LeftControl) then dir = dir - Vector3.new(0, 1, 0) end
        if dir.Magnitude > 0 then dir = dir.Unit * 50 end
        flyBodyVel.Velocity = dir
    end)
end

-- Teleport save/load: "," saves current position, "." teleports there
local function saveTeleportPos()
    if not LocalPlayer.Character then return end
    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    savedTeleportPos = root.CFrame
end

local function teleportToSaved()
    if not savedTeleportPos or not LocalPlayer.Character then return end
    local root = LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.CFrame = savedTeleportPos
end

local function teleportRandomEnemy()
    local targets = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                table.insert(targets, hrp)
            end
        end
    end
    if #targets == 0 then return end
    local char = LocalPlayer.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    root.CFrame = targets[math.random(#targets)].CFrame
end

local function getEnemies()
    local me = LocalPlayer or Players.LocalPlayer
    local myChar = me and me.Character
    local myRoot = myChar and myChar:FindFirstChild("HumanoidRootPart")
    local list = {}
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= me and p.Character and p.Character ~= myChar then
            local hrp = p.Character:FindFirstChild("HumanoidRootPart")
            local hum = p.Character:FindFirstChildOfClass("Humanoid")
            if hrp and hum and hum.Health > 0 then
                local dist = myRoot and (hrp.Position - myRoot.Position).Magnitude or 0
                table.insert(list, { hrp = hrp, dist = dist })
            end
        end
    end
    return me, myChar, myRoot, list
end

-- Always Hit: enlarge enemy character parts locally so your shots connect no matter
-- the aim precision. Client-only (FE-safe) - the server never sees the size change,
-- but your client-side raycast/hit detection does, so bullets register as hits.
local function hitboxApplyChar(char, on)
    if not char then return end
    for _, part in ipairs(char:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "HumanoidRootPart" then
            if on then
                if not part:GetAttribute("AH_OrigSize") then
                    part:SetAttribute("AH_OrigSize", part.Size)
                end
                part.Size = part.Size + Vector3.new(3, 3, 3)
            else
                local o = part:GetAttribute("AH_OrigSize")
                if o then
                    part.Size = o
                    part:SetAttribute("AH_OrigSize", nil)
                end
            end
        end
    end
end

local function hitboxApplyAll(on)
    for _, p in ipairs(Players:GetPlayers()) do
        if p ~= LocalPlayer and p.Character then
            hitboxApplyChar(p.Character, on)
        end
    end
end

local emoteTrack = nil

local function playEmote()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end
    if emoteTrack then
        emoteTrack:Stop()
        emoteTrack = nil
    end
    if emoteAnimationId ~= "" then
        local anim = Instance.new("Animation")
        anim.AnimationId = "rbxassetid://" .. emoteAnimationId
        anim.Parent = char
        local ok, track = pcall(function() return hum:LoadAnimation(anim) end)
        if ok and track then
            emoteTrack = track
            emoteTrack.Looped = true
            emoteTrack.Priority = Enum.AnimationPriority.Action4
            emoteTrack:Play()
        else
            warn("[Emote] failed to load animation " .. tostring(emoteAnimationId) .. " -> " .. tostring(track))
        end
    else
        pcall(function() hum:PlayEmote("Laugh") end)
    end
end

local function respawnLocal()
    if not LocalPlayer then return end
    local char = LocalPlayer.Character
    if char then
        local hum = char:FindFirstChildOfClass("Humanoid")
        if hum and hum.Health > 0 then
            hum.Health = 0
        end
    end
    pcall(function() LocalPlayer:LoadCharacter() end)
end

local function setPanelOpen(state)
    open = state
    if panel then panel.Visible = open end
    if toggleBtnRef then toggleBtnRef.Text = open and "–" or "+" end
end

local function togglePanel()
    setPanelOpen(not open)
end

-- Build GUI and wire controls
local function buildGUI()
    if gui then
        gui:Destroy()
    end

    if mouseMoveConn then mouseMoveConn:Disconnect() end
    if mouseUpConn then mouseUpConn:Disconnect() end
    if rainbowConn then rainbowConn:Disconnect() end

    gui = Instance.new("ScreenGui")
    gui.Name = "FPS_AdminPanel"
    gui.ResetOnSpawn = false
    gui.Parent = LocalPlayer:WaitForChild("PlayerGui")

    -- panel (absolute positioning for drag)
    panel = Instance.new("Frame")
    panel.Name = "Panel"
    panel.Size = UDim2.new(0, 320, 0, 400)
    panel.BackgroundColor3 = Color3.fromRGB(8, 8, 12)
    panel.BorderSizePixel = 0
    panel.ClipsDescendants = true
    panel.Parent = gui

    local panelCorner = Instance.new("UICorner")
    panelCorner.CornerRadius = UDim.new(0, 12)
    panelCorner.Parent = panel

    local panelStroke = Instance.new("UIStroke")
    panelStroke.Color = Color3.fromRGB(30, 30, 40)
    panelStroke.Thickness = 1
    panelStroke.Parent = panel
    panel.Visible = open

    -- title (draggable — TextButton so MouseButton1Down works)
    local title = Instance.new("TextButton")
    title.Name = "Title"
    title.Size = UDim2.new(1, -52, 0, 42)
    title.Position = UDim2.new(0, 14, 0, 0)
    title.BackgroundTransparency = 1
    title.Text = "Weed Niggers"
    title.TextColor3 = Color3.fromRGB(0, 212, 255)
    title.Font = Enum.Font.GothamBold
    title.TextSize = 16
    title.TextXAlignment = Enum.TextXAlignment.Left
    title.Parent = panel

    -- hide/show button (top-right of panel, lives on gui so it stays visible when panel is hidden)
    local toggleBtn = Instance.new("TextButton")
    toggleBtn.Name = "Toggle"
    toggleBtn.Size = UDim2.new(0, 30, 0, 26)
    toggleBtn.Position = UDim2.new(0, 0, 0, 0)
    toggleBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
    toggleBtn.BorderSizePixel = 0
    toggleBtn.Text = "–"
    toggleBtn.TextColor3 = Color3.fromRGB(235, 235, 240)
    toggleBtn.Font = Enum.Font.GothamBold
    toggleBtn.TextSize = 18
    toggleBtn.Parent = gui

    local toggleBtnCorner = Instance.new("UICorner")
    toggleBtnCorner.CornerRadius = UDim.new(0, 6)
    toggleBtnCorner.Parent = toggleBtn

    toggleBtn.MouseButton1Click:Connect(function()
        togglePanel()
    end)
    toggleBtnRef = toggleBtn

    rainbowConn = RunService.RenderStepped:Connect(function()
        title.TextColor3 = Color3.fromHSV(tick() % 1, 1, 1)
    end)

    -- position panel at right side of screen
    local cam = workspace.CurrentCamera
    local vp = cam and cam.ViewportSize or Vector2.new(800, 600)
    panelOpenPos = Vector2.new(vp.X - 330, vp.Y / 2 - 200)
    panel.Position = UDim2.fromOffset(panelOpenPos.X, panelOpenPos.Y)
    toggleBtn.Position = UDim2.fromOffset(panelOpenPos.X + 290, panelOpenPos.Y + 8)

    -- drag title bar
    title.MouseButton1Down:Connect(function()
        panelDragging = true
        local mp = UserInputService:GetMouseLocation()
        panelDragStart = Vector2.new(mp.X, mp.Y)
        panelPosStart = panelOpenPos
    end)

    -- content
    local content = Instance.new("ScrollingFrame")
    content.Name = "Content"
    content.Size = UDim2.new(1, -28, 1, -50)
    content.Position = UDim2.new(0, 14, 0, 46)
    content.BackgroundTransparency = 1
    content.BorderSizePixel = 0
    content.ScrollBarThickness = 8
    content.ScrollBarImageColor3 = Color3.fromRGB(45, 45, 55)
    content.AutomaticCanvasSize = Enum.AutomaticSize.Y
    content.Parent = panel

    local rowY = 0
    local sp = 34
    local sliderHandlers = {}
    local sliderUpHandlers = {}

    -- helper: create toggle switch (returns update function)
    local function addToggle(y, label, getState, setState, onActivate, onDeactivate, hasColor, getColor, cycleColor)
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, sp)
        row.Position = UDim2.new(0, 0, 0, y)
        row.BackgroundTransparency = 1
        row.Parent = content

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 0, 1, 0)
        lbl.BackgroundTransparency = 1
        lbl.Text = label
        lbl.TextColor3 = Color3.fromRGB(190, 190, 195)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = row

        -- auto-size label width
        local textWidth = #label * 7 + 10
        lbl.Size = UDim2.new(0, textWidth, 1, 0)

        -- toggle
        local toggleFrame = Instance.new("Frame")
        toggleFrame.Size = UDim2.new(0, 36, 0, 20)
        toggleFrame.Position = UDim2.new(1, -80 - (hasColor and 28 or 0), 0.5, -10)
        toggleFrame.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
        toggleFrame.BorderSizePixel = 0
        toggleFrame.Parent = row

        local toggleCorner = Instance.new("UICorner")
        toggleCorner.CornerRadius = UDim.new(0, 10)
        toggleCorner.Parent = toggleFrame

        local fill = Instance.new("Frame")
        fill.Size = UDim2.new(0, 0, 1, -4)
        fill.Position = UDim2.new(0, 2, 0, 2)
        fill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        fill.BorderSizePixel = 0
        fill.Parent = toggleFrame

        local fillCorner = Instance.new("UICorner")
        fillCorner.CornerRadius = UDim.new(0, 8)
        fillCorner.Parent = fill

        local knob = Instance.new("Frame")
        knob.Size = UDim2.new(0, 16, 0, 16)
        knob.Position = UDim2.new(0, 2, 0, 2)
        knob.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        knob.BorderSizePixel = 0
        knob.Parent = toggleFrame

        local knobCorner = Instance.new("UICorner")
        knobCorner.CornerRadius = UDim.new(0, 8)
        knobCorner.Parent = knob

        local function update()
            local on = getState()
            TweenService:Create(knob, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Position = UDim2.new(0, on and 18 or 2, 0, 2) }):Play()
            TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, on and 32 or 0, 1, -4) }):Play()
        end

        local btn = Instance.new("TextButton")
        btn.Size = UDim2.new(1, 0, 1, 0)
        btn.BackgroundTransparency = 1
        btn.Text = ""
        btn.ZIndex = 5
        btn.Parent = row

        btn.MouseButton1Click:Connect(function()
            local wasOn = getState()
            setState(not wasOn)
            update()
            if not wasOn and onActivate then onActivate() end
            if wasOn and onDeactivate then onDeactivate() end
        end)

        update()

        if hasColor and getColor and cycleColor then
            local swatch = Instance.new("TextButton")
            swatch.Size = UDim2.new(0, 20, 0, 20)
            swatch.Position = UDim2.new(1, -50, 0.5, -10)
            swatch.Text = ""
            swatch.BackgroundColor3 = getColor()
            swatch.BorderSizePixel = 0
            swatch.Parent = row

            local swatchCorner = Instance.new("UICorner")
            swatchCorner.CornerRadius = UDim.new(0, 5)
            swatchCorner.Parent = swatch

            local swatchStroke = Instance.new("UIStroke")
            swatchStroke.Color = Color3.fromRGB(55, 55, 65)
            swatchStroke.Thickness = 1
            swatchStroke.Parent = swatch

            swatch.MouseButton1Click:Connect(function()
                cycleColor()
                swatch.BackgroundColor3 = getColor()
            end)
        end

        return y + sp, update
    end

    -- aimbot
    rowY = addToggle(rowY, "Aimbot",
        function() return aimbotEnabled end,
        function(v) aimbotEnabled = v end,
        function() if not fovCircle then createFOV() end end,
        function() removeFOV() end
    )

    -- silent aim
    rowY = addToggle(rowY, "Silent Aim",
        function() return silentAimEnabled end,
        function(v) silentAimEnabled = v end,
        nil, nil
    )

    -- always hit (big hitboxes)
    rowY = addToggle(rowY, "Always Hit",
        function() return alwaysHitEnabled end,
        function(v)
            alwaysHitEnabled = v
            hitboxApplyAll(v)
        end,
        nil, nil
    )

    -- silent aim keybind row
    do
        local y = rowY
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.Position = UDim2.new(0, 0, 0, y)
        row.BackgroundTransparency = 1
        row.Parent = content

        local keyLabel = Instance.new("TextLabel")
        keyLabel.Size = UDim2.new(0, 60, 1, 0)
        keyLabel.BackgroundTransparency = 1
        keyLabel.Text = "Silent Key"
        keyLabel.TextColor3 = Color3.fromRGB(150, 150, 155)
        keyLabel.Font = Enum.Font.Gotham
        keyLabel.TextSize = 12
        keyLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyLabel.Parent = row

        local keyBtn = Instance.new("TextButton")
        keyBtn.Size = UDim2.new(0, 42, 0, 22)
        keyBtn.Position = UDim2.new(1, -48, 0.5, -11)
        keyBtn.Text = silentAimKey.Name
        keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        keyBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        keyBtn.BorderSizePixel = 0
        keyBtn.Font = Enum.Font.GothamBold
        keyBtn.TextSize = 12
        keyBtn.Parent = row

        local keyCorner = Instance.new("UICorner")
        keyCorner.CornerRadius = UDim.new(0, 4)
        keyCorner.Parent = keyBtn

        keybindBtnRef = keyBtn
        keyBtn.MouseButton1Click:Connect(function()
            listeningForKey = not listeningForKey
            keyBtn.Text = listeningForKey and "..." or silentAimKey.Name
            keyBtn.BackgroundColor3 = listeningForKey and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(40, 40, 50)
        end)
        rowY = rowY + 34
    end

    -- wallbang (ignore LOS)
    rowY = addToggle(rowY, "Wallbang",
        function() return wallbangEnabled end,
        function(v) wallbangEnabled = v end,
        nil, nil
    )

    -- auto shoot
    rowY = addToggle(rowY, "Auto Shoot",
        function() return autoShootEnabled end,
        function(v) autoShootEnabled = v end,
        nil, nil
    )

    -- auto shoot keybind row
    do
        local y = rowY
        local row = Instance.new("Frame")
        row.Size = UDim2.new(1, 0, 0, 32)
        row.Position = UDim2.new(0, 0, 0, y)
        row.BackgroundTransparency = 1
        row.Parent = content

        local keyLabel = Instance.new("TextLabel")
        keyLabel.Size = UDim2.new(0, 60, 1, 0)
        keyLabel.BackgroundTransparency = 1
        keyLabel.Text = "Auto Key"
        keyLabel.TextColor3 = Color3.fromRGB(150, 150, 155)
        keyLabel.Font = Enum.Font.Gotham
        keyLabel.TextSize = 12
        keyLabel.TextXAlignment = Enum.TextXAlignment.Left
        keyLabel.Parent = row

        local keyBtn = Instance.new("TextButton")
        keyBtn.Size = UDim2.new(0, 42, 0, 22)
        keyBtn.Position = UDim2.new(1, -48, 0.5, -11)
        keyBtn.Text = autoShootKey.Name
        keyBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        keyBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        keyBtn.BorderSizePixel = 0
        keyBtn.Font = Enum.Font.GothamBold
        keyBtn.TextSize = 12
        keyBtn.Parent = row

        local keyCorner = Instance.new("UICorner")
        keyCorner.CornerRadius = UDim.new(0, 4)
        keyCorner.Parent = keyBtn

        autoKeyBtnRef = keyBtn
        keyBtn.MouseButton1Click:Connect(function()
            listeningAutoKey = not listeningAutoKey
            keyBtn.Text = listeningAutoKey and "..." or autoShootKey.Name
            keyBtn.BackgroundColor3 = listeningAutoKey and Color3.fromRGB(180, 60, 60) or Color3.fromRGB(40, 40, 50)
        end)
        rowY = rowY + 34
    end

    rowY = addToggle(rowY, "No Recoil",
        function() return noRecoilEnabled end,
        function(v) noRecoilEnabled = v end,
        nil, nil
    )

    rowY = addToggle(rowY, "No Spread",
        function() return noSpreadEnabled end,
        function(v) noSpreadEnabled = v end,
        nil, nil
    )

    rowY, noclipToggleUpdate = addToggle(rowY, "Noclip",
        function() return noclipEnabled end,
        function(v) noclipEnabled = v end,
        nil, nil
    )

    rowY, flyToggleUpdate = addToggle(rowY, "Fly",
        function() return flyEnabled end,
        function(v) flyEnabled = v end,
        nil, clearFly
    )

    rowY = addToggle(rowY, "Vis Check",
        function() return visCheckEnabled end,
        function(v) visCheckEnabled = v end,
        nil, nil
    )

    -- defense against other players' aimbots
    rowY = addToggle(rowY, "Anti-Aim",
        function() return antiAimEnabled end,
        function(v) antiAimEnabled = v end,
        nil, nil
    )

    -- speed hack toggle
    rowY, speedToggleUpdate = addToggle(rowY, "Speed",
        function() return speedHackEnabled end,
        function(v) setSpeedHack(v) end,
        nil, nil
    )

    -- thin line separator
    do
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, 0, 0, 1)
        sep.Position = UDim2.new(0, 0, 0, rowY)
        sep.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        sep.BorderSizePixel = 0
        sep.Parent = content
        rowY = rowY + 10
    end

    -- teleport buttons (save with "," / teleport with ".")
    do
        local y = rowY
        local btnW = 60
        local gap = 8

        local lbl = Instance.new("TextLabel")
        lbl.Size = UDim2.new(0, 70, 0, 24)
        lbl.Position = UDim2.new(0, 0, 0, y)
        lbl.BackgroundTransparency = 1
        lbl.Text = "Teleport"
        lbl.TextColor3 = Color3.fromRGB(190, 190, 195)
        lbl.Font = Enum.Font.Gotham
        lbl.TextSize = 12
        lbl.TextXAlignment = Enum.TextXAlignment.Left
        lbl.Parent = content

        local function mkBtn(text, x, cb)
            local b = Instance.new("TextButton")
            b.Size = UDim2.new(0, btnW, 0, 24)
            b.Position = UDim2.new(0, x, 0, y)
            b.Text = text
            b.TextColor3 = Color3.fromRGB(255, 255, 255)
            b.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            b.BorderSizePixel = 0
            b.Font = Enum.Font.GothamBold
            b.TextSize = 11
            b.Parent = content
            local c = Instance.new("UICorner")
            c.CornerRadius = UDim.new(0, 4)
            c.Parent = b
            b.MouseButton1Click:Connect(cb)
            return b
        end

        mkBtn("Save (,)", 72, saveTeleportPos)
        mkBtn("TP (.)", 72 + btnW + gap, teleportToSaved)
        mkBtn("Respawn (8)", 72 + (btnW + gap) * 2, respawnLocal)

        local rndBtn = Instance.new("TextButton")
        rndBtn.Size = UDim2.new(0, 110, 0, 24)
        rndBtn.Position = UDim2.new(0, 72, 0, y + 30)
        rndBtn.Text = "TP Random (7)"
        rndBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        rndBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        rndBtn.BorderSizePixel = 0
        rndBtn.Font = Enum.Font.GothamBold
        rndBtn.TextSize = 11
        rndBtn.Parent = content
        local rndCorner = Instance.new("UICorner")
        rndCorner.CornerRadius = UDim.new(0, 4)
        rndCorner.Parent = rndBtn
        rndBtn.MouseButton1Click:Connect(teleportRandomEnemy)

        local emoteBtn = Instance.new("TextButton")
        emoteBtn.Size = UDim2.new(0, 110, 0, 24)
        emoteBtn.Position = UDim2.new(0, 72, 0, y + 86)
        emoteBtn.Text = "Emote (4)"
        emoteBtn.TextColor3 = Color3.fromRGB(255, 255, 255)
        emoteBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
        emoteBtn.BorderSizePixel = 0
        emoteBtn.Font = Enum.Font.GothamBold
        emoteBtn.TextSize = 11
        emoteBtn.Parent = content
        local emoteCorner = Instance.new("UICorner")
        emoteCorner.CornerRadius = UDim.new(0, 4)
        emoteCorner.Parent = emoteBtn
        emoteBtn.MouseButton1Click:Connect(playEmote)

        rowY = y + 118
    end

    -- aimbot target part pills
    do
        local pillData = {
            {"Head", function() return aimbotTargetHead end, function(v) aimbotTargetHead = v end},
            {"Body", function() return aimbotTargetBody end, function(v) aimbotTargetBody = v end},
            {"Legs", function() return aimbotTargetLegs end, function(v) aimbotTargetLegs = v end},
        }
        local pillW = 54
        local pillH = 22
        local gap = 6
        local startX = 4
        local pillSetters = {}
        local pillUpdaters = {}

        for i, pd in ipairs(pillData) do
            local label, get, set = table.unpack(pd)
            local x = startX + (i - 1) * (pillW + gap)

            local pill = Instance.new("Frame")
            pill.Size = UDim2.new(0, pillW, 0, pillH)
            pill.Position = UDim2.new(0, x, 0, rowY)
            pill.BackgroundColor3 = Color3.fromRGB(45, 45, 55)
            pill.BorderSizePixel = 0
            pill.ClipsDescendants = true
            pill.Parent = content

            local pillCorner = Instance.new("UICorner")
            pillCorner.CornerRadius = UDim.new(0, 11)
            pillCorner.Parent = pill

            local fill = Instance.new("Frame")
            fill.Size = UDim2.new(0, 0, 1, 0)
            fill.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
            fill.BorderSizePixel = 0
            fill.Parent = pill

            local fillCorner = Instance.new("UICorner")
            fillCorner.CornerRadius = UDim.new(0, 11)
            fillCorner.Parent = fill

            local btn = Instance.new("TextButton")
            btn.Size = UDim2.new(1, 0, 1, 0)
            btn.BackgroundTransparency = 1
            btn.Text = label
            btn.TextColor3 = Color3.fromRGB(150, 150, 155)
            btn.Font = Enum.Font.Gotham
            btn.TextSize = 11
            btn.Parent = pill

            local function updatePill()
                local on = get()
                TweenService:Create(fill, TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = UDim2.new(0, on and pillW or 0, 1, 0) }):Play()
                btn.TextColor3 = on and Color3.fromRGB(255, 255, 255) or Color3.fromRGB(150, 150, 155)
            end

            btn.MouseButton1Click:Connect(function()
                if get() then return end
                for _, s in ipairs(pillSetters) do s(false) end
                set(true)
                for _, u in ipairs(pillUpdaters) do u() end
            end)

            table.insert(pillSetters, set)
            table.insert(pillUpdaters, updatePill)
            updatePill()
        end
        rowY = rowY + pillH + 4
    end

    rowY = rowY + 2

    -- thin line separator
    do
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, 0, 0, 1)
        sep.Position = UDim2.new(0, 0, 0, rowY)
        sep.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        sep.BorderSizePixel = 0
        sep.Parent = content
        rowY = rowY + 10
    end

    -- ESP rows
    local espRowData = {
        {"Name Tag", function() return espNameEnabled end, function(v) espNameEnabled = v end, "ESPTag", cycleNameColor, function() return nameColor end},
        {"Glow", function() return espGlowEnabled end, function(v) espGlowEnabled = v end, "ESPGlow", cycleGlowColor, function() return glowColor end},
        {"Outlines", function() return espOutlinesEnabled end, function(v) espOutlinesEnabled = v end, "ESPOutlines", cycleOutlinesColor, function() return outlinesColor end},
        {"Skeleton", function() return espSkeletonEnabled end, function(v) espSkeletonEnabled = v end, "ESPSkeleton", cycleSkeletonColor, function() return skeletonColor end},
        {"Box", function() return espBoxEnabled end, function(v) espBoxEnabled = v end, "ESPBox", cycleBoxColor, function() return espBoxColor end},
    }

    for _, d in ipairs(espRowData) do
        local label, get, set, childName, cycleCol, getCol = table.unpack(d)
        local function activate()
            for _, p in ipairs(Players:GetPlayers()) do
                if p ~= LocalPlayer then setupESP(p) end
            end
        end
        local function deactivate()
            for _, p in ipairs(Players:GetPlayers()) do
                if childName == "ESPSkeleton" then
                    if espSkeleDrawings[p] then
                        for _, dr in ipairs(espSkeleDrawings[p]) do dr.line:Remove() end
                        espSkeleDrawings[p] = nil
                    end
                    if espConns[p] and espConns[p].skeleton then
                        espConns[p].skeleton:Disconnect()
                        espConns[p].skeleton = nil
                    end
                elseif childName == "ESPBox" then
                    if espBoxDrawings[p] then
                        espBoxDrawings[p]:Remove()
                        espBoxDrawings[p] = nil
                    end
                    if espConns[p] and espConns[p].box then
                        espConns[p].box:Disconnect()
                        espConns[p].box = nil
                    end
                else
                    local connKey
                    if childName == "ESPTag" then connKey = "tag"
                    elseif childName == "ESPGlow" then connKey = "glow"
                    elseif childName == "ESPOutlines" then connKey = "outlines"
                    end
                    if connKey and espConns[p] and espConns[p][connKey] then
                        espConns[p][connKey]:Disconnect()
                        espConns[p][connKey] = nil
                    end
                end
                if p.Character then
                    local inst = p.Character:FindFirstChild(childName)
                    if inst then inst:Destroy() end
                end
            end
        end
        rowY = addToggle(rowY, label, get, set, activate, deactivate, true, getCol, cycleCol)
    end

    rowY = rowY + 2

    -- thin line separator
    do
        local sep = Instance.new("Frame")
        sep.Size = UDim2.new(1, 0, 0, 1)
        sep.Position = UDim2.new(0, 0, 0, rowY)
        sep.BackgroundColor3 = Color3.fromRGB(30, 30, 40)
        sep.BorderSizePixel = 0
        sep.Parent = content
        rowY = rowY + 10
    end

    -- range slider
    do
        local y = rowY

        local rangeLabel = Instance.new("TextLabel")
        rangeLabel.Size = UDim2.new(1, 0, 0, 16)
        rangeLabel.Position = UDim2.new(0, 0, 0, y)
        rangeLabel.Text = "Aimbot FOV " .. fovRadius
        rangeLabel.TextColor3 = Color3.fromRGB(190, 190, 195)
        rangeLabel.BackgroundTransparency = 1
        rangeLabel.Font = Enum.Font.Gotham
        rangeLabel.TextSize = 11
        rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
        rangeLabel.Parent = content

        local trackBg = Instance.new("Frame")
        trackBg.Size = UDim2.new(1, -14, 0, 3)
        trackBg.Position = UDim2.new(0, 0, 0, y + 22)
        trackBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        trackBg.BorderSizePixel = 0
        trackBg.Parent = content

        local trackBgCorner = Instance.new("UICorner")
        trackBgCorner.CornerRadius = UDim.new(0, 2)
        trackBgCorner.Parent = trackBg

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 0, 1, 0)
        track.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        track.BorderSizePixel = 0
        track.Parent = trackBg

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 2)
        trackCorner.Parent = track

        local trackGradient = Instance.new("UIGradient")
        trackGradient.Color = ColorSequence.new{ ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 180, 255)), ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 70, 220)) }
        trackGradient.Parent = track

        local thumb = Instance.new("TextButton")
        thumb.Size = UDim2.new(0, 16, 0, 16)
        thumb.Text = ""
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel = 0
        thumb.Parent = content

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 8)
        thumbCorner.Parent = thumb

        local thumbStroke = Instance.new("UIStroke")
        thumbStroke.Color = Color3.fromRGB(0, 180, 255)
        thumbStroke.Thickness = 2
        thumbStroke.Parent = thumb

        local rangeMin, rangeMax = 50, 500
        local rangeDefault = 160

        local function updateSlider()
            local trackWidth = trackBg.AbsoluteSize.X
            if trackWidth == 0 then return end
            local relX = (fovRadius - rangeMin) / (rangeMax - rangeMin) * trackWidth
            track.Size = UDim2.new(0, relX, 1, 0)
            thumb.Position = UDim2.fromOffset(relX - 8, y + 22 - 7)
            rangeLabel.Text = "Aimbot FOV " .. fovRadius
            if fovCircle then fovCircle.Radius = fovRadius end
        end

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 30)
        hit.Position = UDim2.new(0, 0, 0, y + 6)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 1
        hit.Parent = content
        thumb.ZIndex = 3

        local function setAimFromX(mouseX)
            local tLeft = trackBg.AbsolutePosition.X
            local tWidth = trackBg.AbsoluteSize.X
            if tWidth == 0 then return end
            local relX = math.clamp(mouseX - tLeft, 0, tWidth)
            fovRadius = math.floor(rangeMin + (relX / tWidth) * (rangeMax - rangeMin))
            updateSlider()
        end

        updateSlider()

        local aimDrag = false
        thumb.MouseButton1Down:Connect(function() aimDrag = true end)
        hit.MouseButton1Down:Connect(function()
            setAimFromX(UserInputService:GetMouseLocation().X)
            aimDrag = true
        end)
        thumb.MouseButton2Click:Connect(function()
            fovRadius = rangeDefault
            updateSlider()
        end)

        table.insert(sliderHandlers, function()
            if not aimDrag then return end
            setAimFromX(UserInputService:GetMouseLocation().X)
        end)

        table.insert(sliderUpHandlers, function()
            aimDrag = false
        end)
    end

    rowY = rowY + 45

    -- camera FOV slider
    do
        local y = rowY

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 16)
        label.Position = UDim2.new(0, 0, 0, y)
        label.Text = "Camera FOV " .. cameraFov
        label.TextColor3 = Color3.fromRGB(190, 190, 195)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = content

        local trackBg = Instance.new("Frame")
        trackBg.Size = UDim2.new(1, -14, 0, 3)
        trackBg.Position = UDim2.new(0, 0, 0, y + 22)
        trackBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        trackBg.BorderSizePixel = 0
        trackBg.Parent = content

        local trackBgCorner = Instance.new("UICorner")
        trackBgCorner.CornerRadius = UDim.new(0, 2)
        trackBgCorner.Parent = trackBg

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 0, 1, 0)
        track.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        track.BorderSizePixel = 0
        track.Parent = trackBg

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 2)
        trackCorner.Parent = track

        local thumb = Instance.new("TextButton")
        thumb.Size = UDim2.new(0, 16, 0, 16)
        thumb.Text = ""
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel = 0
        thumb.Parent = content

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 8)
        thumbCorner.Parent = thumb

        local thumbStroke = Instance.new("UIStroke")
        thumbStroke.Color = Color3.fromRGB(0, 180, 255)
        thumbStroke.Thickness = 2
        thumbStroke.Parent = thumb

        local camMin, camMax = 10, 120
        local camDefault = 75

        local function updateCamSlider()
            local trackWidth = trackBg.AbsoluteSize.X
            if trackWidth == 0 then return end
            local relX = (cameraFov - camMin) / (camMax - camMin) * trackWidth
            track.Size = UDim2.new(0, relX, 1, 0)
            thumb.Position = UDim2.fromOffset(relX - 8, y + 22 - 7)
            label.Text = "Camera FOV " .. cameraFov
            local cam = workspace.CurrentCamera
            if cam then cam.FieldOfView = cameraFov end
        end

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 30)
        hit.Position = UDim2.new(0, 0, 0, y + 6)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 1
        hit.Parent = content
        thumb.ZIndex = 3

        local function setCamFromX(mouseX)
            local tLeft = trackBg.AbsolutePosition.X
            local tWidth = trackBg.AbsoluteSize.X
            if tWidth == 0 then return end
            local relX = math.clamp(mouseX - tLeft, 0, tWidth)
            cameraFov = math.floor(camMin + (camMax - camMin) * (relX / tWidth))
            updateCamSlider()
        end

        updateCamSlider()

        local camDrag = false
        thumb.MouseButton1Down:Connect(function() camDrag = true end)
        hit.MouseButton1Down:Connect(function()
            setCamFromX(UserInputService:GetMouseLocation().X)
            camDrag = true
        end)
        thumb.MouseButton2Click:Connect(function()
            cameraFov = camDefault
            updateCamSlider()
        end)

        table.insert(sliderHandlers, function()
            if not camDrag then return end
            setCamFromX(UserInputService:GetMouseLocation().X)
        end)

        table.insert(sliderUpHandlers, function()
            camDrag = false
        end)
    end

    rowY = rowY + 45

    -- smoothness slider
    do
        local y = rowY

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 16)
        label.Position = UDim2.new(0, 0, 0, y)
        label.Text = "Smoothness " .. math.floor(aimbotSmoothness * 100) .. "%"
        label.TextColor3 = Color3.fromRGB(190, 190, 195)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = content

        local trackBg = Instance.new("Frame")
        trackBg.Size = UDim2.new(1, -14, 0, 3)
        trackBg.Position = UDim2.new(0, 0, 0, y + 22)
        trackBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        trackBg.BorderSizePixel = 0
        trackBg.Parent = content

        local trackBgCorner = Instance.new("UICorner")
        trackBgCorner.CornerRadius = UDim.new(0, 2)
        trackBgCorner.Parent = trackBg

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 0, 1, 0)
        track.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        track.BorderSizePixel = 0
        track.Parent = trackBg

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 2)
        trackCorner.Parent = track

        local thumb = Instance.new("TextButton")
        thumb.Size = UDim2.new(0, 16, 0, 16)
        thumb.Text = ""
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel = 0
        thumb.Parent = content

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 8)
        thumbCorner.Parent = thumb

        local thumbStroke = Instance.new("UIStroke")
        thumbStroke.Color = Color3.fromRGB(0, 180, 255)
        thumbStroke.Thickness = 2
        thumbStroke.Parent = thumb

        local smMin, smMax = 0, 0.95
        local smDefault = 0.3

        local function updateSmSlider()
            local trackWidth = trackBg.AbsoluteSize.X
            if trackWidth == 0 then return end
            local relX = (aimbotSmoothness - smMin) / (smMax - smMin) * trackWidth
            track.Size = UDim2.new(0, relX, 1, 0)
            thumb.Position = UDim2.fromOffset(relX - 8, y + 22 - 7)
            label.Text = "Smoothness " .. math.floor(aimbotSmoothness * 100) .. "%"
        end

        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 30)
        hit.Position = UDim2.new(0, 0, 0, y + 6)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 1
        hit.Parent = content
        thumb.ZIndex = 3

        local function setSmFromX(mouseX)
            local tLeft = trackBg.AbsolutePosition.X
            local tWidth = trackBg.AbsoluteSize.X
            if tWidth == 0 then return end
            local relX = math.clamp(mouseX - tLeft, 0, tWidth)
            aimbotSmoothness = smMin + (smMax - smMin) * (relX / tWidth)
            updateSmSlider()
        end

        updateSmSlider()

        local smDrag = false
        thumb.MouseButton1Down:Connect(function() smDrag = true end)
        hit.MouseButton1Down:Connect(function()
            setSmFromX(UserInputService:GetMouseLocation().X)
            smDrag = true
        end)
        thumb.MouseButton2Click:Connect(function()
            aimbotSmoothness = smDefault
            updateSmSlider()
        end)

        table.insert(sliderHandlers, function()
            if not smDrag then return end
            setSmFromX(UserInputService:GetMouseLocation().X)
        end)

        table.insert(sliderUpHandlers, function()
            smDrag = false
        end)
    end

    rowY = rowY + 45

    -- speed multiplier slider
    do
        local y = rowY

        local label = Instance.new("TextLabel")
        label.Size = UDim2.new(1, 0, 0, 16)
        label.Position = UDim2.new(0, 0, 0, y)
        label.Text = "Speed x" .. string.format("%.1f", speedHackValue)
        label.TextColor3 = Color3.fromRGB(190, 190, 195)
        label.BackgroundTransparency = 1
        label.Font = Enum.Font.Gotham
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = content

        local trackBg = Instance.new("Frame")
        trackBg.Size = UDim2.new(1, -14, 0, 3)
        trackBg.Position = UDim2.new(0, 0, 0, y + 22)
        trackBg.BackgroundColor3 = Color3.fromRGB(35, 35, 45)
        trackBg.BorderSizePixel = 0
        trackBg.Parent = content

        local trackBgCorner = Instance.new("UICorner")
        trackBgCorner.CornerRadius = UDim.new(0, 2)
        trackBgCorner.Parent = trackBg

        local track = Instance.new("Frame")
        track.Size = UDim2.new(0, 0, 1, 0)
        track.BackgroundColor3 = Color3.fromRGB(0, 180, 255)
        track.BorderSizePixel = 0
        track.Parent = trackBg

        local trackCorner = Instance.new("UICorner")
        trackCorner.CornerRadius = UDim.new(0, 2)
        trackCorner.Parent = track

        local thumb = Instance.new("TextButton")
        thumb.Size = UDim2.new(0, 16, 0, 16)
        thumb.Text = ""
        thumb.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
        thumb.BorderSizePixel = 0
        thumb.Parent = content

        local thumbCorner = Instance.new("UICorner")
        thumbCorner.CornerRadius = UDim.new(0, 8)
        thumbCorner.Parent = thumb

        local thumbStroke = Instance.new("UIStroke")
        thumbStroke.Color = Color3.fromRGB(0, 180, 255)
        thumbStroke.Thickness = 2
        thumbStroke.Parent = thumb

        local spMin, spMax = 1, 50
        local spDefault = 2

        local function updateSpSlider()
            local trackWidth = trackBg.AbsoluteSize.X
            if trackWidth == 0 then return end
            local relX = (speedHackValue - spMin) / (spMax - spMin) * trackWidth
            track.Size = UDim2.new(0, relX, 1, 0)
            thumb.Position = UDim2.fromOffset(relX - 8, y + 22 - 7)
            label.Text = "Speed x" .. string.format("%.1f", speedHackValue)
        end

        -- wide transparent hit area so clicking anywhere on the row jumps + drags
        local hit = Instance.new("TextButton")
        hit.Size = UDim2.new(1, 0, 0, 30)
        hit.Position = UDim2.new(0, 0, 0, y + 6)
        hit.BackgroundTransparency = 1
        hit.Text = ""
        hit.ZIndex = 1
        hit.Parent = content

        local function setSpFromX(mouseX)
            local tLeft = trackBg.AbsolutePosition.X
            local tWidth = trackBg.AbsoluteSize.X
            if tWidth == 0 then return end
            local relX = math.clamp(mouseX - tLeft, 0, tWidth)
            speedHackValue = spMin + (spMax - spMin) * (relX / tWidth)
            updateSpSlider()
        end

        updateSpSlider()

        thumb.ZIndex = 3
        local spDrag = false
        thumb.MouseButton1Down:Connect(function() spDrag = true end)
        hit.MouseButton1Down:Connect(function()
            setSpFromX(UserInputService:GetMouseLocation().X)
            spDrag = true
        end)
        thumb.MouseButton2Click:Connect(function()
            speedHackValue = spDefault
            updateSpSlider()
        end)

        table.insert(sliderHandlers, function()
            if not spDrag then return end
            setSpFromX(UserInputService:GetMouseLocation().X)
        end)

        table.insert(sliderUpHandlers, function()
            spDrag = false
        end)
    end

    rowY = rowY + 45

    -- shared mouse handlers for panel drag + all sliders
    mouseMoveConn = UserInputService.InputChanged:Connect(function(input)
        if input.UserInputType ~= Enum.UserInputType.MouseMovement then return end
        if not UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            panelDragging = false
            for _, h in ipairs(sliderUpHandlers) do h() end
            return
        end
        if panelDragging then
            local mp = UserInputService:GetMouseLocation()
            local delta = Vector2.new(mp.X, mp.Y) - panelDragStart
            panelOpenPos = panelPosStart + delta
            panel.Position = UDim2.fromOffset(panelOpenPos.X, panelOpenPos.Y)
            toggleBtn.Position = UDim2.fromOffset(panelOpenPos.X + 290, panelOpenPos.Y + 8)
            return
        end
        for _, h in ipairs(sliderHandlers) do h() end
    end)

    mouseUpConn = UserInputService.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            panelDragging = false
            for _, h in ipairs(sliderUpHandlers) do h() end
        end
    end)

end

-- Build GUI and start loops
local function init()
    if not LocalPlayer then
        LocalPlayer = Players.LocalPlayer
        if not LocalPlayer then
            Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
            LocalPlayer = Players.LocalPlayer
        end
    end

    buildGUI()
    startAimbotLoop()
    startNoclipLoop()
    startFlyLoop()

    -- H key toggles panel visibility
    UserInputService.InputBegan:Connect(function(input, gp)
        if UserInputService:GetFocusedTextBox() then return end
        if input.KeyCode == Enum.KeyCode.H then
            togglePanel()
        end
    end)

    -- silent aim + auto shoot keybind listener
    UserInputService.InputBegan:Connect(function(input, gp)
        if UserInputService:GetFocusedTextBox() then return end
        if listeningForKey and input.KeyCode ~= Enum.KeyCode.Unknown then
            silentAimKey = input.KeyCode
            listeningForKey = false
            if keybindBtnRef then
                keybindBtnRef.Text = silentAimKey.Name
                keybindBtnRef.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            end
        elseif listeningAutoKey and input.KeyCode ~= Enum.KeyCode.Unknown then
            autoShootKey = input.KeyCode
            listeningAutoKey = false
            if autoKeyBtnRef then
                autoKeyBtnRef.Text = autoShootKey.Name
                autoKeyBtnRef.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
            end
        elseif not listeningForKey and not listeningAutoKey and input.KeyCode == autoShootKey then
            autoShootEnabled = not autoShootEnabled
        elseif input.KeyCode == Enum.KeyCode.Comma then
            saveTeleportPos()
        elseif input.KeyCode == Enum.KeyCode.Period then
            teleportToSaved()
        elseif input.KeyCode == Enum.KeyCode.Zero then
            flyEnabled = not flyEnabled
            if not flyEnabled then clearFly() end
            if flyToggleUpdate then flyToggleUpdate() end
        elseif input.KeyCode == Enum.KeyCode.Nine then
            noclipEnabled = not noclipEnabled
            if noclipToggleUpdate then noclipToggleUpdate() end
        elseif input.KeyCode == Enum.KeyCode.Eight then
            setSpeedHack(not speedHackEnabled)
            if speedToggleUpdate then speedToggleUpdate() end
        elseif input.KeyCode == Enum.KeyCode.Seven then
            teleportRandomEnemy()
        elseif input.KeyCode == Enum.KeyCode.Backquote then
            respawnLocal()
        elseif input.KeyCode == Enum.KeyCode.Four then
            playEmote()
        end
    end)

    -- keep features consistent after new players join
    Players.PlayerAdded:Connect(function(p)
        if espNameEnabled or espGlowEnabled or espOutlinesEnabled or espSkeletonEnabled or espBoxEnabled then
            setupESP(p)
        end
    end)

    -- Always Hit: enlarge new / respawning enemies so shots connect
    local function connectHitbox(p)
        if p == LocalPlayer then return end
        p.CharacterAdded:Connect(function(c)
            if alwaysHitEnabled then hitboxApplyChar(c, true) end
        end)
        if p.Character then hitboxApplyChar(p.Character, alwaysHitEnabled) end
    end
    Players.PlayerAdded:Connect(connectHitbox)
    for _, p in ipairs(Players:GetPlayers()) do connectHitbox(p) end

    -- cleanup when a player leaves (prevents leaks from RenderStepped connections)
    Players.PlayerRemoving:Connect(function(p)
        cleanupESP(p)
    end)

    -- reapply ESP to existing players if toggled on
    if espNameEnabled or espGlowEnabled or espOutlinesEnabled or espSkeletonEnabled or espBoxEnabled then
        for _, p in ipairs(Players:GetPlayers()) do
            if p ~= LocalPlayer then
                setupESP(p)
            end
        end
    end
end

-- Speed hack setter (forward-declared at top so GUI toggle + keybind can call it)
function setSpeedHack(v)
    speedHackEnabled = v
    if LocalPlayer and LocalPlayer.Character then
        local hum = LocalPlayer.Character:FindFirstChildOfClass("Humanoid")
        if hum then
            if v then
                hum.WalkSpeed = 16 * speedHackValue
            else
                hum.WalkSpeed = 16
            end
        end
    end
end

-- Defense: Godmode (health lock) + Anti-Aim (jitter to break enemy aimbot locks).
-- Runs once, outside buildGUI, so it isn't duplicated on respawn.
RunService.Heartbeat:Connect(function()
    if not LocalPlayer or not LocalPlayer.Character then return end
    local char = LocalPlayer.Character

    if antiAimEnabled then
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hrp then
            -- random yaw each frame so a locking aimbot can't track your head
            hrp.CFrame = hrp.CFrame * CFrame.Angles(0, math.rad(math.random(-30, 30)), 0)
        end
    end

    if speedHackEnabled then
        local hum = char:FindFirstChildOfClass("Humanoid")
        local hrp = char:FindFirstChild("HumanoidRootPart")
        if hum and hrp then
            -- Try WalkSpeed first (works on standard games)
            local target = 16 * speedHackValue
            if hum.WalkSpeed ~= target then
                hum.WalkSpeed = target
            end
            -- Velocity boost: works even when the game overrides WalkSpeed with a
            -- custom controller. Only push while the player is actually moving,
            -- and preserve vertical velocity so gravity/jumps still work.
            local dir = hum.MoveDirection
            if dir.Magnitude > 0 then
                local baseSpeed = 16
                local newVel = dir * baseSpeed * speedHackValue
                hrp.AssemblyLinearVelocity = Vector3.new(newVel.X, hrp.AssemblyLinearVelocity.Y, newVel.Z)
            end
        end
    end
end)

-- Re-apply WalkSpeed the instant the game tries to reset it (many games force 16
-- every frame). Rehooks on each new character.
local wsConn
local function hookWalkSpeed(char)
    if wsConn then wsConn:Disconnect() end
    local hum = char:WaitForChild("Humanoid", 5)
    if not hum then return end
    wsConn = hum:GetPropertyChangedSignal("WalkSpeed"):Connect(function()
        if not speedHackEnabled then return end
        local target = 16 * speedHackValue
        if hum.WalkSpeed ~= target then
            hum.WalkSpeed = target
        end
    end)
end

-- initial run
init()

if LocalPlayer and LocalPlayer.Character then
    hookWalkSpeed(LocalPlayer.Character)
end

-- rebuild GUI after respawn
if LocalPlayer then
    LocalPlayer.CharacterAdded:Connect(function()
        hookWalkSpeed(LocalPlayer.Character)
        task.wait(1)
        buildGUI()
    end)
end
