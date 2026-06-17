local playersService = game:GetService("Players")
local runService = game:GetService("RunService")
local tweenService = game:GetService("TweenService")
local userInputService = game:GetService("UserInputService")
local camera = workspace.CurrentCamera
local localPlayer = playersService.LocalPlayer

local table_insert = table.insert

local state = {
    enabled = false,
    wall = false,
    npc = false,
    cameraShift = false,
    target = nil,
    connection = nil,
    zoom = 12,
    aimPart = "Head",
    currentDirection = nil,
    collapsed = false,
    radius = 50,
    closestAvailableTarget = nil,
    currentShift = 0,
    highlightTarget = false,
    espEnabled = false,
    currentSlot = 1,
    trackMode = "Camera"
}

local guiPosition = UDim2.new(0.5, -140, 0, 80)

local sharedRaycastParams = RaycastParams.new()
sharedRaycastParams.FilterType = Enum.RaycastFilterType.Exclude

local filterTable = {nil, nil, camera}

local function lineOfSight(targetCharacter, targetPart)
    local character = localPlayer.Character
    if not character or not targetPart then return false end
    
    local origin = camera.CFrame.Position 
    local direction = targetPart.Position - origin
    
    filterTable[1] = character
    filterTable[2] = targetCharacter
    sharedRaycastParams.FilterDescendantsInstances = filterTable
    
    local raycastResult = workspace:Raycast(origin, direction, sharedRaycastParams)
    return raycastResult == nil
end

local gethui = gethui or (getfenv and getfenv().gethui)
local uiParent = (gethui and gethui()) or game:GetService("CoreGui") or localPlayer:WaitForChild("PlayerGui")

local screenGui = Instance.new("ScreenGui")
screenGui.Name = "meggdTracker"
screenGui.ResetOnSpawn = false
screenGui.IgnoreGuiInset = true 
screenGui.Parent = uiParent

local rangeInput = Instance.new("TextBox")

local npcCache = {}

local function addNpc(descendant)
    if descendant:IsA("Humanoid") then
        local char = descendant.Parent
        if char then
            npcCache[char] = descendant
        end
    end
end

workspace.DescendantAdded:Connect(addNpc)
workspace.DescendantRemoving:Connect(function(descendant)
    if descendant:IsA("Humanoid") then
        local char = descendant.Parent
        if char then
            npcCache[char] = nil
        end
    end
end)

for _, desc in ipairs(workspace:GetDescendants()) do
    addNpc(desc)
end

local function getTargets()
    local results = {}
    local playerCharacters = {}
    local allPlayers = playersService:GetPlayers()
    
    for index = 1, #allPlayers do
        local player = allPlayers[index]
        if player.Character then
            playerCharacters[player.Character] = true
        end
    end
    
    if state.npc then
        for character, humanoid in pairs(npcCache) do
            if character and character.Parent and humanoid.Health > 0 then
                if not playerCharacters[character] then
                    table_insert(results, character)
                end
            else
                if not character or not character.Parent then
                    npcCache[character] = nil
                end
            end
        end
    end
    
    for index = 1, #allPlayers do
        local player = allPlayers[index]
        if player ~= localPlayer and player.Character then
            table_insert(results, player.Character)
        end
    end
    
    return results
end

local function getClosestTarget(radius, targets)
    local character = localPlayer.Character
    if not character then return nil end
    local center = camera.ViewportSize / 2
    local closestTarget = nil
    local closestDistance = radius
    
    for index = 1, #targets do
        local targetCharacter = targets[index]
        local bodyPart = targetCharacter:FindFirstChild(state.aimPart) or targetCharacter:FindFirstChild("Head")
        if not bodyPart then continue end
        
        local position, onScreen = camera:WorldToViewportPoint(bodyPart.Position)
        if onScreen then
            local screenPos2D = Vector2.new(position.X, position.Y)
            local distance = (screenPos2D - center).Magnitude
            if distance < closestDistance then
                if state.wall or lineOfSight(targetCharacter, bodyPart) then
                    closestDistance = distance
                    closestTarget = targetCharacter
                end
            end
        end
    end
    
    return closestTarget
end

local espHighlights = {}
local targetHighlight = Instance.new("Highlight")
targetHighlight.Name = "MEGGD_TargetHighlight"
targetHighlight.FillColor = Color3.fromRGB(255, 32, 32)
targetHighlight.OutlineColor = Color3.fromRGB(255, 255, 255)
targetHighlight.FillTransparency = 0.5
targetHighlight.OutlineTransparency = 0
targetHighlight.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop

