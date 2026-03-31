--[[
	Client-side weapon handling.
	Reads player input, enforces local cooldowns for responsive feel,
	communicates fire/reload requests to the server, and manages
	placeholder weapon models attached to the character's hand.
]]

local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local ClientNetwork = require(script.Parent.Parent.Network)
local HUD = require(script.Parent.Parent.UI.HUD)
local AudioController = require(script.Parent.AudioController)
local EventNames = require(ReplicatedStorage.Shared.Network.EventNames)
local WeaponData = require(ReplicatedStorage.Shared.Data.WeaponData)

local WeaponController = {}

local localPlayer = Players.LocalPlayer
local camera = Workspace.CurrentCamera

--------------------------------------------------------------------------------
-- Local weapon state (mirrors server for responsiveness)
--------------------------------------------------------------------------------

local currentWeaponId: string = "PulseBlaster"
local currentAmmo: number = 0
local isReloading: boolean = false
local lastFireTime: number = 0

-- Reference to the currently equipped weapon model
local currentWeaponModel: Model? = nil

-- Whether the fire button is currently held down (for auto-fire weapons)
local isFireHeld: boolean = false

--------------------------------------------------------------------------------
-- Melee Combat UI State
--------------------------------------------------------------------------------
local meleeUIScreenGui: ScreenGui? = nil
local meleeCrosshairFrame: Frame? = nil
local comboCounterLabel: TextLabel? = nil
local comboNameLabel: TextLabel? = nil
local swingDirectionFrame: Frame? = nil
local hitFeedbackFrame: Frame? = nil
local backstabLabel: TextLabel? = nil
local meleeRangePulseConn: RBXScriptConnection? = nil
local comboFadeThread: thread? = nil

-- Theme colors per melee weapon
local MELEE_THEME_COLORS = {
	EnergySword = Color3.fromRGB(0, 200, 255),
	PhaseKnife = Color3.fromRGB(200, 0, 255),
}

-- Melee range per weapon (studs) for crosshair glow detection
local MELEE_RANGE_DETECT = {
	EnergySword = 8,
	PhaseKnife = 6,
}

-- Combo names for each weapon, indexed to match SABER_COMBOS order
local MELEE_COMBO_NAMES = {
	EnergySword = {
		"DIAGONAL SLASH", "BACKHAND SLASH", "OVERHEAD CLEAVE", "HORIZONTAL SWEEP",
		"REVERSE SWEEP", "FORWARD THRUST", "UPPERCUT", "SPINNING STRIKE",
	},
	PhaseKnife = {
		"QUICK SLASH", "REVERSE CUT", "RISING RIP", "LUNGING STAB",
		"CROSS SLASH", "SPINNING SLASH", "LOW SWEEP",
	},
}

-- Swing direction types per combo index (maps to visual slash mark direction)
-- Directions: "diagRight", "diagLeft", "vertical", "horizontal", "thrust"
local MELEE_SWING_DIRECTIONS = {
	EnergySword = { "diagRight", "diagLeft", "vertical", "horizontal", "horizontal", "thrust", "vertical", "horizontal" },
	PhaseKnife = { "diagRight", "diagLeft", "vertical", "thrust", "diagLeft", "horizontal", "horizontal" },
}

--------------------------------------------------------------------------------
-- Placeholder weapon model definitions
--------------------------------------------------------------------------------

-- Each weapon gets a simple geometric shape with a color.
-- Sizes are in studs. Melee weapons attach differently from guns.
local WEAPON_VISUALS = {
	EnergySword = {
		shape = "energysword",
		color = Color3.fromRGB(0, 200, 255),
		material = Enum.Material.Neon,
		size = Vector3.new(0.2, 0.15, 0.6), -- invisible root anchor at grip center
		grip = CFrame.new(0, 0, -0.3) * CFrame.Angles(math.rad(90), 0, 0),
	},
	PulseBlaster = {
		shape = "pulseblaster",
		color = Color3.fromRGB(30, 30, 45),
		material = Enum.Material.Metal,
		size = Vector3.new(0.4, 0.5, 1.8),
		grip = CFrame.new(0, -0.2, -0.6),
	},
	RailRifle = {
		shape = "railrifle", -- custom multi-part build
		color = Color3.fromRGB(30, 30, 45),
		material = Enum.Material.SmoothPlastic,
		size = Vector3.new(0.4, 0.5, 3.0),
		grip = CFrame.new(0, -0.25, -1.0),
	},
	MemorySMG = {
		shape = "memorysmg",
		color = Color3.fromRGB(18, 18, 30),
		material = Enum.Material.Metal,
		size = Vector3.new(0.35, 0.4, 1.4),
		grip = CFrame.new(0, -0.2, -0.4),
	},
	GlitchShotgun = {
		shape = "glitchshotgun",
		color = Color3.fromRGB(55, 55, 70),
		material = Enum.Material.Metal,
		size = Vector3.new(0.5, 0.55, 2.2),
		grip = CFrame.new(0, -0.2, -0.7),
	},
	PhaseKnife = {
		shape = "phaseknife",
		color = Color3.fromRGB(200, 0, 255),
		material = Enum.Material.Neon,
		size = Vector3.new(0.2, 0.15, 0.5),
		grip = CFrame.new(0, 0, -0.25) * CFrame.Angles(math.rad(90), 0, 0),
	},
	ShockLauncher = {
		shape = "shocklauncher",
		color = Color3.fromRGB(40, 40, 55),
		material = Enum.Material.Metal,
		size = Vector3.new(0.55, 0.6, 2.6),
		grip = CFrame.new(0, -0.2, -0.8),
	},
	Sniper = {
		shape = "sniper",
		color = Color3.fromRGB(25, 25, 40),
		material = Enum.Material.Metal,
		size = Vector3.new(0.35, 0.45, 3.2),
		grip = CFrame.new(0, -0.2, -1.2),
	},
}

--------------------------------------------------------------------------------
-- Weapon model creation / destruction
--------------------------------------------------------------------------------

local function destroyWeaponModel()
	if currentWeaponModel then
		currentWeaponModel:Destroy()
		currentWeaponModel = nil
	end
end

