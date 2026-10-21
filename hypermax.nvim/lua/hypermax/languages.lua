local Managers = require("hypermax.managers")

local Languages = {}

-- =========================================================
-- LANGUAGE FILES
-- =========================================================

local files = {
	-- A
	ada = "main.adb",
	assembly = "main.asm",
	awk = "main.awk",
	apex = "main.cls",
	actionscript = "main.as",

	-- B
	bash = "main.sh",
	basic = "main.bas",
	bc = "main.bc",
	blitzBasic = "main.bb",
	boo = "main.boo",

	-- C
	c = "main.c",
	cpp = "main.cpp",
	csharp = "main.cs",
	clojure = "main.clj",
	cobol = "main.cob",
	crystal = "main.cr",
	cuda = "main.cu",
	coffeescript = "main.coffee",
	commonLisp = "main.lisp",

	-- D
	d = "main.d",
	dart = "main.dart",
	delphi = "main.pas",
	dylan = "main.dylan",

	-- E
	eiffel = "main.e",
	elixir = "main.ex",
	elm = "main.elm",
	erlang = "main.erl",
	erlangHeader = "main.hrl",

	-- F
	factor = "main.factor",
	fennel = "main.fnl",
	forth = "main.fth",
	fortran = "main.f90",
	fsharp = "main.fs",

	-- G
	gleam = "main.gleam",
	glsl = "main.glsl",
	go = "main.go",
	groovy = "main.groovy",
	gml = "main.gml",

	-- H
	hack = "main.hack",
	haskell = "main.hs",
	haxe = "main.hx",
	hlsl = "main.hlsl",
	hy = "main.hy",

	-- I
	icon = "main.icn",
	idris = "main.idr",
	inform = "main.inf",
	io = "main.io",

	-- J
	janet = "main.janet",
	java = "Main.java",
	javaScript = "main.js",
	julia = "main.jl",
	j = "main.ijs",

	-- K
	k = "main.k",
	kotlin = "main.kt",
	koka = "main.kk",

	-- L
	lean = "main.lean",
	less = "main.less",
	lisp = "main.lisp",
	logo = "main.logo",
	lua = "main.lua",

	-- M
	maple = "main.mpl",
	matlab = "main.m",
	mercury = "main.m",
	mojo = "main.mojo",
	move = "main.move",

	-- N
	neon = "main.neon",
	nesC = "main.nc",
	nim = "main.nim",
	nix = "main.nix",

	-- O
	oberon = "main.mod",
	objectiveC = "main.m",
	objectiveCpp = "main.mm",
	ocaml = "main.ml",
	odin = "main.odin",

	-- P
	pascal = "main.pas",
	perl = "main.pl",
	php = "main.php",
	pony = "main.pony",
	processing = "main.pde",
	prolog = "main.pro",
	purescript = "main.purs",
	python = "main.py",

	-- Q
	qsharp = "main.qs",
	qml = "main.qml",
	quakeC = "main.qc",

	-- R
	r = "main.r",
	racket = "main.rkt",
	rexx = "main.rexx",
	roc = "main.roc",
	ruby = "main.rb",
	rust = "main.rs",

	-- S
	scala = "main.scala",
	scheme = "main.scm",
	smalltalk = "main.st",
	solidity = "main.sol",
	sql = "main.sql",
	squirrel = "main.nut",
	swift = "main.swift",

	-- T
	tcl = "main.tcl",
	terra = "main.t",
	typescript = "main.ts",
	typst = "main.typ",

	-- U
	unison = "main.u",
	ur = "main.ur",

	-- V
	vala = "main.vala",
	v = "main.v",
	verilog = "main.v",
	vhdl = "main.vhd",
	vimScript = "main.vim",
	visualBasic = "main.vb",

	-- W
	wren = "main.wren",
	wolfram = "main.wl",

	-- X
	x10 = "main.x10",

	-- Y
	yorick = "main.i",

	-- Z
	zig = "main.zig",
	zsh = "main.zsh",
}