local function clearEsp()
    for char, hl in pairs(espHighlights) do
        if hl then hl:Destroy() end
    end
    table.clear(espHighlights)
end

task.spawn(function()
    while true do
        if state.enabled then
            local targets = getTargets()
            state.closestAvailableTarget = getClosestTarget(state.radius, targets)
            
            if state.espEnabled then
                local currentChars = {}
                for i = 1, #targets do
                    local char = targets[i]
                    if char ~= state.target and char:FindFirstChild("HumanoidRootPart") then
                        currentChars[char] = true
                        if not espHighlights[char] then
                            local hl = Instance.new("Highlight")
                            hl.Name = "MEGGD_ESP"
                            hl.FillColor = Color3.fromHex("1E508C")
                            hl.OutlineColor = Color3.fromRGB(255, 255, 255)
                            hl.FillTransparency = 0.6
                            hl.OutlineTransparency = 0
                            hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
                            hl.Parent = char
                            espHighlights[char] = hl
                        end
                    end
                end
                for char, hl in pairs(espHighlights) do
                    if not currentChars[char] or not char.Parent or char == state.target then
                        if hl then hl:Destroy() end
                        espHighlights[char] = nil
                    end
                end
            else
                clearEsp()
            end
        else
            state.closestAvailableTarget = nil
            clearEsp()
        end
        
        if state.enabled and state.highlightTarget and state.target and state.target.Parent then
            if targetHighlight.Parent ~= state.target then
                targetHighlight.Parent = state.target
            end
        else
            targetHighlight.Parent = nil
        end
        
        task.wait(0.1) 
    end
end)

local function stopTracking()
    if state.connection then
        runService:UnbindFromRenderStep("AimLockTrack")
        state.connection = nil
    end
    state.target = nil
    state.currentDirection = nil
    
    local character = localPlayer.Character
    if character then
        local oldMin = localPlayer.CameraMinZoomDistance
        local oldMax = localPlayer.CameraMaxZoomDistance
        local currentZoom = state.zoom or 12
        
        localPlayer.CameraMinZoomDistance = currentZoom
        localPlayer.CameraMaxZoomDistance = currentZoom
        localPlayer.CameraMinZoomDistance = oldMin
        localPlayer.CameraMaxZoomDistance = oldMax
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if humanoid then
            camera.CameraSubject = humanoid
        end
    end
    
    if camera.CameraType ~= Enum.CameraType.Custom then
        camera.CameraType = Enum.CameraType.Custom
    end
end

local trackFilterTable = {nil, nil}

