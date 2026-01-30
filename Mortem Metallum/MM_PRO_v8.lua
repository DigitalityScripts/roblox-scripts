--[[
    MM PRO v8 - ULTIMATE EDITION
    Enhanced based on verified live game analysis
    
    IMPROVEMENTS FROM v7:
    - Added missing attack animation IDs (Shield, Dash, etc.)
    - Kill aura now properly checks IsParrying state before swinging
    - Improved bow aimbot with FOV circle, target priority, and better prediction
    - Added more character state detection (Crawl, Frozen, IsInvincible, etc.)
    - Enhanced ESP with more state indicators
    - Added hitbox expander
    - Better ping compensation
    
    VERIFIED GAME DATA:
    - 42 CharacterInformation values confirmed
    - AimPos/AimRequest remotes for bow
    - All attack animations verified from live gameplay
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")
local LocalPlayer = Players.LocalPlayer
local Camera = Workspace.CurrentCamera

local Modules = ReplicatedStorage:WaitForChild("Modules")
local CharFunClient = require(Modules:WaitForChild("CharFunClient"))


local Events = ReplicatedStorage:WaitForChild("Events")
local Visual = Events:WaitForChild("Visual")
local AimPos = Visual:WaitForChild("AimPos")
local AimRequest = Visual:WaitForChild("AimRequest")
local ArrowReplicate = Events:WaitForChild("ArrowReplicate")
local ROBLOX_INTERPOLATION_DELAY = 0.1

local Stats = game:GetService("Stats")
local function GetPing() 
    local ping = 0.1
    pcall(function() ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000 end)
    return ping
end

local function GetOneWayLatency()
    return GetPing() / 2
end

local function GetNetworkCompensation()
    return GetOneWayLatency() + ROBLOX_INTERPOLATION_DELAY
end

-- PARRY CONSTANTS
local PING_JITTER_BUFFER = 0.02

local Rayfield = loadstring(game:HttpGet('https://sirius.menu/rayfield'))()



-- All verified attack animations (original 29 + new ones found from live game analysis)
local ATTACK_ANIMS = {
    -- Original 29 verified animations
    ["123735079098952"] = true, ["12587812164"] = true, ["12588594047"] = true,
    ["14646201268"] = true, ["14646637871"] = true, ["14647559435"] = true,
    ["14795612864"] = true, ["18781324148"] = true, ["70688005169603"] = true,
    ["8986981647"] = true, ["9017185681"] = true, ["9027616415"] = true,
    ["9027696616"] = true, ["9027992087"] = true, ["9027998635"] = true,
    ["9061947606"] = true, ["9061958351"] = true, ["9070142474"] = true,
    ["9077736277"] = true, ["9077749264"] = true, ["9078040601"] = true,
    ["9091105108"] = true, ["9094150587"] = true, ["9117803523"] = true,
    ["9117946222"] = true, ["9125160646"] = true, ["9133817034"] = true,
    ["9134594915"] = true, ["9134617758"] = true,
    
    -- NEW: Shield animations (verified live)
    ["139417532304331"] = true, -- Shield attack (CRITICAL - was missing!)
    ["117768159132532"] = true, -- Shield Dash
    ["138293746007808"] = true, -- Shield Return
    
    -- NEW: Chainsaw attack animations (verified live from player 'bendmic')
    ["18652227668"] = true,     -- Chainsaw anim2 (actual attack)
    ["10958694908"] = true,     -- Chainsaw OverheadAnim2
    
    -- Misc weapon attacks
    ["18683788650"] = true,     -- Generic weapon attack
    ["9184423585"] = true,      -- Firework throw
    ["9184429176"] = true,      -- Firework turn
    ["3072389950"] = true,      -- Kanabo OverheadAnim2
}

-- Common idle/movement animations to EXCLUDE from chainsaw/continuous weapon detection
local EXCLUDE_ANIMS = {
    -- Standard movement
    ["180435571"] = true, -- idle
    ["180435792"] = true, -- idle variant
    ["180426354"] = true, -- walk/run
    ["125750702"] = true, -- jump
    ["180436148"] = true, -- fall
    ["178130996"] = true, -- sit
    ["180436334"] = true, -- climb
    ["182393478"] = true, -- toolnone
    
    -- Combat actions (not attacks)
    ["9144013465"] = true, -- ParryAnim
    ["8986417922"] = true, -- RollAnim
    ["8986424198"] = true, -- KickAnim
    
    -- Weapon hold/idle animations (CRITICAL: these are NOT attacks!)
    ["8986994076"] = true, -- Chainsaw HOLD animation (verified live - was incorrectly marked as attack)
    ["15432161487"] = true, -- Longbow hold
    ["15440693095"] = true, -- Longbow reload
    ["4499168759"] = true, -- Chainsaw parry animation
}





local Settings = {
    AutoDefense = {
        Enabled = false,
        Range = 15,
    },
    
    KillAura = {
        Enabled = false,
        Range = 10,
        CheckParry = true,      -- Won't swing if enemy is parrying
        CheckRoll = true,       -- Won't swing if enemy is rolling
        CheckInvincible = true, -- Won't swing if enemy has i-frames
        AttackDelay = 0.05,
    },
    
    BowAimbot = {
        Enabled = false,
        Mode = "Closest",           -- Closest, ClosestToCursor, LowestHP
        TargetPart = "Head", -- Head, HumanoidRootPart, UpperTorso
        FOVCheck = true,
        FOVSize = 200,
        ShowFOV = true,
        FOVColor = Color3.fromRGB(255, 255, 255),
        VisibilityCheck = false,
        PredictMovement = true,
    },
    
    Hitbox = {
        Enabled = false,
        Size = 10,
        Transparency = 0.7,
        ExpandHead = true,
        ExpandTorso = true,
    },
    
    ESP = {
        Enabled = false,
        ShowName = true,
        ShowHealth = true,
        ShowDistance = true,
        ShowWeapon = true,
        ShowState = true,
        MaxDistance = 500,
    },
    
    Visuals = {
        ShowBowGhost = false,
        BowGhostColor = Color3.fromRGB(0, 255, 255),
        BowGhostTransparency = 0.6,
        BowGhostRange = 200,
        
        ShowParryGhost = false,
        ParryGhostColor = Color3.fromRGB(255, 80, 80),
        ParryGhostTransparency = 0.6,
        ParryGhostRange = 50,
    },
    
    InfiniteStamina = false
}






-- [[ STATE ]]

local State = {
    lastParryTime = 0,
    lastDashTime = 0,
    lastKillAuraAttack = 0,
    espObjects = {},
    hitboxParts = {},
    originalSizes = {},  -- Store original hitbox sizes
    fovCircle = nil,
    currentTarget = nil,
    bowGhosts = {},           -- Ghost models for bow prediction
    parryGhosts = {},         -- Ghost models for parry/anti-hit prediction
    ghostParts = {},          -- Cached highlight parts
}

-- Ping history for jitter compensation
local PingHistory = {
    samples = {},
    maxSamples = 20,
    lastUpdate = 0,
}

-- Animation tracking for feint detection
local AnimationHistory = {}
local FEINT_COOLDOWN = 0.4  -- How long to remember a feint

-- Velocity smoothing per player (Parry Specific)
local ParryVelocityHistory = {}
local VELOCITY_SAMPLES = 8
local VELOCITY_TIME_WINDOW = 0.25

-- Velocity history for prediction smoothing
local VelocityHistory = {}

local Connections = {}

local PARRY_CONFIG = {
    -- Parry window (seconds before hit) - WIDER for safety
    WindowStart = 0.35,
    WindowEnd = -0.08,
    
    -- Prediction settings
    MaxPredictionTime = 0.5,
    MinConfidence = 0.15,
    
    -- Urgency settings
    UrgencyWindowStart = 0.4,
    UrgencyWindowEnd = 0.0,
    UrgencyMaxBoost = 3.0,
    
    -- Emergency parry settings - MORE AGGRESSIVE
    EmergencyDistance = 10,          -- Increased from 8
    EmergencyPredictionTime = 0.25,  -- Increased from 0.2
    
    -- Roll Attack Specific - MUCH MORE AGGRESSIVE
    RollEmergencyDistance = 18,      -- Increased from 14
    RollApproachSpeedThreshold = 18, -- Speed threshold for dangerous roll approach
    MaxRollDistanceMultiplier = 2.5, -- Max multiplier for roll emergency distance
    
    -- NEW: Predictive triggering for fast approaches
    PredictiveDistance = 25,         -- Start predicting threats at this distance
    PredictiveTimeHorizon = 0.5,     -- How far ahead to predict (seconds)
    MinClosingSpeedForEarly = 15,    -- Minimum closing speed for early trigger
    
    -- Hitbox detection
    HitboxBuffer = 3.0,              -- Increased from 2.5
}



local function GetCharacter()
    return LocalPlayer.Character
end

local function GetCharacterInfo()
    local c = GetCharacter()
    return c and c:FindFirstChild("CharacterInformation")
end

local function GetEquippedTool()
    local c = GetCharacter()
    return c and c:FindFirstChildWhichIsA("Tool")
end

local function GetAbilityType()
    local ci = GetCharacterInfo()
    if ci and ci:FindFirstChild("AbilitySelected") then
        return ci.AbilitySelected.Value
    end
    return "StunParry"
end

local function GetHumanoid(character)
    return character and character:FindFirstChildOfClass("Humanoid")
end

local function GetRootPart(character)
    return character and character:FindFirstChild("HumanoidRootPart")
end



local function IsEnemyParrying(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local isParrying = charInfo:FindFirstChild("IsParrying")
        if isParrying and isParrying.Value == true then
            return true
        end
        -- Also check CanParry == 1 which indicates active parry frames
        local canParry = charInfo:FindFirstChild("CanParry")
        if canParry and canParry.Value == 1 then
            return true
        end
    end
    return false
end

local function IsEnemyRolling(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local isRolling = charInfo:FindFirstChild("IsRolling")
        if isRolling and isRolling.Value == true then
            return true
        end
    end
    return false
end

local function IsEnemyOnParryCooldown(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local onCD = charInfo:FindFirstChild("OnParryCooldown")
        if onCD and onCD.Value == true then
            return true
        end
    end
    return false
end

local function IsEnemyInvincible(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local isInvincible = charInfo:FindFirstChild("IsInvincible")
        if isInvincible and isInvincible.Value ~= 0 then
            return true
        end
    end
    return false
end

local function IsEnemyCrawling(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local crawl = charInfo:FindFirstChild("Crawl")
        if crawl and crawl.Value == true then
            return true
        end
    end
    return false
end

local function IsEnemyFrozen(enemyChar)
    local charInfo = enemyChar:FindFirstChild("CharacterInformation")
    if charInfo then
        local frozen = charInfo:FindFirstChild("Frozen")
        if frozen and frozen.Value ~= 0 then
            return true
        end
    end
    return false
end

-- IMPROVED: Enhanced attack detection with chainsaw support
local function IsEnemyAttacking(enemyChar)
    -- Only skip if parrying (parry cancels attacks)
    -- DO NOT skip if rolling - players can attack during/out of rolls!
    if IsEnemyParrying(enemyChar) then
        return false, 0
    end
    
    local humanoid = GetHumanoid(enemyChar)
    if not humanoid then return false, 0 end
    
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return false, 0 end
    
    local tool = enemyChar:FindFirstChildWhichIsA("Tool")
    local toolName = tool and tool.Name:lower() or ""

    local isContinuousWeapon = toolName:match("chainsaw") or toolName:match("flail")
    
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.IsPlaying and track.Animation then
            local animId = track.Animation.AnimationId:match("(%d+)")
            if animId then
                -- Check known attack animations
                if ATTACK_ANIMS[animId] then
                    return true, track.Speed
                end
                
                -- CONTINUOUS WEAPON DETECTION: Any non-idle animation while holding
                if isContinuousWeapon and track.Speed > 0.3 and not EXCLUDE_ANIMS[animId] then
                    return true, track.Speed
                end
            end
        end
    end
    
    return false, 0
end

local function IsFacing(charA, charB, threshold)
    threshold = threshold or 0.5
    local rootA = GetRootPart(charA)
    local rootB = GetRootPart(charB)
    if not rootA or not rootB then return false end
    
    local direction = (rootB.Position - rootA.Position).Unit
    local dot = rootA.CFrame.LookVector:Dot(direction)
    return dot >= threshold
end

local function GetEnemyHealth(enemyChar)
    local humanoid = GetHumanoid(enemyChar)
    return humanoid and humanoid.Health or 0
end



local function GetNearbyEnemies(range)
    local enemies = {}
    local char = GetCharacter()
    if not char then return enemies end
    
    local myRoot = GetRootPart(char)
    if not myRoot then return enemies end
    
    local myPos = myRoot.Position
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local enemyChar = player.Character
            if enemyChar then
                local enemyRoot = GetRootPart(enemyChar)
                local humanoid = GetHumanoid(enemyChar)
                
                if enemyRoot and humanoid and humanoid.Health > 0 then
                    local distance = (enemyRoot.Position - myPos).Magnitude
                    
                    if distance <= range then
                        local isAttacking, attackSpeed = IsEnemyAttacking(enemyChar)
                        
                        table.insert(enemies, {
                            Player = player,
                            Character = enemyChar,
                            Root = enemyRoot,
                            Humanoid = humanoid,
                            Distance = distance,
                            Health = humanoid.Health,
                            MaxHealth = humanoid.MaxHealth,
                            IsAttacking = isAttacking,
                            AttackSpeed = attackSpeed,
                            IsParrying = IsEnemyParrying(enemyChar),
                            IsRolling = IsEnemyRolling(enemyChar),
                            OnParryCooldown = IsEnemyOnParryCooldown(enemyChar),
                            IsInvincible = IsEnemyInvincible(enemyChar),
                            IsCrawling = IsEnemyCrawling(enemyChar),
                            IsFrozen = IsEnemyFrozen(enemyChar),
                            IsFacingMe = IsFacing(enemyChar, char, 0.5),
                            Tool = enemyChar:FindFirstChildWhichIsA("Tool"),
                            Velocity = enemyRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0),
                        })
                    end
                end
            end
        end
    end
    
    return enemies
end



local function CanSelfParry()
    local char = GetCharacter()
    local ci = GetCharacterInfo()
    if not char or not ci then return false end
    
    -- Check ACTUAL game cooldown state (authoritative source)
    local onCD = ci:FindFirstChild("OnParryCooldown")
    if onCD and onCD.Value == true then return false end
    
    -- Weapon check
    local tool = GetEquippedTool()
    if not tool or not tool:FindFirstChild("hit") then return false end
    
    -- Stamina check (parry typically costs ~10 stamina)
    local stamina = ci:FindFirstChild("Stamina")
    if stamina and stamina.Value < 8 then return false end
    
    local blockedStates = {"IsRolling", "Frozen", "Stunned", "IsParrying", "Crawl"}
    for _, stateName in ipairs(blockedStates) do
        local stateVal = ci:FindFirstChild(stateName)
        if stateVal then
            if stateVal.Value == true then return false end
            if type(stateVal.Value) == "number" and stateVal.Value ~= 0 then return false end
        end
    end
    
    return true
end

local function DoParry()
    local currentTime = tick()
    if currentTime - State.lastParryTime < 2.5 then return false end
    
    local tool = GetEquippedTool()
    if not tool or not tool:FindFirstChild("hit") then return false end
    
    local abilityType = GetAbilityType()
    local success = pcall(function()
        if abilityType == "HealParry" then
            CharFunClient.healparry()
        elseif abilityType == "WinterParry" then
            CharFunClient.winterparry()
        else
            CharFunClient.stunparry()
        end
    end)
    
    if success then
        State.lastParryTime = currentTime
        return true
    end
    return false
end

local function DoDash()
    local currentTime = tick()
    if currentTime - State.lastDashTime < 2.5 then return false end
    
    local success = pcall(function() CharFunClient.roll() end)
    
    if success then
        State.lastDashTime = currentTime
        return true
    end
    return false
end

-- [[ FACING LOGIC ]]

local FacingHistory = {}
local FACING_MEMORY = 0.5

local function IsActuallyFacingMe(enemyChar, myChar, threshold)
    threshold = threshold or 0.5
    local enemyRoot = GetRootPart(enemyChar)
    local myRoot = GetRootPart(myChar)
    if not enemyRoot or not myRoot then return false end
    
    local toMe = (myRoot.Position - enemyRoot.Position)
    local dist = toMe.Magnitude
    if dist < 0.1 then return true end -- On top of each other
    
    local toMeH = Vector3.new(toMe.X, 0, toMe.Z).Unit
    local enemyLook = enemyRoot.CFrame.LookVector
    local enemyH = Vector3.new(enemyLook.X, 0, enemyLook.Z).Unit
    
    return enemyH:Dot(toMeH) > threshold
end

local function TrackFacingHistory(player, isFacing)
    local now = tick()
    if not FacingHistory[player] then
        FacingHistory[player] = { lastFacing = 0 }
    end
    if isFacing then
        FacingHistory[player].lastFacing = now
    end
end

local function HasRecentlyFacedUs(player)
    if not FacingHistory[player] then return false end
    return (tick() - FacingHistory[player].lastFacing) <= FACING_MEMORY
end



-- ARROW PHYSICS & PREDICTION SYSTEM v3 (FIXED VERTICAL AIM)
-- FIXES: 1. Clamp raw velocity 2. Separate horizontal/vertical 3. Stricter limits 4. Clear history on teleport

local ARROW_FRAME_TIME = 0.03
local ROBLOX_GRAVITY = workspace.Gravity or 196.2
local MAX_HORIZONTAL_SPEED = 32 -- Walk/sprint cap
local MAX_VERTICAL_SPEED = 80 -- Jump velocity cap
local VELOCITY_HISTORY_SIZE = 10
local VELOCITY_HISTORY_TIME = 0.3
local PREDICTION_DAMPENING_THRESHOLD = 50
local STRAFE_DETECTION_THRESHOLD = 3
local STRAFE_TIME_WINDOW = 0.5
local STATIONARY_THRESHOLD = 2
local MIN_CONFIDENCE = 0.25
local MAX_VERTICAL_PREDICTION = 25

-- NEW: Network timing constants
local ROBLOX_INTERPOLATION_DELAY = 0.1 -- 100ms standard network interpolation

-- NEW: Acceleration tracking for second-order prediction
local AccelerationHistory = {}

-- Recent facing history for each player
local FacingHistory = {}
local FACING_HISTORY_TIME = 0.5  -- How long to remember they were facing us (seconds)
local FACING_REQUIRED_TIME = 0.15  -- How long they need to face us to count as "recently facing"

local function CalculateArrowFlightFrames(distance)
    local a = 1
    local b = -550
    local c = distance / 0.03
    local discriminant = b * b - 4 * a * c
    
    if discriminant < 0 then
        return 550
    end
    
    local frame = (-b - math.sqrt(discriminant)) / (2 * a)
    return math.clamp(math.floor(frame), 1, 550)
end

local function CalculateGravityDrop(frames)
    return 3.0049249999999996 * 0.03 * frames * frames
end

-- NEW: Clamp velocity to reasonable bounds
local function ClampVelocity(velocity)
    local horizontalVel = Vector3.new(velocity.X, 0, velocity.Z)
    local verticalVel = velocity.Y
    
    -- Clamp horizontal
    if horizontalVel.Magnitude > MAX_HORIZONTAL_SPEED then
        horizontalVel = horizontalVel.Unit * MAX_HORIZONTAL_SPEED
    end
    
    -- Clamp vertical
    verticalVel = math.clamp(verticalVel, -MAX_VERTICAL_SPEED, MAX_VERTICAL_SPEED)
    
    return Vector3.new(horizontalVel.X, verticalVel, horizontalVel.Z)
end

local function IsTargetStationary(velocity)
    local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
    return horizontalSpeed < STATIONARY_THRESHOLD
end

local function GetGroundHeight(position)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    local filterList = {GetCharacter()}
    local explosions = Workspace:FindFirstChild("Explosions")
    if explosions then table.insert(filterList, explosions) end
    local bloodFolder = Workspace:FindFirstChild("BloodFolder")
    if bloodFolder then table.insert(filterList, bloodFolder) end
    local playersFolder = Workspace:FindFirstChild("PlayersCharacters")
    if playersFolder then table.insert(filterList, playersFolder) end
    rayParams.FilterDescendantsInstances = filterList
    
    local rayOrigin = position + Vector3.new(0, 500, 0)
    local rayDirection = Vector3.new(0, -1000, 0)
    
    local result = Workspace:Raycast(rayOrigin, rayDirection, rayParams)
    if result then
        return result.Position.Y
    end
    
    return position.Y - 10
end

local function GetHumanoidState(character)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return nil end
    return humanoid:GetState()
end

local function IsAtJumpApex(character, verticalVelocity)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return false end
    
    local state = humanoid:GetState()
    if state == Enum.HumanoidStateType.Freefall or state == Enum.HumanoidStateType.Jumping then
        if math.abs(verticalVelocity) < 10 then
            return true
        end
    end
    return false
end

local function CanArrowReachPosition(fromPos, toPos, excludeCharacter)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local filterList = {GetCharacter()}
    if excludeCharacter then table.insert(filterList, excludeCharacter) end
    local explosions = Workspace:FindFirstChild("Explosions")
    if explosions then table.insert(filterList, explosions) end
    local bloodFolder = Workspace:FindFirstChild("BloodFolder")
    if bloodFolder then table.insert(filterList, bloodFolder) end
    rayParams.FilterDescendantsInstances = filterList
    
    local direction = toPos - fromPos
    local result = Workspace:Raycast(fromPos, direction, rayParams)
    
    if result then
        local hitDistance = (result.Position - fromPos).Magnitude
        local totalDistance = direction.Magnitude
        
        if hitDistance < totalDistance - 1 then
            return false, fromPos + direction.Unit * math.max(0, hitDistance - 2)
        end
    end
    
    return true, toPos
end

-- Track acceleration for second-order prediction
local function TrackAcceleration(player, velocity)
    local now = tick()
    
    if not AccelerationHistory[player] then
        AccelerationHistory[player] = {
            lastVel = velocity,
            lastTime = now,
            accel = Vector3.new(0, 0, 0)
        }
        return Vector3.new(0, 0, 0)
    end
    
    local hist = AccelerationHistory[player]
    local dt = now - hist.lastTime
    
    if dt > 0.016 then -- At least one frame
        local rawAccel = (velocity - hist.lastVel) / dt
        
        -- Clamp acceleration to reasonable values (prevents spikes)
        local maxAccel = 150 -- studs/s^2
        if rawAccel.Magnitude > maxAccel then
            rawAccel = rawAccel.Unit * maxAccel
        end
        
        -- Smooth acceleration with exponential moving average
        hist.accel = hist.accel:Lerp(rawAccel, 0.3)
        hist.lastVel = velocity
        hist.lastTime = now
    end
    
    return hist.accel
end

-- Track if enemy has recently been facing us
local function TrackFacingHistory(player, isFacingNow)
    local now = tick()
    
    if not FacingHistory[player] then
        FacingHistory[player] = {
            facingTimes = {},  -- Array of {startTime, endTime} when they were facing
            currentlyFacing = false,
            currentFacingStart = 0,
        }
    end
    
    local history = FacingHistory[player]
    
    -- Clean old entries
    local cutoff = now - FACING_HISTORY_TIME
    local newTimes = {}
    for _, period in ipairs(history.facingTimes) do
        if period.endTime > cutoff then
            table.insert(newTimes, period)
        end
    end
    history.facingTimes = newTimes
    
    -- Track current facing state
    if isFacingNow then
        if not history.currentlyFacing then
            -- Just started facing
            history.currentlyFacing = true
            history.currentFacingStart = now
        end
    else
        if history.currentlyFacing then
            -- Just stopped facing - record the period
            local duration = now - history.currentFacingStart
            if duration >= 0.05 then  -- Only record if they faced for at least 50ms
                table.insert(history.facingTimes, {
                    startTime = history.currentFacingStart,
                    endTime = now
                })
            end
            history.currentlyFacing = false
        end
    end
end

-- Check if enemy has recently faced us for a significant amount of time
local function HasRecentlyFacedUs(player)
    local now = tick()
    local history = FacingHistory[player]
    
    if not history then return false end
    
    -- If currently facing, check duration
    if history.currentlyFacing then
        local currentDuration = now - history.currentFacingStart
        if currentDuration >= FACING_REQUIRED_TIME then
            return true
        end
    end
    
    -- Check recent history
    local cutoff = now - FACING_HISTORY_TIME
    local totalFacingTime = 0
    
    for _, period in ipairs(history.facingTimes) do
        if period.endTime > cutoff then
            local effectiveStart = math.max(period.startTime, cutoff)
            totalFacingTime = totalFacingTime + (period.endTime - effectiveStart)
        end
    end
    
    -- Also add current facing time if applicable
    if history.currentlyFacing then
        totalFacingTime = totalFacingTime + (now - history.currentFacingStart)
    end
    
    return totalFacingTime >= FACING_REQUIRED_TIME
end

-- Check if enemy is facing us using their ACTUAL CFrame (not predicted)
local function IsActuallyFacingMe(enemyChar, myChar, threshold)
    threshold = threshold or 0.5
    local enemyRoot = GetRootPart(enemyChar)
    local myRoot = GetRootPart(myChar)
    
    if not enemyRoot or not myRoot then return false end
    
    -- Use ACTUAL current CFrame, not any predicted position
    local directionToMe = (myRoot.Position - enemyRoot.Position).Unit
    local enemyLookVector = enemyRoot.CFrame.LookVector
    local dot = enemyLookVector:Dot(directionToMe)
    
    return dot >= threshold
end

-- Simplified vertical prediction - minimal prediction to avoid overshoot
local function PredictVerticalWithPhysics(targetPart, predictionTime, smoothedVelocity)
    local currentY = targetPart.Position.Y
    
    -- Use smoothed velocity if provided, otherwise get raw (but this shouldn't happen)
    local verticalVel = 0
    if smoothedVelocity then
        verticalVel = smoothedVelocity.Y
    else
        local rawVel = targetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        verticalVel = rawVel.Y
    end
    
    -- Clamp vertical velocity to prevent spike from jumps
    verticalVel = math.clamp(verticalVel, -50, 50)
    
    -- Only predict 15% of vertical movement - jumps are too unpredictable
    local verticalOffset = verticalVel * predictionTime * 0.15
    
    -- Hard clamp the offset to prevent overshooting
    verticalOffset = math.clamp(verticalOffset, -6, 6)
    
    return currentY + verticalOffset
end

-- Predict if target will hit a wall and stop
local function PredictWithWallCollision(startPos, predictedPos, targetChar)
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    
    local filterList = {GetCharacter(), targetChar}
    local explosions = Workspace:FindFirstChild("Explosions")
    if explosions then table.insert(filterList, explosions) end
    local bloodFolder = Workspace:FindFirstChild("BloodFolder")
    if bloodFolder then table.insert(filterList, bloodFolder) end
    local playersFolder = Workspace:FindFirstChild("PlayersCharacters")
    if playersFolder then table.insert(filterList, playersFolder) end
    rayParams.FilterDescendantsInstances = filterList
    
    local direction = predictedPos - startPos
    local distance = direction.Magnitude
    
    if distance < 0.1 then return predictedPos end
    
    local result = Workspace:Raycast(startPos, direction, rayParams)
    
    if result then
        local hitDistance = (result.Position - startPos).Magnitude
        
        -- If wall is closer than predicted position, they'll stop there
        if hitDistance < distance - 1 then
            -- Return position just before the wall
            return startPos + direction.Unit * math.max(0, hitDistance - 2)
        end
    end
    
    return predictedPos
end

-- FIXED: Better velocity processing with teleport detection
-- FIXED: Better velocity processing with teleport detection

local function ClampVelocity(vel, maxSpeed)
    maxSpeed = maxSpeed or 32
    if vel.X ~= vel.X then return Vector3.new(0, 0, 0) end  -- NaN check
    local horizVel = Vector3.new(vel.X, 0, vel.Z)
    if horizVel.Magnitude > maxSpeed then
        horizVel = horizVel.Unit * maxSpeed
    end
    return horizVel
end

local function GetHorizontalVelocity(rootPart)
    if not rootPart then return Vector3.new(0, 0, 0) end
    local vel = rootPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    if vel.X ~= vel.X then return Vector3.new(0, 0, 0) end
    return Vector3.new(vel.X, 0, vel.Z)
end

local function ProcessVelocityData(player, currentVelocity, currentPosition)
    local now = tick()
    
    -- Clamp velocity immediately
    currentVelocity = ClampVelocity(currentVelocity)
    
    if not VelocityHistory[player] then
        VelocityHistory[player] = {
            velocities = {},
            positions = {},
            timestamps = {},
            directionChanges = 0,
            lastDirectionX = 0,
            lastDirectionZ = 0,
            strafeCenter = nil,
            lastUpdateTime = now,
        }
    end
    
    local history = VelocityHistory[player]
    
    -- TELEPORT DETECTION: If position jumped too far, reset history
    if #history.positions > 0 then
        local lastPos = history.positions[#history.positions]
        local lastTime = history.timestamps[#history.timestamps]
        local timeDelta = now - lastTime
        local posDelta = (currentPosition - lastPos).Magnitude
        
        -- If moved more than 50 studs in a short time, likely teleport
        if timeDelta < 0.5 and posDelta > 50 then
            VelocityHistory[player] = {
                velocities = {currentVelocity},
                positions = {currentPosition},
                timestamps = {now},
                directionChanges = 0,
                lastDirectionX = 0,
                lastDirectionZ = 0,
                strafeCenter = nil,
                lastUpdateTime = now,
            }
            return {
                smoothedVelocity = currentVelocity,
                confidence = MIN_CONFIDENCE, -- Low confidence after teleport
                isStrafing = false,
                strafeCenter = nil,
            }
        end
    end
    
    -- Add current sample
    table.insert(history.velocities, currentVelocity)
    table.insert(history.positions, currentPosition)
    table.insert(history.timestamps, now)
    
    -- Remove old samples
    while #history.timestamps > 0 and (now - history.timestamps[1]) > VELOCITY_HISTORY_TIME do
        table.remove(history.velocities, 1)
        table.remove(history.positions, 1)
        table.remove(history.timestamps, 1)
    end
    
    -- Limit size
    while #history.velocities > VELOCITY_HISTORY_SIZE do
        table.remove(history.velocities, 1)
        table.remove(history.positions, 1)
        table.remove(history.timestamps, 1)
    end
    
    -- === STRAFE DETECTION (horizontal only) ===
    local currentDirX = currentVelocity.X > 2 and 1 or (currentVelocity.X < -2 and -1 or 0)
    local currentDirZ = currentVelocity.Z > 2 and 1 or (currentVelocity.Z < -2 and -1 or 0)
    
    if history.lastDirectionX ~= 0 and currentDirX ~= 0 and history.lastDirectionX ~= currentDirX then
        history.directionChanges = history.directionChanges + 1
    end
    if history.lastDirectionZ ~= 0 and currentDirZ ~= 0 and history.lastDirectionZ ~= currentDirZ then
        history.directionChanges = history.directionChanges + 1
    end
    
    history.lastDirectionX = currentDirX
    history.lastDirectionZ = currentDirZ
    
    if now - history.lastUpdateTime > 0.15 then
        history.directionChanges = math.max(0, history.directionChanges - 1)
        history.lastUpdateTime = now
    end
    
    local isStrafing = history.directionChanges >= STRAFE_DETECTION_THRESHOLD
    
    -- Calculate strafe center (HORIZONTAL ONLY - don't use Y from strafe center)
    if isStrafing and #history.positions >= 3 then
        local minX, maxX = math.huge, -math.huge
        local minZ, maxZ = math.huge, -math.huge
        local count = 0
        
        for i, pos in ipairs(history.positions) do
            if now - history.timestamps[i] < STRAFE_TIME_WINDOW then
                minX = math.min(minX, pos.X)
                maxX = math.max(maxX, pos.X)
                minZ = math.min(minZ, pos.Z)
                maxZ = math.max(maxZ, pos.Z)
                count = count + 1
            end
        end
        
        if count >= 3 then
            -- Only store horizontal strafe center, Y will be calculated separately
            history.strafeCenter = Vector3.new(
                (minX + maxX) / 2,
                currentPosition.Y, -- Use current Y, not averaged
                (minZ + maxZ) / 2
            )
        end
    else
        history.strafeCenter = nil
    end
    
    -- === VELOCITY SMOOTHING ===
    local smoothedVelocity = currentVelocity
    local confidence = 1.0
    
    if #history.velocities >= 2 then
        local weightedSum = Vector3.new(0, 0, 0)
        local totalWeight = 0
        
        for i, vel in ipairs(history.velocities) do
            local weight = i / #history.velocities
            weightedSum = weightedSum + vel * weight
            totalWeight = totalWeight + weight
        end
        
        smoothedVelocity = weightedSum / totalWeight
        
        -- IMPORTANT: Re-clamp after smoothing
        smoothedVelocity = ClampVelocity(smoothedVelocity)
        
        -- Calculate velocity variance
        local velocityVariance = 0
        for i = 2, #history.velocities do
            local diff = (history.velocities[i] - history.velocities[i-1]).Magnitude
            velocityVariance = velocityVariance + diff
        end
        velocityVariance = velocityVariance / (#history.velocities - 1)
        
        confidence = math.clamp(1 - (velocityVariance / 60), MIN_CONFIDENCE, 1)
        
        -- Acceleration penalty
        local timeDelta = history.timestamps[#history.timestamps] - history.timestamps[1]
        if timeDelta > 0.01 then
            local accel = (history.velocities[#history.velocities] - history.velocities[1]) / timeDelta
            local accelMagnitude = accel.Magnitude
            
            if accelMagnitude > PREDICTION_DAMPENING_THRESHOLD then
                local accelPenalty = math.clamp(PREDICTION_DAMPENING_THRESHOLD / accelMagnitude, 0.5, 1)
                confidence = math.max(MIN_CONFIDENCE, confidence * accelPenalty)
            end
        end
    end
    
    if isStrafing then
        confidence = math.max(MIN_CONFIDENCE, confidence * 0.6)
    end
    
    return {
        smoothedVelocity = smoothedVelocity,
        confidence = confidence,
        isStrafing = isStrafing,
        strafeCenter = history.strafeCenter,
    }
end

-- MAIN PREDICTION FUNCTION - v4 with proper network timing
local function PredictPosition(targetPart)
    local char = GetCharacter()
    if not char then return targetPart.Position end
    
    local myRoot = GetRootPart(char)
    if not myRoot then return targetPart.Position end
    
    local player = Players:GetPlayerFromCharacter(targetPart.Parent)
    if not player then return targetPart.Position end
    
    local targetChar = targetPart.Parent
    local myPos = myRoot.Position
    local targetPos = targetPart.Position
    local distance = (targetPos - myPos).Magnitude
    
    local rawVelocity = targetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    
    -- Validate velocity (check for NaN/Inf)
    if rawVelocity.X ~= rawVelocity.X or rawVelocity.Y ~= rawVelocity.Y or rawVelocity.Z ~= rawVelocity.Z then
        rawVelocity = Vector3.new(0, 0, 0)
    end
    if math.abs(rawVelocity.X) == math.huge or math.abs(rawVelocity.Y) == math.huge or math.abs(rawVelocity.Z) == math.huge then
        rawVelocity = Vector3.new(0, 0, 0)
    end
    
    rawVelocity = ClampVelocity(rawVelocity)
    
    -- === TIMING CALCULATION (FIXED) ===
    local frames = CalculateArrowFlightFrames(distance)
    local flightTime = frames * ARROW_FRAME_TIME
    
    -- Data Ping is RTT, so divide by 2 for one-way latency
    local oneWayLatency = GetOneWayLatency()
    
    -- Total prediction time:
    -- 1. One-way latency (time for our shot command to reach server)
    -- 2. Interpolation delay (server sees target ahead of us)
    -- 3. Arrow flight time
    local networkCompensation = oneWayLatency + ROBLOX_INTERPOLATION_DELAY
    local totalPredictionTime = networkCompensation + flightTime
    
    -- Calculate gravity drop for arrow
    local gravityDrop = CalculateGravityDrop(frames)
    
    -- If prediction disabled, just compensate for arrow gravity
    if not Settings.BowAimbot.PredictMovement then
        return targetPos + Vector3.new(0, gravityDrop, 0)
    end
    
    -- Stationary target - no movement prediction needed
    if IsTargetStationary(rawVelocity) then
        return targetPos + Vector3.new(0, gravityDrop, 0)
    end
    
    -- === VELOCITY PROCESSING ===
    local data = ProcessVelocityData(player, rawVelocity, targetPos)
    local smoothedVelocity = data.smoothedVelocity
    local confidence = data.confidence
    local isStrafing = data.isStrafing
    local strafeCenter = data.strafeCenter
    
    -- Validate smoothed velocity
    if smoothedVelocity.X ~= smoothedVelocity.X or smoothedVelocity.Y ~= smoothedVelocity.Y or smoothedVelocity.Z ~= smoothedVelocity.Z then
        return targetPos + Vector3.new(0, gravityDrop, 0)
    end
    
    -- === ACCELERATION TRACKING ===
    local acceleration = TrackAcceleration(player, smoothedVelocity)
    
    -- === CONFIDENCE ADJUSTMENTS ===
    -- Distance-based confidence decay (further = less accurate)
    local distanceFactor = math.clamp(1 - (distance / 400), 0.4, 1)
    
    -- Apply confidence to prediction time
    local adjustedPredictionTime = totalPredictionTime * confidence * distanceFactor
    
    -- Cap prediction time to prevent overshooting
    adjustedPredictionTime = math.min(adjustedPredictionTime, 0.7)
    
    -- === HORIZONTAL PREDICTION (First-order + partial second-order) ===
    local horizontalVelocity = Vector3.new(smoothedVelocity.X, 0, smoothedVelocity.Z)
    local horizontalAccel = Vector3.new(acceleration.X, 0, acceleration.Z)
    
    -- First-order prediction: pos + vel * t
    local firstOrderOffset = horizontalVelocity * adjustedPredictionTime
    
    -- Second-order prediction (dampened): 0.5 * accel * t^2
    -- Dampen by 0.3 because acceleration is highly unpredictable
    local secondOrderOffset = horizontalAccel * 0.3 * adjustedPredictionTime * adjustedPredictionTime * 0.5
    
    local horizontalOffset = firstOrderOffset + secondOrderOffset
    
    -- Blend toward strafe center if target is strafing
    if isStrafing and strafeCenter then
        local currentHoriz = Vector3.new(targetPos.X, 0, targetPos.Z)
        local strafeHoriz = Vector3.new(strafeCenter.X, 0, strafeCenter.Z)
        local towardsCenter = strafeHoriz - currentHoriz
        
        -- Blend 35% towards strafe center
        horizontalOffset = horizontalOffset:Lerp(towardsCenter, 0.35)
    end
    
    -- Clamp horizontal movement to physically possible distance
    local maxMove = MAX_HORIZONTAL_SPEED * totalPredictionTime * 1.3
    if horizontalOffset.Magnitude > maxMove then
        horizontalOffset = horizontalOffset.Unit * maxMove
    end
    
    local predictedHorizontal = Vector3.new(targetPos.X, 0, targetPos.Z) + horizontalOffset
    
    -- === VERTICAL PREDICTION (uses smoothed velocity to avoid spikes) ===
    local predictedY = PredictVerticalWithPhysics(targetPart, adjustedPredictionTime, smoothedVelocity)
    
    -- === WALL COLLISION CHECK ===
    local rawPredicted = Vector3.new(predictedHorizontal.X, predictedY, predictedHorizontal.Z)
    local collisionAdjusted = PredictWithWallCollision(targetPos, rawPredicted, targetChar)
    
    -- === APPLY GRAVITY DROP FOR ARROW ===
    local finalPos = Vector3.new(collisionAdjusted.X, collisionAdjusted.Y + gravityDrop, collisionAdjusted.Z)
    
    -- === FINAL VISIBILITY CHECK ===
    local canReach, safePos = CanArrowReachPosition(myPos, finalPos, targetChar)
    if not canReach then
        -- Try fallback to current position + gravity
        local fallbackPos = targetPos + Vector3.new(0, gravityDrop, 0)
        local canReachFallback, _ = CanArrowReachPosition(myPos, fallbackPos, targetChar)
        if canReachFallback then
            return fallbackPos
        end
        return safePos
    end
    
    return finalPos
end

-- PARRY-SPECIFIC PREDICTION SYSTEM - Simplified for short-term melee range

-- Weapon data: reach is what matters for parry
-- Weapon data with normal AND roll-attack hitFrames
local WEAPON_DATA = {
    ["spear"]     = { reach = 9.0, hitFrame = 0.35, rollHitFrame = 0.25, lungeDistance = 4.0 },
    ["halberd"]   = { reach = 8.5, hitFrame = 0.40, rollHitFrame = 0.28, lungeDistance = 3.5 },
    ["greatsword"]= { reach = 7.5, hitFrame = 0.50, rollHitFrame = 0.35, lungeDistance = 3.0 },
    ["sword"]     = { reach = 6.0, hitFrame = 0.42, rollHitFrame = 0.28, lungeDistance = 2.5 },
    ["axe"]       = { reach = 5.5, hitFrame = 0.48, rollHitFrame = 0.32, lungeDistance = 2.0 },
    ["hammer"]    = { reach = 5.5, hitFrame = 0.55, rollHitFrame = 0.38, lungeDistance = 2.0 },
    ["mace"]      = { reach = 5.0, hitFrame = 0.45, rollHitFrame = 0.30, lungeDistance = 2.0 },
    ["shield"]    = { reach = 4.5, hitFrame = 0.28, rollHitFrame = 0.18, lungeDistance = 3.0 },
    ["dagger"]    = { reach = 4.0, hitFrame = 0.32, rollHitFrame = 0.20, lungeDistance = 3.5 },
    ["chainsaw"]  = { reach = 4.0, hitFrame = 0.15, rollHitFrame = 0.10, lungeDistance = 1.0 },
    ["fist"]      = { reach = 3.5, hitFrame = 0.38, rollHitFrame = 0.25, lungeDistance = 2.0 },
    ["default"]   = { reach = 6.0, hitFrame = 0.42, rollHitFrame = 0.28, lungeDistance = 2.5 },
}

local function GetWeaponData(tool)
    if not tool then return WEAPON_DATA["default"] end
    local name = tool.Name:lower()
    for key, data in pairs(WEAPON_DATA) do
        if name:find(key) then
            return data
        end
    end
    return WEAPON_DATA["default"]
end

-- [[ PING SYSTEM - Uses max recent ping for safety ]]

local function UpdatePingHistory()
    local now = tick()
    if now - PingHistory.lastUpdate < 0.05 then return end  -- Rate limit
    PingHistory.lastUpdate = now
    
    local ping = 0.1 -- Default fallback
    pcall(function()
        ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
    end)
    
    table.insert(PingHistory.samples, { time = now, ping = ping })
    
    -- Remove old samples
    while #PingHistory.samples > PingHistory.maxSamples do
        table.remove(PingHistory.samples, 1)
    end
end

local function GetOneWayLatency()
    UpdatePingHistory()
    
    if not Settings.AutoParry.UseMaxPing or #PingHistory.samples < 3 then
        -- Fallback to current ping
        local ping = 0.1
        pcall(function()
             ping = Stats.Network.ServerStatsItem["Data Ping"]:GetValue() / 1000
        end)
        return ping / 2
    end
    
    -- Find max ping in recent history (accounts for jitter)
    local maxPing = 0
    local now = tick()
    for _, sample in ipairs(PingHistory.samples) do
        if now - sample.time < 0.5 then  -- Only last 500ms
            maxPing = math.max(maxPing, sample.ping)
        end
    end
    
    return (maxPing / 2) + PING_JITTER_BUFFER
end

-- [[ VELOCITY SMOOTHING ]]

local function GetParrySmoothedVelocity(player, rootPart)
    if not rootPart then return Vector3.new(0, 0, 0) end
    
    local now = tick()
    local rawVel = rootPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
    local clampedVel = ClampVelocity(rawVel)
    
    if not ParryVelocityHistory[player] then
        ParryVelocityHistory[player] = { samples = {}, lastPos = rootPart.Position }
    end
    
    local history = ParryVelocityHistory[player]
    
    -- Add sample
    table.insert(history.samples, { time = now, vel = clampedVel, pos = rootPart.Position })
    
    -- Remove old samples
    while #history.samples > VELOCITY_SAMPLES do
        table.remove(history.samples, 1)
    end
    while #history.samples > 0 and (now - history.samples[1].time) > VELOCITY_TIME_WINDOW do
        table.remove(history.samples, 1)
    end
    
    -- Calculate weighted average (recent samples weighted more)
    if #history.samples < 2 then return clampedVel end
    
    local weightedSum = Vector3.new(0, 0, 0)
    local totalWeight = 0
    
    for i, sample in ipairs(history.samples) do
        local weight = i / #history.samples  -- Later samples = higher weight
        weightedSum = weightedSum + sample.vel * weight
        totalWeight = totalWeight + weight
    end
    
    local smoothed = weightedSum / totalWeight
    
    -- Also calculate velocity from position delta (more reliable)
    local oldestSample = history.samples[1]
    local newestSample = history.samples[#history.samples]
    local dt = newestSample.time - oldestSample.time
    
    if dt > 0.05 then
        local posVel = (newestSample.pos - oldestSample.pos) / dt
        posVel = ClampVelocity(posVel)
        
        -- Blend smoothed velocity with position-derived velocity
        smoothed = smoothed:Lerp(posVel, 0.3)
    end
    
    return ClampVelocity(smoothed)
end

-- Get horizontal distance (ignoring Y completely)
local function GetHorizontalDistance(posA, posB)
    local dx = posA.X - posB.X
    local dz = posA.Z - posB.Z
    return math.sqrt(dx * dx + dz * dz)
end

-- Predict horizontal distance between two characters after time T
local function PredictHorizontalDistance(myRoot, enemyRoot, timeSeconds)
    local myPos = Vector3.new(myRoot.Position.X, 0, myRoot.Position.Z)
    local enemyPos = Vector3.new(enemyRoot.Position.X, 0, enemyRoot.Position.Z)
    
    local myVel = GetHorizontalVelocity(myRoot)
    local enemyVel = GetHorizontalVelocity(enemyRoot)
    
    -- Simple linear extrapolation (first-order only)
    local predictedMyPos = myPos + myVel * timeSeconds
    local predictedEnemyPos = enemyPos + enemyVel * timeSeconds
    
    return (predictedEnemyPos - predictedMyPos).Magnitude
end

-- Get detailed animation info for timing
local function GetAttackAnimationInfo(enemyChar)
    local humanoid = GetHumanoid(enemyChar)
    if not humanoid then return nil end
    local animator = humanoid:FindFirstChildOfClass("Animator")
    if not animator then return nil end
    
    for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
        if track.IsPlaying and track.Animation and track.Length > 0 then
            local animId = track.Animation.AnimationId:match("(%d+)")
            if animId and ATTACK_ANIMS[animId] then
                local speed = math.max(track.Speed, 0.1)
                local progress = track.TimePosition / track.Length
                local timeRemaining = (track.Length - track.TimePosition) / speed
                
                return {
                    animId = animId,
                    progress = progress,
                    timeRemaining = timeRemaining,
                    length = track.Length,
                    speed = speed,
                    timePosition = track.TimePosition
                }
            end
        end
    end
    return nil
end

-- [[ FEINT DETECTION ]]

local function TrackAnimationForFeint(player, animInfo)
    local now = tick()
    
    if not AnimationHistory[player] then
        AnimationHistory[player] = {
            lastAnimId = nil,
            lastProgress = 0,
            lastTime = now,
            feintDetected = false,
            feintTime = 0,
            progressSamples = {},
        }
    end
    
    local history = AnimationHistory[player]
    
    -- Clear old feint flag
    if history.feintDetected and (now - history.feintTime) > FEINT_COOLDOWN then
        history.feintDetected = false
    end
    
    -- No animation = check if cancelled (feint)
    if not animInfo then
        if history.lastProgress > 0.1 and history.lastProgress < 0.7 then
            -- Animation was in progress but suddenly stopped
            local timeSinceAnim = now - history.lastTime
            if timeSinceAnim < 0.15 then  -- Recent cancel
                history.feintDetected = true
                history.feintTime = now
            end
        end
        history.lastAnimId = nil
        history.lastProgress = 0
        history.progressSamples = {}
        return history.feintDetected
    end
    
    -- Track progress
    table.insert(history.progressSamples, { time = now, progress = animInfo.progress })
    while #history.progressSamples > 5 do
        table.remove(history.progressSamples, 1)
    end
    
    -- Detect animation reset (feint into new attack)
    if history.lastAnimId == animInfo.animId then
        -- Same animation - check for sudden progress decrease (reset)
        if animInfo.progress < history.lastProgress - 0.2 then
            -- Progress went backwards significantly - possible feint
            history.feintDetected = true
            history.feintTime = now
        end
    end
    
    history.lastAnimId = animInfo.animId
    history.lastProgress = animInfo.progress
    history.lastTime = now
    
    return history.feintDetected
end

local function HasRecentlyFeinted(player)
    local history = AnimationHistory[player]
    if not history then return false end
    return history.feintDetected and (tick() - history.feintTime) < FEINT_COOLDOWN
end

-- [[ HIT TIMING CALCULATION ]]

local function GetTimeUntilHit(enemy, myChar)
    local animInfo = GetAttackAnimationInfo(enemy.Character)
    if not animInfo then return nil end
    
    local weaponData = GetWeaponData(enemy.Tool)
    local isRolling = IsEnemyRolling(enemy.Character)
    
    -- Use appropriate hit frame - roll attacks hit faster
    local hitFrame = isRolling and weaponData.rollHitFrame or weaponData.hitFrame
    
    -- Already past hit frame
    if animInfo.progress >= hitFrame then
        return { 
            timeToHit = 0, 
            alreadyPast = true, 
            confidence = 1.0,
            isRollAttack = isRolling
        }
    end
    
    -- Calculate time until hit frame
    local progressToHit = hitFrame - animInfo.progress
    local progressRemaining = 1.0 - animInfo.progress
    
    if progressRemaining <= 0.001 then 
        return { 
            timeToHit = 0, 
            alreadyPast = true, 
            confidence = 1.0,
            isRollAttack = isRolling
        } 
    end
    
    -- Proportional time calculation
    local timeToAnimHit = (progressToHit / progressRemaining) * animInfo.timeRemaining
    
    -- Network compensation - MORE aggressive for roll attacks
    local networkDelay = GetNetworkCompensation()
    if isRolling then
        -- Add extra buffer for roll attacks since they're harder to read
        networkDelay = networkDelay + 0.05
    end
    
    local adjustedTime = timeToAnimHit - networkDelay
    
    -- Already happening on server
    if adjustedTime < 0 then
        return { 
            timeToHit = 0, 
            alreadyPast = true, 
            confidence = 0.9, -- Higher confidence for imminent hits
            isRollAttack = isRolling
        }
    end
    
    -- Calculate confidence - roll attacks get higher base confidence (less time to react)
    local baseConfidence = isRolling and 0.4 or 0.3
    local timeConfidence = math.clamp(1.0 - (adjustedTime / 0.5), baseConfidence, 1.0)
    local speedConfidence = math.clamp(animInfo.speed / 1.2, 0.5, 1.0)
    local progressConfidence = math.clamp(animInfo.progress * 2, 0.3, 1.0)
    
    local confidence = timeConfidence * speedConfidence * progressConfidence
    
    -- Boost confidence for roll attacks
    if isRolling then
        confidence = math.min(confidence * 1.2, 1.0)
    end
    
    return {
        timeToHit = adjustedTime,
        alreadyPast = false,
        confidence = confidence,
        isRollAttack = isRolling,
        animProgress = animInfo.progress
    }
end

-- Made MUCH more generous - game hitboxes are very forgiving
-- [[ SPATIAL HIT DETECTION ]]

local function WillAttackHitUs(enemy, myChar, timeToHit)
    local myRoot = GetRootPart(myChar)
    local enemyRoot = enemy.Root
    if not myRoot or not enemyRoot then return false, math.huge, 0 end
    
    local currentDistance = GetHorizontalDistance(myRoot.Position, enemyRoot.Position)
    local weaponData = GetWeaponData(enemy.Tool)
    
    -- Base reach + hitbox buffer + lunge distance
    local baseReach = weaponData.reach + PARRY_CONFIG.HitboxBuffer + weaponData.lungeDistance
    
    -- Get smoothed velocities
    local enemyVel = GetParrySmoothedVelocity(enemy.Player, enemyRoot)
    local myVel = GetParrySmoothedVelocity(LocalPlayer, myRoot)
    
    -- Direction from enemy to me
    local toMe = myRoot.Position - enemyRoot.Position
    local horizontalToMe = Vector3.new(toMe.X, 0, toMe.Z)
    local directionToMe = horizontalToMe.Magnitude > 0.1 and horizontalToMe.Unit or Vector3.new(0, 0, 0)
    
    -- Relative closing speed (positive = approaching)
    local relativeVel = enemyVel - myVel
    local closingSpeed = relativeVel:Dot(directionToMe)
    
    -- Check if rolling
    local isRolling = IsEnemyRolling(enemy.Character)
    
    -- === IMPROVED: Dynamic attack window based on approach speed ===
    local attackWindow = math.max(timeToHit, 0.2)
    
    -- If they're approaching fast, use a longer prediction window
    if closingSpeed > PARRY_CONFIG.MinClosingSpeedForEarly then
        local speedFactor = closingSpeed / PARRY_CONFIG.MinClosingSpeedForEarly
        attackWindow = math.max(attackWindow, PARRY_CONFIG.PredictiveTimeHorizon * math.min(speedFactor, 1.5))
    end
    
    -- Calculate closing distance during attack window
    local closingDistance = 0
    if closingSpeed > 0 then
        closingDistance = closingSpeed * attackWindow
    end
    
    -- Predicted distance at hit time
    local predictedDistance = currentDistance - closingDistance
    
    -- === IMPROVED: Dynamic effective reach based on closing speed ===
    local effectiveReach = baseReach
    if closingSpeed > 5 then
        -- Scale reach based on closing speed (faster approach = larger effective range)
        local speedBonus = math.min(closingSpeed * 0.2, 8) -- Cap at 8 extra studs
        effectiveReach = effectiveReach + speedBonus
    end
    
    -- === NEW: Roll-specific distance scaling ===
    local rollEmergencyDist = PARRY_CONFIG.RollEmergencyDistance
    if isRolling and closingSpeed > 0 then
        -- Dynamically scale roll emergency distance based on approach speed
        local rollSpeedMultiplier = 1.0
        if closingSpeed >= PARRY_CONFIG.RollApproachSpeedThreshold then
            -- Scale from 1.0 to MaxRollDistanceMultiplier based on speed
            local speedRatio = closingSpeed / PARRY_CONFIG.RollApproachSpeedThreshold
            rollSpeedMultiplier = math.min(speedRatio, PARRY_CONFIG.MaxRollDistanceMultiplier)
        end
        rollEmergencyDist = PARRY_CONFIG.RollEmergencyDistance * rollSpeedMultiplier
    end
    
    -- === NEW: Predictive threat detection ===
    local isPredictiveThreat = false
    if currentDistance <= PARRY_CONFIG.PredictiveDistance then
        -- Calculate time to reach us at current closing speed
        if closingSpeed >= PARRY_CONFIG.MinClosingSpeedForEarly then
            local timeToReach = currentDistance / closingSpeed
            -- If they'll reach us within the prediction horizon, it's a threat
            if timeToReach <= PARRY_CONFIG.PredictiveTimeHorizon then
                isPredictiveThreat = true
            end
        end
    end
    
    -- === THREAT EVALUATION ===
    local minDistance = math.min(currentDistance, predictedDistance)
    local willHit = (minDistance <= effectiveReach)
    
    -- Standard emergency (non-roll)
    local isEmergency = currentDistance <= PARRY_CONFIG.EmergencyDistance
    
    -- Roll emergency with dynamic scaling
    local isRollEmergency = isRolling and currentDistance <= rollEmergencyDist
    
    -- Fast approach emergency: if closing very fast and attacking, trigger regardless of current distance
    local isFastApproachEmergency = false
    if closingSpeed >= 25 and currentDistance <= 22 then
        isFastApproachEmergency = true
    end
    
    -- Return true if ANY threat condition is met
    local isThreat = willHit or isEmergency or isRollEmergency or isPredictiveThreat or isFastApproachEmergency
    
    return isThreat, minDistance, closingSpeed
end





-- FOV Circle
local function CreateFOVCircle()
    if State.fovCircle then return end
    
    State.fovCircle = Drawing.new("Circle")
    State.fovCircle.Thickness = 1
    State.fovCircle.NumSides = 64
    State.fovCircle.Filled = false
    State.fovCircle.Visible = false
end

local function UpdateFOVCircle()
    if not State.fovCircle then
        CreateFOVCircle()
    end
    
    if Settings.BowAimbot.ShowFOV and Settings.BowAimbot.Enabled then
        State.fovCircle.Position = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
        State.fovCircle.Radius = Settings.BowAimbot.FOVSize
        State.fovCircle.Color = Settings.BowAimbot.FOVColor
        State.fovCircle.Visible = true
    else
        State.fovCircle.Visible = false
    end
end

local function IsInFOV(position)
    if not Settings.BowAimbot.FOVCheck then return true end
    
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    if not onScreen then return false end
    
    local screenCenter = Vector2.new(Camera.ViewportSize.X / 2, Camera.ViewportSize.Y / 2)
    local targetPos = Vector2.new(screenPos.X, screenPos.Y)
    local distance = (targetPos - screenCenter).Magnitude
    
    return distance <= Settings.BowAimbot.FOVSize
end

local function GetDistanceToCursor(position)
    local screenPos, onScreen = Camera:WorldToViewportPoint(position)
    if not onScreen then return math.huge end
    
    local mousePos = UserInputService:GetMouseLocation()
    local targetPos = Vector2.new(screenPos.X, screenPos.Y)
    
    return (targetPos - mousePos).Magnitude
end

local function IsTargetVisible(targetPart)
    if not Settings.BowAimbot.VisibilityCheck then return true end
    
    local char = GetCharacter()
    if not char then return false end
    
    local head = char:FindFirstChild("Head")
    if not head then return false end
    
    local rayParams = RaycastParams.new()
    rayParams.FilterType = Enum.RaycastFilterType.Exclude
    rayParams.FilterDescendantsInstances = {char, targetPart.Parent}
    
    local direction = (targetPart.Position - head.Position)
    local result = Workspace:Raycast(head.Position, direction, rayParams)
    
    return result == nil
end

-- Get best target based on mode
local function GetBestTarget()
    if not Settings.BowAimbot.Enabled then return nil end
    
    local char = GetCharacter()
    if not char then return nil end
    
    local myRoot = GetRootPart(char)
    if not myRoot then return nil end
    
    local myPos = myRoot.Position
    local candidates = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local enemyChar = player.Character
            if enemyChar then
                local humanoid = GetHumanoid(enemyChar)
                if humanoid and humanoid.Health > 0 then
                    local targetPart = enemyChar:FindFirstChild(Settings.BowAimbot.TargetPart) or GetRootPart(enemyChar)
                    if targetPart then
                        -- Check FOV
                        if IsInFOV(targetPart.Position) then
                            -- Check visibility
                            if IsTargetVisible(targetPart) then
                                local dist = (targetPart.Position - myPos).Magnitude
                                local cursorDist = GetDistanceToCursor(targetPart.Position)
                                table.insert(candidates, {
                                    Player = player,
                                    Character = enemyChar,
                                    TargetPart = targetPart,
                                    Distance = dist,
                                    CursorDistance = cursorDist,
                                    Health = humanoid.Health
                                })
                            end
                        end
                    end
                end
            end
        end
    end
    
    if #candidates == 0 then return nil end
    
    -- Calculate shot quality for each candidate
    for _, candidate in ipairs(candidates) do
        local velocity = candidate.TargetPart.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        local horizontalSpeed = Vector3.new(velocity.X, 0, velocity.Z).Magnitude
        
        -- Higher quality = easier shot
        candidate.ShotQuality = 1.0
        
        -- Stationary targets are easiest
        if horizontalSpeed < 2 then
            candidate.ShotQuality = candidate.ShotQuality + 0.5
        elseif horizontalSpeed < 8 then
            candidate.ShotQuality = candidate.ShotQuality + 0.2
        end
        
        -- Targets at jump apex are easier
        local verticalVelocity = velocity.Y
        if IsAtJumpApex(candidate.Character, verticalVelocity) then
            candidate.ShotQuality = candidate.ShotQuality + 0.3
        end
    end
    
    -- Sort by mode
    local mode = Settings.BowAimbot.Mode
    if mode == "Easiest" then
        table.sort(candidates, function(a, b) return a.ShotQuality > b.ShotQuality end)
    elseif mode == "LowestHP" then
        table.sort(candidates, function(a, b) return a.Health < b.Health end)
    elseif mode == "ClosestToCursor" then
        table.sort(candidates, function(a, b) return a.CursorDistance < b.CursorDistance end)
    else -- Closest (default)
        table.sort(candidates, function(a, b) return a.Distance < b.Distance end)
    end
    
    return candidates[1]
end

-- Bow aimbot state
local bowAimbotSetup = false

-- Full Longbow LocalScript replacement with aimbot
local takenOverBows = setmetatable({}, {__mode = "k"}) -- Track taken over bows to prevent duplicates (weak keys)

local function SetupLongbowTakeover(longbow)
    if not longbow then return end
    
    -- Prevent duplicate takeovers
    if takenOverBows[longbow] then return end
    takenOverBows[longbow] = true
    
    -- Find and disable the original LocalScript
    local originalScript = nil
    for _, child in ipairs(longbow:GetDescendants()) do
        if child:IsA("LocalScript") then
            if child.Enabled then
                child.Enabled = false
                print("[MM PRO v8] Disabled original Longbow LocalScript")
            end
            originalScript = child -- Keep reference even if disabled
            break
        end
    end
    
    if not originalScript then
        print("[MM PRO v8] No LocalScript found in Longbow - cannot setup")
        takenOverBows[longbow] = nil
        return
    end
    
    -- Recreate all the variables from the original script
    local v_u_1 = LocalPlayer
    local v_u_2 = v_u_1.Character or v_u_1.CharacterAdded:Wait()
    local v_u_3 = UserInputService
    local v_u_4 = Camera
    local v_u_5 = v_u_2:WaitForChild("HumanoidRootPart")
    local v_u_6 = longbow
    local v_u_7 = v_u_6:WaitForChild("wep").Value
    if v_u_7 == nil then
        v_u_6:WaitForChild("wep").Value = v_u_6:WaitForChild("Model")
        v_u_7 = v_u_6.wep.Value
    end
    local v_u_8 = v_u_7:WaitForChild("BowPart")
    local v_u_9 = require(game.ReplicatedStorage.Modules.PlrValidations)
    -- HandlePart might be in BowPart OR Right Arm (if already equipped)
    local v_u_10 = v_u_8:FindFirstChild("HandlePart") or v_u_2:FindFirstChild("Right Arm") and v_u_2["Right Arm"]:FindFirstChild("HandlePart")
    if not v_u_10 then
        v_u_10 = v_u_8:WaitForChild("HandlePart", 2)
    end
    local v11 = v_u_2:WaitForChild("Humanoid"):WaitForChild("Animator")
    -- Load animations from the originalScript (works even if disabled)
    local v_u_12 = v11:LoadAnimation(originalScript:WaitForChild("pull", 2))
    local v_u_13 = v11:LoadAnimation(originalScript:WaitForChild("RLD", 2))
    local v_u_14 = v11:LoadAnimation(originalScript:WaitForChild("shot", 2))
    local v_u_15 = v11:LoadAnimation(originalScript:WaitForChild("hold", 2))
    local v_u_16 = v_u_2:WaitForChild("CharacterInformation")
    local v_u_17 = game.ReplicatedStorage:WaitForChild("Assets"):WaitForChild("Projectiles"):WaitForChild("Arrow")
    -- BowWeld might also be moved to Right Arm
    local v_u_18 = v_u_8:FindFirstChild("BowWeld") or v_u_2:FindFirstChild("Right Arm") and v_u_2["Right Arm"]:FindFirstChild("BowWeld")
    if not v_u_18 then
        v_u_18 = v_u_8:WaitForChild("BowWeld", 2)
    end
    local v_u_19 = not v_u_3.KeyboardEnabled and v_u_3.TouchEnabled and true or false
    local v_u_20 = v_u_1:GetMouse()
    local v_u_21 = RaycastParams.new()
    v_u_21.FilterType = Enum.RaycastFilterType.Exclude
    v_u_21.IgnoreWater = true
    local v_u_22 = v_u_6:WaitForChild("fire")
    local v_u_23 = v_u_6:WaitForChild("hitt")
    local v_u_24 = v_u_6:WaitForChild("activate")
    local v_u_25 = game:GetService("Debris")
    local v_u_26 = require(game.ReplicatedStorage.Modules:WaitForChild("PlayerDatastoreInformation"))
    
    -- Aim position function - MODIFIED FOR AIMBOT
    local function v_u_31()
        -- Check for aimbot target first
        if Settings.BowAimbot.Enabled then
            local target = GetBestTarget()
            if target then
                local predictedPos = PredictPosition(target.TargetPart)
                State.currentTarget = target
                return predictedPos, nil
            end
        end
        
        -- Original aim logic
        local v27
        if v_u_19 and v_u_26.ChangedSettings.MobCrosshair == true then
            v27 = Vector2.new(v_u_4.ViewportSize.X / 2, v_u_4.ViewportSize.Y / 2)
        else
            v27 = v_u_3:GetMouseLocation()
        end
        local v28 = v_u_4:ViewportPointToRay(v27.X, v27.Y)
        local v29 = Workspace:Raycast(v28.Origin, v28.Direction * 1000, v_u_21)
        local v30
        if v29 then
            v30 = v29.Position
        else
            v30 = v28.Origin + v28.Direction * 1000
        end
        return v30, v29
    end
    
    local v_u_32 = v_u_19
    local v_u_33 = {}
    local v_u_34 = false
    local v_u_35 = nil
    
    -- Build filter list
    pcall(function()
        for _, v36 in Workspace.CurrentMap:GetDescendants() do
            if v36.Parent.Name == "Borderparts" or (v36:IsDescendantOf(Workspace.CurrentMap.Crossroads.Flags) or (v36.Name == "SpawnLocation" or (v36.Name == "Drownpart" or (v36.Name == "BLACKLIST" or v36:IsA("Part") and v36.CanCollide == false)))) then
                table.insert(v_u_33, v36)
            end
        end
    end)
    
    local function v_u_40(p37, p38)
        if not p37 then return end
        for _, v39 in p37:GetDescendants() do
            if v39.Name ~= "Handle" and (v39:IsA("BasePart") or (v39:IsA("UnionOperation") or (v39:IsA("WedgePart") or v39:IsA("CornerWedgePart")))) then
                v39.Transparency = p38
            end
        end
    end
    
    local v_u_41 = nil
    local v_u_42 = false
    local v_u_43 = nil
    local v_u_44 = nil
    local v_u_45 = game:GetService("TweenService")
    local v_u_46 = Vector2.new(0, -0.5)
    local v_u_47 = Vector2.new(0, 0.5)
    
    -- Hit event handler
    v_u_23.OnClientEvent:Connect(function()
        if v_u_35 then
            v_u_40(v_u_35, 1)
            task.delay(v_u_35.PrimaryPart.Trail.Lifetime, function()
                if v_u_35 then
                    v_u_35:Destroy()
                end
            end)
        end
    end)
    
    -- Mouse icon handler
    v_u_20:GetPropertyChangedSignal("Icon"):Connect(function()
        if v_u_6.Parent == v_u_2 then
            v_u_20.Icon = "rbxassetid://6546609276"
        end
    end)
    
    -- Main activated handler
    v_u_6.Activated:Connect(function()
        if not v_u_34 and (v_u_9.CanUseTools(v_u_1, v_u_6) and not v_u_42) then
            v_u_24:FireServer()
            local v_u_48 = false
            v_u_42 = true
            local v_u_49 = nil
            v_u_49 = v_u_6.Unequipped:Connect(function()
                if not v_u_48 then
                    v_u_48 = true
                    v_u_42 = false
                end
                v_u_49:Disconnect()
            end)
            pcall(function() v_u_8.pullSOund:Play() end)
            v_u_12:Play()
            v_u_12:AdjustSpeed(0.5)
            task.delay(0.8, function()
                v_u_12:AdjustSpeed(0)
            end)
            if v_u_48 or (not v_u_9.CanUseTools(v_u_1, v_u_6) or v_u_34) then
                v_u_42 = false
            else
                local v50 = os.clock()
                v_u_6.Deactivated:Wait()
                local v51 = v_u_48
                while os.clock() - v50 < 0.8 and not v51 do
                    task.wait(0.016)
                    if v_u_32 then
                        v_u_6.Deactivated:Wait()
                    end
                end
                if v51 or (not v_u_9.CanUseTools(v_u_1, v_u_6) or v_u_34) then
                    v_u_42 = false
                else
                    v_u_12:Stop()
                    v_u_14:Play()
                    v_u_14:AdjustSpeed(1.3)
                    v_u_40(v_u_7.Arrow, 1)
                    pcall(function() v_u_8.shooty:Play() end)
                    task.spawn(function()
                        if v_u_35 then
                            v_u_35:Destroy()
                        end
                        local v52 = { Workspace.Explosions, Workspace.BloodFolder, v_u_2 }
                        for _, v53 in Workspace.PlayersCharacters:GetChildren() do
                            if v_u_1.Team and (Players:GetPlayerFromCharacter(v53) and (Players:GetPlayerFromCharacter(v53).Team == v_u_1.Team and game.ReplicatedStorage.ServerSettings.TeamKill.Value == false)) then
                                table.insert(v52, v53)
                            else
                                for _, v54 in v53:GetChildren() do
                                    if v54:IsA("Accessory") then
                                        local v55 = v54.Handle
                                        table.insert(v52, v55)
                                    end
                                end
                            end
                        end
                        v_u_21.FilterDescendantsInstances = v52
                        local v56, _ = v_u_31()  -- THIS NOW USES AIMBOT WHEN ENABLED
                        local v57 = (v56 - v_u_5.Position).Unit * 2
                        local v58 = CFrame.new(v_u_5.Position + v57, v_u_5.Position + v57 * 2)
                        if Workspace:Raycast(v_u_5.Position, v58.Position - v_u_5.Position, v_u_21) then
                            v58 = CFrame.new(v_u_5.Position, v56)
                        end
                        v_u_22:FireServer(v58, v56, Workspace:GetServerTimeNow())
                        v_u_35 = v_u_17:Clone()
                        local v59 = v_u_35
                        v_u_35.PrimaryPart.CFrame = v58
                        v_u_35.Parent = Workspace.Explosions
                        local v60 = v_u_21
                        v60.FilterDescendantsInstances = { v52, v_u_33 }
                        local v61 = nil
                        for v62 = 1, 1000 do
                            if v_u_35 ~= v59 then
                                break
                            end
                            local v63
                            if v62 == 1 then
                                v63 = v58
                            else
                                local v64 = 3.0049249999999996 * v62
                                local v65 = Vector3.new(0, v64, 0) * 0.03
                                local v66 = (550 - 1 * v62) * 0.03
                                local v67 = math.clamp(v66, 1, 550)
                                local v68 = (CFrame.new(v58.Position + v58.LookVector * v67 * v62) - v65 * v62).Position
                                v63 = CFrame.new(v68, v68 + CFrame.new(v61.Position, v68).LookVector)
                            end
                            if not (v_u_35 and v_u_35.PrimaryPart) then
                                break
                            end
                            v_u_35.PrimaryPart.CFrame = v63 * CFrame.Angles(0, 1.5707963267948966, 0)
                            local v69 = v61 and ((v63.Position - v61.Position).Magnitude or 3) or 3
                            if v61 then
                                if v61.Position.Y > 500 then
                                    v_u_25:AddItem(v_u_35, 5)
                                    return
                                end
                                local v70 = Workspace:Raycast(v61.Position, v61.LookVector * v69, v60)
                                if v70 then
                                    local v71 = CFrame.new(v70.Position, v70.Position + v61.LookVector) * CFrame.Angles(0, 1.5707963267948966, 0)
                                    local v72 = Instance.new("WeldConstraint")
                                    v_u_35.PrimaryPart.Anchored = false
                                    v72.Part0 = v70.Instance
                                    v72.Part1 = v_u_35.PrimaryPart
                                    task.delay(v_u_35.PrimaryPart.Trail.Lifetime, function()
                                        if v_u_35 and v_u_35.PrimaryPart then
                                            v_u_35.PrimaryPart.Trail.Enabled = false
                                        end
                                    end)
                                    pcall(function() v_u_35.PrimaryPart.h1tsound:Play() end)
                                    v_u_35.PrimaryPart.CFrame = v71
                                    v72.Parent = v_u_35
                                    local v73
                                    if v70.Instance.Parent:FindFirstChild("HumanoidRootPart") then
                                        v73 = v70.Instance.Parent:FindFirstChild("Humanoid")
                                    else
                                        v73 = nil
                                    end
                                    local v74 = v_u_23
                                    local v75 = v70.Instance
                                    local v76 = v70.Position
                                    local v77 = v_u_35.PrimaryPart.CFrame
                                    local v78 = Workspace:GetServerTimeNow()
                                    local v79 = 3.0049249999999996 * v62
                                    local v80 = Vector3.new(0, v79, 0) * 0.03
                                    local v81 = (550 - 1 * v62) * 0.03
                                    local v82 = math.clamp(v81, 1, 550)
                                    v74:FireServer(v62, v75, v73, v76, v77, v78, CFrame.new(v58.Position + v58.LookVector * v82 * v62) - v80 * v62)
                                    v_u_25:AddItem(v_u_35, 5)
                                    break
                                end
                            end
                            task.wait(0.03)
                            v61 = v63
                        end
                    end)
                    v_u_34 = true
                    local v83 = v_u_1.PlayerGui:WaitForChild("GameUI"):WaitForChild("Frame")
                    if v_u_44 then
                        v_u_44:Cancel()
                    end
                    v_u_44 = v_u_45:Create(v83.SwordIcon, TweenInfo.new(0.2, Enum.EasingStyle.Linear), {
                        ["ImageTransparency"] = 1
                    })
                    v83.SwordIcon.ImageTransparency = 0.2
                    v83.SwordIcon.UIGradient.Offset = v_u_47
                    local v84 = {
                        ["Offset"] = v_u_46
                    }
                    v_u_43 = v_u_45:Create(v83:WaitForChild("SwordIcon"):WaitForChild("UIGradient"), TweenInfo.new(1.5, Enum.EasingStyle.Linear), v84)
                    v_u_43:Play()
                    task.delay(1.5, function()
                        if v_u_43 then
                            v_u_43:Cancel()
                        end
                        if v_u_44 then
                            v_u_44:Play()
                        end
                        local v_u_85 = nil
                        v_u_85 = v_u_6.Activated:Connect(function()
                            if v_u_9.CanUseTools(v_u_1, v_u_6) then
                                v_u_24:FireServer()
                                v_u_85:Disconnect()
                                v_u_13:Play()
                                v_u_13:AdjustSpeed(0.8)
                                task.wait(0.375)
                                v_u_40(v_u_41, 0)
                                task.wait(0.375)
                                v_u_40(v_u_7.Arrow, 0)
                                v_u_40(v_u_41, 1)
                                v_u_42 = false
                                v_u_34 = false
                            end
                        end)
                    end)
                end
            end
        end
    end)
    
    -- Equipped handler
    v_u_6.Equipped:Connect(function()
        v_u_15:Play()
        if v_u_6:FindFirstChild("Arrow") and not v_u_34 then
            v_u_41 = v_u_6.Arrow
            v_u_41.ArrowFake1.ArrowFake1.Part0 = v_u_2:WaitForChild("Left Arm")
            v_u_41.ArrowFake1.ArrowFake1.Parent = v_u_2:WaitForChild("Left Arm")
            v_u_41.Parent = v_u_2
        end
        v_u_10.Parent = v_u_2:WaitForChild("Right Arm")
        v_u_10.Part0 = v_u_2:WaitForChild("Right Arm")
        v_u_18.Parent = v_u_2["Right Arm"]
        v_u_8.backweld.Part0 = nil
        if v_u_3.TouchEnabled and not v_u_3.KeyboardEnabled then
            local v86 = v_u_16.MobileCrosshairEnabled
            v86.Value = v86.Value + 1
        else
            v_u_20.Icon = "rbxassetid://6546609276"
        end
        if v_u_7.Parent ~= Workspace.Explosions then
            v_u_7.Parent = Workspace.Explosions
        end
    end)
    
    -- Unequipped handler
    v_u_6.Unequipped:Connect(function()
        v_u_15:Stop()
        v_u_12:Stop()
        if v_u_3.TouchEnabled and not v_u_3.KeyboardEnabled then
            local v87 = v_u_16.MobileCrosshairEnabled
            v87.Value = v87.Value - 1
        elseif v_u_20.Icon == "rbxassetid://6546609276" then
            v_u_20.Icon = ""
        end
        if v_u_41 then
            v_u_41.Parent = v_u_6
            if v_u_2["Left Arm"]:FindFirstChild("ArrowFake1") then
                v_u_2["Left Arm"].ArrowFake1.Parent = v_u_41.ArrowFake1
            end
        end
        v_u_10.Part0 = nil
        v_u_10.Parent = v_u_8
        v_u_8.CFrame = v_u_2.Torso.CFrame * CFrame.Angles(1.5707963267948966, 0.7853981633974483, 4.71238898038469) * CFrame.new(Vector3.new(-0.55, 0, 0))
        v_u_8.backweld.Part0 = v_u_2.Torso
    end)
    
    print("[MM PRO v8] Longbow takeover complete with full logic!")
end

-- Watch for Longbow equip
local function SetupBowAimbot()
    if bowAimbotSetup then return end
    bowAimbotSetup = true
    
    local function onCharacter(char)
        char.ChildAdded:Connect(function(child)
            if child.Name == "Longbow" then
                task.wait(0.1)
                SetupLongbowTakeover(child)
            end
        end)
        
        -- Check if already has Longbow
        local existing = char:FindFirstChild("Longbow")
        if existing then
            SetupLongbowTakeover(existing)
        end
    end
    
    LocalPlayer.CharacterAdded:Connect(onCharacter)
    if GetCharacter() then
        onCharacter(GetCharacter())
    end
    
    print("[MM PRO v8] Bow aimbot ready!")
end

-- Initialize bow aimbot
SetupBowAimbot()



local function UpdateHitbox()
    -- Restore and cleanup when disabled
    if not Settings.Hitbox.Enabled then
        for player, sizes in pairs(State.originalSizes) do
            local char = player.Character
            if char then
                for partName, data in pairs(sizes) do
                    local part = char:FindFirstChild(partName)
                    if part and part:IsA("BasePart") then
                        part.Size = data.size
                        part.Transparency = data.transparency
                    end
                end
            end
        end
        State.originalSizes = {}
        State.hitboxParts = {}
        return
    end
    
    -- Clean up for players who left or died
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local humanoid = GetHumanoid(char)
                if humanoid and humanoid.Health > 0 then
                    if not State.originalSizes[player] then
                        State.originalSizes[player] = {}
                    end
                    
                    local function ExpandPart(partName)
                        local part = char:FindFirstChild(partName)
                        if part and part:IsA("BasePart") then
                            -- Store original only once
                            if not State.originalSizes[player][partName] then
                                State.originalSizes[player][partName] = {
                                    size = part.Size,
                                    transparency = part.Transparency
                                }
                            end
                            part.Size = Vector3.new(Settings.Hitbox.Size, Settings.Hitbox.Size, Settings.Hitbox.Size)
                            part.Transparency = Settings.Hitbox.Transparency
                            part.CanCollide = false
                        end
                    end
                    
                    if Settings.Hitbox.ExpandHead then
                        ExpandPart("Head")
                    end
                    if Settings.Hitbox.ExpandTorso then
                        local torso = char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")
                        if torso then
                            ExpandPart(torso.Name)
                        end
                    end
                end
            end
        end
    end
end

-- PREDICTION GHOST VISUALIZATION SYSTEM - Shows transparent "ghost" characters

-- Parts to clone for ghost visualization
local GHOST_PARTS = {"Head", "Torso", "UpperTorso", "LowerTorso", "HumanoidRootPart", 
                     "Left Arm", "Right Arm", "Left Leg", "Right Leg",
                     "LeftUpperArm", "LeftLowerArm", "LeftHand",
                     "RightUpperArm", "RightLowerArm", "RightHand",
                     "LeftUpperLeg", "LeftLowerLeg", "LeftFoot",
                     "RightUpperLeg", "RightLowerLeg", "RightFoot"}

-- Create a ghost model for a character
local function CreateGhostModel(sourceChar, ghostType)
    local ghostFolder = Instance.new("Model")
    ghostFolder.Name = "Ghost_" .. ghostType .. "_" .. sourceChar.Name
    
    local sourceRoot = sourceChar:FindFirstChild("HumanoidRootPart")
    if not sourceRoot then return nil end
    
    -- Create ghost root part first
    local ghostRoot = Instance.new("Part")
    ghostRoot.Name = "GhostRoot"
    ghostRoot.Size = Vector3.new(2, 2, 1)
    ghostRoot.Transparency = 1
    ghostRoot.CanCollide = false
    ghostRoot.Anchored = true
    ghostRoot.CFrame = sourceRoot.CFrame
    ghostRoot.Parent = ghostFolder
    ghostFolder.PrimaryPart = ghostRoot
    
    -- Get color and transparency based on type
    local color, transparency
    if ghostType == "Bow" then
        color = Settings.Visuals.BowGhostColor
        transparency = Settings.Visuals.BowGhostTransparency
    else
        color = Settings.Visuals.ParryGhostColor
        transparency = Settings.Visuals.ParryGhostTransparency
    end
    
    -- Clone visible parts
    for _, partName in ipairs(GHOST_PARTS) do
        local sourcePart = sourceChar:FindFirstChild(partName)
        if sourcePart and sourcePart:IsA("BasePart") then
            local ghostPart = Instance.new("Part")
            ghostPart.Name = partName
            ghostPart.Size = sourcePart.Size
            ghostPart.CFrame = sourcePart.CFrame
            ghostPart.Color = color
            ghostPart.Material = Enum.Material.ForceField
            ghostPart.Transparency = transparency
            ghostPart.CanCollide = false
            ghostPart.Anchored = true
            ghostPart.CastShadow = false
            ghostPart.Parent = ghostFolder
            
            -- Add glow effect
            local highlight = Instance.new("SurfaceLight")
            highlight.Color = color
            highlight.Brightness = 0.5
            highlight.Range = 2
            highlight.Parent = ghostPart
        end
    end
    
    -- Add a beam/line from source to ghost for clarity
    local beam = Instance.new("Beam")
    local attachment0 = Instance.new("Attachment")
    local attachment1 = Instance.new("Attachment")
    
    attachment0.Parent = sourceRoot
    attachment1.Parent = ghostRoot
    
    beam.Attachment0 = attachment0
    beam.Attachment1 = attachment1
    beam.Color = ColorSequence.new(color)
    beam.Transparency = NumberSequence.new(0.5)
    beam.Width0 = 0.1
    beam.Width1 = 0.1
    beam.FaceCamera = true
    beam.Parent = ghostFolder
    
    -- Store attachments for cleanup
    ghostFolder:SetAttribute("Attachment0", attachment0.Name)
    
    ghostFolder.Parent = Workspace:FindFirstChild("Explosions") or Workspace
    
    return ghostFolder
end

-- Update ghost position based on predicted CFrame
local function UpdateGhostPosition(ghost, predictedCFrame, sourceChar)
    if not ghost or not ghost.PrimaryPart then return end
    
    local sourceRoot = sourceChar:FindFirstChild("HumanoidRootPart")
    if not sourceRoot then return end
    
    -- Calculate offset from source root to predicted position
    local offset = predictedCFrame.Position - sourceRoot.Position
    
    -- Update ghost root
    ghost.PrimaryPart.CFrame = predictedCFrame
    
    -- Update all ghost parts to maintain relative positions
    for _, partName in ipairs(GHOST_PARTS) do
        local sourcePart = sourceChar:FindFirstChild(partName)
        local ghostPart = ghost:FindFirstChild(partName)
        
        if sourcePart and ghostPart then
            -- Apply the same offset to each part
            ghostPart.CFrame = sourcePart.CFrame + offset
        end
    end
end

-- Cleanup a ghost model
local function DestroyGhost(ghost)
    if ghost then
        -- Find and destroy the attachment in the source character
        for _, child in ipairs(ghost:GetDescendants()) do
            if child:IsA("Attachment") and child.Parent and child.Parent.Parent ~= ghost then
                pcall(function() child:Destroy() end)
            end
        end
        pcall(function() ghost:Destroy() end)
    end
end

-- Cleanup all ghosts of a type
local function CleanupGhosts(ghostTable)
    for player, ghost in pairs(ghostTable) do
        DestroyGhost(ghost)
        ghostTable[player] = nil
    end
end

-- BOW PREDICTION GHOST

local function UpdateBowGhosts()
    -- If disabled, clean up all bow ghosts
    if not Settings.Visuals.ShowBowGhost then
        CleanupGhosts(State.bowGhosts)
        return
    end
    
    local myChar = GetCharacter()
    if not myChar then 
        CleanupGhosts(State.bowGhosts)
        return 
    end
    
    local myRoot = GetRootPart(myChar)
    if not myRoot then
        CleanupGhosts(State.bowGhosts)
        return
    end
    
    local myPos = myRoot.Position
    
    -- Track which players we've processed this frame
    local processedPlayers = {}
    
    -- Loop through ALL players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local enemyChar = player.Character
            if enemyChar then
                local humanoid = GetHumanoid(enemyChar)
                local enemyRoot = GetRootPart(enemyChar)
                
                if humanoid and humanoid.Health > 0 and enemyRoot then
                    local distance = (enemyRoot.Position - myPos).Magnitude
                    
                    -- Check if within range
                    if distance <= Settings.Visuals.BowGhostRange then
                        processedPlayers[player] = true
                        
                        -- For visualization, always predict the root part so the model stands on the ground correctly
                        local predictedPos = PredictPosition(enemyRoot)
                        
                        -- Calculate predicted CFrame
                        local predictedCFrame = CFrame.new(predictedPos) * 
                            CFrame.Angles(0, select(2, enemyRoot.CFrame:ToEulerAnglesYXZ()), 0)
                        
                        -- Create or update ghost
                        if not State.bowGhosts[player] or not State.bowGhosts[player].Parent then
                            State.bowGhosts[player] = CreateGhostModel(enemyChar, "Bow")
                        end
                        
                        if State.bowGhosts[player] then
                            UpdateGhostPosition(State.bowGhosts[player], predictedCFrame, enemyChar)
                            
                            -- Update colors in case they changed
                            for _, part in ipairs(State.bowGhosts[player]:GetChildren()) do
                                if part:IsA("BasePart") and part.Name ~= "GhostRoot" then
                                    part.Color = Settings.Visuals.BowGhostColor
                                    part.Transparency = Settings.Visuals.BowGhostTransparency
                                end
                            end
                        end
                    else
                        -- Out of range, remove ghost
                        if State.bowGhosts[player] then
                            DestroyGhost(State.bowGhosts[player])
                            State.bowGhosts[player] = nil
                        end
                    end
                else
                    -- Dead or no root, remove ghost
                    if State.bowGhosts[player] then
                        DestroyGhost(State.bowGhosts[player])
                        State.bowGhosts[player] = nil
                    end
                end
            else
                -- No character, remove ghost
                if State.bowGhosts[player] then
                    DestroyGhost(State.bowGhosts[player])
                    State.bowGhosts[player] = nil
                end
            end
        end
    end
    
    -- Clean up ghosts for players who left
    for player, ghost in pairs(State.bowGhosts) do
        if not processedPlayers[player] then
            DestroyGhost(ghost)
            State.bowGhosts[player] = nil
        end
    end
end

-- PARRY/ANTI-HIT PREDICTION GHOST

local function UpdateParryGhosts()
    if not Settings.Visuals.ShowParryGhost then
        CleanupGhosts(State.parryGhosts)
        return
    end
    
    local myChar = GetCharacter()
    if not myChar then 
        CleanupGhosts(State.parryGhosts)
        return 
    end
    
    local myRoot = GetRootPart(myChar)
    if not myRoot then 
        CleanupGhosts(State.parryGhosts)
        return 
    end
    
    local myPos = myRoot.Position
    
    -- Default prediction time for parry ghost (how far ahead to predict)
    local defaultPredictionTime = 0.35
    
    -- Track which players we've processed this frame
    local processedPlayers = {}
    
    -- Loop through ALL players
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local enemyChar = player.Character
            if enemyChar then
                local humanoid = GetHumanoid(enemyChar)
                local enemyRoot = GetRootPart(enemyChar)
                
                if humanoid and humanoid.Health > 0 and enemyRoot then
                    local distance = (enemyRoot.Position - myPos).Magnitude
                    
                    if distance <= Settings.Visuals.ParryGhostRange then
                        processedPlayers[player] = true
                        
                        local timeToPredict = defaultPredictionTime
                        local isAttacking = false
                        local isThreat = false
                        
                        -- Check states using ACTUAL CFrame
                        local charInfo = enemyChar:FindFirstChild("CharacterInformation")
                        local isParrying = charInfo and charInfo:FindFirstChild("IsParrying") and charInfo.IsParrying.Value == true
                        local isRolling = charInfo and charInfo:FindFirstChild("IsRolling") and charInfo.IsRolling.Value == true
                        
                        -- Note: Don't skip rolling enemies - they can roll-attack!
                        if not isParrying then
                            -- Check if facing us using ACTUAL CFrame
                            local isActuallyFacing = IsActuallyFacingMe(enemyChar, myChar, 0.5)
                            
                            -- Track facing history
                            TrackFacingHistory(player, isActuallyFacing)
                            local hasRecentlyFaced = HasRecentlyFacedUs(player)
                            
                            isAttacking, _ = IsEnemyAttacking(enemyChar)
                            
                            if isAttacking and (isActuallyFacing or hasRecentlyFaced) then
                                isThreat = true
                                -- Try to get actual hit timing
                                local enemy = {
                                    Character = enemyChar,
                                    Root = enemyRoot,
                                    Tool = enemyChar:FindFirstChildWhichIsA("Tool")
                                }
                                local hitInfo = nil
                                pcall(function()
                                    hitInfo = GetTimeUntilHit(enemy, myChar)
                                end)
                                if hitInfo then
                                    timeToPredict = math.max(0.05, hitInfo.timeToHit)
                                end
                            end
                        end
                        
                        -- === USE SAME PREDICTION LOGIC AS BOW (with dampening) ===
                        local rawVelocity = enemyRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
                        rawVelocity = ClampVelocity(rawVelocity)
                        
                        local movementOffset = Vector3.new(0, 0, 0)
                        
                        if not IsTargetStationary(rawVelocity) then
                            -- Get smoothed velocity data (same as bow)
                            local data = ProcessVelocityData(player, rawVelocity, enemyRoot.Position)
                            local smoothedVelocity = data.smoothedVelocity
                            local confidence = data.confidence
                            
                            -- Apply confidence and distance factor (same formula as bow)
                            -- Use shorter distance scale for parry (50 studs vs 400 for bow)
                            local distanceFactor = math.clamp(1 - (distance / 50), 0.5, 1)
                            local adjustedPredictionTime = timeToPredict * confidence * distanceFactor
                            
                            -- Cap prediction time
                            adjustedPredictionTime = math.min(adjustedPredictionTime, 0.5)
                            
                            -- Calculate horizontal movement offset only
                            local horizontalVelocity = Vector3.new(smoothedVelocity.X, 0, smoothedVelocity.Z)
                            local horizontalOffset = horizontalVelocity * adjustedPredictionTime
                            
                            -- Clamp to reasonable movement
                            local maxMove = MAX_HORIZONTAL_SPEED * timeToPredict * 1.2
                            if horizontalOffset.Magnitude > maxMove then
                                horizontalOffset = horizontalOffset.Unit * maxMove
                            end
                            
                            movementOffset = horizontalOffset
                        end
                        
                        -- Ghost shows predicted position
                        local predictedPos = enemyRoot.Position + movementOffset
                        
                        -- Calculate predicted CFrame using ACTUAL rotation (not predicted)
                        local predictedCFrame = CFrame.new(predictedPos) * 
                            CFrame.Angles(0, select(2, enemyRoot.CFrame:ToEulerAnglesYXZ()), 0)
                        
                        if not State.parryGhosts[player] or not State.parryGhosts[player].Parent then
                            State.parryGhosts[player] = CreateGhostModel(enemyChar, "Parry")
                        end
                        
                        if State.parryGhosts[player] then
                            -- Calculate offset from actual root to predicted root
                            local offset = predictedPos - enemyRoot.Position
                            
                            -- Update ghost root
                            if State.parryGhosts[player].PrimaryPart then
                                pcall(function()
                                    State.parryGhosts[player].PrimaryPart.CFrame = predictedCFrame
                                end)
                            end
                            
                            -- Update all ghost parts maintaining relative positions
                            for _, partName in ipairs(GHOST_PARTS) do
                                local sourcePart = enemyChar:FindFirstChild(partName)
                                local ghostPart = State.parryGhosts[player]:FindFirstChild(partName)
                                
                                if sourcePart and ghostPart then
                                    pcall(function()
                                        ghostPart.CFrame = sourcePart.CFrame + offset
                                    end)
                                end
                            end
                            
                            local ghostColor = Settings.Visuals.ParryGhostColor
                            local ghostTrans = Settings.Visuals.ParryGhostTransparency
                            
                            if isThreat then
                                -- Attacking and facing us - make more urgent (redder, more solid)
                                local urgencyFactor = math.clamp(1 - (timeToPredict / 0.4), 0, 1)
                                ghostColor = Settings.Visuals.ParryGhostColor:Lerp(Color3.new(1, 0, 0), urgencyFactor * 0.5)
                                ghostTrans = ghostTrans - (urgencyFactor * 0.3)
                                
                                -- Extra red for roll-attacks
                                if isRolling then
                                    ghostColor = ghostColor:Lerp(Color3.new(1, 0.3, 0), 0.3)
                                end
                            elseif isAttacking then
                                -- Attacking but not facing us - slightly different color (orange)
                                ghostColor = Settings.Visuals.ParryGhostColor:Lerp(Color3.new(1, 0.5, 0), 0.3)
                            elseif isRolling then
                                -- Rolling (potential roll-attack) - yellow tint
                                ghostColor = Settings.Visuals.ParryGhostColor:Lerp(Color3.new(1, 1, 0), 0.2)
                            end
                            
                            -- Update colors
                            for _, part in ipairs(State.parryGhosts[player]:GetChildren()) do
                                if part:IsA("BasePart") and part.Name ~= "GhostRoot" then
                                    part.Color = ghostColor
                                    part.Transparency = math.clamp(ghostTrans, 0.2, 0.9)
                                end
                            end
                        end
                    else
                        if State.parryGhosts[player] then
                            DestroyGhost(State.parryGhosts[player])
                            State.parryGhosts[player] = nil
                        end
                    end
                else
                    -- Dead or no root, remove ghost
                    if State.parryGhosts[player] then
                        DestroyGhost(State.parryGhosts[player])
                        State.parryGhosts[player] = nil
                    end
                end
            else
                -- No character, remove ghost
                if State.parryGhosts[player] then
                    DestroyGhost(State.parryGhosts[player])
                    State.parryGhosts[player] = nil
                end
            end
        end
    end
    
    -- Clean up ghosts for players who left
    for player, ghost in pairs(State.parryGhosts) do
        if not processedPlayers[player] then
            DestroyGhost(ghost)
            State.parryGhosts[player] = nil
        end
    end
end

local function UpdateAllGhosts()
    UpdateBowGhosts()
    UpdateParryGhosts()
end



local function CreateESP(player)
    if State.espObjects[player] then return end
    
    local char = player.Character
    if not char then return end
    
    local root = GetRootPart(char)
    if not root then return end
    
    local billboard = Instance.new("BillboardGui")
    billboard.Name = "ESP_" .. player.Name
    billboard.Adornee = root
    billboard.Size = UDim2.new(0, 150, 0, 60)
    billboard.StudsOffset = Vector3.new(0, 3, 0)
    billboard.AlwaysOnTop = true
    billboard.Parent = root
    
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Size = UDim2.new(1, 0, 0.4, 0)
    nameLabel.BackgroundTransparency = 1
    nameLabel.TextColor3 = Color3.new(1, 1, 1)
    nameLabel.TextStrokeTransparency = 0
    nameLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    nameLabel.Font = Enum.Font.GothamBold
    nameLabel.TextSize = 14
    nameLabel.Text = player.Name
    nameLabel.Parent = billboard
    
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Size = UDim2.new(1, 0, 0.3, 0)
    infoLabel.Position = UDim2.new(0, 0, 0.4, 0)
    infoLabel.BackgroundTransparency = 1
    infoLabel.TextColor3 = Color3.new(0.8, 0.8, 0.8)
    infoLabel.TextStrokeTransparency = 0
    infoLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    infoLabel.Font = Enum.Font.Gotham
    infoLabel.TextSize = 11
    infoLabel.Text = ""
    infoLabel.Parent = billboard
    
    local stateLabel = Instance.new("TextLabel")
    stateLabel.Size = UDim2.new(1, 0, 0.3, 0)
    stateLabel.Position = UDim2.new(0, 0, 0.7, 0)
    stateLabel.BackgroundTransparency = 1
    stateLabel.TextColor3 = Color3.new(1, 1, 0)
    stateLabel.TextStrokeTransparency = 0
    stateLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
    stateLabel.Font = Enum.Font.GothamBold
    stateLabel.TextSize = 10
    stateLabel.Text = ""
    stateLabel.Parent = billboard
    
    State.espObjects[player] = {
        Billboard = billboard,
        NameLabel = nameLabel,
        InfoLabel = infoLabel,
        StateLabel = stateLabel
    }
end

local function CleanupESP(player)
    if State.espObjects[player] then
        pcall(function() State.espObjects[player].Billboard:Destroy() end)
        State.espObjects[player] = nil
    end
end

local function UpdateESP()
    if not Settings.ESP.Enabled then
        for player, _ in pairs(State.espObjects) do
            CleanupESP(player)
        end
        return
    end
    
    local myChar = GetCharacter()
    if not myChar then return end
    
    local myRoot = GetRootPart(myChar)
    if not myRoot then return end
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= LocalPlayer then
            local char = player.Character
            if char then
                local root = GetRootPart(char)
                if root then
                    local distance = (root.Position - myRoot.Position).Magnitude
                    
                    if distance <= Settings.ESP.MaxDistance then
                        if not State.espObjects[player] then
                            CreateESP(player)
                        end
                        
                        local esp = State.espObjects[player]
                        if esp and esp.Billboard and esp.Billboard.Parent and esp.Billboard.Adornee then
                            local humanoid = char:FindFirstChildOfClass("Humanoid")
                            local tool = char:FindFirstChildWhichIsA("Tool")
                            
                            -- Info text
                            local healthText = humanoid and string.format("%.0f HP", humanoid.Health) or "?"
                            local distText = string.format("%.0fm", distance)
                            local weaponText = tool and tool.Name or "Unarmed"
                            esp.InfoLabel.Text = healthText .. " | " .. distText .. " | " .. weaponText
                            
                            -- State detection
                            local isAttacking = IsEnemyAttacking(char)
                            local isParrying = IsEnemyParrying(char)
                            local isRolling = IsEnemyRolling(char)
                            local isCrawling = IsEnemyCrawling(char)
                            local isInvincible = IsEnemyInvincible(char)
                            local isFrozen = IsEnemyFrozen(char)
                            
                            -- State text
                            local states = {}
                            if isAttacking then table.insert(states, "ATK") end
                            if isParrying then table.insert(states, "PARRY") end
                            if isRolling then table.insert(states, "ROLL") end
                            if isCrawling then table.insert(states, "DOWN") end
                            if isInvincible then table.insert(states, "INVN") end
                            if isFrozen then table.insert(states, "FRZN") end
                            esp.StateLabel.Text = #states > 0 and table.concat(states, " | ") or ""
                            
                            -- Color based on state
                            if isAttacking then
                                esp.NameLabel.TextColor3 = Color3.fromRGB(255, 50, 50) -- Red
                            elseif isParrying then
                                esp.NameLabel.TextColor3 = Color3.fromRGB(50, 200, 255) -- Cyan
                            elseif isRolling then
                                esp.NameLabel.TextColor3 = Color3.fromRGB(255, 255, 50) -- Yellow
                            elseif isCrawling then
                                esp.NameLabel.TextColor3 = Color3.fromRGB(150, 150, 150) -- Gray
                            elseif isInvincible then
                                esp.NameLabel.TextColor3 = Color3.fromRGB(200, 100, 255) -- Purple
                            else
                                esp.NameLabel.TextColor3 = Color3.fromRGB(255, 255, 255) -- White
                            end
                        else
                            CleanupESP(player)
                            CreateESP(player)
                        end
                    else
                        CleanupESP(player)
                    end
                else
                    CleanupESP(player)
                end
            else
                CleanupESP(player)
            end
        end
    end
end

-- INFINITE STAMINA

local staminaConnection = nil
local function SetupInfiniteStamina()
    if staminaConnection then staminaConnection:Disconnect() end
    
    staminaConnection = RunService.Heartbeat:Connect(function()
        if Settings.InfiniteStamina then
            local ci = GetCharacterInfo()
            if ci then
                local stamina = ci:FindFirstChild("Stamina")
                if stamina then
                    stamina.Value = 100
                end
            end
        end
    end)
end

SetupInfiniteStamina()

-- [[ CLEANUP ]]

local function CleanupPlayer(player)
    if FacingHistory then FacingHistory[player] = nil end
    if AnimationHistory then AnimationHistory[player] = nil end
    if ParryVelocityHistory then ParryVelocityHistory[player] = nil end
    if VelocityHistory then VelocityHistory[player] = nil end
end

Players.PlayerRemoving:Connect(function(player)
    CleanupPlayer(player)
end)

LocalPlayer.CharacterAdded:Connect(function()
    -- Clear all history on respawn (fresh start)
    FacingHistory = {}
    AnimationHistory = {}
    ParryVelocityHistory = {}
    PingHistory.samples = {}
    
    task.wait(1)
    State.lastParryTime = 0
    State.lastDashTime = 0
end)



-- [[ MAIN AUTO DEFENSE ]]
-- ProcessAutoParry has been consolidated into ProcessAutoDefense

local function ProcessAutoDefense(enemies)
    if not Settings.AutoDefense.Enabled then return false, nil end
    
    local myChar = GetCharacter()
    if not myChar then return false, nil end
    
    local myRoot = GetRootPart(myChar)
    if not myRoot then return false, nil end
    
    -- Sort enemies by threat priority (closing speed / distance = urgency)
    table.sort(enemies, function(a, b)
        local aVel = GetParrySmoothedVelocity(a.Player, a.Root)
        local bVel = GetParrySmoothedVelocity(b.Player, b.Root)
        
        local aToMe = (myRoot.Position - a.Root.Position)
        local bToMe = (myRoot.Position - b.Root.Position)
        
        local aDir = aToMe.Magnitude > 0.1 and aToMe.Unit or Vector3.zero
        local bDir = bToMe.Magnitude > 0.1 and bToMe.Unit or Vector3.zero
        
        local aClosing = math.max(0, aVel:Dot(aDir))
        local bClosing = math.max(0, bVel:Dot(bDir))
        
        -- Rolling enemies get priority boost
        local aRollBoost = IsEnemyRolling(a.Character) and 1.5 or 1.0
        local bRollBoost = IsEnemyRolling(b.Character) and 1.5 or 1.0
        
        -- Threat score = (closing speed * roll boost) / distance
        local aThreat = (aClosing * aRollBoost) / math.max(a.Distance, 1)
        local bThreat = (bClosing * bRollBoost) / math.max(b.Distance, 1)
        
        return aThreat > bThreat
    end)
    
    for _, enemy in ipairs(enemies) do
        if enemy.Player == LocalPlayer then continue end
        
        -- Skip if not attacking
        if not enemy.IsAttacking then continue end
        
        -- Get hit timing info
        local hitInfo = GetTimeUntilHit(enemy, myChar)
        
        -- Lower confidence threshold for faster response (was 0.3)
        local confidenceThreshold = 0.2
        
        -- Even lower threshold for rolling enemies (they're faster)
        if IsEnemyRolling(enemy.Character) then
            confidenceThreshold = 0.15
        end
        
        if hitInfo and hitInfo.confidence > confidenceThreshold then
            local willHit, dist, closingSpeed = WillAttackHitUs(enemy, myChar, hitInfo.timeToHit)
            
            -- Additional check: if they're rolling fast toward us and attacking, always consider it a threat
            local isRolling = IsEnemyRolling(enemy.Character)
            local isFastRollApproach = isRolling and closingSpeed >= 18 and dist <= 20
            
            if willHit or isFastRollApproach then
                -- Build reason string for debugging
                local reason = "NORMAL"
                if isFastRollApproach then
                    reason = "FAST_ROLL"
                elseif isRolling then
                    reason = "ROLL"
                elseif closingSpeed >= 20 then
                    reason = "FAST"
                end
                
                -- TRY PARRY FIRST (always prefer parry when available)
                if CanSelfParry() then
                    if DoParry() then 
                        return true, string.format("PARRY [%s]: %s (%.1fm @ %.0f sp)", 
                            reason, enemy.Player.Name, dist, closingSpeed)
                    end
                end
                
                -- FALLBACK TO DASH only if parry is unavailable
                if DoDash() then 
                    return true, string.format("DASH [%s]: %s (%.1fm @ %.0f sp)", 
                        reason, enemy.Player.Name, dist, closingSpeed)
                end
            end
        end
    end
    return false, nil
end


local function MainLoop()
    local char = GetCharacter()
    if not char then return false, "No character" end
    
    local detected = false
    local detectionInfo = "None"
    
    -- OPTIMIZATION: Cache enemies once per frame
    local maxRange = math.max(
        Settings.AutoDefense.Enabled and Settings.AutoDefense.Range or 0,
        Settings.KillAura.Enabled and Settings.KillAura.Range or 0,
        25 -- Minimum scan range
    )
    local allEnemies = GetNearbyEnemies(maxRange)
    
    local function FilterByRange(enemies, range)
        local filtered = {}
        for _, e in ipairs(enemies) do
            if e.Distance <= range then
                table.insert(filtered, e)
            end
        end
        return filtered
    end
    
    -- Update velocity history for all nearby enemies (for prediction)
    for _, enemy in ipairs(allEnemies) do
        if enemy.Player then
            ProcessVelocityData(enemy.Player, enemy.Velocity, enemy.Root.Position)
        end
    end
    
    -- Also update our own velocity history for self-prediction
    local myRoot = GetRootPart(char)
    if myRoot then
        local myVel = myRoot.AssemblyLinearVelocity or Vector3.new(0, 0, 0)
        ProcessVelocityData(LocalPlayer, myVel, myRoot.Position)
    end
    
    -- Auto Defense (parry first, dash as fallback)
    if Settings.AutoDefense.Enabled then
        local defended, info = ProcessAutoDefense(allEnemies)
        if defended then
            detected = true
            detectionInfo = info
        end
    end
    
    if Settings.KillAura.Enabled then
        local tool = GetEquippedTool()
        if tool then
            local currentTime = tick()
            if currentTime - State.lastKillAuraAttack >= Settings.KillAura.AttackDelay then
                local enemies = FilterByRange(allEnemies, Settings.KillAura.Range)
                
                for _, enemy in ipairs(enemies) do
                    if IsFacing(char, enemy.Character, 0.5) then
                        if Settings.KillAura.CheckParry and enemy.IsParrying then
                            continue
                        end
                        if Settings.KillAura.CheckRoll and enemy.IsRolling then
                            continue
                        end
                        if Settings.KillAura.CheckInvincible and enemy.IsInvincible then
                            continue
                        end
                        if enemy.IsCrawling then
                            continue
                        end
                        
                        tool:Activate()
                        State.lastKillAuraAttack = currentTime
                        break
                    end
                end
            end
        end
    end
    
    -- ESP
    UpdateESP()
    
    -- FOV Circle
    UpdateFOVCircle()
    
    -- Hitbox
    UpdateHitbox()
    
    -- Update prediction ghosts
    UpdateAllGhosts()
    
    return detected, detectionInfo
end



local Window = Rayfield:CreateWindow({
    Name = "MM PRO v8 - ULTIMATE",
    Theme = "Default",
    ToggleUIKeybind = Enum.KeyCode.RightShift,
    ConfigurationSaving = {
        Enabled = true,
        FolderName = "MortemMetallumGUI",
        FileName = "v8Config"
    }
})

-- Combat Tab
local CombatTab = Window:CreateTab("Combat", 4483362458)

CombatTab:CreateSection("Auto Defense")
CombatTab:CreateToggle({
    Name = "Enable Auto Defense",
    CurrentValue = false,
    Flag = "AutoDefense",
    Callback = function(V) Settings.AutoDefense.Enabled = V end
})
CombatTab:CreateSlider({
    Name = "Range",
    Range = {5, 25},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 15,
    Flag = "DefenseRange",
    Callback = function(V) Settings.AutoDefense.Range = V end
})

CombatTab:CreateSection("Kill Aura")
CombatTab:CreateToggle({
    Name = "Enable Kill Aura",
    CurrentValue = false,
    Flag = "KillAura",
    Callback = function(V) Settings.KillAura.Enabled = V end
})
CombatTab:CreateSlider({
    Name = "Range",
    Range = {5, 15},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 10,
    Flag = "KillAuraRange",
    Callback = function(V) Settings.KillAura.Range = V end
})
CombatTab:CreateToggle({
    Name = "Skip Parrying Enemies",
    CurrentValue = true,
    Flag = "KACheckParry",
    Callback = function(V) Settings.KillAura.CheckParry = V end
})
CombatTab:CreateToggle({
    Name = "Skip Rolling Enemies",
    CurrentValue = true,
    Flag = "KACheckRoll",
    Callback = function(V) Settings.KillAura.CheckRoll = V end
})
CombatTab:CreateToggle({
    Name = "Skip Invincible Enemies",
    CurrentValue = true,
    Flag = "KACheckInvn",
    Callback = function(V) Settings.KillAura.CheckInvincible = V end
})
CombatTab:CreateParagraph({
    Title = "Kill Aura Info",
    Content = "Won't swing if enemy is parrying, rolling, or invincible. Target must be facing you."
})

-- Bow Tab
local BowTab = Window:CreateTab("Bow Aimbot", 4483362458)

BowTab:CreateSection("Silent Aim")
BowTab:CreateToggle({
    Name = "Enable Bow Aimbot",
    CurrentValue = false,
    Flag = "BowAimbot",
    Callback = function(V) Settings.BowAimbot.Enabled = V end
})
BowTab:CreateDropdown({
    Name = "Targeting Mode",
    Options = {"Closest", "ClosestToCursor", "LowestHP", "Easiest"},
    CurrentOption = {"Closest"},
    Flag = "TargetMode",
    Callback = function(V) Settings.BowAimbot.Mode = V[1] end
})
BowTab:CreateDropdown({
    Name = "Target Part",
    Options = {"HumanoidRootPart", "Head", "UpperTorso"},
    CurrentOption = {"HumanoidRootPart"},
    Flag = "TargetPart",
    Callback = function(V) Settings.BowAimbot.TargetPart = V[1] end
})
BowTab:CreateToggle({
    Name = "Predict Movement",
    CurrentValue = true,
    Flag = "PredictMove",
    Callback = function(V) Settings.BowAimbot.PredictMovement = V end
})

BowTab:CreateSection("FOV Settings")
BowTab:CreateToggle({
    Name = "FOV Check",
    CurrentValue = true,
    Flag = "FOVCheck",
    Callback = function(V) Settings.BowAimbot.FOVCheck = V end
})
BowTab:CreateSlider({
    Name = "FOV Size",
    Range = {50, 500},
    Increment = 10,
    Suffix = " px",
    CurrentValue = 200,
    Flag = "FOVSize",
    Callback = function(V) Settings.BowAimbot.FOVSize = V end
})
BowTab:CreateToggle({
    Name = "Show FOV Circle",
    CurrentValue = true,
    Flag = "ShowFOV",
    Callback = function(V) Settings.BowAimbot.ShowFOV = V end
})
BowTab:CreateToggle({
    Name = "Visibility Check",
    CurrentValue = false,
    Flag = "VisCheck",
    Callback = function(V) Settings.BowAimbot.VisibilityCheck = V end
})
BowTab:CreateParagraph({
    Title = "How It Works",
    Content = "Hooks AimPos remote to redirect arrows to the predicted target position. Accounts for velocity, gravity, and ping."
})

-- Visual Tab
local VisualTab = Window:CreateTab("Visuals", 4483362458)

VisualTab:CreateSection("ESP")
VisualTab:CreateToggle({
    Name = "Enable ESP",
    CurrentValue = false,
    Flag = "ESP",
    Callback = function(V) Settings.ESP.Enabled = V end
})
VisualTab:CreateSlider({
    Name = "Max Distance",
    Range = {100, 1000},
    Increment = 50,
    Suffix = " studs",
    CurrentValue = 500,
    Flag = "ESPDist",
    Callback = function(V) Settings.ESP.MaxDistance = V end
})
VisualTab:CreateParagraph({
    Title = "ESP Colors",
    Content = "RED = Attacking\nCYAN = Parrying\nYELLOW = Rolling\nGRAY = Downed\nPURPLE = Invincible\nWHITE = Idle"
})

VisualTab:CreateSection("Hitbox Expander")
VisualTab:CreateToggle({
    Name = "Enable Hitbox Expander",
    CurrentValue = false,
    Flag = "Hitbox",
    Callback = function(V) Settings.Hitbox.Enabled = V end
})
VisualTab:CreateSlider({
    Name = "Hitbox Size",
    Range = {5, 20},
    Increment = 1,
    Suffix = " studs",
    CurrentValue = 10,
    Flag = "HitboxSize",
    Callback = function(V) Settings.Hitbox.Size = V end
})
VisualTab:CreateSlider({
    Name = "Transparency",
    Range = {0, 1},
    Increment = 0.1,
    Suffix = "",
    CurrentValue = 0.7,
    Flag = "HitboxTrans",
    Callback = function(V) Settings.Hitbox.Transparency = V end
})

VisualTab:CreateSection("Prediction Ghosts")

VisualTab:CreateToggle({
    Name = "Show Bow Prediction Ghosts",
    CurrentValue = false,
    Flag = "BowGhost",
    Callback = function(V) Settings.Visuals.ShowBowGhost = V end
})
VisualTab:CreateSlider({
    Name = "Bow Ghost Range",
    Range = {25, 500},
    Increment = 25,
    Suffix = " studs",
    CurrentValue = 200,
    Flag = "BowGhostRange",
    Callback = function(V) Settings.Visuals.BowGhostRange = V end
})
VisualTab:CreateColorPicker({
    Name = "Bow Ghost Color",
    Color = Color3.fromRGB(0, 255, 255),
    Flag = "BowGhostColor",
    Callback = function(V) Settings.Visuals.BowGhostColor = V end
})
VisualTab:CreateSlider({
    Name = "Bow Ghost Transparency",
    Range = {0.3, 0.9},
    Increment = 0.1,
    Suffix = "",
    CurrentValue = 0.6,
    Flag = "BowGhostTrans",
    Callback = function(V) Settings.Visuals.BowGhostTransparency = V end
})

VisualTab:CreateDivider()

VisualTab:CreateToggle({
    Name = "Show Parry Prediction Ghosts",
    CurrentValue = false,
    Flag = "ParryGhost",
    Callback = function(V) Settings.Visuals.ShowParryGhost = V end
})
VisualTab:CreateSlider({
    Name = "Parry Ghost Range",
    Range = {10, 100},
    Increment = 5,
    Suffix = " studs",
    CurrentValue = 50,
    Flag = "ParryGhostRange",
    Callback = function(V) Settings.Visuals.ParryGhostRange = V end
})
VisualTab:CreateColorPicker({
    Name = "Parry Ghost Color",
    Color = Color3.fromRGB(255, 80, 80),
    Flag = "ParryGhostColor",
    Callback = function(V) Settings.Visuals.ParryGhostColor = V end
})
VisualTab:CreateSlider({
    Name = "Parry Ghost Transparency",
    Range = {0.3, 0.9},
    Increment = 0.1,
    Suffix = "",
    CurrentValue = 0.6,
    Flag = "ParryGhostTrans",
    Callback = function(V) Settings.Visuals.ParryGhostTransparency = V end
})

VisualTab:CreateParagraph({
    Title = "Ghost Info",
    Content = "CYAN = Bow prediction (where arrow will land)\nRED = Parry prediction (where enemy will be)\n\nParry ghosts get BRIGHTER RED when enemy is attacking you!\nORANGE = attacking but not facing you"
})

-- Movement Tab
local MovementTab = Window:CreateTab("Movement", 4483362458)

MovementTab:CreateSection("Stamina")
MovementTab:CreateToggle({
    Name = "Infinite Stamina",
    CurrentValue = false,
    Flag = "InfStamina",
    Callback = function(V) Settings.InfiniteStamina = V end
})

MovementTab:CreateSection("Manual Actions")
MovementTab:CreateButton({
    Name = "Force Parry",
    Callback = function()
        local t = GetAbilityType()
        if t == "HealParry" then
            CharFunClient.healparry()
        elseif t == "WinterParry" then
            CharFunClient.winterparry()
        else
            CharFunClient.stunparry()
        end
    end
})
MovementTab:CreateButton({
    Name = "Force Dash",
    Callback = function() CharFunClient.roll() end
})
MovementTab:CreateButton({
    Name = "Force Kick",
    Callback = function() CharFunClient.kick() end
})
MovementTab:CreateButton({
    Name = "Reset Cooldowns",
    Callback = function()
        pcall(function() CharFunClient.ResetCooldowns() end)
        State.lastParryTime = 0
        State.lastDashTime = 0
    end
})

-- Info Tab
local InfoTab = Window:CreateTab("Info", 4483362458)

InfoTab:CreateSection("Status")
local statusLabel = InfoTab:CreateLabel("Ready")
local detectLabel = InfoTab:CreateLabel("Detected: None")
local targetLabel = InfoTab:CreateLabel("Target: None")

InfoTab:CreateSection("Keybinds")
InfoTab:CreateParagraph({
    Title = "Toggle Keybinds",
    Content = "Z = Auto Parry\nX = Kill Aura\nC = ESP\nV = Bow Aimbot\nB = Hitbox Expander\nRightShift = Toggle GUI"
})

InfoTab:CreateSection("Settings")
InfoTab:CreateButton({
    Name = "Destroy GUI",
    Callback = function()
        for _, c in pairs(Connections) do
            if c then pcall(function() c:Disconnect() end) end
        end
        if staminaConnection then 
            pcall(function() staminaConnection:Disconnect() end) 
            staminaConnection = nil
        end
        
        -- Clear drawing objects properly
        if State.fovCircle then 
            pcall(function() 
                State.fovCircle.Visible = false
                State.fovCircle:Remove() 
            end)
            State.fovCircle = nil
        end
        
        for player, _ in pairs(State.espObjects) do
            CleanupESP(player)
        end
        State.espObjects = {}
        
        -- Restore original sizes before destroying
        for player, sizes in pairs(State.originalSizes) do
            local char = player.Character
            if char then
                for partName, data in pairs(sizes) do
                    local part = char:FindFirstChild(partName)
                    if part and part:IsA("BasePart") then
                        pcall(function()
                            part.Size = data.size
                            part.Transparency = data.transparency
                        end)
                    end
                end
            end
        end
        State.originalSizes = {}
        State.hitboxParts = {}
        
        -- Clear velocity history
        VelocityHistory = {}
        
        -- Clean up ghosts
        CleanupGhosts(State.bowGhosts)
        CleanupGhosts(State.parryGhosts)
        
        Rayfield:Destroy()
    end
})

--[[═══════════════════════════════════════════════════════════════
    CONNECTIONS
═══════════════════════════════════════════════════════════════]]

-- Main Loop
Connections.Main = RunService.Heartbeat:Connect(function()
    local detected, detectionInfo = MainLoop()
    
    if detected then
        detectLabel:Set(detectionInfo)
    else
        detectLabel:Set("Detected: None")
    end
    
    -- Update target label
    if State.currentTarget then
        targetLabel:Set("Target: " .. State.currentTarget.Player.Name)
    else
        targetLabel:Set("Target: None")
    end
    
    -- Update status
    local ci = GetCharacterInfo()
    local stamina = ci and ci:FindFirstChild("Stamina")
    local ping = math.floor(GetPing() * 1000)
    statusLabel:Set(string.format("Ping: %dms | Stamina: %s", ping, stamina and tostring(math.floor(stamina.Value)) or "?"))
end)

-- Character respawn handler
Connections.CharacterAdded = LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    State.lastParryTime = 0
    State.lastDashTime = 0
    State.lastKillAuraAttack = 0
    State.currentTarget = nil
    takenOverBows = setmetatable({}, {__mode = "k"})
    
    -- Clean up old ESP
    for player, _ in pairs(State.espObjects) do
        CleanupESP(player)
    end
    
    -- Clear velocity and acceleration history for fresh prediction data
    VelocityHistory = {}
    AccelerationHistory = {}
    
    -- Clean up ghosts on respawn
    CleanupGhosts(State.bowGhosts)
    CleanupGhosts(State.parryGhosts)
    
    -- Clear facing history
    FacingHistory = {}
end)

-- Clean up ESP when players leave
Connections.PlayerRemoving = Players.PlayerRemoving:Connect(function(player)
    CleanupESP(player)
    if State.hitboxParts[player] then
        -- Don't destroy parts here, they are part of the character which is being removed
        State.hitboxParts[player] = nil
        State.originalSizes[player] = nil
    end
    VelocityHistory[player] = nil
    AccelerationHistory[player] = nil
    FacingHistory[player] = nil
    
    -- Clean up ghosts for this player
    if State.bowGhosts[player] then
        DestroyGhost(State.bowGhosts[player])
        State.bowGhosts[player] = nil
    end
    if State.parryGhosts[player] then
        DestroyGhost(State.parryGhosts[player])
        State.parryGhosts[player] = nil
    end
end)

-- Keybinds
Connections.Keybinds = UserInputService.InputBegan:Connect(function(input, gameProcessed)
    if gameProcessed then return end
    
    if input.KeyCode == Enum.KeyCode.Z then
        Settings.AutoDefense.Enabled = not Settings.AutoDefense.Enabled
        Rayfield:Notify({
            Title = "Auto Defense",
            Content = Settings.AutoDefense.Enabled and "Enabled" or "Disabled",
            Duration = 1
        })
    elseif input.KeyCode == Enum.KeyCode.X then
        Settings.KillAura.Enabled = not Settings.KillAura.Enabled
        Rayfield:Notify({
            Title = "Kill Aura",
            Content = Settings.KillAura.Enabled and "Enabled" or "Disabled",
            Duration = 1
        })
    elseif input.KeyCode == Enum.KeyCode.C then
        Settings.ESP.Enabled = not Settings.ESP.Enabled
        Rayfield:Notify({
            Title = "ESP",
            Content = Settings.ESP.Enabled and "Enabled" or "Disabled",
            Duration = 1
        })
    elseif input.KeyCode == Enum.KeyCode.V then
        Settings.BowAimbot.Enabled = not Settings.BowAimbot.Enabled
        Rayfield:Notify({
            Title = "Bow Aimbot",
            Content = Settings.BowAimbot.Enabled and "Enabled" or "Disabled",
            Duration = 1
        })
    elseif input.KeyCode == Enum.KeyCode.B then
        Settings.Hitbox.Enabled = not Settings.Hitbox.Enabled
        Rayfield:Notify({
            Title = "Hitbox Expander",
            Content = Settings.Hitbox.Enabled and "Enabled" or "Disabled",
            Duration = 1
        })
    end
end)

-- Load config and notify
Rayfield:LoadConfiguration()

-- Startup notification
Rayfield:Notify({
    Title = "MM PRO v8 - ULTIMATE",
    Content = "Loaded!\nZ/X/C/V/B = Toggles\nRightShift = GUI",
    Duration = 5
})

print("[MM PRO v8] Loaded!")
print("[MM PRO v8] - " .. tostring((function() local c=0 for _ in pairs(ATTACK_ANIMS) do c=c+1 end return c end)()) .. " attack anims verified")
print("[MM PRO v8] - Kill aura checks parry/roll/invincible states")
print("[MM PRO v8] - Silent aim with prediction + FOV")
print("[MM PRO v8] - Enhanced ESP with state detection")
print("[MM PRO v8] - Keybinds: Z/X/C/V/B")
