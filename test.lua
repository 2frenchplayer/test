local Players = game:GetService("Players")
local PathfindingService = game:GetService("PathfindingService")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local job = workspace:WaitForChild("Map")
	:WaitForChild("Tiles")
	:WaitForChild("GasStationTile")
	:WaitForChild("Quick11")
	:WaitForChild("Interior")
	:WaitForChild("ShelfStockingJob")

local normalBox = job:WaitForChild("NormalBox")
local shelves = job:WaitForChild("Shelves")

print("[ShelfAuto] Script client chargé. Appuie sur L pour ouvrir l'interface.")

local enabled = false
local busy = false
local currentHumanoid
local currentRoot
local originalWalkSpeed
local AUTO_WALK_SPEED = 30
local PATH_RETRIES = 3

local gui = Instance.new("ScreenGui")
gui.Name = "ShelfAutoUI"
gui.ResetOnSpawn = false
gui.Parent = player:WaitForChild("PlayerGui")

local panel = Instance.new("Frame")
panel.Size = UDim2.fromOffset(290, 204)
panel.Position = UDim2.new(0.5, -145, 0.5, -102)
panel.BackgroundColor3 = Color3.fromRGB(26, 29, 38)
panel.BorderSizePixel = 0
panel.Visible = false
panel.Parent = gui

local corner = Instance.new("UICorner")
corner.CornerRadius = UDim.new(0, 10)
corner.Parent = panel

local title = Instance.new("TextLabel")
title.Size = UDim2.new(1, -24, 0, 34)
title.Position = UDim2.fromOffset(12, 8)
title.BackgroundTransparency = 1
title.Font = Enum.Font.GothamBold
title.TextSize = 18
title.TextXAlignment = Enum.TextXAlignment.Left
title.TextColor3 = Color3.fromRGB(255, 255, 255)
title.Text = "Shelf automation  •  v1.7"
title.Parent = panel

local status = Instance.new("TextLabel")
status.Size = UDim2.new(1, -24, 0, 28)
status.Position = UDim2.fromOffset(12, 45)
status.BackgroundTransparency = 1
status.Font = Enum.Font.Gotham
status.TextSize = 13
status.TextWrapped = true
status.TextXAlignment = Enum.TextXAlignment.Left
status.TextColor3 = Color3.fromRGB(185, 193, 210)
status.Text = "Prêt — appuie sur Activer."
status.Parent = panel

local toggle = Instance.new("TextButton")
toggle.Size = UDim2.new(1, -24, 0, 42)
toggle.Position = UDim2.fromOffset(12, 96)
toggle.BackgroundColor3 = Color3.fromRGB(49, 126, 81)
toggle.BorderSizePixel = 0
toggle.Font = Enum.Font.GothamBold
toggle.TextSize = 15
toggle.TextColor3 = Color3.fromRGB(255, 255, 255)
toggle.Text = "Activer"
toggle.Parent = panel

local buttonCorner = Instance.new("UICorner")
buttonCorner.CornerRadius = UDim.new(0, 7)
buttonCorner.Parent = toggle

local killButton = Instance.new("TextButton")
killButton.Size = UDim2.new(1, -24, 0, 42)
killButton.Position = UDim2.fromOffset(12, 150)
killButton.BackgroundColor3 = Color3.fromRGB(105, 42, 42)
killButton.BorderSizePixel = 0
killButton.Font = Enum.Font.GothamBold
killButton.TextSize = 15
killButton.TextColor3 = Color3.fromRGB(255, 255, 255)
killButton.Text = "Kill le script"
killButton.Parent = panel

local killButtonCorner = Instance.new("UICorner")
killButtonCorner.CornerRadius = UDim.new(0, 7)
killButtonCorner.Parent = killButton

local function setStatus(text)
	status.Text = text
	print("[ShelfAuto] " .. text)
end