local function startTracking()
    if state.connection then
        runService:UnbindFromRenderStep("AimLockTrack")
    end
    state.connection = true
    
    local lastFrameTime = os.clock()
    
    runService:BindToRenderStep("AimLockTrack", Enum.RenderPriority.Camera.Value, function()
        local currentTime = os.clock()
        local deltaTime = currentTime - lastFrameTime
        lastFrameTime = currentTime
        
        local currentTarget = state.target
        local isValid = false
        
        if currentTarget and currentTarget.Parent then
            local humanoid = currentTarget:FindFirstChildOfClass("Humanoid")
            local targetPart = currentTarget:FindFirstChild(state.aimPart) or currentTarget:FindFirstChild("Head")
            if humanoid and humanoid.Health > 0 and targetPart then
                local inRangeAndVisible = true
                if not state.wall and not lineOfSight(currentTarget, targetPart) then
                    inRangeAndVisible = false
                end
                if inRangeAndVisible then
                    isValid = true
                end
            end
        end
        
        if not isValid then
            currentTarget = state.closestAvailableTarget
        end
        
        state.target = currentTarget
        
        local character = localPlayer.Character
        if state.target and character then
            local rootPart = character:FindFirstChild("HumanoidRootPart")
            local humanoid = state.target:FindFirstChildOfClass("Humanoid")
            local targetRoot = state.target:FindFirstChild("HumanoidRootPart")
            
            if rootPart and humanoid and humanoid.Health > 0 and targetRoot then
                if state.trackMode == "Camera" then
                    if camera.CameraType ~= Enum.CameraType.Scriptable then
                        camera.CameraType = Enum.CameraType.Scriptable
                    end
                    
                    local basePosition = rootPart.Position + Vector3.new(0, 1.5, 0)
                    local targetPosition
                    
                    if state.aimPart == "Head" then
                        targetPosition = targetRoot.Position + Vector3.new(0, 1.5, 0)
                    else
                        local customPart = state.target:FindFirstChild(state.aimPart) or state.target:FindFirstChild("Head")
                        targetPosition = customPart and customPart.Position or targetRoot.Position
                    end
                    
                    local targetDirection = (targetPosition - basePosition).Unit
                    state.currentDirection = targetDirection
                    
                    local currentZoom = state.zoom or 12
                    local finalPosition
                    
                    if currentZoom <= 2 then
                        finalPosition = basePosition
                    else
                        local idealPosition = basePosition - (state.currentDirection * currentZoom)
                        
                        trackFilterTable[1] = character
                        trackFilterTable[2] = state.target
                        sharedRaycastParams.FilterDescendantsInstances = trackFilterTable
                        local raycastResult = workspace:Raycast(basePosition, idealPosition - basePosition, sharedRaycastParams)
                        
                        finalPosition = idealPosition
                        if raycastResult then
                            finalPosition = raycastResult.Position + (raycastResult.Normal * 0.5)
                        end
                    end
                    
                    local targetShift = state.cameraShift and 2.5 or 0
                    state.currentShift = state.currentShift + (targetShift - state.currentShift) * math.min(deltaTime * 14, 1)
                    
                    local finalCFrame = CFrame.lookAt(finalPosition, finalPosition + state.currentDirection)
                    if state.currentShift > 0.001 then
                        finalCFrame = finalCFrame * CFrame.new(state.currentShift, 0, 0)
                    end
                    
                    camera.CFrame = finalCFrame
                    camera.Focus = rootPart.CFrame
                else
                    if camera.CameraType ~= Enum.CameraType.Custom then
                        camera.CameraType = Enum.CameraType.Custom
                    end
                    local targetPos = targetRoot.Position
                    local lookAtPos = Vector3.new(targetPos.X, rootPart.Position.Y, targetPos.Z)
                    rootPart.CFrame = CFrame.lookAt(rootPart.Position, lookAtPos)
                end
            else
                stopTracking()
                startTracking()
            end
        else
            if camera.CameraType ~= Enum.CameraType.Custom then
                camera.CameraType = Enum.CameraType.Custom
            end
            if character then
                local localHumanoid = character:FindFirstChildOfClass("Humanoid")
                if localHumanoid and camera.CameraSubject ~= localHumanoid then
                    camera.CameraSubject = localHumanoid
                end
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local basePosition = rootPart.Position + Vector3.new(0, 1.5, 0)
                    local distance = (camera.CFrame.Position - basePosition).Magnitude
                    if distance > 0.1 and distance < 60 then
                        state.zoom = distance
                    end
                end
            end
        end
    end)
end

userInputService.InputChanged:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseWheel then
        if state.enabled and state.target then
            local scrollDirection = input.Position.Z
            state.zoom = math.clamp(state.zoom - (scrollDirection * 2), 0.5, 60)
        end
    end
end)

local lastScale = 1
userInputService.TouchPinch:Connect(function(touchPositions, scale, velocity, inputState)
    if state.enabled and state.target then
        if inputState == Enum.UserInputState.Begin then
            lastScale = scale
        elseif inputState == Enum.UserInputState.Change then
            local deltaScale = scale - lastScale
            state.zoom = math.clamp(state.zoom - (deltaScale * 15), 0.5, 60)
            lastScale = scale
        end
    end
end)

local fovFrame = Instance.new("Frame")
fovFrame.AnchorPoint = Vector2.new(0.5, 0.5)
fovFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
fovFrame.BackgroundColor3 = Color3.fromHex("1E508C")
fovFrame.BackgroundTransparency = 0.94 
fovFrame.BorderSizePixel = 0
fovFrame.Visible = false
fovFrame.Parent = screenGui

local fovCorner = Instance.new("UICorner")
fovCorner.CornerRadius = UDim.new(1, 0)
fovCorner.Parent = fovFrame

local fovStroke = Instance.new("UIStroke")
fovStroke.Color = Color3.fromHex("1E508C")
fovStroke.Thickness = 3 
fovStroke.Transparency = 0.2 
fovStroke.Parent = fovFrame

