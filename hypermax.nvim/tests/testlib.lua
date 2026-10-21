-- Tiny pure-Lua test runner for HyperMax.
-- No third-party test framework.

local Test = {
	passed = 0,
	failed = 0,
	total = 0,
	failures = {},
}

-- =========================================================
-- TERMINAL COLORS
-- =========================================================

local Colors = {
	Reset = "\27[0m",
	Red = "\27[31m",
	Green = "\27[32m",
	Yellow = "\27[33m",
	Blue = "\27[34m",
	Magenta = "\27[35m",
	Cyan = "\27[36m",
	Gray = "\27[90m",
}

-- =========================================================
-- STATUS COLORS
-- =========================================================

local Status_Colors = {
	["[PASS]"] = Colors.Green,
	["[FAIL]"] = Colors.Red,

	["[INSTALLED]"] = Colors.Green,
	["[MISSING]"] = Colors.Red,
	["[UNCONFIGURED]"] = Colors.Yellow,
	["[SKIPPED]"] = Colors.Yellow,

	["[NO VERSION CHECK]"] = Colors.Gray,
	["[VERSION FAILED]"] = Colors.Magenta,
	["[MANAGER VERSION FAILED]"] = Colors.Magenta,

	["[INSTALLED MANAGER]"] = Colors.Green,
	["[MISSING MANAGER]"] = Colors.Red,

	["[INFO]"] = Colors.Blue,
	["[WARNING]"] = Colors.Yellow,
	["[ERROR]"] = Colors.Red,
}

-- Longest tags first, so manager statuses are matched correctly.
local Status_Tags = {
	"[MANAGER VERSION FAILED]",
	"[INSTALLED MANAGER]",
	"[MISSING MANAGER]",
	"[NO VERSION CHECK]",
	"[VERSION FAILED]",
	"[UNCONFIGURED]",
	"[INSTALLED]",
	"[MISSING]",
	"[SKIPPED]",
	"[WARNING]",
	"[ERROR]",
	"[INFO]",
	"[PASS]",
	"[FAIL]",
}

-- =========================================================
-- OUTPUT HELPERS
-- =========================================================

local function Write_Line(message)
	io.stdout:write(tostring(message), "\n")
	io.stdout:flush()
end

local function Color_Status(message)
	for _, tag in ipairs(Status_Tags) do
		local color = Status_Colors[tag]

		if message:sub(1, #tag) == tag then
			return color .. tag .. Colors.Reset .. message:sub(#tag + 1)
		end
	end

	return message
end

-- Color status tags from all test files automatically.
-- Existing print("message") calls continue to work.
_G.print = function(...)
	local values = {}

	for i = 1, select("#", ...) do
		values[i] = tostring(select(i, ...))
	end

	local message = table.concat(values, "\t")
	Write_Line(Color_Status(message))
end

local function Value(value)
	if type(value) == "string" then
		return string.format("%q", value)
	end

	return tostring(value) .. " (" .. type(value) .. ")"
end

local function Print_Status(color, status, message)
	Write_Line(color .. "[" .. status .. "]" .. Colors.Reset .. " " .. message)
end

-- =========================================================
-- TEST RUNNER
-- =========================================================

function Test.Run(name, callback)
	Test.total = Test.total + 1

	local ok, err = xpcall(callback, debug.traceback)

	if ok then
		Test.passed = Test.passed + 1
		Print_Status(Colors.Green, "PASS", name)
		return true
	end

	Test.failed = Test.failed + 1

	Test.failures[#Test.failures + 1] = {
		name = name,
		error = tostring(err),
	}

	Print_Status(Colors.Red, "FAIL", name)

	Write_Line(Colors.Red .. "       " .. tostring(err):gsub("\n", "\n       ") .. Colors.Reset)

	return false
end

-- =========================================================
-- ASSERTIONS
-- =========================================================

function Test.Equal(expected, actual, message)
	if expected ~= actual then
		error(
			(message or "Values are not equal")
				.. "\n  expected: "
				.. Value(expected)
				.. "\n  actual:   "
				.. Value(actual),
			2
		)
	end
end

function Test.Not_Equal(expected, actual, message)
	if expected == actual then
		error(message or ("Expected values to differ, both were " .. Value(actual)), 2)
	end
end

function Test.True(value, message)
	if value ~= true then
		error((message or "Expected true") .. "; got " .. Value(value), 2)
	end
end

function Test.False(value, message)
	if value ~= false then
		error((message or "Expected false") .. "; got " .. Value(value), 2)
	end
end

function Test.Nil(value, message)
	if value ~= nil then
		error((message or "Expected nil") .. "; got " .. Value(value), 2)
	end
end

function Test.Not_Nil(value, message)
	if value == nil then
		error(message or "Expected a non-nil value", 2)
	end
end

function Test.Type(expected_type, value, message)
	if type(value) ~= expected_type then
		error((message or "Unexpected type") .. "; expected " .. expected_type .. ", got " .. type(value), 2)
	end
end

function Test.Error(callback, message)
	local ok, err = pcall(callback)

	if ok then
		error(message or "Expected function to raise an error", 2)
	end

	return err
end

-- =========================================================
-- TEST SUMMARY
-- =========================================================

function Test.Finish()
	Write_Line("")

	Write_Line(Colors.Cyan .. "============= HYPERMAX TEST RESULTS =============" .. Colors.Reset)

	Write_Line(Colors.Green .. "Passed: " .. Test.passed .. Colors.Reset)

	Write_Line((Test.failed > 0 and Colors.Red or Colors.Green) .. "Failed: " .. Test.failed .. Colors.Reset)

	Write_Line(Colors.Cyan .. "Total:  " .. Test.total .. Colors.Reset)

	Write_Line(Colors.Cyan .. "=================================================" .. Colors.Reset)

	if Test.failed > 0 then
		Write_Line(Colors.Red .. "Failures:" .. Colors.Reset)

		for _, failure in ipairs(Test.failures) do
			Write_Line(Colors.Red .. "- " .. failure.name .. ": " .. failure.error .. Colors.Reset)
		end

		return false
	end

	Write_Line(Colors.Green .. "All tests passed!" .. Colors.Reset)

	return true
end

return Test