local function createWeaponModel(weaponId: string)
	destroyWeaponModel()

	local character = localPlayer.Character
	if not character then
		return
	end

	local rightHand = character:FindFirstChild("RightHand") -- R15
		or character:FindFirstChild("Right Arm") -- R6

	if not rightHand then
		return
	end

	local visual = WEAPON_VISUALS[weaponId]
	if not visual then
		-- Fallback: small grey box
		visual = {
			shape = "gun",
			color = Color3.fromRGB(100, 100, 100),
			material = Enum.Material.SmoothPlastic,
			size = Vector3.new(0.3, 0.3, 1.0),
			grip = CFrame.new(0, -0.2, -0.4),
		}
	end

	local model = Instance.new("Model")
	model.Name = "WeaponModel"

	-- Main body part
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = visual.size
	body.Color = visual.color
	body.Material = visual.material
	body.CanCollide = false
	body.Massless = true
	body.Anchored = false
	body.Parent = model

	-- Weld body to the hand
	local weld = Instance.new("Motor6D")
	weld.Name = "GripWeld"
	weld.Part0 = rightHand
	weld.Part1 = body
	weld.C0 = visual.grip
	weld.Parent = body

	-- Add a barrel/accent piece for guns
	if visual.barrel then
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Size = visual.barrel.size
		barrel.Color = visual.barrel.color
		barrel.Material = visual.barrel.material
		barrel.CanCollide = false
		barrel.Massless = true
		barrel.Anchored = false
		barrel.Parent = model

		local barrelWeld = Instance.new("Motor6D")
		barrelWeld.Name = "BarrelWeld"
		barrelWeld.Part0 = body
		barrelWeld.Part1 = barrel
		barrelWeld.C0 = visual.barrel.offset
		barrelWeld.Parent = barrel
	end


	------------------------------------------------------------------------
	-- RAIL RIFLE: Long, precise, high-tech sci-fi rifle
	------------------------------------------------------------------------
	if visual.shape == "railrifle" then
		-- Helper to create a part and weld it
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = mat
			p.CanCollide = false
			p.Massless = true
			p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent
			w.Part1 = p
			w.C0 = offset
			w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(80, 230, 255)
		local purple = Color3.fromRGB(140, 40, 255)

		------------------------------------------------------------------------
		-- CORE SILHOUETTE (receiver, barrel, stock, grip)
		------------------------------------------------------------------------

		-- Main receiver body (large block that defines the weapon profile)
		local receiver = makePart("Receiver", Vector3.new(0.35, 0.4, 2.8), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, -0.1))

		-- Upper receiver rail surface
		makePart("UpperRail", Vector3.new(0.18, 0.06, 2.2), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.22, -0.1))

		-- Lower receiver plate
		makePart("LowerPlate", Vector3.new(0.3, 0.05, 2.0), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, -0.21, 0))

		------------------------------------------------------------------------
		-- BARREL (cylinder extending forward)
		------------------------------------------------------------------------
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Shape = Enum.PartType.Cylinder
		barrel.Size = Vector3.new(1.8, 0.15, 0.15)
		barrel.Color = midMetal
		barrel.Material = Enum.Material.Metal
		barrel.CanCollide = false
		barrel.Massless = true
		barrel.Anchored = false
		barrel.Parent = model
		local bw = Instance.new("Motor6D")
		bw.Part0 = receiver
		bw.Part1 = barrel
		bw.C0 = CFrame.new(0, 0.05, -2.3) * CFrame.Angles(0, 0, math.rad(90))
		bw.Parent = barrel

		-- Barrel shroud (outer cylinder around barrel)
		local shroud = Instance.new("Part")
		shroud.Name = "BarrelShroud"
		shroud.Shape = Enum.PartType.Cylinder
		shroud.Size = Vector3.new(1.0, 0.25, 0.25)
		shroud.Color = darkMetal
		shroud.Material = Enum.Material.SmoothPlastic
		shroud.CanCollide = false
		shroud.Massless = true
		shroud.Anchored = false
		shroud.Parent = model
		local sw = Instance.new("Motor6D")
		sw.Part0 = receiver
		sw.Part1 = shroud
		sw.C0 = CFrame.new(0, 0.05, -1.8) * CFrame.Angles(0, 0, math.rad(90))
		sw.Parent = shroud

		-- Muzzle brake (cylinder at barrel tip)
		local muzzle = Instance.new("Part")
		muzzle.Name = "MuzzleBrake"
		muzzle.Shape = Enum.PartType.Cylinder
		muzzle.Size = Vector3.new(0.2, 0.22, 0.22)
		muzzle.Color = lightMetal
		muzzle.Material = Enum.Material.Metal
		muzzle.CanCollide = false
		muzzle.Massless = true
		muzzle.Anchored = false
		muzzle.Parent = model
		local mw = Instance.new("Motor6D")
		mw.Part0 = receiver
		mw.Part1 = muzzle
		mw.C0 = CFrame.new(0, 0.05, -3.2) * CFrame.Angles(0, 0, math.rad(90))
		mw.Parent = muzzle

		-- MuzzleGlow (for muzzle flash system)
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.1, 0.1, 0.1), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0, 0.05, -3.35))
		muzzleGlow.Transparency = 0.5

		------------------------------------------------------------------------
		-- STOCK (angular wedge tapering backward)
		------------------------------------------------------------------------
		local stock = Instance.new("WedgePart")
		stock.Name = "Stock"
		stock.Size = Vector3.new(0.28, 0.35, 0.9)
		stock.Color = darkMetal
		stock.Material = Enum.Material.SmoothPlastic
		stock.CanCollide = false
		stock.Massless = true
		stock.Anchored = false
		stock.Parent = model
		local stw = Instance.new("Motor6D")
		stw.Part0 = receiver
		stw.Part1 = stock
		stw.C0 = CFrame.new(0, 0.02, 1.7) * CFrame.Angles(0, math.rad(180), 0)
		stw.Parent = stock

		-- Stock plate (flat back cap)
		makePart("StockPlate", Vector3.new(0.26, 0.3, 0.06), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.02, 1.7))

		------------------------------------------------------------------------
		-- SCOPE (cylinder on top with lens)
		------------------------------------------------------------------------
		local scope = Instance.new("Part")
		scope.Name = "Scope"
		scope.Shape = Enum.PartType.Cylinder
		scope.Size = Vector3.new(0.7, 0.14, 0.14)
		scope.Color = darkMetal
		scope.Material = Enum.Material.SmoothPlastic
		scope.CanCollide = false
		scope.Massless = true
		scope.Anchored = false
		scope.Parent = model
		local scw = Instance.new("Motor6D")
		scw.Part0 = receiver
		scw.Part1 = scope
		scw.C0 = CFrame.new(0, 0.35, -0.3) * CFrame.Angles(0, 0, math.rad(90))
		scw.Parent = scope

		-- Scope mount blocks
		makePart("ScopeMount1", Vector3.new(0.1, 0.1, 0.08), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.28, -0.55))
		makePart("ScopeMount2", Vector3.new(0.1, 0.1, 0.08), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.28, -0.05))

		-- Scope lens (front)
		local lens = Instance.new("Part")
		lens.Name = "ScopeLens"
		lens.Shape = Enum.PartType.Cylinder
		lens.Size = Vector3.new(0.04, 0.16, 0.16)
		lens.Color = cyan
		lens.Material = Enum.Material.Neon
		lens.Transparency = 0.3
		lens.CanCollide = false
		lens.Massless = true
		lens.Anchored = false
		lens.Parent = model
		local lw = Instance.new("Motor6D")
		lw.Part0 = receiver
		lw.Part1 = lens
		lw.C0 = CFrame.new(0, 0.35, -0.65) * CFrame.Angles(0, 0, math.rad(90))
		lw.Parent = lens

		------------------------------------------------------------------------
		-- SIDE PLATING (thin offset panels)
		------------------------------------------------------------------------
		makePart("SidePanelL", Vector3.new(0.04, 0.3, 1.8), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(-0.19, 0, -0.2))
		makePart("SidePanelR", Vector3.new(0.04, 0.3, 1.8), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0.19, 0, -0.2))

		-- Rear armor plates (thicker near stock)
		makePart("RearPlateL", Vector3.new(0.05, 0.25, 0.6), lightMetal, Enum.Material.DiamondPlate,
			receiver, CFrame.new(-0.2, 0, 0.8))
		makePart("RearPlateR", Vector3.new(0.05, 0.25, 0.6), lightMetal, Enum.Material.DiamondPlate,
			receiver, CFrame.new(0.2, 0, 0.8))

		------------------------------------------------------------------------
		-- NEON GLOW ACCENTS (thin, embedded)
		------------------------------------------------------------------------
		-- Side glow strips (inset into body)
		makePart("GlowStripL", Vector3.new(0.02, 0.04, 1.6), cyan, Enum.Material.Neon,
			receiver, CFrame.new(-0.17, 0.08, -0.3))
		makePart("GlowStripR", Vector3.new(0.02, 0.04, 1.6), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0.17, 0.08, -0.3))

		-- Top rail glow line
		makePart("TopGlowLine", Vector3.new(0.04, 0.02, 1.4), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0, 0.24, -0.3))

		------------------------------------------------------------------------
		-- ENERGY CHAMBER (visible power cell area)
		------------------------------------------------------------------------
		-- Chamber window (transparent section)
		local chamber = makePart("EnergyChamber", Vector3.new(0.15, 0.2, 0.35), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0, 0, 0.3))
		chamber.Transparency = 0.4

		-- Chamber housing frame
		makePart("ChamberFrameTop", Vector3.new(0.2, 0.03, 0.4), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.11, 0.3))
		makePart("ChamberFrameBot", Vector3.new(0.2, 0.03, 0.4), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, -0.11, 0.3))

		------------------------------------------------------------------------
		-- VENT DETAILS (rear body)
		------------------------------------------------------------------------
		for i = 0, 2 do
			makePart("Vent" .. i, Vector3.new(0.36, 0.025, 0.04), lightMetal, Enum.Material.Metal,
				receiver, CFrame.new(0, 0.12 - i * 0.1, 1.2))
		end

		------------------------------------------------------------------------
		-- LIGHTING & EFFECTS
		------------------------------------------------------------------------
		local chamberLight = Instance.new("PointLight")
		chamberLight.Color = cyan
		chamberLight.Brightness = 0.6
		chamberLight.Range = 3
		chamberLight.Parent = chamber

		local muzzleLight = Instance.new("PointLight")
		muzzleLight.Color = cyan
		muzzleLight.Brightness = 0.3
		muzzleLight.Range = 2
		muzzleLight.Parent = muzzleGlow

		-- Subtle particle glow on muzzle
		local muzzleParticle = Instance.new("ParticleEmitter")
		muzzleParticle.Name = "MuzzleAmbient"
		muzzleParticle.Color = ColorSequence.new(cyan)
		muzzleParticle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.05),
			NumberSequenceKeypoint.new(1, 0),
		})
		muzzleParticle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		muzzleParticle.Lifetime = NumberRange.new(0.15, 0.3)
		muzzleParticle.Rate = 8
		muzzleParticle.Speed = NumberRange.new(0.5, 1.5)
		muzzleParticle.SpreadAngle = Vector2.new(30, 30)
		muzzleParticle.LightEmission = 1
		muzzleParticle.LightInfluence = 0
		muzzleParticle.Parent = muzzleGlow
	end

	------------------------------------------------------------------------
	-- ENERGY SWORD: Mechanical handle with bright glowing blade
	------------------------------------------------------------------------
	if visual.shape == "energysword" then
		-- Hide the root anchor part (it's just used for welding)
		body.Transparency = 1

		-- Helper to create a part and weld it to a parent
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = mat
			p.CanCollide = false
			p.Massless = true
			p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent
			w.Part1 = p
			w.C0 = offset
			w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(80, 230, 255)
		local purple = Color3.fromRGB(140, 40, 255)

		------------------------------------------------------------------------
		-- GRIP (layered mechanical handle)
		------------------------------------------------------------------------

		-- Main grip cylinder
		local gripCore = Instance.new("Part")
		gripCore.Name = "GripCore"
		gripCore.Shape = Enum.PartType.Cylinder
		gripCore.Size = Vector3.new(0.55, 0.18, 0.18)
		gripCore.Color = darkMetal
		gripCore.Material = Enum.Material.SmoothPlastic
		gripCore.CanCollide = false
		gripCore.Massless = true
		gripCore.Anchored = false
		gripCore.Parent = model
		local gcw = Instance.new("Motor6D")
		gcw.Part0 = body
		gcw.Part1 = gripCore
		gcw.C0 = CFrame.new(0, 0, 0) * CFrame.Angles(0, 0, math.rad(90))
		gcw.Parent = gripCore

		-- Grip texture rings (3 thin cylinders for ridges)
		for i = -1, 1 do
			local ring = Instance.new("Part")
			ring.Name = "GripRing" .. i
			ring.Shape = Enum.PartType.Cylinder
			ring.Size = Vector3.new(0.04, 0.2, 0.2)
			ring.Color = midMetal
			ring.Material = Enum.Material.Metal
			ring.CanCollide = false
			ring.Massless = true
			ring.Anchored = false
			ring.Parent = model
			local rw = Instance.new("Motor6D")
			rw.Part0 = gripCore
			rw.Part1 = ring
			rw.C0 = CFrame.new(i * 0.15, 0, 0)
			rw.Parent = ring
		end

		-- Grip wrap block (ergonomic shape layer)
		makePart("GripWrap", Vector3.new(0.14, 0.5, 0.16), midMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		-- Pommel (end cap cylinder)
		local pommel = Instance.new("Part")
		pommel.Name = "Pommel"
		pommel.Shape = Enum.PartType.Cylinder
		pommel.Size = Vector3.new(0.1, 0.22, 0.22)
		pommel.Color = lightMetal
		pommel.Material = Enum.Material.Metal
		pommel.CanCollide = false
		pommel.Massless = true
		pommel.Anchored = false
		pommel.Parent = model
		local pw = Instance.new("Motor6D")
		pw.Part0 = body
		pw.Part1 = pommel
		pw.C0 = CFrame.new(0, -0.3, 0) * CFrame.Angles(math.rad(90), 0, 0)
		pw.Parent = pommel

		-- Grip power cell (small neon inset)
		local gripCell = makePart("GripPowerCell", Vector3.new(0.06, 0.12, 0.08), cyan, Enum.Material.Neon,
			body, CFrame.new(0.06, -0.1, 0))
		gripCell.Transparency = 0.2

		-- Grip button detail
		makePart("GripButton", Vector3.new(0.04, 0.04, 0.04), lightMetal, Enum.Material.Metal,
			body, CFrame.new(-0.08, 0.05, 0))

		------------------------------------------------------------------------
		-- CROSSGUARD / EMITTER HOUSING
		------------------------------------------------------------------------
		-- Main emitter block
		local emitter = makePart("EmitterHousing", Vector3.new(0.3, 0.14, 0.2), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0.32, 0))

		-- Crossguard wings (angular wedges)
		local guardL = Instance.new("WedgePart")
		guardL.Name = "GuardLeft"
		guardL.Size = Vector3.new(0.08, 0.1, 0.2)
		guardL.Color = midMetal
		guardL.Material = Enum.Material.Metal
		guardL.CanCollide = false
		guardL.Massless = true
		guardL.Anchored = false
		guardL.Parent = model
		local glw = Instance.new("Motor6D")
		glw.Part0 = emitter
		glw.Part1 = guardL
		glw.C0 = CFrame.new(-0.18, 0, 0) * CFrame.Angles(0, 0, math.rad(-30))
		glw.Parent = guardL

		local guardR = Instance.new("WedgePart")
		guardR.Name = "GuardRight"
		guardR.Size = Vector3.new(0.08, 0.1, 0.2)
		guardR.Color = midMetal
		guardR.Material = Enum.Material.Metal
		guardR.CanCollide = false
		guardR.Massless = true
		guardR.Anchored = false
		guardR.Parent = model
		local grw = Instance.new("Motor6D")
		grw.Part0 = emitter
		grw.Part1 = guardR
		grw.C0 = CFrame.new(0.18, 0, 0) * CFrame.Angles(0, 0, math.rad(30))
		grw.Parent = guardR

		-- Emitter vent slits
		makePart("EmitterVent1", Vector3.new(0.32, 0.02, 0.04), lightMetal, Enum.Material.Metal,
			emitter, CFrame.new(0, 0.04, 0.06))
		makePart("EmitterVent2", Vector3.new(0.32, 0.02, 0.04), lightMetal, Enum.Material.Metal,
			emitter, CFrame.new(0, -0.04, 0.06))

		-- Emitter glow core (where blade emerges)
		local emitterCore = makePart("EmitterCore", Vector3.new(0.12, 0.04, 0.12), brightCyan, Enum.Material.Neon,
			emitter, CFrame.new(0, 0.08, 0))

		------------------------------------------------------------------------
		-- BLADE (clean neon with tapered tip)
		------------------------------------------------------------------------
		-- Main blade body (large neon part)
		local bladeMain = makePart("BladeMain", Vector3.new(0.06, 2.6, 0.18), cyan, Enum.Material.Neon,
			body, CFrame.new(0, 1.72, 0))

		-- Blade core line (thin bright strip down center)
		local bladeCore = makePart("BladeCore", Vector3.new(0.02, 2.6, 0.04), brightCyan, Enum.Material.Neon,
			bladeMain, CFrame.new(0, 0, 0))

		-- Blade tip (wedge for tapered point)
		local bladeTip = Instance.new("WedgePart")
		bladeTip.Name = "BladeTip"
		bladeTip.Size = Vector3.new(0.06, 0.4, 0.18)
		bladeTip.Color = cyan
		bladeTip.Material = Enum.Material.Neon
		bladeTip.CanCollide = false
		bladeTip.Massless = true
		bladeTip.Anchored = false
		bladeTip.Parent = model
		local btw = Instance.new("Motor6D")
		btw.Part0 = bladeMain
		btw.Part1 = bladeTip
		btw.C0 = CFrame.new(0, 1.5, 0)
		btw.Parent = bladeTip

		------------------------------------------------------------------------
		-- LIGHTING & EFFECTS
		------------------------------------------------------------------------
		local bladeLight = Instance.new("PointLight")
		bladeLight.Color = cyan
		bladeLight.Brightness = 1.2
		bladeLight.Range = 8
		bladeLight.Parent = bladeMain

		local emitterLight = Instance.new("PointLight")
		emitterLight.Color = cyan
		emitterLight.Brightness = 0.5
		emitterLight.Range = 3
		emitterLight.Parent = emitterCore

		local cellLight = Instance.new("PointLight")
		cellLight.Color = cyan
		cellLight.Brightness = 0.3
		cellLight.Range = 1.5
		cellLight.Parent = gripCell

		-- Soft blade glow particles
		local bladeGlow = Instance.new("ParticleEmitter")
		bladeGlow.Name = "BladeGlow"
		bladeGlow.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, brightCyan),
			ColorSequenceKeypoint.new(1, cyan),
		})
		bladeGlow.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.15),
			NumberSequenceKeypoint.new(1, 0),
		})
		bladeGlow.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.4),
			NumberSequenceKeypoint.new(1, 1),
		})
		bladeGlow.Lifetime = NumberRange.new(0.2, 0.5)
		bladeGlow.Rate = 20
		bladeGlow.Speed = NumberRange.new(0.2, 0.8)
		bladeGlow.SpreadAngle = Vector2.new(180, 180)
		bladeGlow.LightEmission = 1
		bladeGlow.LightInfluence = 0
		bladeGlow.Parent = bladeMain
	end

	------------------------------------------------------------------------
	-- PHASE KNIFE: Compact assassin weapon with purple energy blade
	------------------------------------------------------------------------
	if visual.shape == "phaseknife" then
		body.Transparency = 1

		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = mat
			p.CanCollide = false
			p.Massless = true
			p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent
			w.Part1 = p
			w.C0 = offset
			w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(22, 18, 35)
		local midMetal = Color3.fromRGB(40, 35, 55)
		local lightMetal = Color3.fromRGB(60, 55, 75)
		local purple = Color3.fromRGB(140, 40, 255)
		local brightPurple = Color3.fromRGB(180, 80, 255)
		local magenta = Color3.fromRGB(200, 0, 180)

		------------------------------------------------------------------------
		-- GRIP (short tactical, angular)
		------------------------------------------------------------------------

		-- Main grip block (ergonomic shape)
		local gripMain = makePart("GripMain", Vector3.new(0.13, 0.4, 0.14), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		-- Grip texture panel
		makePart("GripTexture", Vector3.new(0.14, 0.32, 0.1), midMetal, Enum.Material.DiamondPlate,
			gripMain, CFrame.new(0, 0, 0.01))

		-- Grip bottom wedge (angular taper)
		local gripTaper = Instance.new("WedgePart")
		gripTaper.Name = "GripTaper"
		gripTaper.Size = Vector3.new(0.12, 0.12, 0.12)
		gripTaper.Color = darkMetal
		gripTaper.Material = Enum.Material.SmoothPlastic
		gripTaper.CanCollide = false
		gripTaper.Massless = true
		gripTaper.Anchored = false
		gripTaper.Parent = model
		local gtw = Instance.new("Motor6D")
		gtw.Part0 = gripMain
		gtw.Part1 = gripTaper
		gtw.C0 = CFrame.new(0, -0.25, 0) * CFrame.Angles(0, math.rad(180), 0)
		gtw.Parent = gripTaper

		-- Compact power cell in grip
		local powerCell = makePart("PowerCell", Vector3.new(0.05, 0.1, 0.06), purple, Enum.Material.Neon,
			gripMain, CFrame.new(0.05, -0.05, 0))
		powerCell.Transparency = 0.2

		------------------------------------------------------------------------
		-- BLADE GUARD (small angular housing)
		------------------------------------------------------------------------
		local guard = makePart("BladeGuard", Vector3.new(0.22, 0.1, 0.16), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.25, 0))

		-- Guard accent wedges
		local guardWedgeL = Instance.new("WedgePart")
		guardWedgeL.Name = "GuardWedgeL"
		guardWedgeL.Size = Vector3.new(0.06, 0.06, 0.1)
		guardWedgeL.Color = lightMetal
		guardWedgeL.Material = Enum.Material.Metal
		guardWedgeL.CanCollide = false
		guardWedgeL.Massless = true
		guardWedgeL.Anchored = false
		guardWedgeL.Parent = model
		local gwlw = Instance.new("Motor6D")
		gwlw.Part0 = guard
		gwlw.Part1 = guardWedgeL
		gwlw.C0 = CFrame.new(-0.12, 0, 0) * CFrame.Angles(0, 0, math.rad(-20))
		gwlw.Parent = guardWedgeL

		local guardWedgeR = Instance.new("WedgePart")
		guardWedgeR.Name = "GuardWedgeR"
		guardWedgeR.Size = Vector3.new(0.06, 0.06, 0.1)
		guardWedgeR.Color = lightMetal
		guardWedgeR.Material = Enum.Material.Metal
		guardWedgeR.CanCollide = false
		guardWedgeR.Massless = true
		guardWedgeR.Anchored = false
		guardWedgeR.Parent = model
		local gwrw = Instance.new("Motor6D")
		gwrw.Part0 = guard
		gwrw.Part1 = guardWedgeR
		gwrw.C0 = CFrame.new(0.12, 0, 0) * CFrame.Angles(0, 0, math.rad(20))
		gwrw.Parent = guardWedgeR

		-- Guard emitter glow
		local guardGlow = makePart("GuardGlow", Vector3.new(0.08, 0.03, 0.08), brightPurple, Enum.Material.Neon,
			guard, CFrame.new(0, 0.05, 0))

		------------------------------------------------------------------------
		-- BLADE (shorter than sword, sharp glowing edge)
		------------------------------------------------------------------------
		-- Main blade body
		local bladeMain = makePart("BladeMain", Vector3.new(0.04, 1.4, 0.12), purple, Enum.Material.Neon,
			body, CFrame.new(0, 1.0, 0))

		-- Blade inner core
		local bladeInner = makePart("BladeCore", Vector3.new(0.02, 1.4, 0.03), brightPurple, Enum.Material.Neon,
			bladeMain, CFrame.new(0, 0, 0))

		-- Blade tip (pointed wedge)
		local bladeTip = Instance.new("WedgePart")
		bladeTip.Name = "BladeTip"
		bladeTip.Size = Vector3.new(0.04, 0.3, 0.12)
		bladeTip.Color = purple
		bladeTip.Material = Enum.Material.Neon
		bladeTip.CanCollide = false
		bladeTip.Massless = true
		bladeTip.Anchored = false
		bladeTip.Parent = model
		local btw = Instance.new("Motor6D")
		btw.Part0 = bladeMain
		btw.Part1 = bladeTip
		btw.C0 = CFrame.new(0, 0.85, 0)
		btw.Parent = bladeTip

		-- Purple edge accent (neon strip along blade side)
		makePart("EdgeAccentL", Vector3.new(0.01, 1.3, 0.02), magenta, Enum.Material.Neon,
			bladeMain, CFrame.new(-0.02, 0, 0.05))
		makePart("EdgeAccentR", Vector3.new(0.01, 1.3, 0.02), magenta, Enum.Material.Neon,
			bladeMain, CFrame.new(0.02, 0, 0.05))

		------------------------------------------------------------------------
		-- LIGHTING & EFFECTS
		------------------------------------------------------------------------
		local bladeLight = Instance.new("PointLight")
		bladeLight.Color = purple
		bladeLight.Brightness = 1.0
		bladeLight.Range = 6
		bladeLight.Parent = bladeMain

		local guardLight = Instance.new("PointLight")
		guardLight.Color = purple
		guardLight.Brightness = 0.4
		guardLight.Range = 2
		guardLight.Parent = guardGlow

		local cellLight = Instance.new("PointLight")
		cellLight.Color = purple
		cellLight.Brightness = 0.3
		cellLight.Range = 1
		cellLight.Parent = powerCell

		-- Subtle blade particles
		local bladeParticle = Instance.new("ParticleEmitter")
		bladeParticle.Name = "BladeGlow"
		bladeParticle.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, brightPurple),
			ColorSequenceKeypoint.new(0.5, purple),
			ColorSequenceKeypoint.new(1, magenta),
		})
		bladeParticle.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.08),
			NumberSequenceKeypoint.new(1, 0),
		})
		bladeParticle.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		bladeParticle.Lifetime = NumberRange.new(0.15, 0.35)
		bladeParticle.Rate = 15
		bladeParticle.Speed = NumberRange.new(0.3, 1.0)
		bladeParticle.SpreadAngle = Vector2.new(160, 160)
		bladeParticle.LightEmission = 1
		bladeParticle.LightInfluence = 0
		bladeParticle.Parent = bladeMain
	end

	------------------------------------------------------------------------
	-- MEMORY SMG: Lightweight, aggressive, compact tactical SMG
	------------------------------------------------------------------------
	if visual.shape == "memorysmg" then
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.Color = color
			p.Material = mat
			p.CanCollide = false
			p.Massless = true
			p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent
			w.Part1 = p
			w.C0 = offset
			w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(80, 230, 255)
		local purple = Color3.fromRGB(140, 40, 255)

		------------------------------------------------------------------------
		-- CORE SILHOUETTE (compact receiver, barrel, grip, stock)
		------------------------------------------------------------------------

		-- Main receiver body
		local receiver = makePart("Receiver", Vector3.new(0.3, 0.35, 1.2), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0.02, -0.1))

		-- Upper receiver surface
		makePart("UpperReceiver", Vector3.new(0.22, 0.05, 1.0), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.19, 0))

		-- Lower receiver plate
		makePart("LowerReceiver", Vector3.new(0.26, 0.04, 0.9), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, -0.18, 0.05))

		------------------------------------------------------------------------
		-- BARREL (short cylinder extending forward)
		------------------------------------------------------------------------
		local barrel = Instance.new("Part")
		barrel.Name = "Barrel"
		barrel.Shape = Enum.PartType.Cylinder
		barrel.Size = Vector3.new(0.7, 0.12, 0.12)
		barrel.Color = midMetal
		barrel.Material = Enum.Material.Metal
		barrel.CanCollide = false
		barrel.Massless = true
		barrel.Anchored = false
		barrel.Parent = model
		local bw = Instance.new("Motor6D")
		bw.Part0 = receiver
		bw.Part1 = barrel
		bw.C0 = CFrame.new(0, 0.04, -0.9) * CFrame.Angles(0, 0, math.rad(90))
		bw.Parent = barrel

		-- Muzzle (small cylinder at tip)
		local muzzlePart = Instance.new("Part")
		muzzlePart.Name = "Muzzle"
		muzzlePart.Shape = Enum.PartType.Cylinder
		muzzlePart.Size = Vector3.new(0.12, 0.16, 0.16)
		muzzlePart.Color = lightMetal
		muzzlePart.Material = Enum.Material.Metal
		muzzlePart.CanCollide = false
		muzzlePart.Massless = true
		muzzlePart.Anchored = false
		muzzlePart.Parent = model
		local mmw = Instance.new("Motor6D")
		mmw.Part0 = receiver
		mmw.Part1 = muzzlePart
		mmw.C0 = CFrame.new(0, 0.04, -1.3) * CFrame.Angles(0, 0, math.rad(90))
		mmw.Parent = muzzlePart

		-- MuzzleGlow (for muzzle flash system)
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.08, 0.08, 0.08), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0, 0.04, -1.4))
		muzzleGlow.Transparency = 0.5

		------------------------------------------------------------------------
		-- ANGLED PISTOL GRIP (WedgePart)
		------------------------------------------------------------------------
		local grip = Instance.new("WedgePart")
		grip.Name = "PistolGrip"
		grip.Size = Vector3.new(0.14, 0.35, 0.2)
		grip.Color = darkMetal
		grip.Material = Enum.Material.SmoothPlastic
		grip.CanCollide = false
		grip.Massless = true
		grip.Anchored = false
		grip.Parent = model
		local gw = Instance.new("Motor6D")
		gw.Part0 = receiver
		gw.Part1 = grip
		gw.C0 = CFrame.new(0, -0.33, 0.2) * CFrame.Angles(math.rad(15), 0, 0)
		gw.Parent = grip

		-- Grip texture
		makePart("GripTexture", Vector3.new(0.15, 0.25, 0.12), midMetal, Enum.Material.DiamondPlate,
			receiver, CFrame.new(0, -0.28, 0.2) * CFrame.Angles(math.rad(15), 0, 0))

		------------------------------------------------------------------------
		-- COMPACT FOLDING STOCK (thin blocks + wedge)
		------------------------------------------------------------------------
		-- Stock arm (thin horizontal bar)
		makePart("StockArm", Vector3.new(0.08, 0.08, 0.6), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0, 0.08, 0.85))

		-- Stock butt wedge
		local stockButt = Instance.new("WedgePart")
		stockButt.Name = "StockButt"
		stockButt.Size = Vector3.new(0.14, 0.18, 0.2)
		stockButt.Color = darkMetal
		stockButt.Material = Enum.Material.SmoothPlastic
		stockButt.CanCollide = false
		stockButt.Massless = true
		stockButt.Anchored = false
		stockButt.Parent = model
		local sbw = Instance.new("Motor6D")
		sbw.Part0 = receiver
		sbw.Part1 = stockButt
		sbw.C0 = CFrame.new(0, 0.08, 1.15) * CFrame.Angles(0, math.rad(180), 0)
		sbw.Parent = stockButt

		------------------------------------------------------------------------
		-- MAGAZINE (thin rectangle underneath)
		------------------------------------------------------------------------
		local mag = makePart("Magazine", Vector3.new(0.1, 0.3, 0.18), darkMetal, Enum.Material.SmoothPlastic,
			receiver, CFrame.new(0, -0.3, -0.15))

		-- Magazine bottom cap
		makePart("MagCap", Vector3.new(0.12, 0.04, 0.2), midMetal, Enum.Material.Metal,
			mag, CFrame.new(0, -0.16, 0))

		------------------------------------------------------------------------
		-- SIDE PANELS & NEON ACCENTS
		------------------------------------------------------------------------
		-- Side panels
		makePart("SidePanelL", Vector3.new(0.03, 0.25, 0.9), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(-0.16, 0, 0))
		makePart("SidePanelR", Vector3.new(0.03, 0.25, 0.9), midMetal, Enum.Material.Metal,
			receiver, CFrame.new(0.16, 0, 0))

		-- Embedded blue glow strips (sides)
		makePart("GlowStripL", Vector3.new(0.02, 0.03, 0.7), cyan, Enum.Material.Neon,
			receiver, CFrame.new(-0.15, 0.06, -0.05))
		makePart("GlowStripR", Vector3.new(0.02, 0.03, 0.7), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0.15, 0.06, -0.05))

		-- Top rail glow
		makePart("TopGlow", Vector3.new(0.03, 0.02, 0.5), cyan, Enum.Material.Neon,
			receiver, CFrame.new(0, 0.18, -0.1))

		------------------------------------------------------------------------
		-- DIGITAL DISPLAY (SurfaceGui with "MEM-256")
		------------------------------------------------------------------------
		local displayPart = makePart("Display", Vector3.new(0.03, 0.12, 0.2), darkMetal, Enum.Material.SmoothPlastic,
			receiver, CFrame.new(-0.165, -0.04, 0.15))

		local displayGui = Instance.new("SurfaceGui")
		displayGui.Name = "MemDisplay"
		displayGui.Face = Enum.NormalId.Left
		displayGui.LightInfluence = 0
		displayGui.Brightness = 2
		displayGui.SizingMode = Enum.SurfaceGuiSizingMode.FixedSize
		displayGui.CanvasSize = Vector2.new(200, 120)
		displayGui.Parent = displayPart

		local displayBg = Instance.new("Frame")
		displayBg.Name = "Background"
		displayBg.Size = UDim2.new(1, 0, 1, 0)
		displayBg.BackgroundColor3 = Color3.fromRGB(5, 5, 15)
		displayBg.BorderSizePixel = 0
		displayBg.Parent = displayGui

		local displayText = Instance.new("TextLabel")
		displayText.Name = "MemLabel"
		displayText.Size = UDim2.new(1, 0, 1, 0)
		displayText.BackgroundTransparency = 1
		displayText.Text = "MEM-256"
		displayText.TextColor3 = cyan
		displayText.TextScaled = true
		displayText.Font = Enum.Font.Code
		displayText.Parent = displayBg

		------------------------------------------------------------------------
		-- LIGHTING & EFFECTS
		------------------------------------------------------------------------
		local muzzleLight = Instance.new("PointLight")
		muzzleLight.Color = cyan
		muzzleLight.Brightness = 0.3
		muzzleLight.Range = 2
		muzzleLight.Parent = muzzleGlow

		local displayLight = Instance.new("PointLight")
		displayLight.Color = cyan
		displayLight.Brightness = 0.2
		displayLight.Range = 1.5
		displayLight.Parent = displayPart

		-- Muzzle ambient particles
		local muzzAmb = Instance.new("ParticleEmitter")
		muzzAmb.Name = "MuzzleAmbient"
		muzzAmb.Color = ColorSequence.new(cyan)
		muzzAmb.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.04),
			NumberSequenceKeypoint.new(1, 0),
		})
		muzzAmb.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0.3),
			NumberSequenceKeypoint.new(1, 1),
		})
		muzzAmb.Lifetime = NumberRange.new(0.15, 0.4)
		muzzAmb.Rate = 12
		muzzAmb.Speed = NumberRange.new(0.5, 2)
		muzzAmb.SpreadAngle = Vector2.new(60, 60)
		muzzAmb.LightEmission = 1
		muzzAmb.LightInfluence = 0
		muzzAmb.Parent = muzzleGlow
	end

	------------------------------------------------------------------------
	-- PULSE BLASTER: Compact balanced pistol with central cyan energy core
	------------------------------------------------------------------------
	if visual.shape == "pulseblaster" then
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name; p.Size = size; p.Color = color; p.Material = mat
			p.CanCollide = false; p.Massless = true; p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent; w.Part1 = p; w.C0 = offset; w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(140, 240, 255)
		local whiteCyan = Color3.fromRGB(220, 250, 255)
		local purple = Color3.fromRGB(140, 40, 255)

		-- === MAIN RECEIVER BODY ===
		local receiver = makePart("Receiver", Vector3.new(0.35, 0.4, 1.6), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		-- Top rail plate
		makePart("TopPlate", Vector3.new(0.24, 0.06, 1.4), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.22, -0.05))

		-- === BARREL (cylinder, medium length) ===
		local barrel = makePart("Barrel", Vector3.new(1.1, 0.14, 0.14), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -1.15))
		barrel.Shape = Enum.PartType.Cylinder
		local bW = barrel:FindFirstChildOfClass("Motor6D")
		if bW then bW.C0 = CFrame.new(0, 0.02, -1.15) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Barrel shroud
		makePart("BarrelShroud", Vector3.new(0.26, 0.24, 0.6), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -0.85))

		-- === MUZZLE RING ===
		local muzzleRing = makePart("MuzzleRing", Vector3.new(0.06, 0.2, 0.2), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -1.72))
		muzzleRing.Shape = Enum.PartType.Cylinder
		local mrW = muzzleRing:FindFirstChildOfClass("Motor6D")
		if mrW then mrW.C0 = CFrame.new(0, 0.02, -1.72) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Muzzle glow (for tracer/flash system)
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.04, 0.14, 0.14), cyan, Enum.Material.Neon,
			body, CFrame.new(0, 0.02, -1.76))
		muzzleGlow.Shape = Enum.PartType.Cylinder
		local mgW = muzzleGlow:FindFirstChildOfClass("Motor6D")
		if mgW then mgW.C0 = CFrame.new(0, 0.02, -1.76) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === CENTRAL ENERGY CORE ORB ===
		local coreOrb = makePart("CoreOrb", Vector3.new(0.22, 0.22, 0.22), whiteCyan, Enum.Material.Neon,
			body, CFrame.new(0, 0.02, -0.05))
		coreOrb.Shape = Enum.PartType.Ball

		-- Core housing ring
		local coreHousing = makePart("CoreHousing", Vector3.new(0.06, 0.36, 0.36), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -0.05))
		coreHousing.Shape = Enum.PartType.Cylinder
		local chW = coreHousing:FindFirstChildOfClass("Motor6D")
		if chW then chW.C0 = CFrame.new(0, 0.02, -0.05) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === SIDE RAILS ===
		makePart("SideRailL", Vector3.new(0.04, 0.08, 1.0), midMetal, Enum.Material.Metal,
			body, CFrame.new(-0.16, 0.02, -0.7))
		makePart("SideRailR", Vector3.new(0.04, 0.08, 1.0), midMetal, Enum.Material.Metal,
			body, CFrame.new(0.16, 0.02, -0.7))

		-- === GRIP (angled WedgePart + block) ===
		local grip = makePart("Grip", Vector3.new(0.14, 0.36, 0.2), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.36, 0.3) * CFrame.Angles(math.rad(12), 0, 0))

		local gripWedge = Instance.new("WedgePart")
		gripWedge.Name = "GripTaper"; gripWedge.Size = Vector3.new(0.14, 0.12, 0.18)
		gripWedge.Color = darkMetal; gripWedge.Material = Enum.Material.SmoothPlastic
		gripWedge.CanCollide = false; gripWedge.Massless = true; gripWedge.Anchored = false
		gripWedge.Parent = model
		local gwW = Instance.new("Motor6D")
		gwW.Part0 = grip; gwW.Part1 = gripWedge
		gwW.C0 = CFrame.new(0, -0.22, 0); gwW.Parent = gripWedge

		-- Trigger guard
		makePart("TriggerGuard", Vector3.new(0.05, 0.12, 0.24), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.28, 0.14))

		-- Trigger
		makePart("Trigger", Vector3.new(0.03, 0.07, 0.03), lightMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.24, 0.18) * CFrame.Angles(math.rad(15), 0, 0))

		-- === SMALL STOCK (block + wedge taper) ===
		local stock = makePart("Stock", Vector3.new(0.22, 0.28, 0.5), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.02, 0.95))

		local stockWedge = Instance.new("WedgePart")
		stockWedge.Name = "StockTaper"; stockWedge.Size = Vector3.new(0.22, 0.2, 0.3)
		stockWedge.Color = darkMetal; stockWedge.Material = Enum.Material.SmoothPlastic
		stockWedge.CanCollide = false; stockWedge.Massless = true; stockWedge.Anchored = false
		stockWedge.Parent = model
		local swW = Instance.new("Motor6D")
		swW.Part0 = stock; swW.Part1 = stockWedge
		swW.C0 = CFrame.new(0, 0.04, 0.35); swW.Parent = stockWedge

		makePart("StockPad", Vector3.new(0.2, 0.24, 0.04), lightMetal, Enum.Material.SmoothPlastic,
			stock, CFrame.new(0, 0, 0.27))

		-- === EMBEDDED CYAN GLOW STRIPS ===
		makePart("GlowStripL", Vector3.new(0.025, 0.025, 1.2), cyan, Enum.Material.Neon,
			body, CFrame.new(-0.17, 0.08, -0.15))
		makePart("GlowStripR", Vector3.new(0.025, 0.025, 1.2), cyan, Enum.Material.Neon,
			body, CFrame.new(0.17, 0.08, -0.15))
		makePart("GlowStripBotL", Vector3.new(0.025, 0.02, 0.6), cyan, Enum.Material.Neon,
			body, CFrame.new(-0.17, -0.1, 0.1))
		makePart("GlowStripBotR", Vector3.new(0.025, 0.02, 0.6), cyan, Enum.Material.Neon,
			body, CFrame.new(0.17, -0.1, 0.1))

		-- === VENT DETAILS ===
		for i = 0, 2 do
			makePart("VentL" .. i, Vector3.new(0.03, 0.06, 0.04), Color3.fromRGB(8, 8, 15), Enum.Material.SmoothPlastic,
				body, CFrame.new(-0.14, 0.02, -0.65 + i * 0.15))
			makePart("VentR" .. i, Vector3.new(0.03, 0.06, 0.04), Color3.fromRGB(8, 8, 15), Enum.Material.SmoothPlastic,
				body, CFrame.new(0.14, 0.02, -0.65 + i * 0.15))
		end

		-- === DIGITAL AMMO DISPLAY (SurfaceGui) ===
		local ammoDisplay = makePart("AmmoDisplay", Vector3.new(0.04, 0.1, 0.16), Color3.fromRGB(3, 3, 10), Enum.Material.SmoothPlastic,
			body, CFrame.new(0.19, 0.06, 0.2))

		local ammoGui = Instance.new("SurfaceGui")
		ammoGui.Name = "AmmoScreen"
		ammoGui.Face = Enum.NormalId.Right
		ammoGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		ammoGui.PixelsPerStud = 80
		ammoGui.Brightness = 1.8
		ammoGui.Parent = ammoDisplay

		local ammoFrame = Instance.new("Frame")
		ammoFrame.Size = UDim2.new(1, 0, 1, 0)
		ammoFrame.BackgroundColor3 = Color3.fromRGB(0, 3, 10)
		ammoFrame.BorderSizePixel = 0
		ammoFrame.Parent = ammoGui

		local ammoText = Instance.new("TextLabel")
		ammoText.Name = "AmmoCount"
		ammoText.Size = UDim2.new(1, 0, 0.8, 0)
		ammoText.Position = UDim2.new(0, 0, 0.1, 0)
		ammoText.BackgroundTransparency = 1
		ammoText.Text = "88"
		ammoText.TextColor3 = cyan
		ammoText.TextScaled = true
		ammoText.Font = Enum.Font.Code
		ammoText.Parent = ammoFrame

		-- === LIGHTING ===
		local coreLight = Instance.new("PointLight")
		coreLight.Color = brightCyan
		coreLight.Brightness = 3.5
		coreLight.Range = 12
		coreLight.Parent = coreOrb

		local muzzLight = Instance.new("PointLight")
		muzzLight.Color = cyan
		muzzLight.Brightness = 1.5
		muzzLight.Range = 5
		muzzLight.Parent = muzzleGlow

		-- === PARTICLES: core energy swirl ===
		local coreSparks = Instance.new("ParticleEmitter")
		coreSparks.Name = "CoreSparks"
		coreSparks.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(220, 250, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(100, 100, 255)),
		})
		coreSparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(0.5, 0.08), NumberSequenceKeypoint.new(1, 0) })
		coreSparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		coreSparks.Lifetime = NumberRange.new(0.12, 0.35)
		coreSparks.Rate = 30
		coreSparks.Speed = NumberRange.new(1, 3)
		coreSparks.SpreadAngle = Vector2.new(360, 360)
		coreSparks.LightEmission = 1
		coreSparks.LightInfluence = 0
		coreSparks.Parent = coreOrb

		-- Muzzle ambient particles
		local muzzAmb = Instance.new("ParticleEmitter")
		muzzAmb.Name = "MuzzleAmbient"
		muzzAmb.Color = ColorSequence.new(brightCyan)
		muzzAmb.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.08), NumberSequenceKeypoint.new(1, 0) })
		muzzAmb.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		muzzAmb.Lifetime = NumberRange.new(0.15, 0.4)
		muzzAmb.Rate = 15
		muzzAmb.Speed = NumberRange.new(0.5, 2)
		muzzAmb.SpreadAngle = Vector2.new(50, 50)
		muzzAmb.LightEmission = 1
		muzzAmb.LightInfluence = 0
		muzzAmb.Parent = muzzleGlow
	end

	------------------------------------------------------------------------
	-- GLITCH SHOTGUN: Heavy brutal shotgun with glitch energy chamber
	------------------------------------------------------------------------
	if visual.shape == "glitchshotgun" then
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name; p.Size = size; p.Color = color; p.Material = mat
			p.CanCollide = false; p.Massless = true; p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent; w.Part1 = p; w.C0 = offset; w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local purple = Color3.fromRGB(140, 40, 255)
		local magenta = Color3.fromRGB(200, 0, 180)
		local brightMagenta = Color3.fromRGB(255, 120, 255)
		local cyan = Color3.fromRGB(0, 200, 255)

		-- === HEAVY WIDE RECEIVER ===
		local receiver = makePart("Receiver", Vector3.new(0.5, 0.5, 2.0), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		makePart("TopPlate", Vector3.new(0.36, 0.06, 1.8), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.28, -0.05))

		-- === WIDE BARREL (large cylinder, short and thick) ===
		local barrel = makePart("Barrel", Vector3.new(0.8, 0.3, 0.3), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -1.3))
		barrel.Shape = Enum.PartType.Cylinder
		local bW = barrel:FindFirstChildOfClass("Motor6D")
		if bW then bW.C0 = CFrame.new(0, 0.02, -1.3) * CFrame.Angles(0, 0, math.rad(90)) end

		makePart("BarrelHousing", Vector3.new(0.44, 0.4, 0.7), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -0.95))

		-- Muzzle glow
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.04, 0.24, 0.24), magenta, Enum.Material.Neon,
			body, CFrame.new(0, 0.02, -1.72))
		muzzleGlow.Shape = Enum.PartType.Cylinder
		local mgW = muzzleGlow:FindFirstChildOfClass("Motor6D")
		if mgW then mgW.C0 = CFrame.new(0, 0.02, -1.72) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === PUMP MECHANISM ===
		local pump = makePart("PumpTube", Vector3.new(0.7, 0.1, 0.1), lightMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.18, -0.8))
		pump.Shape = Enum.PartType.Cylinder
		local pW = pump:FindFirstChildOfClass("Motor6D")
		if pW then pW.C0 = CFrame.new(0, -0.18, -0.8) * CFrame.Angles(0, 0, math.rad(90)) end

		makePart("PumpHandle", Vector3.new(0.16, 0.1, 0.18), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.2, -0.5))

		-- === CHUNKY FOREGRIP ===
		makePart("Foregrip", Vector3.new(0.16, 0.22, 0.2), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.36, -0.4) * CFrame.Angles(math.rad(8), 0, 0))

		-- === ENERGY CHAMBER (ball with purple neon glow) ===
		local energyCore = makePart("EnergyCore", Vector3.new(0.28, 0.28, 0.28), brightMagenta, Enum.Material.Neon,
			body, CFrame.new(0, 0.02, -0.3))
		energyCore.Shape = Enum.PartType.Ball

		local chamberRing = makePart("ChamberRing", Vector3.new(0.06, 0.36, 0.36), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -0.3))
		chamberRing.Shape = Enum.PartType.Cylinder
		local crW = chamberRing:FindFirstChildOfClass("Motor6D")
		if crW then crW.C0 = CFrame.new(0, 0.02, -0.3) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === HEAVY STOCK ===
		local stock = makePart("Stock", Vector3.new(0.32, 0.38, 0.6), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.02, 1.15))

		local stockWedge = Instance.new("WedgePart")
		stockWedge.Name = "StockTaper"; stockWedge.Size = Vector3.new(0.32, 0.28, 0.35)
		stockWedge.Color = darkMetal; stockWedge.Material = Enum.Material.SmoothPlastic
		stockWedge.CanCollide = false; stockWedge.Massless = true; stockWedge.Anchored = false
		stockWedge.Parent = model
		local swW = Instance.new("Motor6D")
		swW.Part0 = stock; swW.Part1 = stockWedge
		swW.C0 = CFrame.new(0, 0.05, 0.4); swW.Parent = stockWedge

		makePart("StockPad", Vector3.new(0.28, 0.32, 0.04), lightMetal, Enum.Material.SmoothPlastic,
			stock, CFrame.new(0, 0, 0.32))

		-- === PISTOL GRIP ===
		local grip = makePart("Grip", Vector3.new(0.16, 0.38, 0.22), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.4, 0.35) * CFrame.Angles(math.rad(12), 0, 0))

		local gripWedge = Instance.new("WedgePart")
		gripWedge.Name = "GripTaper"; gripWedge.Size = Vector3.new(0.16, 0.1, 0.2)
		gripWedge.Color = darkMetal; gripWedge.Material = Enum.Material.SmoothPlastic
		gripWedge.CanCollide = false; gripWedge.Massless = true; gripWedge.Anchored = false
		gripWedge.Parent = model
		local ggW = Instance.new("Motor6D")
		ggW.Part0 = grip; ggW.Part1 = gripWedge
		ggW.C0 = CFrame.new(0, -0.22, 0); ggW.Parent = gripWedge

		makePart("TriggerGuard", Vector3.new(0.06, 0.14, 0.28), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.32, 0.16))

		-- === SIDE ARMOR PLATES (DiamondPlate) ===
		makePart("ArmorPlateL", Vector3.new(0.04, 0.3, 0.8), midMetal, Enum.Material.DiamondPlate,
			body, CFrame.new(-0.27, 0.04, -0.2))
		makePart("ArmorPlateR", Vector3.new(0.04, 0.3, 0.8), midMetal, Enum.Material.DiamondPlate,
			body, CFrame.new(0.27, 0.04, -0.2))

		-- === GLITCH ACCENT STRIPS (segmented purple + magenta) ===
		makePart("GlitchStripL1", Vector3.new(0.025, 0.03, 0.5), purple, Enum.Material.Neon,
			body, CFrame.new(-0.26, 0.12, -0.1))
		makePart("GlitchStripL2", Vector3.new(0.025, 0.03, 0.25), magenta, Enum.Material.Neon,
			body, CFrame.new(-0.26, 0.12, 0.55))
		makePart("GlitchStripR1", Vector3.new(0.025, 0.03, 0.5), purple, Enum.Material.Neon,
			body, CFrame.new(0.26, 0.12, -0.1))
		makePart("GlitchStripR2", Vector3.new(0.025, 0.03, 0.25), magenta, Enum.Material.Neon,
			body, CFrame.new(0.26, 0.12, 0.55))
		makePart("GlitchSeg1", Vector3.new(0.025, 0.02, 0.08), magenta, Enum.Material.Neon,
			body, CFrame.new(-0.26, -0.08, -0.5))
		makePart("GlitchSeg2", Vector3.new(0.025, 0.02, 0.06), purple, Enum.Material.Neon,
			body, CFrame.new(0.26, -0.08, -0.35))
		makePart("GlitchSeg3", Vector3.new(0.025, 0.02, 0.1), magenta, Enum.Material.Neon,
			body, CFrame.new(-0.26, -0.08, 0.2))

		-- === SHELL HOLDERS (small cylinders on side) ===
		for i = 0, 2 do
			local shell = makePart("Shell" .. i, Vector3.new(0.08, 0.04, 0.04), lightMetal, Enum.Material.Metal,
				body, CFrame.new(0.27, 0.02, 0.2 + i * 0.12))
			shell.Shape = Enum.PartType.Cylinder
			local shW = shell:FindFirstChildOfClass("Motor6D")
			if shW then shW.C0 = CFrame.new(0.27, 0.02, 0.2 + i * 0.12) * CFrame.Angles(0, 0, math.rad(90)) end
		end

		-- === LIGHTING ===
		local chamberLight = Instance.new("PointLight")
		chamberLight.Color = purple
		chamberLight.Brightness = 3
		chamberLight.Range = 10
		chamberLight.Parent = energyCore

		-- === PARTICLES: glitch energy ===
		local glitchParticles = Instance.new("ParticleEmitter")
		glitchParticles.Name = "GlitchEnergy"
		glitchParticles.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 100, 255)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(200, 50, 255)),
			ColorSequenceKeypoint.new(0.7, Color3.fromRGB(0, 200, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 60, 200)),
		})
		glitchParticles.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(0.5, 0.06), NumberSequenceKeypoint.new(1, 0) })
		glitchParticles.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.5, 0.3), NumberSequenceKeypoint.new(1, 1) })
		glitchParticles.Lifetime = NumberRange.new(0.08, 0.25)
		glitchParticles.Rate = 45
		glitchParticles.Speed = NumberRange.new(2, 6)
		glitchParticles.SpreadAngle = Vector2.new(160, 160)
		glitchParticles.LightEmission = 1
		glitchParticles.LightInfluence = 0
		glitchParticles.Parent = energyCore

		local pixelDebris = Instance.new("ParticleEmitter")
		pixelDebris.Name = "PixelDebris"
		pixelDebris.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(0, 220, 255)),
			ColorSequenceKeypoint.new(0.5, Color3.fromRGB(200, 60, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 80, 180)),
		})
		pixelDebris.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(1, 0) })
		pixelDebris.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
		pixelDebris.Lifetime = NumberRange.new(0.15, 0.5)
		pixelDebris.Rate = 20
		pixelDebris.Speed = NumberRange.new(1, 3)
		pixelDebris.SpreadAngle = Vector2.new(180, 180)
		pixelDebris.Rotation = NumberRange.new(0, 360)
		pixelDebris.RotSpeed = NumberRange.new(-300, 300)
		pixelDebris.LightEmission = 1
		pixelDebris.LightInfluence = 0
		pixelDebris.Parent = energyCore
	end

	------------------------------------------------------------------------
	-- SHOCK LAUNCHER: Bulky experimental launcher with front coil chamber
	------------------------------------------------------------------------
	if visual.shape == "shocklauncher" then
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name; p.Size = size; p.Color = color; p.Material = mat
			p.CanCollide = false; p.Massless = true; p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent; w.Part1 = p; w.C0 = offset; w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(140, 240, 255)
		local yellow = Color3.fromRGB(255, 240, 180)
		local purple = Color3.fromRGB(140, 40, 255)

		-- === HEAVY BODY ===
		local receiver = makePart("Receiver", Vector3.new(0.5, 0.55, 2.4), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		makePart("TopPlate", Vector3.new(0.34, 0.06, 2.0), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.3, -0.1))

		-- === LARGE FRONT COIL CHAMBER ===
		local coilOuter = makePart("CoilOuter", Vector3.new(0.3, 0.55, 0.55), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0, -1.1))
		coilOuter.Shape = Enum.PartType.Cylinder
		local coW = coilOuter:FindFirstChildOfClass("Motor6D")
		if coW then coW.C0 = CFrame.new(0, 0, -1.1) * CFrame.Angles(0, 0, math.rad(90)) end

		local coilEnergy = makePart("CoilEnergy", Vector3.new(0.32, 0.42, 0.42), purple, Enum.Material.Neon,
			body, CFrame.new(0, 0, -1.1))
		coilEnergy.Shape = Enum.PartType.Cylinder
		local ceW = coilEnergy:FindFirstChildOfClass("Motor6D")
		if ceW then ceW.C0 = CFrame.new(0, 0, -1.1) * CFrame.Angles(0, 0, math.rad(90)) end

		local coilFrontRing = makePart("CoilFrontRing", Vector3.new(0.06, 0.6, 0.6), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0, -1.3))
		coilFrontRing.Shape = Enum.PartType.Cylinder
		local cfrW = coilFrontRing:FindFirstChildOfClass("Motor6D")
		if cfrW then cfrW.C0 = CFrame.new(0, 0, -1.3) * CFrame.Angles(0, 0, math.rad(90)) end

		local coilRearRing = makePart("CoilRearRing", Vector3.new(0.06, 0.6, 0.6), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0, -0.9))
		coilRearRing.Shape = Enum.PartType.Cylinder
		local crrW = coilRearRing:FindFirstChildOfClass("Motor6D")
		if crrW then crrW.C0 = CFrame.new(0, 0, -0.9) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === HEAVY BARREL (inside the coil) ===
		local innerBarrel = makePart("InnerBarrel", Vector3.new(0.6, 0.12, 0.12), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0, -1.1))
		innerBarrel.Shape = Enum.PartType.Cylinder
		local ibW = innerBarrel:FindFirstChildOfClass("Motor6D")
		if ibW then ibW.C0 = CFrame.new(0, 0, -1.1) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Muzzle glow
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.04, 0.18, 0.18), cyan, Enum.Material.Neon,
			body, CFrame.new(0, 0, -1.42))
		muzzleGlow.Shape = Enum.PartType.Cylinder
		local mgW = muzzleGlow:FindFirstChildOfClass("Motor6D")
		if mgW then mgW.C0 = CFrame.new(0, 0, -1.42) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === POWER TUBE (along top, yellow-white neon glow) ===
		local powerTube = makePart("PowerTube", Vector3.new(1.6, 0.08, 0.08), yellow, Enum.Material.Neon,
			body, CFrame.new(0, 0.28, -0.4))
		powerTube.Shape = Enum.PartType.Cylinder
		local ptW = powerTube:FindFirstChildOfClass("Motor6D")
		if ptW then ptW.C0 = CFrame.new(0, 0.28, -0.4) * CFrame.Angles(0, 0, math.rad(90)) end

		makePart("TubeBracket1", Vector3.new(0.12, 0.06, 0.12), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.3, -0.1))
		makePart("TubeBracket2", Vector3.new(0.12, 0.06, 0.12), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.3, -0.7))

		-- === INDUSTRIAL GRIP ===
		local grip = makePart("Grip", Vector3.new(0.18, 0.4, 0.24), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.46, 0.4) * CFrame.Angles(math.rad(14), 0, 0))

		local gripWedge = Instance.new("WedgePart")
		gripWedge.Name = "GripTaper"; gripWedge.Size = Vector3.new(0.18, 0.12, 0.22)
		gripWedge.Color = darkMetal; gripWedge.Material = Enum.Material.SmoothPlastic
		gripWedge.CanCollide = false; gripWedge.Massless = true; gripWedge.Anchored = false
		gripWedge.Parent = model
		local gwW = Instance.new("Motor6D")
		gwW.Part0 = grip; gwW.Part1 = gripWedge
		gwW.C0 = CFrame.new(0, -0.24, 0); gwW.Parent = gripWedge

		makePart("TriggerGuard", Vector3.new(0.06, 0.16, 0.3), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.36, 0.2))

		-- === HEAVY STOCK with support strut ===
		local stock = makePart("Stock", Vector3.new(0.34, 0.4, 0.7), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.04, 1.4))

		local stockWedge = Instance.new("WedgePart")
		stockWedge.Name = "StockTaper"; stockWedge.Size = Vector3.new(0.34, 0.3, 0.4)
		stockWedge.Color = darkMetal; stockWedge.Material = Enum.Material.SmoothPlastic
		stockWedge.CanCollide = false; stockWedge.Massless = true; stockWedge.Anchored = false
		stockWedge.Parent = model
		local ssW = Instance.new("Motor6D")
		ssW.Part0 = stock; ssW.Part1 = stockWedge
		ssW.C0 = CFrame.new(0, 0.05, 0.45); ssW.Parent = stockWedge

		makePart("StockStrut", Vector3.new(0.04, 0.04, 0.5), lightMetal, Enum.Material.Metal,
			stock, CFrame.new(0, -0.16, 0.05))

		-- === SIDE PANELS ===
		makePart("SidePanelL", Vector3.new(0.05, 0.36, 1.4), midMetal, Enum.Material.Metal,
			body, CFrame.new(-0.27, 0, 0))
		makePart("SidePanelR", Vector3.new(0.05, 0.36, 1.4), midMetal, Enum.Material.Metal,
			body, CFrame.new(0.27, 0, 0))

		-- === ELECTRICAL ARCING EFFECTS ===
		makePart("ArcTop", Vector3.new(0.025, 0.025, 0.15), brightCyan, Enum.Material.Neon,
			body, CFrame.new(0, 0.3, -1.1) * CFrame.Angles(0, math.rad(15), 0))
		makePart("ArcBot", Vector3.new(0.025, 0.025, 0.12), brightCyan, Enum.Material.Neon,
			body, CFrame.new(0, -0.3, -1.1) * CFrame.Angles(0, math.rad(-10), 0))
		makePart("ArcLeft", Vector3.new(0.025, 0.12, 0.025), brightCyan, Enum.Material.Neon,
			body, CFrame.new(-0.3, 0, -1.1))
		makePart("ArcRight", Vector3.new(0.025, 0.12, 0.025), brightCyan, Enum.Material.Neon,
			body, CFrame.new(0.3, 0, -1.1))

		-- === DIGITAL TARGETING DISPLAY ===
		local displayScreen = makePart("DisplayScreen", Vector3.new(0.2, 0.12, 0.3), Color3.fromRGB(3, 5, 12), Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0.35, 0.2))

		local dispGui = Instance.new("SurfaceGui")
		dispGui.Name = "TacDisplay"
		dispGui.Face = Enum.NormalId.Top
		dispGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		dispGui.PixelsPerStud = 80
		dispGui.Brightness = 2
		dispGui.Parent = displayScreen

		local dispFrame = Instance.new("Frame")
		dispFrame.Size = UDim2.new(1, 0, 1, 0)
		dispFrame.BackgroundColor3 = Color3.fromRGB(0, 5, 15)
		dispFrame.BorderSizePixel = 0
		dispFrame.Parent = dispGui

		local dispText = Instance.new("TextLabel")
		dispText.Size = UDim2.new(1, 0, 0.8, 0)
		dispText.Position = UDim2.new(0, 0, 0.1, 0)
		dispText.BackgroundTransparency = 1
		dispText.Text = "SHK-04"
		dispText.TextColor3 = cyan
		dispText.TextScaled = true
		dispText.Font = Enum.Font.Code
		dispText.Parent = dispFrame

		-- === LIGHTING ===
		local chamberLight = Instance.new("PointLight")
		chamberLight.Color = purple
		chamberLight.Brightness = 3
		chamberLight.Range = 14
		chamberLight.Parent = coilEnergy

		local tubeLight = Instance.new("PointLight")
		tubeLight.Color = yellow
		tubeLight.Brightness = 2
		tubeLight.Range = 8
		tubeLight.Parent = powerTube

		local muzzLight = Instance.new("PointLight")
		muzzLight.Color = cyan
		muzzLight.Brightness = 2
		muzzLight.Range = 6
		muzzLight.Parent = muzzleGlow

		-- === PARTICLES: lightning energy in chamber ===
		local lightning = Instance.new("ParticleEmitter")
		lightning.Name = "LightningEnergy"
		lightning.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(200, 220, 255)),
			ColorSequenceKeypoint.new(0.3, Color3.fromRGB(100, 60, 255)),
			ColorSequenceKeypoint.new(0.6, Color3.fromRGB(0, 180, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 80, 255)),
		})
		lightning.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.12), NumberSequenceKeypoint.new(0.3, 0.06), NumberSequenceKeypoint.new(1, 0) })
		lightning.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.4, 0.2), NumberSequenceKeypoint.new(1, 1) })
		lightning.Lifetime = NumberRange.new(0.06, 0.2)
		lightning.Rate = 55
		lightning.Speed = NumberRange.new(3, 8)
		lightning.SpreadAngle = Vector2.new(180, 180)
		lightning.LightEmission = 1
		lightning.LightInfluence = 0
		lightning.Parent = coilEnergy

		local muzzSparks = Instance.new("ParticleEmitter")
		muzzSparks.Name = "MuzzleSparks"
		muzzSparks.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(180, 230, 255)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(80, 140, 255)),
		})
		muzzSparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 0) })
		muzzSparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
		muzzSparks.Lifetime = NumberRange.new(0.1, 0.35)
		muzzSparks.Rate = 20
		muzzSparks.Speed = NumberRange.new(2, 5)
		muzzSparks.SpreadAngle = Vector2.new(60, 60)
		muzzSparks.LightEmission = 1
		muzzSparks.LightInfluence = 0
		muzzSparks.Parent = muzzleGlow
	end

	------------------------------------------------------------------------
	-- SNIPER: Long-range precision rifle with scope and energy rails
	------------------------------------------------------------------------
	if visual.shape == "sniper" then
		local function makePart(name: string, size: Vector3, color: Color3, mat: Enum.Material, parent: BasePart, offset: CFrame): Part
			local p = Instance.new("Part")
			p.Name = name; p.Size = size; p.Color = color; p.Material = mat
			p.CanCollide = false; p.Massless = true; p.Anchored = false
			p.Parent = model
			local w = Instance.new("Motor6D")
			w.Part0 = parent; w.Part1 = p; w.C0 = offset; w.Parent = p
			return p
		end

		local darkMetal = Color3.fromRGB(18, 18, 30)
		local midMetal = Color3.fromRGB(35, 35, 50)
		local lightMetal = Color3.fromRGB(55, 55, 70)
		local cyan = Color3.fromRGB(0, 200, 255)
		local brightCyan = Color3.fromRGB(140, 240, 255)
		local red = Color3.fromRGB(255, 40, 40)

		-- === MAIN RECEIVER (long, narrow precision body) ===
		local receiver = makePart("Receiver", Vector3.new(0.3, 0.35, 3.0), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0, 0))

		-- Top rail
		makePart("TopRail", Vector3.new(0.2, 0.05, 2.6), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.2, -0.1))

		-- Side plating
		makePart("SidePlateL", Vector3.new(0.04, 0.28, 2.4), midMetal, Enum.Material.Metal,
			body, CFrame.new(-0.17, 0, -0.2))
		makePart("SidePlateR", Vector3.new(0.04, 0.28, 2.4), midMetal, Enum.Material.Metal,
			body, CFrame.new(0.17, 0, -0.2))

		-- === LONG PRECISION BARREL (thin cylinder) ===
		local barrel = makePart("Barrel", Vector3.new(1.8, 0.12, 0.12), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -2.3))
		barrel.Shape = Enum.PartType.Cylinder
		local bW = barrel:FindFirstChildOfClass("Motor6D")
		if bW then bW.C0 = CFrame.new(0, 0.02, -2.3) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Barrel shroud (slim housing around barrel base)
		makePart("BarrelShroud", Vector3.new(0.22, 0.2, 0.8), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -1.6))

		-- Barrel suppressor rings
		for i = 0, 3 do
			local ring = makePart("BarrelRing" .. i, Vector3.new(0.04, 0.16, 0.16), lightMetal, Enum.Material.Metal,
				body, CFrame.new(0, 0.02, -2.0 - i * 0.4))
			ring.Shape = Enum.PartType.Cylinder
			local rW = ring:FindFirstChildOfClass("Motor6D")
			if rW then rW.C0 = CFrame.new(0, 0.02, -2.0 - i * 0.4) * CFrame.Angles(0, 0, math.rad(90)) end
		end

		-- === MUZZLE BRAKE (cylinder with vent slots) ===
		local muzzleBrake = makePart("MuzzleBrake", Vector3.new(0.18, 0.16, 0.16), lightMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.02, -3.3))
		muzzleBrake.Shape = Enum.PartType.Cylinder
		local mbW = muzzleBrake:FindFirstChildOfClass("Motor6D")
		if mbW then mbW.C0 = CFrame.new(0, 0.02, -3.3) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Muzzle brake vent slots
		makePart("MuzzleVentT", Vector3.new(0.08, 0.02, 0.04), Color3.fromRGB(8, 8, 15), Enum.Material.SmoothPlastic,
			body, CFrame.new(0, 0.12, -3.28))
		makePart("MuzzleVentB", Vector3.new(0.08, 0.02, 0.04), Color3.fromRGB(8, 8, 15), Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.08, -3.28))

		-- MuzzleGlow (red neon for sniper - REQUIRED for tracer/flash system)
		local muzzleGlow = makePart("MuzzleGlow", Vector3.new(0.04, 0.1, 0.1), red, Enum.Material.Neon,
			body, CFrame.new(0, 0.02, -3.42))
		muzzleGlow.Shape = Enum.PartType.Cylinder
		local mgW = muzzleGlow:FindFirstChildOfClass("Motor6D")
		if mgW then mgW.C0 = CFrame.new(0, 0.02, -3.42) * CFrame.Angles(0, 0, math.rad(90)) end

		-- === PREMIUM SCOPE (cylinder with lens caps) ===
		local scopeMount = makePart("ScopeMount", Vector3.new(0.12, 0.06, 0.7), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, 0.26, 0))

		local scopeBody = makePart("ScopeBody", Vector3.new(0.8, 0.18, 0.18), darkMetal, Enum.Material.Metal,
			scopeMount, CFrame.new(0, 0.12, 0))
		scopeBody.Shape = Enum.PartType.Cylinder
		local sbW = scopeBody:FindFirstChildOfClass("Motor6D")
		if sbW then sbW.C0 = CFrame.new(0, 0.12, 0) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Scope front lens cap
		local scopeFrontCap = makePart("ScopeFrontCap", Vector3.new(0.06, 0.2, 0.2), midMetal, Enum.Material.Metal,
			scopeMount, CFrame.new(0, 0.12, -0.42))
		scopeFrontCap.Shape = Enum.PartType.Cylinder
		local sfW = scopeFrontCap:FindFirstChildOfClass("Motor6D")
		if sfW then sfW.C0 = CFrame.new(0, 0.12, -0.42) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Scope rear lens cap
		local scopeRearCap = makePart("ScopeRearCap", Vector3.new(0.06, 0.2, 0.2), midMetal, Enum.Material.Metal,
			scopeMount, CFrame.new(0, 0.12, 0.42))
		scopeRearCap.Shape = Enum.PartType.Cylinder
		local srW = scopeRearCap:FindFirstChildOfClass("Motor6D")
		if srW then srW.C0 = CFrame.new(0, 0.12, 0.42) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Scope front lens (red glow)
		local scopeLens = makePart("ScopeLens", Vector3.new(0.03, 0.14, 0.14), red, Enum.Material.Neon,
			scopeMount, CFrame.new(0, 0.12, -0.46))
		scopeLens.Shape = Enum.PartType.Cylinder
		local slW = scopeLens:FindFirstChildOfClass("Motor6D")
		if slW then slW.C0 = CFrame.new(0, 0.12, -0.46) * CFrame.Angles(0, 0, math.rad(90)) end

		-- Scope adjustment knobs
		makePart("ScopeKnobL", Vector3.new(0.06, 0.06, 0.06), lightMetal, Enum.Material.Metal,
			scopeMount, CFrame.new(-0.12, 0.16, 0.1))
		makePart("ScopeKnobR", Vector3.new(0.06, 0.06, 0.06), lightMetal, Enum.Material.Metal,
			scopeMount, CFrame.new(0.12, 0.16, 0.1))

		-- === BOLT ACTION DETAIL ===
		local boltHandle = makePart("BoltHandle", Vector3.new(0.1, 0.05, 0.05), lightMetal, Enum.Material.Metal,
			body, CFrame.new(0.18, 0.14, 0.3))
		local boltKnob = makePart("BoltKnob", Vector3.new(0.05, 0.05, 0.05), lightMetal, Enum.Material.Metal,
			boltHandle, CFrame.new(0.07, 0, 0))
		boltKnob.Shape = Enum.PartType.Ball

		-- === RED NEON ACCENT LINES (thin, elegant) ===
		makePart("AccentLineL", Vector3.new(0.02, 0.02, 2.2), red, Enum.Material.Neon,
			body, CFrame.new(-0.16, 0.1, -0.3))
		makePart("AccentLineR", Vector3.new(0.02, 0.02, 2.2), red, Enum.Material.Neon,
			body, CFrame.new(0.16, 0.1, -0.3))
		makePart("AccentLineTop", Vector3.new(0.08, 0.02, 1.6), red, Enum.Material.Neon,
			body, CFrame.new(0, 0.18, -0.5))

		-- === SLIM GRIP + WEDGE TAPER ===
		local grip = makePart("Grip", Vector3.new(0.14, 0.32, 0.18), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.34, 0.4) * CFrame.Angles(math.rad(10), 0, 0))
		local gripWedge = Instance.new("WedgePart")
		gripWedge.Name = "GripTaper"; gripWedge.Size = Vector3.new(0.14, 0.12, 0.18)
		gripWedge.Color = darkMetal; gripWedge.Material = Enum.Material.SmoothPlastic
		gripWedge.CanCollide = false; gripWedge.Massless = true; gripWedge.Anchored = false
		gripWedge.Parent = model
		local gwW = Instance.new("Motor6D")
		gwW.Part0 = grip; gwW.Part1 = gripWedge
		gwW.C0 = CFrame.new(0, -0.22, 0) * CFrame.Angles(math.rad(180), 0, 0)
		gwW.Parent = gripWedge

		-- Trigger guard
		makePart("TriggerGuard", Vector3.new(0.05, 0.12, 0.24), darkMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.26, 0.25))

		-- === SLIM MAGAZINE ===
		local mag = makePart("Magazine", Vector3.new(0.1, 0.2, 0.12), midMetal, Enum.Material.Metal,
			body, CFrame.new(0, -0.28, -0.1))
		makePart("MagGlow", Vector3.new(0.02, 0.14, 0.02), red, Enum.Material.Neon,
			mag, CFrame.new(0.04, 0, 0))

		-- === ELEGANT STOCK + WEDGE TAPER ===
		local stock = makePart("Stock", Vector3.new(0.24, 0.26, 0.7), darkMetal, Enum.Material.SmoothPlastic,
			body, CFrame.new(0, -0.02, 1.8))
		local stockWedge = Instance.new("WedgePart")
		stockWedge.Name = "StockTaper"; stockWedge.Size = Vector3.new(0.24, 0.26, 0.3)
		stockWedge.Color = darkMetal; stockWedge.Material = Enum.Material.SmoothPlastic
		stockWedge.CanCollide = false; stockWedge.Massless = true; stockWedge.Anchored = false
		stockWedge.Parent = model
		local swW = Instance.new("Motor6D")
		swW.Part0 = stock; swW.Part1 = stockWedge
		swW.C0 = CFrame.new(0, 0, 0.5) * CFrame.Angles(0, math.rad(180), 0)
		swW.Parent = stockWedge

		-- Stock buttpad
		makePart("StockPad", Vector3.new(0.2, 0.22, 0.04), lightMetal, Enum.Material.SmoothPlastic,
			stock, CFrame.new(0, 0, 0.37))

		-- Cheek rest
		makePart("CheekRest", Vector3.new(0.12, 0.07, 0.35), midMetal, Enum.Material.SmoothPlastic,
			stock, CFrame.new(0, 0.15, 0.05))

		-- Stock accent line
		makePart("StockAccent", Vector3.new(0.02, 0.03, 0.5), red, Enum.Material.Neon,
			stock, CFrame.new(0.12, 0, 0))

		-- === BIPOD LEGS (two thin angled parts) ===
		makePart("BipodLegL", Vector3.new(0.03, 0.18, 0.03), midMetal, Enum.Material.Metal,
			body, CFrame.new(-0.08, -0.28, -1.0) * CFrame.Angles(math.rad(25), 0, 0))
		makePart("BipodLegR", Vector3.new(0.03, 0.18, 0.03), midMetal, Enum.Material.Metal,
			body, CFrame.new(0.08, -0.28, -1.0) * CFrame.Angles(math.rad(25), 0, 0))
		makePart("BipodFootL", Vector3.new(0.04, 0.02, 0.04), lightMetal, Enum.Material.Metal,
			body, CFrame.new(-0.08, -0.38, -1.08))
		makePart("BipodFootR", Vector3.new(0.04, 0.02, 0.04), lightMetal, Enum.Material.Metal,
			body, CFrame.new(0.08, -0.38, -1.08))

		-- === SURFACEGUI RANGEFINDER on scope ===
		local rangeDisplay = makePart("RangeDisplay", Vector3.new(0.04, 0.05, 0.08), Color3.fromRGB(3, 3, 10), Enum.Material.SmoothPlastic,
			scopeMount, CFrame.new(0.1, 0.16, 0.2))
		local rangeGui = Instance.new("SurfaceGui")
		rangeGui.Name = "RangeHUD"
		rangeGui.Face = Enum.NormalId.Right
		rangeGui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		rangeGui.PixelsPerStud = 80
		rangeGui.Brightness = 1.5
		rangeGui.Parent = rangeDisplay
		local rangeFrame = Instance.new("Frame")
		rangeFrame.Size = UDim2.new(1, 0, 1, 0)
		rangeFrame.BackgroundColor3 = Color3.fromRGB(0, 2, 8)
		rangeFrame.BorderSizePixel = 0
		rangeFrame.Parent = rangeGui
		local rangeText = Instance.new("TextLabel")
		rangeText.Size = UDim2.new(1, 0, 1, 0)
		rangeText.BackgroundTransparency = 1
		rangeText.Text = "250m"
		rangeText.TextColor3 = red
		rangeText.TextScaled = true
		rangeText.Font = Enum.Font.Code
		rangeText.Parent = rangeFrame

		-- === LIGHTING ===
		local muzzLight = Instance.new("PointLight")
		muzzLight.Color = red
		muzzLight.Brightness = 1.8
		muzzLight.Range = 5
		muzzLight.Parent = muzzleGlow

		local scopeLight = Instance.new("PointLight")
		scopeLight.Color = red
		scopeLight.Brightness = 0.8
		scopeLight.Range = 3
		scopeLight.Parent = scopeLens

		local accentLight = Instance.new("PointLight")
		accentLight.Color = red
		accentLight.Brightness = 0.5
		accentLight.Range = 4
		accentLight.Parent = receiver

		-- === PARTICLES: muzzle ambient ===
		local muzzAmb = Instance.new("ParticleEmitter")
		muzzAmb.Name = "MuzzleAmbient"
		muzzAmb.Color = ColorSequence.new(red)
		muzzAmb.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.05), NumberSequenceKeypoint.new(1, 0) })
		muzzAmb.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 1) })
		muzzAmb.Lifetime = NumberRange.new(0.1, 0.25)
		muzzAmb.Rate = 8
		muzzAmb.Speed = NumberRange.new(0.5, 2)
		muzzAmb.SpreadAngle = Vector2.new(30, 30)
		muzzAmb.LightEmission = 1
		muzzAmb.LightInfluence = 0
		muzzAmb.Parent = muzzleGlow

		-- Scope lens shimmer
		local lensShimmer = Instance.new("ParticleEmitter")
		lensShimmer.Name = "LensShimmer"
		lensShimmer.Color = ColorSequence.new({
			ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 80, 80)),
			ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 40, 40)),
		})
		lensShimmer.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.03), NumberSequenceKeypoint.new(1, 0) })
		lensShimmer.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.3), NumberSequenceKeypoint.new(1, 1) })
		lensShimmer.Lifetime = NumberRange.new(0.15, 0.4)
		lensShimmer.Rate = 6
		lensShimmer.Speed = NumberRange.new(0.2, 0.8)
		lensShimmer.SpreadAngle = Vector2.new(60, 60)
		lensShimmer.LightEmission = 1
		lensShimmer.LightInfluence = 0
		lensShimmer.Parent = scopeLens
	end

	-- Add a handle wrap for blades
	if visual.shape == "blade" then
		local handle = Instance.new("Part")
		handle.Name = "Handle"
		handle.Size = Vector3.new(0.25, 0.25, 0.6)
		handle.Color = Color3.fromRGB(50, 50, 50)
		handle.Material = Enum.Material.SmoothPlastic
		handle.CanCollide = false
		handle.Massless = true
		handle.Anchored = false
		handle.Parent = model

		local handleWeld = Instance.new("Motor6D")
		handleWeld.Name = "HandleWeld"
		handleWeld.Part0 = body
		handleWeld.Part1 = handle
		-- Place handle at the base of the blade
		handleWeld.C0 = CFrame.new(0, 0, visual.size.Z / 2 + 0.15)
		handleWeld.Parent = handle
	end

	model.PrimaryPart = body
	model.Parent = character
	currentWeaponModel = model

	-- Store the base grip CFrame for animation system reference
	originalGripC0 = visual.grip
	meleeComboIndex = 0

	-- Apply holding pose and play equip trick animation
	task.spawn(function()
		task.wait(0.05) -- brief delay for model to settle
		applyHoldingPose(character, weaponId)
		playEquipTrickAnimation(weaponId)
	end)