-- =========================================================
-- RUNTIME / COMPILER EXECUTABLES
--
-- These are executable names checked with vim.fn.executable().
-- A missing entry means HyperMax does not yet know which
-- executable to check for that language.
-- =========================================================

local runtimes = {
	ada = "gnatmake",
	assembly = "nasm",
	awk = "awk",
	bash = "bash",
	bc = "bc",
	c = "cc",
	cpp = "c++",
	csharp = "dotnet",
	clojure = "clojure",
	cobol = "cobc",
	crystal = "crystal",
	cuda = "nvcc",
	coffeescript = "coffee",
	commonLisp = "sbcl",
	d = "dmd",
	dart = "dart",
	delphi = "fpc",
	elixir = "elixir",
	elm = "elm",
	erlang = "erl",
	factor = "factor",
	fennel = "fennel",
	fortran = "gfortran",
	fsharp = "dotnet",
	gleam = "gleam",
	go = "go",
	groovy = "groovy",
	haskell = "ghc",
	haxe = "haxe",
	hy = "hy",
	idris = "idris2",
	janet = "janet",
	java = "java",
	javaScript = "node",
	julia = "julia",
	kotlin = "kotlinc",
	koka = "koka",
	lean = "lean",
	lua = "lua",
	mojo = "mojo",
	nim = "nim",
	nix = "nix",
	ocaml = "ocaml",
	odin = "odin",
	perl = "perl",
	php = "php",
	pony = "ponyc",
	prolog = "swipl",
	purescript = "purs",
	python = "python3",
	qsharp = "dotnet",
	r = "R",
	racket = "racket",
	ruby = "ruby",
	rust = "rustc",
	scala = "scala",
	scheme = "guile",
	solidity = "solc",
	swift = "swift",
	tcl = "tclsh",
	typescript = "tsc",
	typst = "typst",
	vala = "valac",
	v = "v",
	vimScript = "vim",
	visualBasic = "dotnet",
	zig = "zig",
	zsh = "zsh",
}

-- =========================================================
-- BUILD THE LANGUAGE REGISTRY
-- =========================================================

Languages.registry = {}

for id, filename in pairs(files) do
	Languages.registry[id] = {
		id = id,
		name = id,
		file = filename,
		executable = runtimes[id],
		managers = Managers.registry[id] or {
			native = {
				name = "Native / no project manager",
			},
		},
	}
end

-- =========================================================
-- PUBLIC FUNCTIONS
-- =========================================================

-- Return every registered language.
function Languages.Get_All()
	return Languages.registry
end

-- Return a language by its registry ID.
function Languages.Get(id)
	return Languages.registry[id]
end

-- Return whether a language is registered.
function Languages.Exists(id)
	return Languages.registry[id] ~= nil
end

-- Return the number of registered languages.
function Languages.Count()
	local count = 0

	for _ in pairs(Languages.registry) do
		count = count + 1
	end

	return count
end

-- Check whether the language's configured executable exists.
--
-- true  = executable exists
-- false = executable is missing
-- nil   = language is unknown or has no configured executable
function Languages.Is_Installed(id)
	local language = Languages.registry[id]

	if not language or not language.executable then
		return nil
	end

	return vim.fn.executable(language.executable) == 1
end

-- Return the configured executable for a language.
function Languages.Get_Executable(id)
	local language = Languages.registry[id]

	if not language then
		return nil
	end

	return language.executable
end

-- Return the default source filename for a language.
function Languages.Get_Default_File(id)
	local language = Languages.registry[id]

	if not language then
		return nil
	end

	return language.file
end

-- Return all registered language IDs in alphabetical order.
function Languages.Get_IDs()
	local ids = {}

	for id in pairs(Languages.registry) do
		ids[#ids + 1] = id
	end

	table.sort(ids)

	return ids
end

return Languages