local mainFrame = Instance.new("Frame")
mainFrame.Size = UDim2.new(0, 280, 0, 45)
mainFrame.Position = UDim2.new(0.5, -140, 0, 80)
mainFrame.BackgroundColor3 = Color3.fromHex("28282D")
mainFrame.BorderSizePixel = 0
mainFrame.ClipsDescendants = true
mainFrame.Parent = screenGui

local uiStroke = Instance.new("UIStroke")
uiStroke.Color = Color3.fromRGB(155, 32, 32)
uiStroke.Thickness = 1
uiStroke.Parent = mainFrame

local headerFrame = Instance.new("Frame")
headerFrame.Size = UDim2.new(1, 0, 0, 45)
headerFrame.BackgroundColor3 = Color3.fromHex("28282D")
headerFrame.BorderSizePixel = 0
headerFrame.Parent = mainFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, -100, 1, 0)
titleLabel.Position = UDim2.new(0, 12, 0, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Font = Enum.Font.Arcade
titleLabel.TextSize = 13
titleLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
titleLabel.Text = "MEGGD AimLock"
titleLabel.TextXAlignment = Enum.TextXAlignment.Left
titleLabel.Parent = headerFrame

local toggleButton = Instance.new("TextButton")
toggleButton.Size = UDim2.new(0, 50, 0, 24)
toggleButton.Position = UDim2.new(1, -58, 0.5, -12)
toggleButton.BackgroundColor3 = Color3.fromRGB(155, 32, 32)
toggleButton.BorderSizePixel = 0
toggleButton.Font = Enum.Font.Arcade
toggleButton.TextSize = 12
toggleButton.TextColor3 = Color3.fromRGB(210, 210, 210)
toggleButton.Text = "OFF"
toggleButton.AutoButtonColor = false
toggleButton.Parent = headerFrame

local collapseButton = Instance.new("TextButton")
collapseButton.Size = UDim2.new(0, 24, 0, 24)
collapseButton.Position = UDim2.new(1, -88, 0.5, -12)
collapseButton.BackgroundColor3 = Color3.fromHex("1E508C")
collapseButton.BorderSizePixel = 0
collapseButton.Text = ""
collapseButton.AutoButtonColor = false
collapseButton.BackgroundTransparency = 1
collapseButton.ClipsDescendants = true
collapseButton.Visible = false
collapseButton.Parent = headerFrame

local collapseStroke = Instance.new("UIStroke")
collapseStroke.Color = Color3.fromRGB(52, 52, 65)
collapseStroke.Thickness = 1
collapseStroke.Transparency = 1
collapseStroke.Parent = collapseButton

local arrowLabel = Instance.new("TextLabel")
arrowLabel.Size = UDim2.new(1, 0, 1, 0)
arrowLabel.Position = UDim2.new(0.5, 0, 0.5, 0)
arrowLabel.AnchorPoint = Vector2.new(0.5, 0.5)
arrowLabel.BackgroundTransparency = 1
arrowLabel.Font = Enum.Font.Arcade
arrowLabel.TextSize = 16
arrowLabel.TextColor3 = Color3.fromRGB(210, 210, 210)
arrowLabel.Text = "▼"
arrowLabel.TextXAlignment = Enum.TextXAlignment.Center
arrowLabel.TextTransparency = 1
arrowLabel.Parent = collapseButton

local pagesContainer = Instance.new("Frame")
pagesContainer.Size = UDim2.new(1, 0, 0, 186)
pagesContainer.Position = UDim2.new(0, 0, 0, 46)
pagesContainer.BackgroundTransparency = 1
pagesContainer.ClipsDescendants = true
pagesContainer.Parent = mainFrame

local page1 = Instance.new("Frame")
page1.Size = UDim2.new(1, 0, 1, 0)
page1.Position = UDim2.new(0, 0, 0, 0)
page1.BackgroundTransparency = 1
page1.Parent = pagesContainer

local page2 = Instance.new("Frame")
page2.Size = UDim2.new(1, 0, 1, 0)
page2.Position = UDim2.new(1, 0, 0, 0)
page2.BackgroundTransparency = 1
page2.Parent = pagesContainer

local dotsFrame = Instance.new("Frame")
dotsFrame.Size = UDim2.new(0, 60, 0, 12)
dotsFrame.Position = UDim2.new(0.5, -30, 0, 168)
dotsFrame.BackgroundTransparency = 1
dotsFrame.ZIndex = 5
dotsFrame.Parent = mainFrame

local dot1 = Instance.new("Frame")
dot1.AnchorPoint = Vector2.new(0.5, 0.5)
dot1.Size = UDim2.new(0, 7, 0, 7)
dot1.Position = UDim2.new(0.3, 0, 0.5, 0)
dot1.BackgroundColor3 = Color3.fromHex("00C8FF")
dot1.BorderSizePixel = 0
dot1.Parent = dotsFrame
local d1Corner = Instance.new("UICorner")
d1Corner.CornerRadius = UDim.new(1, 0)
d1Corner.Parent = dot1

local dot2 = Instance.new("Frame")
dot2.AnchorPoint = Vector2.new(0.5, 0.5)
dot2.Size = UDim2.new(0, 4, 0, 4)
dot2.Position = UDim2.new(0.7, 0, 0.5, 0)
dot2.BackgroundColor3 = Color3.fromHex("005577")
dot2.BackgroundTransparency = 0.4
dot2.BorderSizePixel = 0
dot2.Parent = dotsFrame
local d2Corner = Instance.new("UICorner")
d2Corner.CornerRadius = UDim.new(1, 0)
d2Corner.Parent = dot2

local function updateSlot()
    local p1Target = state.currentSlot == 1 and UDim2.new(0, 0, 0, 0) or UDim2.new(-1, 0, 0, 0)
    local p2Target = state.currentSlot == 1 and UDim2.new(1, 0, 0, 0) or UDim2.new(0, 0, 0, 0)
    
    tweenService:Create(page1, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = p1Target}):Play()
    tweenService:Create(page2, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {Position = p2Target}):Play()
    
    if state.currentSlot == 1 then
        tweenService:Create(dot1, TweenInfo.new(0.15), {Size = UDim2.new(0, 7, 0, 7), BackgroundColor3 = Color3.fromHex("00C8FF"), BackgroundTransparency = 0}):Play()
        tweenService:Create(dot2, TweenInfo.new(0.15), {Size = UDim2.new(0, 4, 0, 4), BackgroundColor3 = Color3.fromHex("005577"), BackgroundTransparency = 0.4}):Play()
    else
        tweenService:Create(dot1, TweenInfo.new(0.15), {Size = UDim2.new(0, 4, 0, 4), BackgroundColor3 = Color3.fromHex("005577"), BackgroundTransparency = 0.4}):Play()
        tweenService:Create(dot2, TweenInfo.new(0.15), {Size = UDim2.new(0, 7, 0, 7), BackgroundColor3 = Color3.fromHex("00C8FF"), BackgroundTransparency = 0}):Play()
    end
