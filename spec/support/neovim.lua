-- Minimal Neovim API surface for pure Lua unit tests.
-- Integration behavior remains covered by the headless Neovim suite.

local function Deep_Copy(value, seen)
	if type(value) ~= "table" then
		return value
	end

	seen = seen or {}
	if seen[value] then
		return seen[value]
	end

	local copy = {}
	seen[value] = copy
	for key, item in pairs(value) do
		copy[Deep_Copy(key, seen)] = Deep_Copy(item, seen)
	end
	return setmetatable(copy, getmetatable(value))
end

local registered_commands = {}
local notifications = {}

_G.vim = {
	deepcopy = Deep_Copy,
	tbl_contains = function(values, expected)
		for _, value in ipairs(values) do
			if value == expected then return true end
		end
		return false
	end,
	tbl_keys = function(value)
		local keys = {}
		for key in pairs(value) do
			keys[#keys + 1] = key
		end
		return keys
	end,
	validate = function(name, value, expected_type)
		if type(value) ~= expected_type then
			error(string.format("%s: expected %s, got %s", name, expected_type, type(value)))
		end
	end,
	fn = {
		getcompletion = function(prefix, completion_type)
			assert.are.equal("dir", completion_type)
			local candidates = { "src/", "tests/", "lua/" }
			local matches = {}
			for _, candidate in ipairs(candidates) do
				if candidate:sub(1, #prefix) == prefix then
					matches[#matches + 1] = candidate
				end
			end
			return matches
		end,
	},
	log = {
		levels = {
			INFO = 1,
			WARN = 2,
			ERROR = 3,
		},
	},
	notify = function(message, level)
		notifications[#notifications + 1] = { message = message, level = level }
	end,
	api = {
		nvim_create_user_command = function(name, callback, options)
			if registered_commands[name] then
				error("Command already exists: " .. name)
			end
			registered_commands[name] = {
				callback = callback,
				options = Deep_Copy(options),
			}
		end,
	},
}

return {
	commands = registered_commands,
	notifications = notifications,
}