end

--------------------------------------------------------------------------------
-- Weapon Animation System — Full FPS viewmodel, Star Wars melee combos,
-- weapon bob/sway, muzzle flash, polished reload/equip/shoot animations
--------------------------------------------------------------------------------

-- Animation state
local isPlayingAnimation: boolean = false
local equipAnimPlaying: boolean = false
local originalGripC0: CFrame? = nil

-- Weapon bob/sway state (updated every frame)
local weaponBobTime: number = 0
local lastCameraLook: Vector3 = Vector3.zero
local swayOffset: CFrame = CFrame.identity

-- Melee combo state (Star Wars lightsaber system)
local meleeComboIndex: number = 0
local lastMeleeSwingTime: number = 0
local COMBO_RESET_TIME = 0.8 -- seconds before combo resets

-- First-person arm visibility connection
local fpConnection: RBXScriptConnection? = nil

-- Muzzle flash reference (reused per shot)
local muzzleFlashPart: Part? = nil

-- Weapon-specific animation configs
local WEAPON_ANIM_CONFIG = {
	-- Guns: held in front, two-handed
	PulseBlaster = {
		holdType = "rifle",
		recoilAngle = 8, recoilKick = 0.06, recoilDuration = 0.08,
		reloadDuration = 1.5, trickType = "spin",
		fpOffset = CFrame.new(0.35, -0.3, -0.6) * CFrame.Angles(math.rad(-2), math.rad(2), 0),
	},
	RailRifle = {
		holdType = "rifle",
		recoilAngle = 16, recoilKick = 0.1, recoilDuration = 0.14,
		reloadDuration = 2.5, trickType = "flip",
		fpOffset = CFrame.new(0.35, -0.32, -0.7) * CFrame.Angles(math.rad(-2), math.rad(2), 0),
	},
	MemorySMG = {
		holdType = "smg",
		recoilAngle = 3, recoilKick = 0.03, recoilDuration = 0.04,
		reloadDuration = 1.8, trickType = "spin",
		fpOffset = CFrame.new(0.3, -0.28, -0.5) * CFrame.Angles(math.rad(-2), math.rad(2), 0),
	},
	GlitchShotgun = {
		holdType = "shotgun",
		recoilAngle = 22, recoilKick = 0.15, recoilDuration = 0.16,
		reloadDuration = 2.8, trickType = "pump",
		fpOffset = CFrame.new(0.35, -0.3, -0.65) * CFrame.Angles(math.rad(-2), math.rad(2), 0),
	},
	ShockLauncher = {
		holdType = "heavy",
		recoilAngle = 28, recoilKick = 0.18, recoilDuration = 0.2,
		reloadDuration = 3.0, trickType = "shoulder",
		fpOffset = CFrame.new(0.4, -0.35, -0.7) * CFrame.Angles(math.rad(-3), math.rad(3), 0),
	},
	Sniper = {
		holdType = "rifle",
		recoilAngle = 20, recoilKick = 0.12, recoilDuration = 0.18,
		reloadDuration = 3.0, trickType = "bolt",
		fpOffset = CFrame.new(0.35, -0.3, -0.8) * CFrame.Angles(math.rad(-2), math.rad(2), 0),
	},
	-- Melee: Star Wars lightsaber combat
	EnergySword = {
		holdType = "sword", trickType = "ignite",
		fpOffset = CFrame.new(0.4, -0.25, -0.5) * CFrame.Angles(math.rad(-5), math.rad(5), 0),
	},
	PhaseKnife = {
		holdType = "knife", trickType = "reverse_grip",
		fpOffset = CFrame.new(0.3, -0.2, -0.4) * CFrame.Angles(math.rad(-3), math.rad(5), 0),
	},
}

