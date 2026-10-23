local Managers = {}

-- =========================================================
-- PROJECT MANAGER REGISTRY
--
-- Structure:
--
-- language_id = {
--     manager_id = {
--         name = "Display name",
--         executable = "command to check",
--     },
-- }
--
-- `native` means no separate project manager is required.
-- An absent executable means no executable check is performed.
-- =========================================================

Managers.registry = {

	-- =====================================================
	-- A
	-- =====================================================

	ada = {
		native = { name = "GNAT Native" },
		alire = { name = "Alire", executable = "alr" },
	},

	assembly = {
		native = { name = "NASM / Assembler" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	apex = {
		native = { name = "Salesforce Apex" },
		sf = { name = "Salesforce CLI", executable = "sf" },
	},

	actionscript = {
		native = { name = "ActionScript" },
		mxmlc = { name = "Apache Flex SDK", executable = "mxmlc" },
	},

	awk = {
		native = { name = "AWK Script" },
	},

	-- =====================================================
	-- B
	-- =====================================================

	bash = {
		native = { name = "Bash Script" },
		make = { name = "Make", executable = "make" },
	},

	basic = {
		native = { name = "BASIC" },
		freebasic = { name = "FreeBASIC", executable = "fbc" },
	},

	bc = {
		native = { name = "bc Script" },
	},

	blitzBasic = {
		native = { name = "BlitzBasic" },
	},

	boo = {
		native = { name = "Boo" },
	},

	-- =====================================================
	-- C
	-- =====================================================

	c = {
		native = { name = "Native C" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
		meson = { name = "Meson", executable = "meson" },
		xmake = { name = "xmake", executable = "xmake" },
		bazel = { name = "Bazel", executable = "bazel" },
	},

	cpp = {
		native = { name = "Native C++" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
		meson = { name = "Meson", executable = "meson" },
		xmake = { name = "xmake", executable = "xmake" },
		bazel = { name = "Bazel", executable = "bazel" },
		premake = { name = "Premake", executable = "premake5" },
	},

	csharp = {
		native = { name = ".NET", executable = "dotnet" },
		nuget = { name = "NuGet / .NET", executable = "dotnet" },
	},

	clojure = {
		native = { name = "Clojure CLI", executable = "clojure" },
		deps = { name = "Clojure CLI / deps.edn", executable = "clojure" },
		lein = { name = "Leiningen", executable = "lein" },
		boot = { name = "Boot", executable = "boot" },
	},

	cobol = {
		native = { name = "GnuCOBOL", executable = "cobc" },
		make = { name = "Make", executable = "make" },
	},

	crystal = {
		native = { name = "Crystal" },
		shards = { name = "Shards", executable = "shards" },
	},

	cuda = {
		native = { name = "CUDA Toolkit", executable = "nvcc" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	coffeescript = {
		native = { name = "CoffeeScript", executable = "coffee" },
		npm = { name = "npm", executable = "npm" },
		pnpm = { name = "pnpm", executable = "pnpm" },
		yarn = { name = "Yarn", executable = "yarn" },
		bun = { name = "Bun", executable = "bun" },
	},

	commonLisp = {
		native = { name = "Common Lisp / SBCL", executable = "sbcl" },
		quicklisp = { name = "Quicklisp" },
		asdf = { name = "ASDF" },
	},

	-- =====================================================
	-- D
	-- =====================================================

	d = {
		native = { name = "D Compiler" },
		dub = { name = "DUB", executable = "dub" },
		make = { name = "Make", executable = "make" },
	},

	dart = {
		native = { name = "Dart", executable = "dart" },
		pub = { name = "Dart Pub", executable = "dart" },
	},

	delphi = {
		native = { name = "Free Pascal", executable = "fpc" },
		lazarus = { name = "Lazarus", executable = "lazbuild" },
	},

	dylan = {
		native = { name = "Open Dylan", executable = "dylan" },
	},

	-- =====================================================
	-- E
	-- =====================================================

	eiffel = {
		native = { name = "Eiffel Compiler" },
	},

	elixir = {
		native = { name = "Elixir", executable = "elixir" },
		mix = { name = "Mix", executable = "mix" },
	},

	elm = {
		native = { name = "Elm", executable = "elm" },
	},

	erlang = {
		native = { name = "Erlang", executable = "erl" },
		rebar3 = { name = "Rebar3", executable = "rebar3" },
		erlangMk = { name = "erlang.mk", executable = "make" },
	},

	erlangHeader = {
		native = { name = "Erlang Header" },
	},

	-- =====================================================
	-- F
	-- =====================================================

	factor = {
		native = { name = "Factor", executable = "factor" },
	},

	fennel = {
		native = { name = "Fennel", executable = "fennel" },
		luarocks = { name = "LuaRocks", executable = "luarocks" },
	},

	forth = {
		native = { name = "Forth" },
		gforth = { name = "Gforth", executable = "gforth" },
	},

	fortran = {
		native = { name = "Fortran" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
		meson = { name = "Meson", executable = "meson" },
	},

	fsharp = {
		native = { name = ".NET F#", executable = "dotnet" },
		nuget = { name = "NuGet / .NET", executable = "dotnet" },
	},

	-- =====================================================
	-- G
	-- =====================================================

	gleam = {
		native = { name = "Gleam", executable = "gleam" },
		rebar3 = { name = "Rebar3", executable = "rebar3" },
	},

	glsl = {
		native = { name = "GLSL Shader" },
		glslang = { name = "glslang", executable = "glslangValidator" },
		shaderc = { name = "Shaderc", executable = "glslc" },
	},

	go = {
		native = { name = "Go Modules", executable = "go" },
		goWork = { name = "Go Workspaces", executable = "go" },
	},

	groovy = {
		native = { name = "Groovy", executable = "groovy" },
		gradle = { name = "Gradle", executable = "gradle" },
	},

	gml = {
		native = { name = "GameMaker Language" },
	},

	-- =====================================================
	-- H
	-- =====================================================

	hack = {
		native = { name = "Hack", executable = "hhvm" },
		composer = { name = "Composer", executable = "composer" },
	},

	haskell = {
		native = { name = "GHC", executable = "ghc" },
		cabal = { name = "Cabal", executable = "cabal" },
		stack = { name = "Stack", executable = "stack" },
	},

	haxe = {
		native = { name = "Haxe", executable = "haxe" },
		haxelib = { name = "Haxelib", executable = "haxelib" },
	},

	hlsl = {
		native = { name = "HLSL Shader" },
		dxc = { name = "DirectX Shader Compiler", executable = "dxc" },
		glslang = { name = "glslang", executable = "glslangValidator" },
	},

	hy = {
		native = { name = "Hy", executable = "hy" },
		pip = { name = "Python pip", executable = "pip3" },
	},

	-- =====================================================
	-- I
	-- =====================================================

	icon = {
		native = { name = "Icon Language" },
	},

	idris = {
		native = { name = "Idris 2", executable = "idris2" },
		pack = { name = "Idris Pack", executable = "pack" },
	},

	inform = {
		native = { name = "Inform 7" },
		inform7 = { name = "Inform 7 Compiler", executable = "inform7" },
	},

	io = {
		native = { name = "Io Language" },
	},

	-- =====================================================
	-- J
	-- =====================================================

	janet = {
		native = { name = "Janet", executable = "janet" },
		jpm = { name = "JPM", executable = "jpm" },
	},

	java = {
		native = { name = "Standard Java", executable = "java" },
		maven = { name = "Maven", executable = "mvn" },
		gradle = { name = "Gradle", executable = "gradle" },
	},

	javaScript = {
		native = { name = "Node.js", executable = "node" },
		npm = { name = "npm", executable = "npm" },
		pnpm = { name = "pnpm", executable = "pnpm" },
		yarn = { name = "Yarn", executable = "yarn" },
		bun = { name = "Bun", executable = "bun" },
	},

	julia = {
		native = { name = "Julia", executable = "julia" },
		pkg = { name = "Julia Pkg", executable = "julia" },
	},

	j = {
		native = { name = "J Language" },
	},

	-- =====================================================
	-- K
	-- =====================================================

	k = {
		native = { name = "K Language" },
	},

	kotlin = {
		native = { name = "Kotlin", executable = "kotlinc" },
		gradle = { name = "Gradle", executable = "gradle" },
		maven = { name = "Maven", executable = "mvn" },
	},

	koka = {
		native = { name = "Koka", executable = "koka" },
	},

	-- =====================================================
	-- L
	-- =====================================================

	lean = {
		native = { name = "Lean", executable = "lean" },
		lake = { name = "Lake", executable = "lake" },
	},

	less = {
		native = { name = "Less", executable = "lessc" },
		npm = { name = "npm", executable = "npm" },
	},

	lisp = {
		native = { name = "Common Lisp", executable = "sbcl" },
		quicklisp = { name = "Quicklisp" },
		asdf = { name = "ASDF" },
	},

	logo = {
		native = { name = "Logo" },
	},

	lua = {
		native = { name = "Standard Lua", executable = "lua" },
		luarocks = { name = "LuaRocks", executable = "luarocks" },
	},

	-- =====================================================
	-- M
	-- =====================================================

	maple = {
		native = { name = "Maple" },
	},

	matlab = {
		native = { name = "MATLAB", executable = "matlab" },
	},

	mercury = {
		native = { name = "Mercury", executable = "mmc" },
		mmake = { name = "mmake", executable = "mmake" },
	},

	mojo = {
		native = { name = "Mojo", executable = "mojo" },
	},

	move = {
		native = { name = "Move" },
		aptos = { name = "Aptos CLI", executable = "aptos" },
		sui = { name = "Sui CLI", executable = "sui" },
	},

	-- =====================================================
	-- N
	-- =====================================================

	neon = {
		native = { name = "NEON Configuration" },
	},

	nesC = {
		native = { name = "nesC" },
		make = { name = "Make", executable = "make" },
	},

	nim = {
		native = { name = "Nim", executable = "nim" },
		nimble = { name = "Nimble", executable = "nimble" },
	},

	nix = {
		native = { name = "Nix", executable = "nix" },
		flakes = { name = "Nix Flakes", executable = "nix" },
	},

	-- =====================================================
	-- O
	-- =====================================================

	oberon = {
		native = { name = "Oberon" },
	},

	objectiveC = {
		native = { name = "Objective-C" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	objectiveCpp = {
		native = { name = "Objective-C++" },
		make = { name = "Make", executable = "make" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	ocaml = {
		native = { name = "OCaml", executable = "ocaml" },
		dune = { name = "Dune", executable = "dune" },
		opam = { name = "opam", executable = "opam" },
	},

	odin = {
		native = { name = "Odin", executable = "odin" },
		ols = { name = "Odin Language Server", executable = "ols" },
	},

	-- =====================================================
	-- P
	-- =====================================================

	pascal = {
		native = { name = "Free Pascal", executable = "fpc" },
		lazarus = { name = "Lazarus", executable = "lazbuild" },
	},

	perl = {
		native = { name = "Perl", executable = "perl" },
		cpan = { name = "CPAN", executable = "cpan" },
		cpanm = { name = "cpanm", executable = "cpanm" },
	},

	php = {
		native = { name = "PHP", executable = "php" },
		composer = { name = "Composer", executable = "composer" },
	},

	pony = {
		native = { name = "Pony", executable = "ponyc" },
		corral = { name = "Corral", executable = "corral" },
	},

	processing = {
		native = { name = "Processing" },
	},

	prolog = {
		native = { name = "SWI-Prolog", executable = "swipl" },
		pack = { name = "SWI-Prolog Packs", executable = "swipl" },
	},

	purescript = {
		native = { name = "PureScript", executable = "purs" },
		spago = { name = "Spago", executable = "spago" },
	},

	python = {
		native = { name = "Standard Python", executable = "python3" },
		venv = { name = "Python venv", executable = "python3" },
		uv = { name = "uv", executable = "uv" },
		poetry = { name = "Poetry", executable = "poetry" },
		pipenv = { name = "Pipenv", executable = "pipenv" },
		conda = { name = "Conda", executable = "conda" },
		hatch = { name = "Hatch", executable = "hatch" },
		pdm = { name = "PDM", executable = "pdm" },
	},

	-- =====================================================
	-- Q
	-- =====================================================

	qsharp = {
		native = { name = "Q# / .NET", executable = "dotnet" },
		nuget = { name = "NuGet / .NET", executable = "dotnet" },
	},

	qml = {
		native = { name = "Qt QML", executable = "qml" },
		qmake = { name = "qmake", executable = "qmake" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	quakeC = {
		native = { name = "QuakeC" },
	},

	-- =====================================================
	-- R
	-- =====================================================

	r = {
		native = { name = "R", executable = "R" },
		renv = { name = "renv", executable = "R" },
	},

	racket = {
		native = { name = "Racket", executable = "racket" },
		raco = { name = "Raco", executable = "raco" },
	},

	rexx = {
		native = { name = "REXX" },
	},

	roc = {
		native = { name = "Roc", executable = "roc" },
	},

	ruby = {
		native = { name = "Ruby", executable = "ruby" },
		bundler = { name = "Bundler", executable = "bundle" },
		rake = { name = "Rake", executable = "rake" },
	},

	rust = {
		native = { name = "rustc", executable = "rustc" },
		cargo = { name = "Cargo", executable = "cargo" },
	},

	-- =====================================================
	-- S
	-- =====================================================

	scala = {
		native = { name = "Scala", executable = "scala" },
		scalaCli = { name = "Scala CLI", executable = "scala" },
		sbt = { name = "sbt", executable = "sbt" },
		mill = { name = "Mill", executable = "mill" },
	},

	scheme = {
		native = { name = "Guile Scheme", executable = "guile" },
		racket = { name = "Racket", executable = "racket" },
	},

	smalltalk = {
		native = { name = "Smalltalk" },
	},

	solidity = {
		native = { name = "Solidity", executable = "solc" },
		hardhat = { name = "Hardhat", executable = "npx" },
		foundry = { name = "Foundry", executable = "forge" },
	},

	sql = {
		native = { name = "SQL Script" },
		sqlite = { name = "SQLite", executable = "sqlite3" },
		postgres = { name = "PostgreSQL", executable = "psql" },
		mysql = { name = "MySQL", executable = "mysql" },
	},

	squirrel = {
		native = { name = "Squirrel" },
	},

	swift = {
		native = { name = "Swift", executable = "swift" },
		spm = { name = "Swift Package Manager", executable = "swift" },
	},

	-- =====================================================
	-- T
	-- =====================================================

	tcl = {
		native = { name = "Tcl", executable = "tclsh" },
	},

	terra = {
		native = { name = "Terra" },
	},

	typescript = {
		native = { name = "TypeScript", executable = "tsc" },
		npm = { name = "npm", executable = "npm" },
		pnpm = { name = "pnpm", executable = "pnpm" },
		yarn = { name = "Yarn", executable = "yarn" },
		bun = { name = "Bun", executable = "bun" },
	},

	typst = {
		native = { name = "Typst", executable = "typst" },
	},

	-- =====================================================
	-- U
	-- =====================================================

	unison = {
		native = { name = "Unison" },
	},

	ur = {
		native = { name = "Ur/Web" },
	},

	-- =====================================================
	-- V
	-- =====================================================

	vala = {
		native = { name = "Vala", executable = "valac" },
		meson = { name = "Meson", executable = "meson" },
		cmake = { name = "CMake", executable = "cmake" },
	},

	v = {
		native = { name = "V", executable = "v" },
	},

	verilog = {
		native = { name = "Verilog" },
		iverilog = { name = "Icarus Verilog", executable = "iverilog" },
		verilator = { name = "Verilator", executable = "verilator" },
	},

	vhdl = {
		native = { name = "VHDL" },
		ghdl = { name = "GHDL", executable = "ghdl" },
	},

	vimScript = {
		native = { name = "Vim Script", executable = "vim" },
	},

	visualBasic = {
		native = { name = "Visual Basic / .NET", executable = "dotnet" },
	},

	-- =====================================================
	-- W
	-- =====================================================

	wren = {
		native = { name = "Wren" },
	},

	wolfram = {
		native = { name = "Wolfram Language" },
	},

	-- =====================================================
	-- X
	-- =====================================================

	x10 = {
		native = { name = "X10" },
	},

	-- =====================================================
	-- Y
	-- =====================================================

	yorick = {
		native = { name = "Yorick" },
	},

	-- =====================================================
	-- Z
	-- =====================================================

	zig = {
		native = { name = "Zig", executable = "zig" },
		zon = { name = "Zig package/build support", executable = "zig" },
	},

	zsh = {
		native = { name = "Zsh Script", executable = "zsh" },
	},
}

-- =========================================================
-- PUBLIC FUNCTIONS
-- =========================================================

-- Get the managers for a language.
function Managers.Get_For_Language(language_id)
	return Managers.registry[language_id] or {
		native = {
			name = "Native / no project manager",
		},
	}
end

-- Get a specific manager for a language.
function Managers.Get(language_id, manager_id)
	local language_managers = Managers.registry[language_id]

	if not language_managers then
		return nil
	end

	return language_managers[manager_id]
end

-- Check whether a manager's executable is installed.
--
-- true  = executable exists
-- false = executable is missing
-- nil   = manager has no executable check
function Managers.Is_Installed(language_id, manager_id)
	local manager = Managers.Get(language_id, manager_id)

	if not manager or not manager.executable then
		return nil
	end

	return vim.fn.executable(manager.executable) == 1
end

-- Return manager IDs in alphabetical order.
function Managers.Get_IDs(language_id)
	local result = {}
	local language_managers = Managers.Get_For_Language(language_id)

	for id in pairs(language_managers) do
		result[#result + 1] = id
	end

	table.sort(result)

	return result
end

-- Return manager entries suitable for a selection menu.
function Managers.Get_Choices(language_id)
	local result = {}
	local language_managers = Managers.Get_For_Language(language_id)

	for id, manager in pairs(language_managers) do
		result[#result + 1] = {
			id = id,
			name = manager.name,
			executable = manager.executable,
			installed = manager.executable and vim.fn.executable(manager.executable) == 1 or nil,
		}
	end

	table.sort(result, function(a, b)
		return a.name:lower() < b.name:lower()
	end)

	return result
end

-- Check whether a manager ID exists for a language.
function Managers.Exists(language_id, manager_id)
	local language_managers = Managers.registry[language_id]

	return language_managers ~= nil and language_managers[manager_id] ~= nil
end

return Managers
