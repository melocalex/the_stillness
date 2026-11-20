-- Studio screenshot rig (a tool, never part of the game; see build.sh).
-- After the player spawns, cycles fixed cameras so builds of different
-- commits are shot identically, and hides the HUD. Eye/look heights are
-- above the terrain surface (terrain-only raycast, water counts as surface)
-- unless abs = true.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local HOLD = 14
local CAMS = {
	{ name = "cabin-north-yard", eye = { 22, -22, 6 }, look = { 0, -248, 14 } },
	{ name = "lake-shore", eye = { -30, -98, 5 }, look = { 70, -230, 8 } },
	{ name = "radio-hill", eye = { -205, -45, 8 }, look = { 150, -700, 60 } },
	{ name = "porch-south", eye = { 4, 24, 7 }, look = { 330, 420, 10 } },
	{ name = "aerial", eye = { 0, 700, 650 }, look = { 0, 0, -300 }, abs = true },
}

local function ground(x: number, z: number): number
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Include
	p.FilterDescendantsInstances = { workspace.Terrain }
	local hit = workspace:Raycast(Vector3.new(x, 2000, z), Vector3.new(0, -2600, 0), p)
	return if hit then hit.Position.Y else 0
end

local function frame(c): CFrame
	if c.abs then
		return CFrame.lookAt(
			Vector3.new(c.eye[1], c.eye[2], c.eye[3]),
			Vector3.new(c.look[1], c.look[2], c.look[3])
		)
	end
	local eye = Vector3.new(c.eye[1], ground(c.eye[1], c.eye[2]) + c.eye[3], c.eye[2])
	local look = Vector3.new(c.look[1], ground(c.look[1], c.look[2]) + c.look[3], c.look[2])
	return CFrame.lookAt(eye, look)
end

local player = Players.LocalPlayer
if not player.Character then
	player.CharacterAdded:Wait()
end
task.wait(5)
local cam = workspace.CurrentCamera
local current: CFrame? = nil
RunService:BindToRenderStep("ShotRig", Enum.RenderPriority.Last.Value + 10, function()
	if current then
		cam.CameraType = Enum.CameraType.Scriptable
		cam.FieldOfView = 70
		cam.CFrame = current
	end
end)
while true do
	for _, c in CAMS do
		for _, g in player.PlayerGui:GetChildren() do
			if g:IsA("ScreenGui") then
				g.Enabled = false
			end
		end
		current = frame(c)
		print(string.format("[Shot] %s  %s", c.name, tostring(current.Position)))
		task.wait(HOLD)
	end
end