local function setEnabled(value)
	enabled = value
	print("[ShelfAuto] Automatisation " .. (value and "activée" or "arrêtée") .. ".")
	toggle.Text = value and "Arrêter" or "Activer"
	toggle.BackgroundColor3 = value and Color3.fromRGB(169, 68, 68) or Color3.fromRGB(49, 126, 81)
	if not value then
		if currentHumanoid and currentHumanoid.Parent and originalWalkSpeed then
			currentHumanoid.WalkSpeed = originalWalkSpeed
			originalWalkSpeed = nil
		end
		setStatus("Arrêté.")
	end
end

local function killCurrentClient()
	print("[ShelfAuto] Script client arrêté définitivement par la touche L.")
	enabled = false
	busy = false
	gui:Destroy()
	script:Destroy()
end

local function getCharacterParts()
	local character = player.Character or player.CharacterAdded:Wait()
	local humanoid = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid")
	local root = character:FindFirstChild("HumanoidRootPart") or character:WaitForChild("HumanoidRootPart")
	return character, humanoid, root
end

local function getInteractionPosition(target)
	local _, _, root = getCharacterParts()
	local prompt = target:FindFirstChildWhichIsA("ProximityPrompt", true)
	local activationDistance = prompt and prompt.MaxActivationDistance or 8
	local distanceFromTarget = math.max(3, math.min(activationDistance - 1, 7))

	local horizontal = Vector3.new(
		root.Position.X - target.Position.X,
		0,
		root.Position.Z - target.Position.Z
	)
	if horizontal.Magnitude < 0.1 then
		horizontal = Vector3.new(1, 0, 0)
	end

	return Vector3.new(target.Position.X, root.Position.Y, target.Position.Z)
		+ horizontal.Unit * distanceFromTarget
end

local function moveTo(position)
	local _, humanoid, root = getCharacterParts()
	if humanoid.Health <= 0 or not enabled then return false end

	if not originalWalkSpeed then
		originalWalkSpeed = humanoid.WalkSpeed
	end
	humanoid.WalkSpeed = AUTO_WALK_SPEED

	for attempt = 1, PATH_RETRIES do
		local path = PathfindingService:CreatePath({
			AgentRadius = 2,
			AgentHeight = 5,
			AgentCanJump = true,
			WaypointSpacing = 4,
		})

		local computed = pcall(function()
			path:ComputeAsync(root.Position, position)
		end)

		if computed and path.Status == Enum.PathStatus.Success then
			local blocked = false
			local waypointIndex = 1
			local blockedConnection = path.Blocked:Connect(function(blockedIndex)
				if blockedIndex >= waypointIndex then
					blocked = true
				end
			end)

			local completed = true
			for index, waypoint in ipairs(path:GetWaypoints()) do
				waypointIndex = index
				if not enabled or humanoid.Health <= 0 then
					completed = false
					break
				end
				if waypoint.Action == Enum.PathWaypointAction.Jump then
					humanoid.Jump = true
				end
				humanoid:MoveTo(waypoint.Position)
				local reached = humanoid.MoveToFinished:Wait()
				if not reached or blocked then
					completed = false
					break
				end
			end
			blockedConnection:Disconnect()

			if completed then
				return true
			end
			warn("[ShelfAuto] Chemin bloqué par un mur, recalcul " .. attempt .. "/" .. PATH_RETRIES .. ".")
		else
			warn("[ShelfAuto] Aucun chemin valide, recalcul " .. attempt .. "/" .. PATH_RETRIES .. ".")
		end
		task.wait(0.15)
	end

	warn("[ShelfAuto] Aucun chemin généré : essai de marche directe.")
	setStatus("Navigation indisponible, marche directe…")
	humanoid:MoveTo(position)
	local reachedDirectly = humanoid.MoveToFinished:Wait()
	if reachedDirectly or (root.Position - position).Magnitude <= 7 then
		return true
	end

	warn("[ShelfAuto] Destination inaccessible après plusieurs essais.")
	return false
end

