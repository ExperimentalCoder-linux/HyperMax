local uv = vim.uv or vim.loop

local Languages = require("hypermax.languages")
local Managers = require("hypermax.managers")
local Layouts = require("hypermax.layouts")
local Config = require("hypermax.config")
local Progress = require("hypermax.progress")

local Project = {}

-- =========================================================
-- NOTIFICATIONS AND INPUT
-- =========================================================

local function Notify(message, level)
	vim.notify("HyperMax: " .. message, level or vim.log.levels.INFO)
end

local function Input(prompt, default, callback)
	vim.ui.input({
		prompt = prompt,
		default = default or "",
	}, callback)
end

local function Confirm(message, callback)
	vim.ui.select({ "Yes", "No" }, {
		prompt = message,
	}, function(choice)
		callback(choice == "Yes")
	end)
end

local function Select_Item(items, prompt, format_item, callback)
	if #items == 0 then
		Notify("No choices are available for " .. prompt, vim.log.levels.WARN)
		return
	end

	vim.ui.select(items, {
		prompt = prompt,
		format_item = format_item,
	}, callback)
end

-- =========================================================
-- FILESYSTEM
-- =========================================================

local function Join_Path(...)
	local parts = { ... }
	return table.concat(parts, "/"):gsub("/+", "/")
end

local function Is_Safe_Relative_Path(path)
	if type(path) ~= "string" or path == "" then
		return false
	end

	if path:find("%z") or path:find("\\") then
		return false
	end

	if path:sub(1, 1) == "/" then
		return false
	end

	if path:match("^%a:") then
		return false
	end

	for part in path:gmatch("[^/]+") do
		if part == "." or part == ".." then
			return false
		end
	end

	return true
end

