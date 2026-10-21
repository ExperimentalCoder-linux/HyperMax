local Test = require("tests.testlib")
local Languages = require("hypermax.languages")
local Managers = require("hypermax.managers")

local Version_Flags = {
	"--version",
	"-v",
	"-V",
}

local No_Version_Check = {
	html = true,
	sql = true,
	assembly = true,
	tcl = true,
}

local No_Manager_Version_Check = {
	tclsh = true,
}

local function Is_Executable(executable)
	return executable ~= nil and executable ~= "" and vim.fn.executable(executable) == 1
end

local function Get_Version(executable)
	for _, flag in ipairs(Version_Flags) do
		local output = vim.fn.systemlist({ executable, flag })
		local exit_code = vim.v.shell_error

		if exit_code == 0 and output and #output > 0 then
			return true, table.concat(output, "\n"), flag
		end
	end

	return false, nil, nil
end

local function First_Line(text)
	if not text then
		return ""
	end

	return text:match("([^\n]*)") or ""
end

-- =========================================================
-- INSTALLED LANGUAGE ENVIRONMENT
-- =========================================================

Test.Run("Environment: inspect registered language executables", function()
	local installed = 0
	local missing = 0
	local skipped = 0
	local version_failed = 0

	for _, id in ipairs(Languages.Get_IDs()) do
		local executable = Languages.Get_Executable(id)

		if No_Version_Check[id] then
			skipped = skipped + 1
			print("[NO VERSION CHECK] " .. id)
		elseif not executable or executable == "" then
			skipped = skipped + 1
			print("[UNCONFIGURED] " .. id .. " has no executable")
		elseif not Is_Executable(executable) then
			missing = missing + 1
			print("[MISSING] " .. id .. " -> " .. executable)
		else
			installed = installed + 1

			local ok, version, flag = Get_Version(executable)

			if ok then
				print("[INSTALLED] " .. id .. " -> " .. executable .. " [" .. flag .. "] " .. First_Line(version))
			else
				version_failed = version_failed + 1

				print("[VERSION FAILED] " .. id .. " -> " .. executable .. " (tried --version, -v, -V)")
			end
		end
	end

	print("")
	print("Language environment summary:")
	print("  Installed:       " .. installed)
	print("  Missing:         " .. missing)
	print("  Skipped:         " .. skipped)
	print("  Version failures:" .. version_failed)
end)

-- =========================================================
-- INSTALLED PROJECT MANAGER ENVIRONMENT
-- =========================================================

Test.Run("Environment: inspect registered manager executables", function()
	local seen = {}
	local installed = 0
	local missing = 0
	local skipped = 0
	local version_failed = 0

	for language_id, manager_entries in pairs(Managers.registry) do
		for manager_id, manager in pairs(manager_entries) do
			local executable = manager.executable

			if not executable or executable == "" then
				skipped = skipped + 1
			elseif seen[executable] then
				-- Test each unique executable only once.
			else
				seen[executable] = true

				if not Is_Executable(executable) then
					missing = missing + 1

					print(
						"[MISSING MANAGER] "
							.. manager_id
							.. " -> "
							.. executable
							.. " (language: "
							.. language_id
							.. ")"
					)
				elseif No_Manager_Version_Check[executable] then
					skipped = skipped + 1

					print("[NO VERSION CHECK] " .. executable .. " (manager)")
				else
					installed = installed + 1

					local ok, version, flag = Get_Version(executable)

					if ok then
						print(
							"[INSTALLED MANAGER] "
								.. manager_id
								.. " -> "
								.. executable
								.. " ["
								.. flag
								.. "] "
								.. First_Line(version)
						)
					else
						version_failed = version_failed + 1

						print("[MANAGER VERSION FAILED] " .. executable .. " (tried --version, -v, -V)")
					end
				end
			end
		end
	end

	print("")
	print("Project manager environment summary:")
	print("  Installed:       " .. installed)
	print("  Missing:         " .. missing)
	print("  Skipped:         " .. skipped)
	print("  Version failures:" .. version_failed)
end)