--------------------------------------------------------------------------------
-- Star Wars Lightsaber Combo Definitions
-- Each combo step: { angles = CFrame rotation, offset = CFrame position shift,
--   windUp = anticipation CFrame, duration = swing time, returnDuration = recovery }
--------------------------------------------------------------------------------

local SABER_COMBOS = {
	EnergySword = {
		-- 1: BIG diagonal slash right-to-left (classic opening swing, ~100° arc)
		{
			windUp = CFrame.Angles(math.rad(55), math.rad(80), math.rad(35)) * CFrame.new(0.4, 0.3, 0.1),
			strike = CFrame.Angles(math.rad(-95), math.rad(-70), math.rad(-30)) * CFrame.new(-0.4, -0.2, -0.2),
			duration = 0.18, windUpTime = 0.08, returnTime = 0.14,
		},
		-- 2: BIG diagonal slash left-to-right (backhand, ~100° arc the other way)
		{
			windUp = CFrame.Angles(math.rad(50), math.rad(-85), math.rad(-40)) * CFrame.new(-0.4, 0.3, 0.1),
			strike = CFrame.Angles(math.rad(-90), math.rad(75), math.rad(35)) * CFrame.new(0.4, -0.2, -0.2),
			duration = 0.17, windUpTime = 0.07, returnTime = 0.13,
		},
		-- 3: MASSIVE overhead cleave (sword goes straight up, slams straight down ~110°)
		{
			windUp = CFrame.Angles(math.rad(110), math.rad(0), math.rad(5)) * CFrame.new(0, 0.5, 0.2),
			strike = CFrame.Angles(math.rad(-100), math.rad(0), math.rad(-5)) * CFrame.new(0, -0.4, -0.3),
			duration = 0.22, windUpTime = 0.1, returnTime = 0.16,
		},
		-- 4: WIDE horizontal sweep right-to-left (sweeping 120° arc at chest height)
		{
			windUp = CFrame.Angles(math.rad(-15), math.rad(95), math.rad(15)) * CFrame.new(0.5, 0.05, 0),
			strike = CFrame.Angles(math.rad(-20), math.rad(-100), math.rad(-10)) * CFrame.new(-0.5, -0.05, -0.15),
			duration = 0.16, windUpTime = 0.06, returnTime = 0.12,
		},
		-- 5: WIDE horizontal sweep left-to-right (mirror of combo 4)
		{
			windUp = CFrame.Angles(math.rad(-15), math.rad(-95), math.rad(-15)) * CFrame.new(-0.5, 0.05, 0),
			strike = CFrame.Angles(math.rad(-20), math.rad(100), math.rad(10)) * CFrame.new(0.5, -0.05, -0.15),
			duration = 0.16, windUpTime = 0.06, returnTime = 0.12,
		},
		-- 6: FORWARD THRUST / LUNGE (pull back, stab forward hard)
		{
			windUp = CFrame.Angles(math.rad(25), math.rad(0), math.rad(0)) * CFrame.new(0, 0.1, 0.5),
			strike = CFrame.Angles(math.rad(-8), math.rad(0), math.rad(0)) * CFrame.new(0, -0.05, -0.7),
			duration = 0.14, windUpTime = 0.08, returnTime = 0.18,
		},
		-- 7: UPPERCUT SLASH (low to high, ~100° rising arc)
		{
			windUp = CFrame.Angles(math.rad(-40), math.rad(20), math.rad(10)) * CFrame.new(0.15, -0.3, 0),
			strike = CFrame.Angles(math.rad(95), math.rad(-15), math.rad(-5)) * CFrame.new(-0.1, 0.4, -0.2),
			duration = 0.18, windUpTime = 0.07, returnTime = 0.14,
		},
		-- 8: SPINNING 360 SLASH (dramatic full rotation sweep)
		{
			windUp = CFrame.Angles(math.rad(30), math.rad(-50), math.rad(20)) * CFrame.new(-0.3, 0.2, 0),
			strike = CFrame.Angles(math.rad(-60), math.rad(220), math.rad(-15)) * CFrame.new(0.3, -0.1, -0.2),
			duration = 0.26, windUpTime = 0.08, returnTime = 0.18,
		},
	},
	PhaseKnife = {
		-- 1: FAST diagonal slash right (assassin opening, wide 90° arc)
		{
			windUp = CFrame.Angles(math.rad(40), math.rad(65), math.rad(30)) * CFrame.new(0.3, 0.2, 0.05),
			strike = CFrame.Angles(math.rad(-80), math.rad(-55), math.rad(-25)) * CFrame.new(-0.3, -0.15, -0.15),
			duration = 0.1, windUpTime = 0.04, returnTime = 0.08,
		},
		-- 2: FAST reverse slash left (backhand whip, wide 90° arc other way)
		{
			windUp = CFrame.Angles(math.rad(35), math.rad(-70), math.rad(-30)) * CFrame.new(-0.3, 0.2, 0.05),
			strike = CFrame.Angles(math.rad(-75), math.rad(60), math.rad(25)) * CFrame.new(0.3, -0.15, -0.15),
			duration = 0.09, windUpTime = 0.04, returnTime = 0.07,
		},
		-- 3: VICIOUS upward rip (gut-to-chin, ~95° rising arc)
		{
			windUp = CFrame.Angles(math.rad(-35), math.rad(15), math.rad(10)) * CFrame.new(0.1, -0.25, 0),
			strike = CFrame.Angles(math.rad(85), math.rad(-10), math.rad(-5)) * CFrame.new(-0.05, 0.35, -0.15),
			duration = 0.11, windUpTime = 0.05, returnTime = 0.09,
		},
		-- 4: LUNGING STAB (pull back hard, thrust forward deep)
		{
			windUp = CFrame.Angles(math.rad(15), math.rad(0), math.rad(0)) * CFrame.new(0, 0.05, 0.35),
			strike = CFrame.Angles(math.rad(-5), math.rad(0), math.rad(0)) * CFrame.new(0, -0.03, -0.55),
			duration = 0.08, windUpTime = 0.05, returnTime = 0.12,
		},
		-- 5: CROSS SLASH downward (X-pattern stroke, ~85° diagonal)
		{
			windUp = CFrame.Angles(math.rad(45), math.rad(-50), math.rad(-30)) * CFrame.new(-0.25, 0.25, 0),
			strike = CFrame.Angles(math.rad(-75), math.rad(55), math.rad(25)) * CFrame.new(0.25, -0.2, -0.12),
			duration = 0.09, windUpTime = 0.04, returnTime = 0.08,
		},
		-- 6: SPINNING BACKSTAB (quick 180 whirl slash)
		{
			windUp = CFrame.Angles(math.rad(20), math.rad(-40), math.rad(15)) * CFrame.new(-0.2, 0.15, 0),
			strike = CFrame.Angles(math.rad(-50), math.rad(180), math.rad(-10)) * CFrame.new(0.2, -0.1, -0.15),
			duration = 0.14, windUpTime = 0.05, returnTime = 0.1,
		},
		-- 7: WIDE horizontal sweep (low sweeping cut at waist level)
		{
			windUp = CFrame.Angles(math.rad(-20), math.rad(80), math.rad(10)) * CFrame.new(0.35, -0.1, 0),
			strike = CFrame.Angles(math.rad(-25), math.rad(-85), math.rad(-8)) * CFrame.new(-0.35, -0.05, -0.12),
			duration = 0.1, windUpTime = 0.04, returnTime = 0.09,
		},
	},
}