local function Is_Directory(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "directory"
end

local function Is_File(path)
	local stat = uv.fs_stat(path)
	return stat ~= nil and stat.type == "file"
end

local function Ensure_Directory(path)
	if Is_Directory(path) then
		return true
	end

	local ok = vim.fn.mkdir(path, "p")

	if ok == 0 and not Is_Directory(path) then
		return false, "Could not create directory: " .. path
	end

	return true
end

local function Read_File(path)
	local file = io.open(path, "rb")

	if not file then
		return nil
	end

	local contents = file:read("*a")
	file:close()

	return contents
end

-- Creates a file only if it does not already exist.
-- Uses exclusive creation so existing files are not overwritten.
local function Write_New_File(path, contents)
	local parent = vim.fn.fnamemodify(path, ":h")

	local ok, err = Ensure_Directory(parent)

	if not ok then
		return false, err
	end

	local fd, open_err = uv.fs_open(path, "wx", 420)

	if not fd then
		return false, open_err or ("Could not create " .. path)
	end

	local write_ok, write_err = true, nil

	if contents ~= "" then
		local written, result = uv.fs_write(fd, contents, 0)

		if not written then
			write_ok = false
			write_err = result or "File write failed."
		elseif written ~= #contents then
			write_ok = false
			write_err = "Incomplete file write."
		end
	end

	uv.fs_close(fd)

	if not write_ok then
		os.remove(path)
		return false, write_err
	end

	return true
end

-- =========================================================
-- LANGUAGE HELPERS
-- =========================================================

local function Get_Language_Name(id)
	local language = Languages.Get(id)

	if type(language) == "table" then
		return language.name or id
	end

	return id
end

local function Get_Language_File(id)
	local filename = Languages.Get_Default_File(id)

	if type(filename) == "string" and filename ~= "" then
		return filename
	end

	return "main.txt"
end

local function Sort_Languages(ids, favourites)
	local rank = {}

	for index, id in ipairs(favourites or {}) do
		rank[id] = index
	end

	table.sort(ids, function(a, b)
		local a_rank = rank[a] or math.huge
		local b_rank = rank[b] or math.huge

		if a_rank ~= b_rank then
			return a_rank < b_rank
		end

		return a < b
	end)

	return ids
end

local function Get_Language_Choices(options)
	local ids = Languages.Get_IDs()

	Sort_Languages(ids, options.favourite_languages)

	return ids
end

-- =========================================================
-- SOURCE TEMPLATES
-- =========================================================

local Templates = {
	c = [[#include <stdio.h>

int main(void) {
    printf("Hello, World!\n");
    return 0;
}
]],

	cpp = [[#include <iostream>

int main() {
    std::cout << "Hello, World!\n";
    return 0;
}
]],

	python = [[def main():
    print("Hello, World!")


if __name__ == "__main__":
    main()
]],

	java = [[public class Main {
    public static void main(String[] args) {
        System.out.println("Hello, World!");
    }
}
]],

	javaScript = [[function main() {
    console.log("Hello, World!");
}

main();
]],

	typescript = [[function main(): void {
    console.log("Hello, World!");
}

main();
]],

	lua = [[local function main()
    print("Hello, World!")
end

main()
]],

	rust = [[fn main() {
    println!("Hello, World!");
}
]],

	-- 	go = [[package main
	--
	-- import "fmt"
	--
	-- func main() {
	--     fmt.Println("Hello, World!")
	-- }
	-- ]],

	csharp = [[using System;

class Program {
    static void Main() {
        Console.WriteLine("Hello, World!");
    }
}
]],

	bash = [[#!/usr/bin/env bash

set -e

echo "Hello, World!"
]],

	ruby = [[def main
  puts "Hello, World!"
end

main
]],

	php = [[<?php

echo "Hello, World!\n";
]],

	swift = [[import Foundation

print("Hello, World!")
]],

	kotlin = [[fun main() {
    println("Hello, World!")
}
]],

	zig = [[const std = @import("std");

pub fn main() void {
    std.debug.print("Hello, World!\n", .{});
}
]],

	go = [[package main

import "fmt"

func main() {
    fmt.Println("Hello, World!")
}
]],
}

local function Get_Source_Template(language_id)
	return Templates[language_id] or ""
end

-- =========================================================
-- MANAGER PROJECT FILES
-- =========================================================

local function Get_Manager_Files(language_id, manager_id)
	local files = {}

	if manager_id == "cmake" and language_id == "cpp" then
		files["CMakeLists.txt"] = [[cmake_minimum_required(VERSION 3.16)
project(HyperMaxProject LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

add_executable(main src/main.cpp)
]]
	elseif manager_id == "cmake" and language_id == "c" then
		files["CMakeLists.txt"] = [[cmake_minimum_required(VERSION 3.16)
project(HyperMaxProject LANGUAGES C)

add_executable(main src/main.c)
]]
	elseif manager_id == "make" and language_id == "cpp" then
		files["Makefile"] = [[CXX := g++
CXXFLAGS := -Wall -Wextra -Wpedantic -std=c++17 -O2
TARGET := main
SOURCE := src/main.cpp

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CXX) $(CXXFLAGS) $(SOURCE) -o $(TARGET)

clean:
	rm -f $(TARGET)
]]
	elseif manager_id == "make" and language_id == "c" then
		files["Makefile"] = [[CC := cc
CFLAGS := -Wall -Wextra -Wpedantic -std=c17 -O2
TARGET := main
SOURCE := src/main.c

.PHONY: all clean

all: $(TARGET)

$(TARGET): $(SOURCE)
	$(CC) $(CFLAGS) $(SOURCE) -o $(TARGET)

clean:
	rm -f $(TARGET)
]]
	elseif manager_id == "cargo" and language_id == "rust" then
		files["Cargo.toml"] = [[ [package]
name = "hypermax_project"
version = "0.1.0"
edition = "2021"

[dependencies]
]]
	elseif manager_id == "npm" and language_id == "javaScript" then
		files["package.json"] = [[{
  "name": "hypermax-project",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "start": "node src/main.js"
  }
}
]]
	elseif manager_id == "npm" and language_id == "typescript" then
		files["package.json"] = [[{
  "name": "hypermax-project",
  "version": "1.0.0",
  "private": true,
  "scripts": {
    "build": "tsc",
    "start": "node dist/main.js"
  },
  "devDependencies": {
    "typescript": "^5.0.0"
  }
}
]]
		files["tsconfig.json"] = [[{
  "compilerOptions": {
    "target": "ES2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "outDir": "dist",
    "strict": true
  },
  "include": ["src/**/*.ts"]
}
]]
	elseif manager_id == "uv" and language_id == "python" then
		files["pyproject.toml"] = [[ [project]
name = "hypermax-project"
version = "0.1.0"
requires-python = ">=3.10"
dependencies = []
]]
	elseif manager_id == "maven" and language_id == "java" then
		files["pom.xml"] = [[<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <groupId>org.hypermax</groupId>
    <artifactId>hypermax-project</artifactId>
    <version>1.0-SNAPSHOT</version>
    <properties>
        <maven.compiler.release>17</maven.compiler.release>
        <project.build.sourceEncoding>UTF-8</project.build.sourceEncoding>
    </properties>
</project>
]]
	end

	return files
