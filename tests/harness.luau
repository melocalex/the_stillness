--!strict
-- Minimal test harness for pure Luau logic, run under Lune.

local harness = {}

local passed = 0
local failed = 0
local failures: { string } = {}
local currentSuite = ""

function harness.describe(name: string, body: () -> ())
	currentSuite = name
	body()
end

function harness.it(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		passed += 1
	else
		failed += 1
		table.insert(failures, string.format("%s > %s\n    %s", currentSuite, name, tostring(err)))
	end
end

function harness.eq(actual: any, expected: any, msg: string?)
	if actual ~= expected then
		error(
			string.format(
				"%sexpected %s, got %s",
				if msg then msg .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function harness.near(actual: number, expected: number, tolerance: number?, msg: string?)
	local tol = tolerance or 1e-6
	if math.abs(actual - expected) > tol then
		error(
			string.format(
				"%sexpected ~%s, got %s",
				if msg then msg .. ": " else "",
				tostring(expected),
				tostring(actual)
			),
			2
		)
	end
end

function harness.truthy(v: any, msg: string?)
	if not v then
		error(msg or "expected truthy value", 2)
	end
end

function harness.falsy(v: any, msg: string?)
	if v then
		error(msg or "expected falsy value", 2)
	end
end

function harness.report(): boolean
	for _, f in failures do
		print("FAIL " .. f)
	end
	print(string.format("\n%d passed, %d failed", passed, failed))
	return failed == 0
end

return harness