--------------------------------------------------------------------------------
-- First-Person Visibility System
-- Forces arms, hands, and weapon to be visible when camera is in first person.
-- Overrides Roblox's default behavior of hiding the character in FP.
--------------------------------------------------------------------------------

local FP_ARM_PARTS = { "RightUpperArm", "RightLowerArm", "RightHand", "LeftUpperArm", "LeftLowerArm", "LeftHand" }

local function setupFirstPersonVisibility()
	-- Disconnect previous if any
	if fpConnection then
		fpConnection:Disconnect()
		fpConnection = nil
	end

	fpConnection = RunService.RenderStepped:Connect(function()
		local character = localPlayer.Character
		if not character then return end

		-- Force arm parts visible in first person by overriding LocalTransparencyModifier
		for _, partName in FP_ARM_PARTS do
			local part = character:FindFirstChild(partName)
			if part and part:IsA("BasePart") then
				part.LocalTransparencyModifier = 0
			end
		end

		-- Also keep weapon model parts visible
		if currentWeaponModel then
			for _, part in currentWeaponModel:GetDescendants() do
				if part:IsA("BasePart") then
					part.LocalTransparencyModifier = 0
				end
			end
		end
	end)
end

--------------------------------------------------------------------------------
-- Weapon Bob & Sway System (Call of Duty style)
-- Runs every frame to create natural weapon movement
--------------------------------------------------------------------------------