end

-- =========================================================
-- PROJECT CONTENT
-- =========================================================

local function Build_Readme(project_name, language_id, manager_id)
	return string.format(
		"# %s\n\n"
			.. "## Overview\n\n"
			.. "A %s project generated with HyperMax.nvim.\n\n"
			.. "## Requirements\n\n"
			.. "Install the required language runtime and development tools.\n\n"
			.. "## Project manager\n\n"
			.. "%s\n\n"
			.. "## Build and run\n\n"
			.. "Add the build and run instructions for this project here.\n",
		project_name,
		Get_Language_Name(language_id),
		manager_id
	)
end

local function Build_Default_Manifest(language_id, manager_id, project_name, options)
	local manifest = {
		directories = {},
		files = {},
		entry = Get_Language_File(language_id),
	}

	-- Use the central layout system for shared defaults,
	-- language commands, credits, and selected layouts.
	local built = Layouts.Build_Manifest(language_id, "", project_name)

	if type(built) == "table" then
		manifest = built
		manifest.directories = manifest.directories or {}
		manifest.files = manifest.files or {}
	end

	-- Keep all paths relative to the new project root.
	local entry = manifest.entry or Get_Language_File(language_id)

	if not manifest.files[entry] then
		manifest.files[entry] = Get_Source_Template(language_id)
	end

	if options.create_readme and not manifest.files["README.md"] then
		manifest.files["README.md"] = Build_Readme(project_name, language_id, manager_id)
	end

	if options.create_gitignore and not manifest.files[".gitignore"] then
		manifest.files[".gitignore"] = [[build/
dist/
out/
*.o
*.obj
*.exe
*.class
__pycache__/
.venv/
venv/
node_modules/
target/
]]
	end

	if options.create_default_directories then
		local defaults = { "src", "tests", "docs" }

		for _, directory in ipairs(defaults) do
			if not vim.tbl_contains(manifest.directories, directory) then
				manifest.directories[#manifest.directories + 1] = directory
			end
		end
	end

	local manager_files = Get_Manager_Files(language_id, manager_id)

	for path, content in pairs(manager_files) do
		if not manifest.files[path] then
			manifest.files[path] = content
		end
	end

	return manifest
end

local function Build_Layout_Manifest(language_id, layout_id, project_name, manager_id, options)
	if not layout_id or layout_id == "" then
		return Build_Default_Manifest(language_id, manager_id, project_name, options)
	end

	local manifest = Layouts.Build_Manifest(language_id, layout_id, project_name)

	if type(manifest) ~= "table" then
		return nil, "Could not build layout manifest."
	end

	manifest.directories = manifest.directories or {}
	manifest.files = manifest.files or {}

	-- The layout may already contain its own manager files.
	-- Add missing files for the selected manager without replacing them.
	local manager_files = Get_Manager_Files(language_id, manager_id)

	for path, content in pairs(manager_files) do
		if not manifest.files[path] then
			manifest.files[path] = content
		end
	end

	if options.create_readme and not manifest.files["README.md"] then
		manifest.files["README.md"] = Build_Readme(project_name, language_id, manager_id)
	end

	if options.create_gitignore and not manifest.files[".gitignore"] then
		manifest.files[".gitignore"] = [[build/
dist/
out/
*.o
*.obj
*.exe
*.class
__pycache__/
.venv/
venv/
node_modules/
target/
]]
	end

	return manifest
end

-- =========================================================
-- PROGRESS AND MANIFEST WRITING
-- =========================================================

local function Add_Manifest_Task(tasks, root, relative_path, kind, content)
	if not Is_Safe_Relative_Path(relative_path) then
		return false, "Unsafe project path: " .. tostring(relative_path)
	end

	tasks[#tasks + 1] = {
		type = kind,
		relative_path = relative_path,
		full_path = Join_Path(root, relative_path),
		content = content,
	}

	return true
end

local function Create_From_Manifest(root, manifest, options)
	local tasks = {}
	local directories = {}
	local directory_seen = {}

	local function Add_Directory(relative_path)
		if not Is_Safe_Relative_Path(relative_path) then
			return false, "Unsafe directory path: " .. tostring(relative_path)
		end

		if not directory_seen[relative_path] then
			directory_seen[relative_path] = true
			directories[#directories + 1] = relative_path
		end

		return true
	end

	for _, directory in ipairs(manifest.directories or {}) do
		local ok, err = Add_Directory(directory)

		if not ok then
			return false, err
		end
	end

	for relative_path in pairs(manifest.files or {}) do
		if not Is_Safe_Relative_Path(relative_path) then
			return false, "Unsafe file path: " .. tostring(relative_path)
		end

		local parent = vim.fn.fnamemodify(relative_path, ":h")

		if parent ~= "." then
			local current = ""

			for part in parent:gmatch("[^/]+") do
				current = current == "" and part or (current .. "/" .. part)

				local ok, err = Add_Directory(current)

				if not ok then
					return false, err
				end
			end
		end
	end

	table.sort(directories, function(a, b)
		local a_depth = select(2, a:gsub("/", ""))
		local b_depth = select(2, b:gsub("/", ""))

		if a_depth ~= b_depth then
			return a_depth < b_depth
		end

		return a < b
	end)

	-- Directories are counted as work too.
	for _, directory in ipairs(directories) do
		tasks[#tasks + 1] = {
			type = "directory",
			relative_path = directory,
			full_path = Join_Path(root, directory),
		}
	end

	local file_paths = {}

	for relative_path in pairs(manifest.files or {}) do
		file_paths[#file_paths + 1] = relative_path
	end

	table.sort(file_paths)

	for _, relative_path in ipairs(file_paths) do
		local ok, err = Add_Manifest_Task(tasks, root, relative_path, "file", manifest.files[relative_path])

		if not ok then
			return false, err
		end
	end

	local total = #tasks
	local completed = 0

	if options.show_progress then
		Progress.Start("Creating project", total)
		Progress.Log("Project: " .. root)
	end

	local function Update_Progress(task)
		completed = completed + 1

		if options.show_progress then
			Progress.Update(task.type .. ": " .. task.relative_path, completed, total)
		end
	end

	-- Preflight before writing: do not overwrite existing files.
	for _, task in ipairs(tasks) do
		if task.type == "file" and uv.fs_stat(task.full_path) then
			if options.show_progress then
				Progress.Finish(false, "File already exists.")
				Progress.Log(task.full_path)
			end

			return false, "Refusing to overwrite existing file: " .. task.full_path
		end
	end

	local ok, err = Ensure_Directory(root)

	if not ok then
		if options.show_progress then
			Progress.Finish(false, err)
		end

		return false, err
	end

	for _, task in ipairs(tasks) do
		local task_ok, task_err

		if task.type == "directory" then
			task_ok, task_err = Ensure_Directory(task.full_path)
		else
			task_ok, task_err = Write_New_File(task.full_path, task.content or "")
		end

		if not task_ok then
			if options.show_progress then
				Progress.Log("ERROR: " .. task.relative_path)
				Progress.Log(tostring(task_err))
				Progress.Finish(false, "Project creation failed.")
			end

			return false, task_err
		end

		Update_Progress(task)
	end

	if options.show_progress then
		Progress.Finish(true, "Project created successfully.")
	end

	return true
end

-- =========================================================
-- MANAGER VALIDATION
-- =========================================================

local function Get_Manager_Name(language_id, manager_id)
	local manager = Managers.Get(language_id, manager_id)

	if type(manager) == "table" then
		return manager.name or manager_id
	end

	return manager_id
end

local function Check_Manager(language_id, manager_id, callback)
	local manager = Managers.Get(language_id, manager_id)

	if type(manager) ~= "table" then
		callback(true)
		return
	end

	-- Native means no separate project manager is required.
	if manager_id == "native" or not manager.executable then
		callback(true)
		return
	end

	if vim.fn.executable(manager.executable) == 1 then
		callback(true)
		return
	end

	Confirm(Get_Manager_Name(language_id, manager_id) .. " does not appear to be installed. Continue anyway?", callback)
end

-- =========================================================
-- OPEN PROJECT
-- =========================================================

local function Open_Project(root, entry, options)
	if not options.open_after_create then
		return
	end

	local relative_entry = entry or ""

	if relative_entry ~= "" and Is_Safe_Relative_Path(relative_entry) then
		local path = Join_Path(root, relative_entry)

		if Is_File(path) then
			vim.cmd("edit " .. vim.fn.fnameescape(path))
			return
		end
	end

	vim.cmd("tcd " .. vim.fn.fnameescape(root))
end

-- =========================================================
-- CREATE PROJECT
-- =========================================================

local function Create_Project(options, language_id, manager_id, root, project_name, layout_id)
	local language = Languages.Get(language_id)

	if options.remember_last_project ~= false then
		Config.options.last_project_path = root
		Config.save()
	end

	if not language then
		Notify("Unknown language: " .. language_id, vim.log.levels.ERROR)
		return
	end

	local manager = Managers.Get(language_id, manager_id)

	if not manager then
		Notify("Unknown manager '" .. manager_id .. "' for " .. language_id, vim.log.levels.ERROR)
		return
	end

	local manifest, manifest_err = Build_Layout_Manifest(language_id, layout_id, project_name, manager_id, options)

	if not manifest then
		Notify("Could not prepare project: " .. tostring(manifest_err), vim.log.levels.ERROR)
		return
	end

	local entry = manifest.entry or Get_Language_File(language_id)

	local ok, err = Create_From_Manifest(root, manifest, options)

	if not ok then
		Notify("Project creation failed: " .. tostring(err), vim.log.levels.ERROR)
		return
	end

	Notify("Created project: " .. root)

	Open_Project(root, entry, options)
end

-- =========================================================
-- PROJECT WIZARD
-- =========================================================

function Project.Create(user_options)
	local options = vim.tbl_deep_extend("force", {}, Config.options or {}, user_options or {})

	local language_ids = Get_Language_Choices(options)

	Select_Item(language_ids, "Choose project language", function(id)
		local favourite = vim.tbl_contains(options.favourite_languages or {}, id)

		return (favourite and "★ " or "  ") .. Get_Language_Name(id) .. " (" .. id .. ")"
	end, function(language_id)
		if not language_id then
			return
		end

		local manager_ids = Managers.Get_IDs(language_id)

		if type(manager_ids) ~= "table" or #manager_ids == 0 then
			manager_ids = { "native" }
		end

		local default_manager = options.default_manager or "native"

		-- Put the configured default manager first.
		table.sort(manager_ids, function(a, b)
			if a == default_manager then
				return true
			end

			if b == default_manager then
				return false
			end

			return a < b
		end)

		Select_Item(manager_ids, "Choose project manager", function(id)
			return Get_Manager_Name(language_id, id) .. " (" .. id .. ")"
		end, function(manager_id)
			if not manager_id then
				return
			end

			local default_location = options.project_dir or vim.fn.expand("~/Projects")

			Input("Project starting location: ", default_location, function(location)
				if location == nil then
					return
				end

				location = vim.trim(location)

				if location == "" then
					Notify("Project location cannot be empty.", vim.log.levels.ERROR)
					return
				end

				location = vim.fn.expand(location)

				Input("Project name: ", "MyProject", function(project_name)
					if project_name == nil then
						return
					end

					project_name = vim.trim(project_name)

					if
						project_name == ""
						or project_name:find("[/\\]")
						or project_name == "."
						or project_name == ".."
					then
						Notify("Invalid project name.", vim.log.levels.ERROR)
						return
					end

					local layouts = Layouts.Get_For_Language(language_id) or {}

					local choices = {
						{
							id = "",
							name = "Default project",
							description = "Use the standard project structure.",
						},
					}

					for _, layout in ipairs(layouts) do
						if type(layout) == "string" then
							local item = Layouts.Get(layout)

							if item then
								choices[#choices + 1] = item
							end
						elseif type(layout) == "table" then
							choices[#choices + 1] = layout
						end
					end

					local preferred_layout = options.default_layout or ""

					table.sort(choices, function(a, b)
						if a.id == preferred_layout then
							return true
						end

						if b.id == preferred_layout then
							return false
						end

						return (a.name or a.id) < (b.name or b.id)
					end)

					Select_Item(choices, "Choose project layout", function(layout)
						local name = layout.name or layout.id or "Default project"

						local description = layout.description

						if description and description ~= "" then
							return name .. " — " .. description
						end

						return name
					end, function(layout)
						if not layout then
							return
						end

						local layout_id = layout.id or ""

						local root = Join_Path(location, project_name)

						if uv.fs_stat(root) then
							Notify("Project path already exists: " .. root, vim.log.levels.ERROR)
							return
						end

						local function Continue()
							Check_Manager(language_id, manager_id, function(continue)
								if not continue then
									Notify("Project creation cancelled.")
									return
								end

								Create_Project(options, language_id, manager_id, root, project_name, layout_id)
							end)
						end

						if options.confirm_before_create then
							Confirm("Create " .. project_name .. " in " .. root .. "?", function(confirmed)
								if confirmed then
									Continue()
								else
									Notify("Project creation cancelled.")
								end
							end)
						else
							Continue()
						end
					end)
				end)
			end)
		end)
	end)
end

-- =========================================================
-- LIST EXISTING PROJECTS
-- =========================================================

function Project.List()
	local options = Config.options or {}
	local root = vim.fn.expand(options.project_dir or "~/Projects")
	local entries = uv.fs_scandir(root)

	if not entries then
		Notify("Project directory does not exist: " .. root, vim.log.levels.WARN)
		return
	end

	local projects = {}

	while true do
		local name, kind = uv.fs_scandir_next(entries)

		if not name then
			break
		end

		if kind == "directory" and name:sub(1, 1) ~= "." then
			local path = Join_Path(root, name)

			projects[#projects + 1] = {
				name = name,
				path = path,
			}
		end
	end

	table.sort(projects, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	Select_Item(projects, "Choose project", function(project)
		return project.name
	end, function(project)
		if not project then
			return
		end

		vim.cmd("tcd " .. vim.fn.fnameescape(project.path))
		Notify("Opened project: " .. project.path)
	end)
end

-- =========================================================
-- OPEN LAST PROJECT
-- =========================================================

function Project.Open_Last()
	local options = Config.options or {}
	local path = options.last_project_path

	if type(path) ~= "string" or path == "" then
		Notify("No last project has been saved yet.", vim.log.levels.WARN)
		return
	end

	path = vim.fn.expand(path)

	if not Is_Directory(path) then
		Notify("Last project directory no longer exists: " .. path, vim.log.levels.ERROR)
		return
	end

	vim.cmd("tcd " .. vim.fn.fnameescape(path))
	Notify("Opened project: " .. path)
end

-- =========================================================
-- LOAD A LAYOUT INTO A NEW PROJECT
-- =========================================================

function Project.Load_Layout()
	local ids = Layouts.Get_IDs()
	local choices = {}

	for _, id in ipairs(ids) do
		local layout = Layouts.Get(id)

		if layout then
			choices[#choices + 1] = layout
		end
	end

	Select_Item(choices, "Choose layout", function(layout)
		return (layout.name or layout.id)
			.. (layout.description and layout.description ~= "" and " — " .. layout.description or "")
	end, function(layout)
		if not layout then
			return
		end

		local options = vim.tbl_deep_extend("force", {}, Config.options or {}, { default_layout = layout.id })

		Project.Create(options)
	end)
end

-- =========================================================
-- SAVE CURRENT DIRECTORY AS A LAYOUT
-- =========================================================

local function Scan_Directory(root)
	local layout = {
		name = vim.fn.fnamemodify(root, ":t"),
		description = "",
		directories = {},
		files = {},
	}

	local ignored = {
		[".git"] = true,
		[".hg"] = true,
		[".svn"] = true,
		["node_modules"] = true,
		["target"] = true,
		["build"] = true,
		["dist"] = true,
		[".venv"] = true,
		["venv"] = true,
		["__pycache__"] = true,
		[".idea"] = true,
		[".vscode"] = true,
	}

	local function Walk(directory, relative)
		local entries = uv.fs_scandir(directory)

		if not entries then
			return
		end

		while true do
			local name, kind = uv.fs_scandir_next(entries)

			if not name then
				break
			end

			if not ignored[name] and name:sub(1, 1) ~= "." then
				local relative_path = relative == "" and name or (relative .. "/" .. name)

				local full_path = Join_Path(directory, name)

				if kind == "directory" then
					if Is_Safe_Relative_Path(relative_path) then
						layout.directories[#layout.directories + 1] = relative_path

						Walk(full_path, relative_path)
					end
				elseif kind == "file" and Is_Safe_Relative_Path(relative_path) then
					local contents = Read_File(full_path)

					if contents ~= nil then
						layout.files[relative_path] = contents
					end
				end
			end
		end
	end

	Walk(root, "")

	return layout
end

function Project.Save_Layout()
	local current = vim.fn.getcwd()

	Input("Layout ID (letters, numbers, '_' or '-'): ", vim.fn.fnamemodify(current, ":t"), function(id)
		id = vim.trim(id or "")

		if not id:match("^[%w_-]+$") then
			Notify("Invalid layout ID.", vim.log.levels.ERROR)
			return
		end

		local layout = Scan_Directory(current)

		Input("Layout display name: ", layout.name, function(name)
			name = vim.trim(name or "")

			if name == "" then
				Notify("Layout name cannot be empty.", vim.log.levels.ERROR)
				return
			end

			layout.name = name

			Input("Description: ", layout.description, function(description)
				layout.description = description or ""

				Confirm("Save layout '" .. id .. "' to HyperMax?", function(save)
					if not save then
						Notify("Layout save cancelled.")
						return
					end

					local ok, err = Layouts.Save(id, layout)

					if not ok then
						Notify("Could not save layout: " .. tostring(err), vim.log.levels.ERROR)
						return
					end

					Notify("Saved layout '" .. id .. "' from " .. current)
				end)
			end)
		end)
	end)
end

return Project