end

local swipeData = {active = false, startX = 0, startY = 0, moved = false}

userInputService.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
        local pos = input.Position
        local guiPos = pagesContainer.AbsolutePosition
        local guiSize = pagesContainer.AbsoluteSize
        
        if pos.X >= guiPos.X and pos.X <= guiPos.X + guiSize.X and pos.Y >= guiPos.Y and pos.Y <= guiPos.Y + guiSize.Y then
            swipeData.active = true
            swipeData.startX = pos.X
            swipeData.startY = pos.Y
            swipeData.moved = false
        end
    end
end)

userInputService.InputChanged:Connect(function(input)
    if swipeData.active and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local deltaX = input.Position.X - swipeData.startX
        if math.abs(deltaX) > 15 then
            swipeData.moved = true
        end
    end
end)

userInputService.InputEnded:Connect(function(input)
    if swipeData.active and (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) then
        swipeData.active = false
        local deltaX = input.Position.X - swipeData.startX
        
        if math.abs(deltaX) > 25 then
            if deltaX < 0 and state.currentSlot == 1 then
                state.currentSlot = 2
                updateSlot()
            elseif deltaX > 0 and state.currentSlot == 2 then
                state.currentSlot = 1
                updateSlot()
            end
        end
        
        task.defer(function()
            swipeData.moved = false
        end)
    end
end)

local function connectSafeButton(button, callback)
    button.Activated:Connect(function()
        if swipeData.moved then return end
        callback()
    end)
end