local BOB_SPEED = 8       -- How fast the bob cycles
local BOB_AMOUNT_X = 0.015 -- Horizontal bob amplitude
local BOB_AMOUNT_Y = 0.012 -- Vertical bob amplitude
local SWAY_AMOUNT = 0.08   -- How much weapon lags behind camera turns
local SWAY_SMOOTH = 12     -- How fast sway catches up
local IDLE_SWAY_SPEED = 1.2 -- Subtle breathing sway when still
local IDLE_SWAY_AMOUNT = 0.003

-- Melee idle sway (lightsaber hum float)
local SABER_IDLE_SPEED = 0.8
local SABER_IDLE_AMOUNT_Y = 0.008
local SABER_IDLE_AMOUNT_ROT = 1.5 -- degrees

local function updateWeaponMotion(dt: number)
	if not currentWeaponModel then return end
	if equipAnimPlaying or isPlayingAnimation then return end

	local body = currentWeaponModel:FindFirstChild("Body")
	if not body then return end
	local gripWeld = body:FindFirstChild("GripWeld")
	if not gripWeld then return end

	if not originalGripC0 then
		originalGripC0 = gripWeld.C0
	end

	local character = localPlayer.Character
	if not character then return end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid then return end

	local currentLook = camera.CFrame.LookVector
	local config = WEAPON_ANIM_CONFIG[currentWeaponId]
	if not config then return end

	-- Calculate movement speed for bob intensity
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local moveSpeed = 0
	if rootPart then
		local vel = rootPart.AssemblyLinearVelocity
		moveSpeed = Vector3.new(vel.X, 0, vel.Z).Magnitude
	end

	local isMoving = moveSpeed > 1
	local isMelee = config.holdType == "sword" or config.holdType == "knife"

	-- Update bob timer
	if isMoving then
		weaponBobTime += dt * BOB_SPEED * math.clamp(moveSpeed / 16, 0.5, 2)
	else
		weaponBobTime += dt * IDLE_SWAY_SPEED
	end

	-- Calculate weapon bob (walking bounce)
	local bobX, bobY = 0, 0
	if isMoving then
		bobX = math.cos(weaponBobTime) * BOB_AMOUNT_X * math.clamp(moveSpeed / 16, 0.3, 1.5)
		bobY = math.abs(math.sin(weaponBobTime)) * BOB_AMOUNT_Y * math.clamp(moveSpeed / 16, 0.3, 1.5)
	else
		-- Subtle idle breathing sway
		bobX = math.sin(weaponBobTime * 0.7) * IDLE_SWAY_AMOUNT
		bobY = math.cos(weaponBobTime) * IDLE_SWAY_AMOUNT * 0.6
	end

	-- Calculate camera sway (weapon lags behind quick turns)
	local lookDelta = currentLook - lastCameraLook
	lastCameraLook = currentLook

	local swayX = -lookDelta.X * SWAY_AMOUNT
	local swayY = -lookDelta.Y * SWAY_AMOUNT
	swayX = math.clamp(swayX, -0.04, 0.04)
	swayY = math.clamp(swayY, -0.04, 0.04)

	-- Melee-specific: lightsaber idle float
	local meleeIdleRot = CFrame.identity
	if isMelee and not isMoving then
		local floatY = math.sin(weaponBobTime * SABER_IDLE_SPEED) * SABER_IDLE_AMOUNT_Y
		local floatRot = math.sin(weaponBobTime * SABER_IDLE_SPEED * 0.6) * math.rad(SABER_IDLE_AMOUNT_ROT)
		meleeIdleRot = CFrame.new(0, floatY, 0) * CFrame.Angles(floatRot, floatRot * 0.5, 0)
	end

	-- Combine all motion into final offset
	local motionOffset = CFrame.new(bobX + swayX, bobY + swayY, 0) * meleeIdleRot

	gripWeld.C0 = originalGripC0 * motionOffset
end

--------------------------------------------------------------------------------
-- Muzzle Flash System
--------------------------------------------------------------------------------

local function spawnMuzzleFlash()
	if not currentWeaponModel then return end

	-- Find the muzzle point (look for MuzzleGlow, MuzzleTip, or barrel tip)
	local muzzleParent = currentWeaponModel:FindFirstChild("MuzzleGlow", true)
		or currentWeaponModel:FindFirstChild("MuzzleDot", true)
		or currentWeaponModel:FindFirstChild("MuzzleTip", true)
		or currentWeaponModel:FindFirstChild("BarrelCore", true)

	if not muzzleParent or not muzzleParent:IsA("BasePart") then return end

	-- Create flash light burst
	local flash = Instance.new("PointLight")
	flash.Color = Color3.fromRGB(200, 240, 255)
	flash.Brightness = 8
	flash.Range = 12
	flash.Parent = muzzleParent

	-- Create flash part (bright sphere that appears for 1 frame)
	local flashPart = Instance.new("Part")
	flashPart.Name = "MuzzleFlash"
	flashPart.Size = Vector3.new(0.3, 0.3, 0.3)
	flashPart.Color = Color3.fromRGB(255, 255, 255)
	flashPart.Material = Enum.Material.Neon
	flashPart.Transparency = 0.3
	flashPart.Shape = Enum.PartType.Ball
	flashPart.CanCollide = false
	flashPart.Massless = true
	flashPart.Anchored = false
	flashPart.Parent = currentWeaponModel

	local flashWeld = Instance.new("Weld")
	flashWeld.Part0 = muzzleParent
	flashWeld.Part1 = flashPart
	flashWeld.C0 = CFrame.new(0, 0, -0.15)
	flashWeld.Parent = flashPart

	-- Quick burst particle
	local burstEmitter = Instance.new("ParticleEmitter")
	burstEmitter.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 250, 220)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(200, 230, 255)),
	})
	burstEmitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 0) })
	burstEmitter.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	burstEmitter.Lifetime = NumberRange.new(0.04, 0.12)
	burstEmitter.Rate = 0 -- emit via burst
	burstEmitter.Speed = NumberRange.new(5, 15)
	burstEmitter.SpreadAngle = Vector2.new(25, 25)
	burstEmitter.LightEmission = 1
	burstEmitter.LightInfluence = 0
	burstEmitter.Parent = muzzleParent
	burstEmitter:Emit(8)

	-- Fade out and clean up
	task.delay(0.06, function()
		flash.Brightness = 3
		flashPart.Transparency = 0.7
	end)
	task.delay(0.1, function()
		flash:Destroy()
		flashPart:Destroy()
		burstEmitter:Destroy()
	end)
end

--------------------------------------------------------------------------------
-- Bullet Tracer System — visible neon energy bolts from muzzle to target
--------------------------------------------------------------------------------

local TRACER_COLORS = {
	PulseBlaster  = Color3.fromRGB(0, 200, 255),      -- cyan
	RailRifle     = Color3.fromRGB(255, 120, 40),      -- orange-red
	MemorySMG     = Color3.fromRGB(60, 140, 255),      -- blue
	GlitchShotgun = Color3.fromRGB(180, 60, 255),      -- purple
	ShockLauncher = Color3.fromRGB(255, 240, 100),      -- yellow-white
	Sniper        = Color3.fromRGB(255, 40, 40),        -- bright red
}

local TRACER_DEFAULT_COLOR = Color3.fromRGB(0, 200, 255)

local function spawnSingleTracer(muzzlePos: Vector3, targetPos: Vector3, color: Color3, thickness: number)
	local distance = (targetPos - muzzlePos).Magnitude
	if distance < 1 then return end

	local midpoint = muzzlePos:Lerp(targetPos, 0.5)

	-- Create the tracer bolt
	local bolt = Instance.new("Part")
	bolt.Name = "BulletTracer"
	bolt.Anchored = true
	bolt.CanCollide = false
	bolt.CanQuery = false
	bolt.CanTouch = false
	bolt.Material = Enum.Material.Neon
	bolt.Color = color
	bolt.Size = Vector3.new(thickness, thickness, distance)
	bolt.CFrame = CFrame.lookAt(midpoint, targetPos)
	bolt.Transparency = 0

	-- Glow light
	local glow = Instance.new("PointLight")
	glow.Color = color
	glow.Brightness = 3
	glow.Range = 6
	glow.Parent = bolt

	-- Particle trail for extra flair
	local trail = Instance.new("ParticleEmitter")
	trail.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, color), ColorSequenceKeypoint.new(1, Color3.new(1, 1, 1)) })
	trail.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, thickness * 2), NumberSequenceKeypoint.new(1, 0) })
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = NumberRange.new(0.05, 0.12)
	trail.Rate = 200
	trail.Speed = NumberRange.new(0, 0)
	trail.LightEmission = 1
	trail.LightInfluence = 0
	trail.Parent = bolt

	bolt.Parent = Workspace

	-- Tween transparency to fade out then destroy
	local fadeTween = TweenService:Create(bolt,
		TweenInfo.new(0.15, Enum.EasingStyle.Linear),
		{ Transparency = 1 })
	fadeTween:Play()
	fadeTween.Completed:Connect(function()
		bolt:Destroy()
	end)
end

local function spawnBulletTracer()
	if not currentWeaponModel then return end

	-- Find the muzzle point (same logic as spawnMuzzleFlash)
	local muzzlePart = currentWeaponModel:FindFirstChild("MuzzleGlow", true)
		or currentWeaponModel:FindFirstChild("MuzzleDot", true)
		or currentWeaponModel:FindFirstChild("MuzzleTip", true)
		or currentWeaponModel:FindFirstChild("BarrelCore", true)

	if not muzzlePart or not muzzlePart:IsA("BasePart") then return end

	local muzzlePos = muzzlePart.Position

	-- Get weapon data for range
	local wData = WeaponData[currentWeaponId]
	local maxRange = (wData and wData.range) or 120

	-- Raycast from camera in look direction to find target point
	local camCF = camera.CFrame
	local rayOrigin = camCF.Position
	local rayDir = camCF.LookVector * maxRange

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	local character = localPlayer.Character
	local filterList = { currentWeaponModel }
	if character then table.insert(filterList, character) end
	rayParams.FilterDescendantsInstances = filterList

	local result = Workspace:Raycast(rayOrigin, rayDir, rayParams)
	local targetPos = if result then result.Position else (rayOrigin + rayDir)

	-- Determine tracer color and thickness
	local color = TRACER_COLORS[currentWeaponId] or TRACER_DEFAULT_COLOR
	local thickness = if currentWeaponId == "Sniper" then 0.12 else 0.08

	-- GlitchShotgun fires 6 pellets with spread
	if currentWeaponId == "GlitchShotgun" then
		local PELLET_COUNT = 6
		local SPREAD_ANGLE = 5 -- degrees
		for _ = 1, PELLET_COUNT do
			local spreadRad = math.rad(SPREAD_ANGLE)
			local offsetDir = CFrame.new(Vector3.zero, (targetPos - muzzlePos).Unit)
				* CFrame.Angles(
					(math.random() - 0.5) * 2 * spreadRad,
					(math.random() - 0.5) * 2 * spreadRad,
					0
				)
			local pelletTarget = muzzlePos + offsetDir.LookVector * (targetPos - muzzlePos).Magnitude
			spawnSingleTracer(muzzlePos, pelletTarget, color, thickness)
		end
	else
		spawnSingleTracer(muzzlePos, targetPos, color, thickness)
	end
end

--------------------------------------------------------------------------------
-- Holding Pose — positions character arms to hold weapon in front
--------------------------------------------------------------------------------

