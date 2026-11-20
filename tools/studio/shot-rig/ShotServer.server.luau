-- Studio screenshot rig (a tool, never part of the game; see build.sh):
-- fast-forwards the clock to 11:00 and freezes it, so shots of different
-- builds share the same light.

local RS = game:GetService("ReplicatedStorage")
repeat
	task.wait(0.5)
until RS:GetAttribute("ClockTime") ~= nil
RS:SetAttribute("TimeScale", 60)
repeat
	task.wait()
until ((RS:GetAttribute("ClockTime") :: number?) or 0) >= 11
RS:SetAttribute("TimeScale", 0)
print("[Shot] clock frozen at", RS:GetAttribute("ClockTime"), RS:GetAttribute("Weather"))