local function updateFrameSize()
    local targetSize = UDim2.new(0, 280, 0, 45)
    local targetRotation = 0
    if state.enabled and not state.collapsed then
        targetSize = UDim2.new(0, 280, 0, 235)
    end
    if state.collapsed then
        targetRotation = 180
    end
    tweenService:Create(mainFrame, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Size = targetSize
    }):Play()
    tweenService:Create(arrowLabel, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
        Rotation = targetRotation
    }):Play()
end

local separatorFrame = Instance.new("Frame")
separatorFrame.Size = UDim2.new(1, -20, 0, 1)
separatorFrame.Position = UDim2.new(0, 10, 0, 45)
separatorFrame.BackgroundColor3 = Color3.fromRGB(48, 48, 58)
separatorFrame.BorderSizePixel = 0
separatorFrame.Parent = mainFrame

local wallButton = Instance.new("TextButton")
wallButton.Size = UDim2.new(1, -20, 0, 32)
wallButton.Position = UDim2.new(0, 10, 0, 9)
wallButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
wallButton.BorderSizePixel = 0
wallButton.Font = Enum.Font.Arcade
wallButton.TextSize = 11
wallButton.TextColor3 = Color3.fromRGB(120, 120, 130)
wallButton.Text = "IGNORING THE WALL"
wallButton.TextXAlignment = Enum.TextXAlignment.Center
wallButton.AutoButtonColor = false
wallButton.Parent = page1

local npcButton = Instance.new("TextButton")
npcButton.Size = UDim2.new(1, -20, 0, 32)
npcButton.Position = UDim2.new(0, 10, 0, 47)
npcButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
npcButton.BorderSizePixel = 0
npcButton.Font = Enum.Font.Arcade
npcButton.TextSize = 11
npcButton.TextColor3 = Color3.fromRGB(120, 120, 130)
npcButton.Text = "TARGET NPC"
npcButton.TextXAlignment = Enum.TextXAlignment.Center
npcButton.AutoButtonColor = false
npcButton.Parent = page1

local shiftButton = Instance.new("TextButton")
shiftButton.Size = UDim2.new(1, -20, 0, 32)
shiftButton.Position = UDim2.new(0, 10, 0, 85)
shiftButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
shiftButton.BorderSizePixel = 0
shiftButton.Font = Enum.Font.Arcade
shiftButton.TextSize = 11
shiftButton.TextColor3 = Color3.fromRGB(120, 120, 130)
shiftButton.Text = "MOVE THE CAMERA TO THE RIGHT"
shiftButton.TextXAlignment = Enum.TextXAlignment.Center
shiftButton.AutoButtonColor = false
shiftButton.Parent = page1

local rangeFrame = Instance.new("Frame")
rangeFrame.Size = UDim2.new(1, -20, 0, 32)
rangeFrame.Position = UDim2.new(0, 10, 0, 190)
rangeFrame.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
rangeFrame.BorderSizePixel = 0
rangeFrame.Parent = mainFrame

local rangeLabel = Instance.new("TextLabel")
rangeLabel.Size = UDim2.new(0, 42, 1, 0)
rangeLabel.Position = UDim2.new(0, 5, 0, 0)
rangeLabel.BackgroundTransparency = 1
rangeLabel.Font = Enum.Font.Arcade
rangeLabel.TextSize = 11
rangeLabel.TextColor3 = Color3.fromRGB(120, 120, 130)
rangeLabel.Text = "RANGE"
rangeLabel.TextXAlignment = Enum.TextXAlignment.Left
rangeLabel.Parent = rangeFrame

rangeInput.Size = UDim2.new(0, 40, 0, 22)
rangeInput.Position = UDim2.new(0, 50, 0.5, -11)
rangeInput.BackgroundColor3 = Color3.fromHex("28282D")
rangeInput.BorderSizePixel = 1
rangeInput.BorderColor3 = Color3.fromRGB(52, 52, 65)
rangeInput.Font = Enum.Font.Arcade
rangeInput.TextSize = 11
rangeInput.TextColor3 = Color3.fromRGB(210, 210, 210)
rangeInput.PlaceholderText = "50"
rangeInput.Text = "50"
rangeInput.ClearTextOnFocus = false
rangeInput.Parent = rangeFrame