local function applyHoldingPose(character: Model, weaponId: string)
	if not character then return end

	local rightShoulder = character:FindFirstChild("RightUpperArm") and character.RightUpperArm:FindFirstChild("RightShoulder")
	local leftShoulder = character:FindFirstChild("LeftUpperArm") and character.LeftUpperArm:FindFirstChild("LeftShoulder")

	if not rightShoulder or not leftShoulder then return end

	local config = WEAPON_ANIM_CONFIG[weaponId]
	if not config then return end

	local tweenInfo = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

	if config.holdType == "rifle" or config.holdType == "smg" or config.holdType == "shotgun" or config.holdType == "heavy" then
		local rightTarget = rightShoulder.C0 * CFrame.Angles(math.rad(-75), math.rad(12), 0)
		local leftTarget = leftShoulder.C0 * CFrame.Angles(math.rad(-70), math.rad(-18), 0)
		TweenService:Create(rightShoulder, tweenInfo, { C0 = rightTarget }):Play()
		TweenService:Create(leftShoulder, tweenInfo, { C0 = leftTarget }):Play()
	elseif config.holdType == "sword" then
		-- Two-handed lightsaber guard stance: both arms forward gripping the hilt,
		-- knees bent, leaning slightly forward — ready to charge
		local rightTarget = rightShoulder.C0 * CFrame.Angles(math.rad(-65), math.rad(15), math.rad(8))
		local leftTarget = leftShoulder.C0 * CFrame.Angles(math.rad(-60), math.rad(-20), math.rad(-8))
		TweenService:Create(rightShoulder, tweenInfo, { C0 = rightTarget }):Play()
		TweenService:Create(leftShoulder, tweenInfo, { C0 = leftTarget }):Play()

		-- Bend knees: lower hip height slightly for combat-ready crouch
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			TweenService:Create(humanoid, tweenInfo, { HipHeight = humanoid.HipHeight - 0.4 }):Play()
		end
	elseif config.holdType == "knife" then
		-- Two-handed knife stance: both hands forward in aggressive low guard,
		-- knees bent, body coiled ready to spring
		local rightTarget = rightShoulder.C0 * CFrame.Angles(math.rad(-55), math.rad(12), math.rad(12))
		local leftTarget = leftShoulder.C0 * CFrame.Angles(math.rad(-50), math.rad(-15), math.rad(-10))
		TweenService:Create(rightShoulder, tweenInfo, { C0 = rightTarget }):Play()
		TweenService:Create(leftShoulder, tweenInfo, { C0 = leftTarget }):Play()

		-- Bend knees for coiled assassin stance
		local humanoid = character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			TweenService:Create(humanoid, tweenInfo, { HipHeight = humanoid.HipHeight - 0.35 }):Play()
		end
	end
end

--------------------------------------------------------------------------------
-- Melee Combat UI — Crosshair, Combo Counter, Swing Indicator, Hit Feedback
--------------------------------------------------------------------------------

local function isEnemyInMeleeRange(weaponId: string): boolean
	local range = MELEE_RANGE_DETECT[weaponId] or 8
	local character = localPlayer.Character
	if not character then return false end
	local rootPart = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not rootPart then return false end
	local origin = rootPart.Position
	for _, otherPlayer in Players:GetPlayers() do
		if otherPlayer ~= localPlayer and otherPlayer.Character then
			local otherRoot = otherPlayer.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if otherRoot then
				if (otherRoot.Position - origin).Magnitude <= range then
					return true
				end
			end
		end
	end
	return false
end

local function createMeleeUI(weaponId: string)
	if meleeUIScreenGui then
		meleeUIScreenGui:Destroy()
		meleeUIScreenGui = nil
	end
	if meleeRangePulseConn then
		meleeRangePulseConn:Disconnect()
		meleeRangePulseConn = nil
	end

	local themeColor = MELEE_THEME_COLORS[weaponId] or Color3.fromRGB(0, 200, 255)

	local gui = Instance.new("ScreenGui")
	gui.Name = "MeleeCombatUI"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 15
	gui.Parent = localPlayer:WaitForChild("PlayerGui")
	meleeUIScreenGui = gui

	-- 1. Melee Crosshair (X reticle with four thin lines)
	local crosshairContainer = Instance.new("Frame")
	crosshairContainer.Name = "MeleeCrosshair"
	crosshairContainer.Size = UDim2.fromOffset(60, 60)
	crosshairContainer.Position = UDim2.fromScale(0.5, 0.5)
	crosshairContainer.AnchorPoint = Vector2.new(0.5, 0.5)
	crosshairContainer.BackgroundTransparency = 1
	crosshairContainer.Parent = gui
	meleeCrosshairFrame = crosshairContainer

	local LINE_LENGTH = 22
	local LINE_THICKNESS = 2
	local GAP = 6
	local lineAngles = { 45, 135, 225, 315 }
	for _, angle in lineAngles do
		local rad = math.rad(angle)
		local dirX = math.cos(rad)
		local dirY = math.sin(rad)
		local line = Instance.new("Frame")
		line.Name = "CrossLine_" .. tostring(angle)
		line.Size = UDim2.fromOffset(LINE_LENGTH, LINE_THICKNESS)
		line.AnchorPoint = Vector2.new(0, 0.5)
		line.Position = UDim2.fromOffset(30 + dirX * GAP, 30 + dirY * GAP)
		line.Rotation = angle
		line.BackgroundColor3 = themeColor
		line.BackgroundTransparency = 0.2
		line.BorderSizePixel = 0
		line.Parent = crosshairContainer
		local stroke = Instance.new("UIStroke")
		stroke.Color = themeColor
		stroke.Thickness = 1
		stroke.Transparency = 0.5
		stroke.Parent = line
		local glow = Instance.new("Frame")
		glow.Name = "Glow"
		glow.Size = UDim2.new(1, 4, 1, 4)
		glow.Position = UDim2.fromOffset(-2, -2)
		glow.BackgroundColor3 = themeColor
		glow.BackgroundTransparency = 0.85
		glow.BorderSizePixel = 0
		glow.Parent = line
	end

	local centerDot = Instance.new("Frame")
	centerDot.Name = "CenterDot"
	centerDot.Size = UDim2.fromOffset(4, 4)
	centerDot.Position = UDim2.fromScale(0.5, 0.5)
	centerDot.AnchorPoint = Vector2.new(0.5, 0.5)
	centerDot.BackgroundColor3 = themeColor
	centerDot.BackgroundTransparency = 0.3
	centerDot.BorderSizePixel = 0
	centerDot.Parent = crosshairContainer
	local dotCorner = Instance.new("UICorner")
	dotCorner.CornerRadius = UDim.new(1, 0)
	dotCorner.Parent = centerDot

	meleeRangePulseConn = RunService.RenderStepped:Connect(function()
		if not crosshairContainer or not crosshairContainer.Parent then return end
		local inRange = isEnemyInMeleeRange(weaponId)
		local targetTransp = if inRange then 0 else 0.2
		local glowTransp = if inRange then 0.5 else 0.85
		local scale = if inRange then 1.15 else 1.0
		for _, child in crosshairContainer:GetChildren() do
			if child:IsA("Frame") and child.Name ~= "CenterDot" then
				child.BackgroundTransparency = targetTransp
				local glowFrame = child:FindFirstChild("Glow")
				if glowFrame then
					glowFrame.BackgroundTransparency = glowTransp
				end
			end
		end
		crosshairContainer.Size = UDim2.fromOffset(math.floor(60 * scale), math.floor(60 * scale))
	end)

	-- 2. Combo Counter Display (bottom-right)
	local comboFrame = Instance.new("Frame")
	comboFrame.Name = "ComboFrame"
	comboFrame.Size = UDim2.fromOffset(200, 90)
	comboFrame.Position = UDim2.new(1, -30, 1, -140)
	comboFrame.AnchorPoint = Vector2.new(1, 1)
	comboFrame.BackgroundTransparency = 1
	comboFrame.Parent = gui

	local comboNum = Instance.new("TextLabel")
	comboNum.Name = "ComboNumber"
	comboNum.Size = UDim2.new(1, 0, 0, 55)
	comboNum.Position = UDim2.fromOffset(0, 0)
	comboNum.BackgroundTransparency = 1
	comboNum.Font = Enum.Font.GothamBold
	comboNum.TextColor3 = themeColor
	comboNum.TextSize = 48
	comboNum.TextStrokeColor3 = Color3.new(0, 0, 0)
	comboNum.TextStrokeTransparency = 0.3
	comboNum.TextXAlignment = Enum.TextXAlignment.Right
	comboNum.TextTransparency = 1
	comboNum.Text = ""
	comboNum.Parent = comboFrame
	comboCounterLabel = comboNum
	local comboStroke = Instance.new("UIStroke")
	comboStroke.Color = themeColor
	comboStroke.Thickness = 1.5
	comboStroke.Transparency = 0.4
	comboStroke.Parent = comboNum

	local comboName = Instance.new("TextLabel")
	comboName.Name = "ComboName"
	comboName.Size = UDim2.new(1, 0, 0, 25)
	comboName.Position = UDim2.fromOffset(0, 55)
	comboName.BackgroundTransparency = 1
	comboName.Font = Enum.Font.GothamMedium
	comboName.TextColor3 = themeColor
	comboName.TextSize = 18
	comboName.TextStrokeColor3 = Color3.new(0, 0, 0)
	comboName.TextStrokeTransparency = 0.5
	comboName.TextXAlignment = Enum.TextXAlignment.Right
	comboName.TextTransparency = 1
	comboName.Text = ""
	comboName.Parent = comboFrame
	comboNameLabel = comboName
	local nameStroke = Instance.new("UIStroke")
	nameStroke.Color = themeColor
	nameStroke.Thickness = 1
	nameStroke.Transparency = 0.6
	nameStroke.Parent = comboName

	-- 3. Swing Direction Indicator (center of screen)
	local swingFrame = Instance.new("Frame")
	swingFrame.Name = "SwingDirection"
	swingFrame.Size = UDim2.fromOffset(120, 120)
	swingFrame.Position = UDim2.fromScale(0.5, 0.5)
	swingFrame.AnchorPoint = Vector2.new(0.5, 0.5)
	swingFrame.BackgroundTransparency = 1
	swingFrame.Visible = false
	swingFrame.Parent = gui
	swingDirectionFrame = swingFrame

	-- 4. Hit Feedback (screen edge flash + backstab text)
	local hitFlash = Instance.new("Frame")
	hitFlash.Name = "HitFlash"
	hitFlash.Size = UDim2.fromScale(1, 1)
	hitFlash.Position = UDim2.fromScale(0, 0)
	hitFlash.BackgroundColor3 = themeColor
	hitFlash.BackgroundTransparency = 1
	hitFlash.BorderSizePixel = 0
	hitFlash.ZIndex = 20
	hitFlash.Parent = gui
	hitFeedbackFrame = hitFlash
	local gradient = Instance.new("UIGradient")
	gradient.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0),
		NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.7, 1),
		NumberSequenceKeypoint.new(1, 0),
	})
	gradient.Parent = hitFlash

	local bsLabel = Instance.new("TextLabel")
	bsLabel.Name = "BackstabText"
	bsLabel.Size = UDim2.fromOffset(400, 60)
	bsLabel.Position = UDim2.fromScale(0.5, 0.35)
	bsLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	bsLabel.BackgroundTransparency = 1
	bsLabel.Font = Enum.Font.GothamBold
	bsLabel.TextColor3 = Color3.fromRGB(255, 50, 50)
	bsLabel.TextSize = 42
	bsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
	bsLabel.TextStrokeTransparency = 0.2
	bsLabel.TextTransparency = 1
	bsLabel.Text = "BACKSTAB!"
	bsLabel.ZIndex = 21
	bsLabel.Parent = gui
	backstabLabel = bsLabel
	local bsStroke = Instance.new("UIStroke")
	bsStroke.Color = Color3.fromRGB(255, 50, 50)
	bsStroke.Thickness = 2
	bsStroke.Transparency = 0.3
	bsStroke.Parent = bsLabel
end

local function destroyMeleeUI()
	if meleeRangePulseConn then
		meleeRangePulseConn:Disconnect()
		meleeRangePulseConn = nil
	end
	if comboFadeThread then
		task.cancel(comboFadeThread)
		comboFadeThread = nil
	end
	if meleeUIScreenGui then
		meleeUIScreenGui:Destroy()
		meleeUIScreenGui = nil
	end
	meleeCrosshairFrame = nil
	comboCounterLabel = nil
	comboNameLabel = nil
	swingDirectionFrame = nil
	hitFeedbackFrame = nil
	backstabLabel = nil
end

local function updateComboUI(comboIndex: number, weaponId: string)
	if not comboCounterLabel or not comboNameLabel then return end
	local themeColor = MELEE_THEME_COLORS[weaponId] or Color3.fromRGB(0, 200, 255)
	local names = MELEE_COMBO_NAMES[weaponId]
	local comboName = if names and names[comboIndex] then names[comboIndex] else "STRIKE"
	if comboFadeThread then
		task.cancel(comboFadeThread)
		comboFadeThread = nil
	end
	comboCounterLabel.Text = tostring(comboIndex)
	comboCounterLabel.TextTransparency = 0
	comboCounterLabel.TextColor3 = themeColor
	comboNameLabel.Text = comboName
	comboNameLabel.TextTransparency = 0
	comboNameLabel.TextColor3 = themeColor
	comboCounterLabel.TextSize = 64
	TweenService:Create(comboCounterLabel,
		TweenInfo.new(0.15, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ TextSize = 48 }):Play()
	comboNameLabel.TextSize = 24
	TweenService:Create(comboNameLabel,
		TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ TextSize = 18 }):Play()
	comboFadeThread = task.delay(COMBO_RESET_TIME, function()
		if not comboCounterLabel or not comboNameLabel then return end
		TweenService:Create(comboCounterLabel,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }):Play()
		TweenService:Create(comboNameLabel,
			TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ TextTransparency = 1 }):Play()
		comboFadeThread = nil
	end)
end

local function showSwingDirection(comboIndex: number, weaponId: string)
	if not swingDirectionFrame then return end
	local themeColor = MELEE_THEME_COLORS[weaponId] or Color3.fromRGB(0, 200, 255)
	local directions = MELEE_SWING_DIRECTIONS[weaponId]
	local dir = if directions and directions[comboIndex] then directions[comboIndex] else "diagRight"
	for _, child in swingDirectionFrame:GetChildren() do
		child:Destroy()
	end
	local lineConfigs = {}
	if dir == "diagRight" then
		lineConfigs = { { 0, 0, 100, -45 } }
	elseif dir == "diagLeft" then
		lineConfigs = { { 0, 0, 100, 45 } }
	elseif dir == "vertical" then
		lineConfigs = { { 0, 0, 100, 90 } }
	elseif dir == "horizontal" then
		lineConfigs = { { 0, 0, 100, 0 } }
	elseif dir == "thrust" then
		lineConfigs = { { 0, 0, 50, 0 }, { 15, -8, 30, -35 }, { 15, 8, 30, 35 } }
	end
	for _, cfg in lineConfigs do
		local offsetX, offsetY, length, rot = cfg[1], cfg[2], cfg[3], cfg[4]
		local slashLine = Instance.new("Frame")
		slashLine.Name = "SlashLine"
		slashLine.Size = UDim2.fromOffset(length, 3)
		slashLine.Position = UDim2.fromOffset(60 + offsetX, 60 + offsetY)
		slashLine.AnchorPoint = Vector2.new(0.5, 0.5)
		slashLine.Rotation = rot
		slashLine.BackgroundColor3 = themeColor
		slashLine.BackgroundTransparency = 0.1
		slashLine.BorderSizePixel = 0
		slashLine.Parent = swingDirectionFrame
		local lineStroke = Instance.new("UIStroke")
		lineStroke.Color = themeColor
		lineStroke.Thickness = 1
		lineStroke.Transparency = 0.3
		lineStroke.Parent = slashLine
	end
	swingDirectionFrame.Visible = true
	task.delay(0.15, function()
		if not swingDirectionFrame or not swingDirectionFrame.Parent then return end
		for _, child in swingDirectionFrame:GetChildren() do
			if child:IsA("Frame") then
				TweenService:Create(child,
					TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
					{ BackgroundTransparency = 1 }):Play()
			end
		end
		task.delay(0.15, function()
			if swingDirectionFrame and swingDirectionFrame.Parent then
				swingDirectionFrame.Visible = false
				for _, child in swingDirectionFrame:GetChildren() do
					child:Destroy()
				end
			end
		end)
	end)
end

local function showMeleeHitFeedback(isBackstab: boolean, weaponId: string)
	if not hitFeedbackFrame then return end
	local themeColor = MELEE_THEME_COLORS[weaponId] or Color3.fromRGB(0, 200, 255)
	hitFeedbackFrame.BackgroundColor3 = themeColor
	hitFeedbackFrame.BackgroundTransparency = 0.6
	TweenService:Create(hitFeedbackFrame,
		TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
		{ BackgroundTransparency = 1 }):Play()
	if isBackstab and backstabLabel then
		backstabLabel.TextTransparency = 0
		backstabLabel.TextSize = 56
		TweenService:Create(backstabLabel,
			TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ TextSize = 42 }):Play()
		task.delay(0.8, function()
			if not backstabLabel or not backstabLabel.Parent then return end
			TweenService:Create(backstabLabel,
				TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ TextTransparency = 1 }):Play()
		end)
	end
end

--------------------------------------------------------------------------------
-- Shoot Animation — Lightsaber combos for melee, recoil for guns
--------------------------------------------------------------------------------