local function usePrompt(prompt)
	if not prompt or not prompt.Enabled or not enabled then
		warn("[ShelfAuto] ProximityPrompt indisponible.")
		return false
	end
	print("[ShelfAuto] Interaction E : " .. prompt:GetFullName())
	local ok = pcall(function()
		prompt:InputHoldBegin()
		task.wait(math.max(prompt.HoldDuration, 0.1) + 0.1)
		prompt:InputHoldEnd()
	end)
	if not ok then
		warn("[ShelfAuto] L'interaction E a échoué : " .. prompt:GetFullName())
	end
	return ok
end

local function getActiveShelf()
	-- Le jeu crée une flèche locale dont Attachment0 est parenté à l'étagère cible.
	-- Les marqueurs Shelf restent volontairement invisibles.
	local arrow = workspace:FindFirstChild("ArrowDirection")
	if arrow and arrow:IsA("Beam") and arrow.Attachment0 then
		local target = arrow.Attachment0.Parent
		if target and target:IsA("BasePart") and target:IsDescendantOf(shelves) then
			print("[ShelfAuto] Étagère cible détectée par la flèche : " .. target:GetFullName())
			return target
		end
	end

	local _, _, root = getCharacterParts()
	local selected, bestDistance
	for _, shelf in ipairs(shelves:GetChildren()) do
		if shelf:IsA("BasePart") and shelf.Transparency < 0.99 then
			local prompt = shelf:FindFirstChildWhichIsA("ProximityPrompt", true)
			if prompt and prompt.Enabled then
				local distance = (root.Position - shelf.Position).Magnitude
				if not bestDistance or distance < bestDistance then
					selected, bestDistance = shelf, distance
				end
			end
		end
	end
	return selected
end

local function waitForActiveShelf(timeout)
	local deadline = os.clock() + timeout
	repeat
		local shelf = getActiveShelf()
		if shelf then
			return shelf
		end
		task.wait(0.25)
	until not enabled or os.clock() >= deadline
	return nil
end

local function runCycle()
	if busy or not enabled then return end
	busy = true

	setStatus("Déplacement vers NormalBox…")
	if not moveTo(getInteractionPosition(normalBox)) then
		if enabled then setStatus("NormalBox inaccessible.") end
		busy = false
		return
	end

	if not enabled then busy = false return end
	setStatus("Interaction avec NormalBox (E)…")
	usePrompt(normalBox:FindFirstChildWhichIsA("ProximityPrompt", true))
	setStatus("Recherche d'une étagère active…")
	local shelf = waitForActiveShelf(8)
	if not shelf then
		setStatus("Aucune étagère cible détectée (flèche absente).")
		busy = false
		return
	end

	setStatus("Déplacement vers l'étagère active…")
	if not moveTo(shelf.Position) then
		if enabled then setStatus("Étagère inaccessible.") end
		busy = false
		return
	end

	if enabled then
		-- Cette étagère se déclenche au contact du HumanoidRootPart, pas avec E.
		setStatus("Étagère atteinte : contact déclenché.")
	end

	if enabled then
		setStatus("Attente de 10 secondes…")
		task.wait(10)
		if enabled then setStatus("Cycle terminé.") end
	end
	busy = false
end

local function bindCharacter(character)
	currentHumanoid = character:WaitForChild("Humanoid")
	currentRoot = character:WaitForChild("HumanoidRootPart")
	currentHumanoid.Died:Connect(function()
		print("[ShelfAuto] Mort détectée : déplacement sous la map.")
		setEnabled(false)
		if currentRoot and currentRoot.Parent then
			currentRoot.CFrame = CFrame.new(currentRoot.Position.X, -500, currentRoot.Position.Z)
		end
	end)
end

if player.Character then bindCharacter(player.Character) end
player.CharacterAdded:Connect(bindCharacter)

UserInputService.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.L then
		panel.Visible = not panel.Visible
		print("[ShelfAuto] Interface " .. (panel.Visible and "ouverte" or "fermée") .. ".")
	end
end)

killButton.MouseButton1Click:Connect(killCurrentClient)

toggle.MouseButton1Click:Connect(function()
	setEnabled(not enabled)
	if enabled then
		task.spawn(runCycle)
	end
end)
--