local trackModeButton = Instance.new("TextButton")
trackModeButton.Size = UDim2.new(0, 90, 0, 22)
trackModeButton.Position = UDim2.new(0, 95, 0.5, -11)
trackModeButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
trackModeButton.BorderSizePixel = 1
trackModeButton.BorderColor3 = Color3.fromRGB(52, 52, 65)
trackModeButton.Font = Enum.Font.Arcade
trackModeButton.TextSize = 10
trackModeButton.TextColor3 = Color3.fromRGB(210, 210, 210)
trackModeButton.Text = "CAMERA"
trackModeButton.AutoButtonColor = false
trackModeButton.Parent = rangeFrame

local partToggleButton = Instance.new("TextButton")
partToggleButton.Size = UDim2.new(0, 65, 0, 22)
partToggleButton.Position = UDim2.new(0, 190, 0.5, -11)
partToggleButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
partToggleButton.BorderSizePixel = 1
partToggleButton.BorderColor3 = Color3.fromRGB(52, 52, 65)
partToggleButton.Font = Enum.Font.Arcade
partToggleButton.TextSize = 11
partToggleButton.TextColor3 = Color3.fromRGB(210, 210, 210)
partToggleButton.Text = "HEAD"
partToggleButton.AutoButtonColor = false
partToggleButton.Parent = rangeFrame

local espButton = Instance.new("TextButton")
espButton.Size = UDim2.new(1, -20, 0, 32)
espButton.Position = UDim2.new(0, 10, 0, 9)
espButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
espButton.BorderSizePixel = 0
espButton.Font = Enum.Font.Arcade
espButton.TextSize = 11
espButton.TextColor3 = Color3.fromRGB(120, 120, 130)
espButton.Text = "ESP"
espButton.TextXAlignment = Enum.TextXAlignment.Center
espButton.AutoButtonColor = false
espButton.Parent = page2

local highlightButton = Instance.new("TextButton")
highlightButton.Size = UDim2.new(1, -20, 0, 32)
highlightButton.Position = UDim2.new(0, 10, 0, 47)
highlightButton.BackgroundColor3 = Color3.fromRGB(33, 33, 40)
highlightButton.BorderSizePixel = 0
highlightButton.Font = Enum.Font.Arcade
highlightButton.TextSize = 11
highlightButton.TextColor3 = Color3.fromRGB(120, 120, 130)
highlightButton.Text = "HIGHLIGHT TARGET"
highlightButton.TextXAlignment = Enum.TextXAlignment.Center
highlightButton.AutoButtonColor = false
highlightButton.Parent = page2

local dragData = {active = false, input = nil, startMouse = nil, startFrame = nil}

headerFrame.InputBegan:Connect(function(input)
    if (input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch) and not dragData.active then
        dragData.active = true
        dragData.input = input
        dragData.startMouse = input.Position
        dragData.startFrame = guiPosition
    end
end)

userInputService.InputEnded:Connect(function(input)
    if input == dragData.input then
        dragData.active = false
        dragData.input = nil
    end
end)

userInputService.InputChanged:Connect(function(input)
    if dragData.active and input == dragData.input and (input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch) then
        local delta = input.Position - dragData.startMouse
        local newX = dragData.startFrame.X.Offset + delta.X
        local newY = dragData.startFrame.Y.Offset + delta.Y
        local viewport = camera.ViewportSize
        local frameSize = mainFrame.AbsoluteSize
        newX = math.clamp(newX, 0, viewport.X - frameSize.X)
        newY = math.clamp(newY, 0, viewport.Y - frameSize.Y)
        guiPosition = UDim2.new(0, newX, 0, newY)
    end
end)

local function updateRadiusCache()
    local value = tonumber(rangeInput.Text)
    if value and value > 0 then
        state.radius = value
    else
        state.radius = 50
        rangeInput.Text = "50"
    end
end
rangeInput.FocusLost:Connect(updateRadiusCache)
rangeInput:GetPropertyChangedSignal("Text"):Connect(updateRadiusCache)

runService.RenderStepped:Connect(function(deltaTime)
    mainFrame.Position = mainFrame.Position:Lerp(guiPosition, math.min(deltaTime * 14, 1))
    if state.enabled then
        fovFrame.Size = fovFrame.Size:Lerp(UDim2.new(0, state.radius * 2, 0, state.radius * 2), math.min(deltaTime * 10, 1))
        fovFrame.Visible = true
    else
        fovFrame.Visible = false
    end
end)