local function playShootAnimation(weaponId: string)
	if isPlayingAnimation then return end
	if not currentWeaponModel then return end

	local config = WEAPON_ANIM_CONFIG[weaponId]
	if not config then return end

	local body = currentWeaponModel:FindFirstChild("Body")
	if not body then return end
	local gripWeld = body:FindFirstChild("GripWeld")
	if not gripWeld then return end

	if not originalGripC0 then
		originalGripC0 = gripWeld.C0
	end
	local baseC0 = originalGripC0

	local isMelee = config.holdType == "sword" or config.holdType == "knife"

	if isMelee then
		--------------------------------------------------------------------
		-- STAR WARS LIGHTSABER COMBO SYSTEM
		--------------------------------------------------------------------
		local combos = SABER_COMBOS[weaponId]
		if not combos then return end

		-- Advance combo or reset if too long since last swing
		local now = tick()
		if (now - lastMeleeSwingTime) > COMBO_RESET_TIME then
			meleeComboIndex = 0
		end
		meleeComboIndex = (meleeComboIndex % #combos) + 1
		lastMeleeSwingTime = now

		local combo = combos[meleeComboIndex]
		isPlayingAnimation = true

		-- Update melee UI: combo counter + swing direction indicator
		updateComboUI(meleeComboIndex, weaponId)
		showSwingDirection(meleeComboIndex, weaponId)

		-- Phase 1: WIND-UP (anticipation — pull back before the strike)
		local windUpTarget = baseC0 * combo.windUp
		local windUpTween = TweenService:Create(gripWeld,
			TweenInfo.new(combo.windUpTime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = windUpTarget })
		windUpTween:Play()

		-- Phase 2: STRIKE (fast, powerful slash with follow-through)
		task.delay(combo.windUpTime, function()
			if not gripWeld or not gripWeld.Parent then
				isPlayingAnimation = false
				return
			end
			local strikeTarget = baseC0 * combo.strike
			local strikeTween = TweenService:Create(gripWeld,
				TweenInfo.new(combo.duration, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ C0 = strikeTarget })
			strikeTween:Play()

			-- Phase 3: RECOVERY (smooth return to guard position)
			task.delay(combo.duration, function()
				if not gripWeld or not gripWeld.Parent then
					isPlayingAnimation = false
					return
				end
				local returnTween = TweenService:Create(gripWeld,
					TweenInfo.new(combo.returnTime, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
					{ C0 = baseC0 })
				returnTween:Play()
				task.delay(combo.returnTime, function()
					isPlayingAnimation = false
				end)
			end)
		end)
	else
		--------------------------------------------------------------------
		-- GUN RECOIL + MUZZLE FLASH
		--------------------------------------------------------------------
		isPlayingAnimation = true
		local recoilAngle = config.recoilAngle or 10
		local recoilKick = config.recoilKick or 0.08
		local duration = config.recoilDuration or 0.1

		-- Muzzle flash + bullet tracer
		spawnMuzzleFlash()
		spawnBulletTracer()

		-- Recoil: kick up and back
		local recoilTarget = baseC0
			* CFrame.Angles(math.rad(recoilAngle), math.rad(math.random(-2, 2)), 0)
			* CFrame.new(0, 0, recoilKick)

		local recoilTween = TweenService:Create(gripWeld,
			TweenInfo.new(duration * 0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = recoilTarget })
		recoilTween:Play()

		-- Return smoothly
		task.delay(duration * 0.6, function()
			if not gripWeld or not gripWeld.Parent then
				isPlayingAnimation = false
				return
			end
			local returnTween = TweenService:Create(gripWeld,
				TweenInfo.new(duration * 1.8, Enum.EasingStyle.Sine, Enum.EasingDirection.Out),
				{ C0 = baseC0 })
			returnTween:Play()
			task.delay(duration * 1.8, function()
				isPlayingAnimation = false
			end)
		end)
	end
end

--------------------------------------------------------------------------------
-- Reload Animation — weapon-type specific, multi-phase
--------------------------------------------------------------------------------

local function playReloadAnimation(weaponId: string)
	if not currentWeaponModel then return end

	local config = WEAPON_ANIM_CONFIG[weaponId]
	if not config then return end

	local body = currentWeaponModel:FindFirstChild("Body")
	if not body then return end
	local gripWeld = body:FindFirstChild("GripWeld")
	if not gripWeld then return end

	if not originalGripC0 then
		originalGripC0 = gripWeld.C0
	end
	local baseC0 = originalGripC0
	local reloadTime = config.reloadDuration or 2.0

	if config.holdType == "shotgun" then
		-- Shotgun: pump-action reload — tilt, chamber shells, pump, ready
		-- Phase 1: tilt gun to expose loading port
		local tiltSide = baseC0 * CFrame.Angles(math.rad(20), math.rad(-35), math.rad(15)) * CFrame.new(0, -0.1, 0)
		TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = tiltSide }):Play()

		-- Phase 2: chamber individual shells (slight jabs)
		local shellCount = 3
		for i = 1, shellCount do
			task.delay(reloadTime * (0.2 + i * 0.12), function()
				if not gripWeld or not gripWeld.Parent then return end
				local jabIn = tiltSide * CFrame.new(0, 0.03, -0.04)
				TweenService:Create(gripWeld, TweenInfo.new(0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = jabIn }):Play()
				task.delay(0.06, function()
					if not gripWeld or not gripWeld.Parent then return end
					TweenService:Create(gripWeld, TweenInfo.new(0.05, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = tiltSide }):Play()
				end)
			end)
		end

		-- Phase 3: pump action
		task.delay(reloadTime * 0.7, function()
			if not gripWeld or not gripWeld.Parent then return end
			local pumpBack = baseC0 * CFrame.new(0, 0, 0.12) * CFrame.Angles(math.rad(5), 0, 0)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = pumpBack }):Play()
			task.delay(reloadTime * 0.1, function()
				if not gripWeld or not gripWeld.Parent then return end
				local pumpForward = baseC0 * CFrame.new(0, 0, -0.04)
				TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.06, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = pumpForward }):Play()
			end)
		end)

		-- Phase 4: return to ready
		task.delay(reloadTime * 0.9, function()
			if not gripWeld or not gripWeld.Parent then return end
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
		end)

	elseif config.holdType == "heavy" then
		-- Heavy weapon: open chamber, swap cell, slam shut
		local openChamber = baseC0 * CFrame.Angles(math.rad(35), math.rad(15), 0) * CFrame.new(0, -0.2, 0)
		TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = openChamber }):Play()

		task.delay(reloadTime * 0.35, function()
			if not gripWeld or not gripWeld.Parent then return end
			local cellOut = openChamber * CFrame.new(0, -0.15, 0)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.1, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = cellOut }):Play()
		end)

		task.delay(reloadTime * 0.55, function()
			if not gripWeld or not gripWeld.Parent then return end
			local cellIn = openChamber * CFrame.new(0, 0.02, 0)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = cellIn }):Play()
		end)

		task.delay(reloadTime * 0.75, function()
			if not gripWeld or not gripWeld.Parent then return end
			-- Slam shut
			local slamShut = baseC0 * CFrame.Angles(math.rad(-3), 0, 0) * CFrame.new(0, 0.02, -0.03)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.08, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = slamShut }):Play()
		end)

		task.delay(reloadTime * 0.88, function()
			if not gripWeld or not gripWeld.Parent then return end
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
		end)

	else
		-- Standard magazine reload: eject mag, insert new, chamber
		-- Phase 1: tilt weapon and drop magazine
		local tiltTarget = baseC0 * CFrame.Angles(math.rad(25), math.rad(-18), math.rad(5)) * CFrame.new(0, -0.12, 0)
		TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = tiltTarget }):Play()

		-- Phase 2: magazine out (slight pull down)
		task.delay(reloadTime * 0.28, function()
			if not gripWeld or not gripWeld.Parent then return end
			local magOut = tiltTarget * CFrame.new(0, -0.06, 0)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.08, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = magOut }):Play()
		end)

		-- Phase 3: new magazine in (push up with snap)
		task.delay(reloadTime * 0.5, function()
			if not gripWeld or not gripWeld.Parent then return end
			local magIn = baseC0 * CFrame.Angles(math.rad(12), math.rad(-5), 0) * CFrame.new(0, -0.03, 0.04)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = magIn }):Play()
		end)

		-- Phase 4: chamber round (quick pull-release on bolt/slide)
		task.delay(reloadTime * 0.72, function()
			if not gripWeld or not gripWeld.Parent then return end
			local boltBack = baseC0 * CFrame.new(0, 0, 0.06) * CFrame.Angles(math.rad(4), 0, 0)
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.06, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = boltBack }):Play()
			task.delay(reloadTime * 0.08, function()
				if not gripWeld or not gripWeld.Parent then return end
				local boltFwd = baseC0 * CFrame.new(0, 0, -0.02)
				TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.05, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = boltFwd }):Play()
			end)
		end)

		-- Phase 5: snap to ready
		task.delay(reloadTime * 0.88, function()
			if not gripWeld or not gripWeld.Parent then return end
			TweenService:Create(gripWeld, TweenInfo.new(reloadTime * 0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
		end)
	end
end

--------------------------------------------------------------------------------
-- Equip Trick Animation — unique per weapon, plays on first draw
--------------------------------------------------------------------------------

local function playEquipTrickAnimation(weaponId: string)
	if not currentWeaponModel then return end

	local config = WEAPON_ANIM_CONFIG[weaponId]
	if not config then return end

	local body = currentWeaponModel:FindFirstChild("Body")
	if not body then return end
	local gripWeld = body:FindFirstChild("GripWeld")
	if not gripWeld then return end

	equipAnimPlaying = true

	if not originalGripC0 then
		originalGripC0 = gripWeld.C0
	end
	local baseC0 = originalGripC0
	local dur = 0.55

	if config.trickType == "ignite" then
		-- LIGHTSABER IGNITE: start low and dark, sweep up dramatically
		-- Begin held low at side
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(80), math.rad(-20), 0) * CFrame.new(0, -0.3, 0.2)

		-- Phase 1: bring up to eye level with dramatic arc
		local raiseTarget = baseC0 * CFrame.Angles(math.rad(-10), math.rad(15), math.rad(5)) * CFrame.new(0.05, 0.1, -0.1)
		local t1 = TweenService:Create(gripWeld,
			TweenInfo.new(dur * 0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ C0 = raiseTarget })
		t1:Play()

		-- Phase 2: slight flourish twist then settle into guard
		task.delay(dur * 0.55, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			local flourish = baseC0 * CFrame.Angles(math.rad(5), math.rad(-10), math.rad(-3))
			TweenService:Create(gripWeld,
				TweenInfo.new(dur * 0.2, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut),
				{ C0 = flourish }):Play()
		end)

		task.delay(dur * 0.8, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld,
				TweenInfo.new(dur * 0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ C0 = baseC0 }):Play()
			task.delay(dur * 0.2, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "reverse_grip" then
		-- KNIFE: flip to reverse grip, spin, catch
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(60), 0, 0) * CFrame.new(0, -0.15, 0.1)

		-- Quick flip
		local flipTarget = baseC0 * CFrame.Angles(math.rad(-180), math.rad(90), 0) * CFrame.new(0.05, 0.1, 0)
		TweenService:Create(gripWeld,
			TweenInfo.new(dur * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ C0 = flipTarget }):Play()

		task.delay(dur * 0.4, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			-- Catch and settle
			local catchTarget = baseC0 * CFrame.Angles(math.rad(-5), math.rad(-5), 0) * CFrame.new(0, 0.02, -0.02)
			TweenService:Create(gripWeld,
				TweenInfo.new(dur * 0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ C0 = catchTarget }):Play()
		end)

		task.delay(dur * 0.75, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld,
				TweenInfo.new(dur * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ C0 = baseC0 }):Play()
			task.delay(dur * 0.25, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "spin" then
		-- Gun spin: trigger-finger spin then catch
		local step1 = baseC0 * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(0, 0.08, 0)
		local step2 = baseC0 * CFrame.Angles(0, math.rad(350), 0) * CFrame.new(0, 0.02, 0)

		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(15), 0, 0) * CFrame.new(0, -0.1, 0.05)

		TweenService:Create(gripWeld, TweenInfo.new(dur * 0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { C0 = step1 }):Play()

		task.delay(dur * 0.35, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = step2 }):Play()
		end)

		task.delay(dur * 0.7, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
			task.delay(dur * 0.3, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "pump" then
		-- Shotgun: bring up from low, pump-action rack
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(40), 0, 0) * CFrame.new(0, -0.25, 0.1)

		local raiseUp = baseC0 * CFrame.Angles(math.rad(5), 0, 0)
		TweenService:Create(gripWeld, TweenInfo.new(dur * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = raiseUp }):Play()

		task.delay(dur * 0.35, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			local pumpBack = baseC0 * CFrame.new(0, 0, 0.14)
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = pumpBack }):Play()
		end)

		task.delay(dur * 0.55, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			local pumpFwd = baseC0 * CFrame.new(0, 0, -0.03)
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.12, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = pumpFwd }):Play()
		end)

		task.delay(dur * 0.75, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
			task.delay(dur * 0.25, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "shoulder" then
		-- Heavy: heave from low to shoulder with weight feel
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(50), 0, 0) * CFrame.new(0, -0.4, 0.15)

		TweenService:Create(gripWeld,
			TweenInfo.new(dur * 0.6, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
			{ C0 = baseC0 * CFrame.Angles(math.rad(-3), 0, 0) }):Play()

		task.delay(dur * 0.65, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.35, Enum.EasingStyle.Sine, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
			task.delay(dur * 0.35, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "bolt" then
		-- Sniper: bring up and work the bolt
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(30), math.rad(-10), 0) * CFrame.new(0, -0.2, 0.1)

		local readyPos = baseC0 * CFrame.Angles(math.rad(3), 0, 0)
		TweenService:Create(gripWeld, TweenInfo.new(dur * 0.3, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = readyPos }):Play()

		-- Bolt back
		task.delay(dur * 0.35, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			local boltBack = baseC0 * CFrame.new(0, 0, 0.1) * CFrame.Angles(math.rad(5), 0, 0)
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = boltBack }):Play()
		end)

		-- Bolt forward
		task.delay(dur * 0.55, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			local boltFwd = baseC0 * CFrame.new(0, 0, -0.02)
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.1, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = boltFwd }):Play()
		end)

		task.delay(dur * 0.72, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
			task.delay(dur * 0.28, function() equipAnimPlaying = false end)
		end)

	elseif config.trickType == "flip" then
		-- Rail Rifle: flip forward and catch
		gripWeld.C0 = baseC0 * CFrame.Angles(math.rad(20), 0, 0) * CFrame.new(0, -0.15, 0.08)

		local flipUp = baseC0 * CFrame.Angles(math.rad(-180), 0, 0) * CFrame.new(0, 0.15, 0)
		TweenService:Create(gripWeld, TweenInfo.new(dur * 0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { C0 = flipUp }):Play()

		task.delay(dur * 0.45, function()
			if not gripWeld or not gripWeld.Parent then equipAnimPlaying = false return end
			TweenService:Create(gripWeld, TweenInfo.new(dur * 0.3, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { C0 = baseC0 }):Play()
			task.delay(dur * 0.3, function() equipAnimPlaying = false end)
		end)
	else
		equipAnimPlaying = false
	end
end

--------------------------------------------------------------------------------
-- HUD helper
--------------------------------------------------------------------------------

local function pushWeaponHud()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end
	HUD.updateWeaponInfo(weaponDef.name, currentAmmo, weaponDef.magazineSize, isReloading)
end

local function refreshWeaponState()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end
	currentAmmo = weaponDef.magazineSize
	isReloading = false
	lastFireTime = 0
	pushWeaponHud()
end

--------------------------------------------------------------------------------
-- Fire logic
--------------------------------------------------------------------------------

local function tryFire()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	if isReloading then
		return
	end

	if weaponDef.magazineSize > 0 and currentAmmo <= 0 then
		return
	end

	local now = tick()
	local fireCooldown = 1.0 / weaponDef.fireRate
	if (now - lastFireTime) < fireCooldown then
		return
	end
	lastFireTime = now

	if weaponDef.magazineSize > 0 then
		currentAmmo -= 1
	end

	pushWeaponHud()
	AudioController.playWeaponFire()
	playShootAnimation(currentWeaponId)

	local camCF = camera.CFrame
	ClientNetwork.fireServer(EventNames.WeaponFire, {
		origin = camCF.Position,
		direction = camCF.LookVector,
	})
end

--------------------------------------------------------------------------------
-- Reload logic
--------------------------------------------------------------------------------

local function tryReload()
	local weaponDef = WeaponData[currentWeaponId]
	if not weaponDef then
		return
	end

	if weaponDef.magazineSize <= 0 then
		return
	end

	if isReloading then
		return
	end
	if currentAmmo >= weaponDef.magazineSize then
		return
	end

	isReloading = true
	ClientNetwork.fireServer(EventNames.WeaponReload)
	AudioController.playWeaponReload()
	playReloadAnimation(currentWeaponId)
	pushWeaponHud()

	task.delay(weaponDef.reloadTime, function()
		currentAmmo = weaponDef.magazineSize
		isReloading = false
		pushWeaponHud()
	end)
end

--------------------------------------------------------------------------------
-- Input handling
--------------------------------------------------------------------------------

local function onInputBegan(input: InputObject, gameProcessed: boolean)
	if gameProcessed then
		return
	end

	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFireHeld = true
		tryFire()
	elseif input.KeyCode == Enum.KeyCode.R then
		tryReload()
	end
end

local function onInputEnded(input: InputObject, _gameProcessed: boolean)
	if input.UserInputType == Enum.UserInputType.MouseButton1 then
		isFireHeld = false
	end
end

-- Auto-fire loop: while mouse is held, keep firing for autoFire weapons only
local function onHeartbeat()
	if not isFireHeld then
		return
	end
	local weaponDef = WeaponData[currentWeaponId]
	if weaponDef and weaponDef.autoFire then
		tryFire()
	end
end

--------------------------------------------------------------------------------
-- Network listeners
--------------------------------------------------------------------------------

local function onWeaponHitConfirm(_data: any)
	print("[WeaponController] Hit confirmed on", _data.targetName)

	-- Melee hit feedback: flash screen edges and show backstab text
	local config = WEAPON_ANIM_CONFIG[currentWeaponId]
	if config and (config.holdType == "sword" or config.holdType == "knife") then
		local isBackstab = _data.isBackstab == true
		showMeleeHitFeedback(isBackstab, currentWeaponId)
	end
end

--------------------------------------------------------------------------------
-- Public API
--------------------------------------------------------------------------------

function WeaponController.setWeapon(weaponId: string)
	currentWeaponId = weaponId
	refreshWeaponState()
	createWeaponModel(weaponId)

	-- Create or destroy melee UI based on weapon type
	local config = WEAPON_ANIM_CONFIG[weaponId]
	if config and (config.holdType == "sword" or config.holdType == "knife") then
		createMeleeUI(weaponId)
	else
		destroyMeleeUI()
	end
end

function WeaponController.getAmmo(): number
	return currentAmmo
end

function WeaponController.getIsReloading(): boolean
	return isReloading
end

function WeaponController.init()
	refreshWeaponState()

	-- Input
	UserInputService.InputBegan:Connect(onInputBegan)
	UserInputService.InputEnded:Connect(onInputEnded)
	RunService.Heartbeat:Connect(onHeartbeat)

	-- First-person visibility: force arms + weapon visible in FP
	setupFirstPersonVisibility()

	-- Weapon bob & sway: update every render frame for smooth motion
	RunService.RenderStepped:Connect(function(dt)
		updateWeaponMotion(dt)
	end)

	-- Initialize camera look tracking
	lastCameraLook = camera.CFrame.LookVector

	-- Network events from server
	ClientNetwork.onServerEvent(EventNames.WeaponEquip, function(weaponState)
		WeaponController.setWeapon(weaponState.weaponId)
	end)
	ClientNetwork.onServerEvent(EventNames.WeaponHitConfirm, onWeaponHitConfirm)

	-- Re-create weapon model on respawn
	localPlayer.CharacterAdded:Connect(function()
		-- Small delay to let the character fully load
		task.wait(0.2)
		-- Reset animation state
		originalGripC0 = nil
		meleeComboIndex = 0
		isPlayingAnimation = false
		equipAnimPlaying = false
		if currentWeaponId then
			createWeaponModel(currentWeaponId)
		end
	end)

	-- If character already exists, equip now
	if localPlayer.Character then
		createWeaponModel(currentWeaponId)
	end

	print("[WeaponController] Initialized")
end

return WeaponController