connectSafeButton(wallButton, function()
    state.wall = not state.wall
    if state.wall then
        wallButton.TextColor3 = Color3.fromHex("1E508C")
        tweenService:Create(wallButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(28, 38, 56)
        }):Play()
    else
        wallButton.TextColor3 = Color3.fromRGB(120, 120, 130)
        tweenService:Create(wallButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(33, 33, 40)
        }):Play()
    end
end)

connectSafeButton(npcButton, function()
    state.npc = not state.npc
    if state.npc then
        npcButton.TextColor3 = Color3.fromHex("1E508C")
        tweenService:Create(npcButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(28, 38, 56)
        }):Play()
    else
        npcButton.TextColor3 = Color3.fromRGB(120, 120, 130)
        tweenService:Create(npcButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(33, 33, 40)
        }):Play()
    end
end)

connectSafeButton(shiftButton, function()
    state.cameraShift = not state.cameraShift
    if state.cameraShift then
        shiftButton.TextColor3 = Color3.fromHex("1E508C")
        tweenService:Create(shiftButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(28, 38, 56)
        }):Play()
    else
        shiftButton.TextColor3 = Color3.fromRGB(120, 120, 130)
        tweenService:Create(shiftButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(33, 33, 40)
        }):Play()
    end
end)

connectSafeButton(trackModeButton, function()
    if state.trackMode == "Camera" then
        state.trackMode = "Character"
        trackModeButton.Text = "CHARACTER"
    else
        state.trackMode = "Camera"
        trackModeButton.Text = "CAMERA"
    end
end)

connectSafeButton(highlightButton, function()
    state.highlightTarget = not state.highlightTarget
    if state.highlightTarget then
        highlightButton.TextColor3 = Color3.fromHex("1E508C")
        tweenService:Create(highlightButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(28, 38, 56)
        }):Play()
    else
        highlightButton.TextColor3 = Color3.fromRGB(120, 120, 130)
        tweenService:Create(highlightButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(33, 33, 40)
        }):Play()
    end
end)

connectSafeButton(espButton, function()
    state.espEnabled = not state.espEnabled
    if state.espEnabled then
        espButton.TextColor3 = Color3.fromHex("1E508C")
        tweenService:Create(espButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(28, 38, 56)
        }):Play()
    else
        espButton.TextColor3 = Color3.fromRGB(120, 120, 130)
        tweenService:Create(espButton, TweenInfo.new(0.12, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(33, 33, 40)
        }):Play()
    end
end)

connectSafeButton(partToggleButton, function()
    if state.aimPart == "Head" then
        state.aimPart = "HumanoidRootPart"
        partToggleButton.Text = "HRP"
    else
        state.aimPart = "Head"
        partToggleButton.Text = "HEAD"
    end
end)

collapseButton.Activated:Connect(function()
    if not state.enabled then return end
    state.collapsed = not state.collapsed
    updateFrameSize()
end)

toggleButton.Activated:Connect(function()
    state.enabled = not state.enabled
    if state.enabled then
        toggleButton.Text = "ON"
        tweenService:Create(toggleButton, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromHex("1E508C")
        }):Play()
        tweenService:Create(uiStroke, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {
            Color = Color3.fromHex("1E508C")
        }):Play()
        
        collapseButton.Visible = true
        tweenService:Create(collapseButton, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {BackgroundTransparency = 0}):Play()
        tweenService:Create(collapseStroke, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {Transparency = 0}):Play()
        tweenService:Create(arrowLabel, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {TextTransparency = 0}):Play()
        
        startTracking()
    else
        toggleButton.Text = "OFF"
        tweenService:Create(toggleButton, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {
            BackgroundColor3 = Color3.fromRGB(155, 32, 32)
        }):Play()
        tweenService:Create(uiStroke, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {
            Color = Color3.fromRGB(155, 32, 32)
        }):Play()
        
        state.collapsed = false
        state.currentSlot = 1
        updateSlot()
        
        tweenService:Create(collapseButton, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {BackgroundTransparency = 1}):Play()
        tweenService:Create(collapseStroke, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {Transparency = 1}):Play()
        tweenService:Create(arrowLabel, TweenInfo.new(0.14, Enum.EasingStyle.Linear), {TextTransparency = 1}):Play()
        
        task.delay(0.14, function()
            if not state.enabled then
                collapseButton.Visible = false
            end
        end)
        
        stopTracking()
    end
    updateFrameSize()
end)