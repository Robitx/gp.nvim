local sqlite = require("sqlite.db")
local sqlite_clib = require("sqlite.defs")
local gp = require("gp")
local u = require("gp.utils")
local logger = require("gp.logger")

-- Describes files we've scanned previously to produce the list of function definitions
---@class SrcFileEntry
---@field id number: unique id
---@field filename string: path relative to the git/project root
---@field file_size number: -- zie of the file at last scan in bytes
---@field filetype string: filetype as reported by neovim at last scan
---@field mod_time number: last file modification time reported by the os at last scan
---@field last_scan_time number: unix time stamp indicating when the last scan of this file was made

-- Describes where each of the functions are in the project
---@class FunctionDefEntry
---@field id number: unique id
---@field name string: Name of the function
---@field file string: In which file is the function defined?
---@field start_line number: Which line in the file does the definition start?
---@field end_line number: Which line in the file does the definition end?

---@class Db
---@field db sqlite_db
local Db = {}

--- @return Db
Db._new = function(db)
	return setmetatable({ db = db }, { __index = Db })
end

--- Opens and/or creates a SQLite database for storing function definitions.
-- @return Db|nil A new Db object if successful, nil if an error occurs
-- @side-effect Creates .gp directory and database file if they don't exist
-- @side-effect Logs errors if unable to locate project root or create directory
function Db.open()
	local git_root = gp._H.find_git_root()
	if git_root == "" then
		logger.error("[db.open] Unable to locate project root")
		return nil
	end

	local db_file = u.path_join(git_root, ".gp/function_defs.sqlite")
	if not u.ensure_parent_path_exists(db_file) then
		logger.error("[db.open] Unable create directory for db file: " .. db_file)
		return nil
	end

	local db = sqlite({
		uri = db_file,

		-- The `src_files` table stores a list of known src files and the last time they were scanned
		src_files = {
			id = true,
			filename = { type = "text", required = true }, -- relative to the git/project root
			file_size = { type = "integer", required = true }, -- size of the file at last scan
			filetype = { type = "text", required = true }, -- filetype as reported by neovim at last scan
			mod_time = { type = "integer", required = true }, -- file mod time reported by the fs at last scan
			last_scan_time = { type = "integer", required = true }, -- unix timestamp
		},

		opts = { keep_open = true },
	})

	db:eval("PRAGMA foreign_keys = ON;")

	-- sqlite.lua doesn't seem to support adding random table options
	-- In this case, being able to perform an upsert in the function_defs table depends on
	-- having UNIQUE file and fn name pair.
	db:eval([[
		CREATE TABLE IF NOT EXISTS function_defs (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			file TEXT NOT NULL REFERENCES src_files(filename) on DELETE CASCADE,
			name TEXT NOT NULL,
			start_line INTEGER NOT NULL,
			end_line INTEGER NOT NULL,
			UNIQUE (file, name)
		);
	]])

	db:eval("CREATE UNIQUE INDEX IF NOT EXISTS idx_src_files_filename ON src_files (filename);")

	return Db._new(db)
end

--- Gathers information on a file to populate most of a SrcFileEntry.
--- @return SrcFileEntry|nil
function Db.collect_src_file_data(relative_path)
	local uv = vim.uv or vim.loop

	-- Construct the full path to the file
	local proj_root = gp._H.find_git_root()
	local fullpath = u.path_join(proj_root, relative_path)

	-- If the file doesn't exist, there is nothing to collect
	local stat = uv.fs_stat(fullpath)
	if not stat then
		logger.debug("[Db.collection_src_file_data] failed: " .. relative_path)
		return nil
	end

	local entry = {}

	entry.filename = relative_path
	entry.file_size = stat.size
	entry.filetype = vim.filetype.match({ filename = fullpath })
	entry.mod_time = stat.mtime.sec

	return entry
end

-- Upserts a single src file entry into the database
--- @param file SrcFileEntry
function Db:upsert_src_file(file)
	if not self.db then
		logger.error("[db.upsert_src_file] Database not initialized")
		return false
	end

	local sql = [[
        INSERT INTO src_files (filename, file_size, filetype, mod_time, last_scan_time)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT(filename) DO UPDATE SET
            file_size = excluded.file_size,
            filetype = excluded.filetype,
            mod_time = excluded.mod_time,
            last_scan_time = excluded.last_scan_time
        WHERE filename = ?
    ]]

	local success = self.db:eval(sql, {
		-- For the INSERT VALUES clause
		file.filename,
		file.file_size,
		file.filetype,
		file.mod_time,
		file.last_scan_time,

		-- For the WHERE claue
		file.filename,
	})

	if not success then
		logger.error("[db.upsert_src_file] Failed to upsert file: " .. file.filename)
		return false
	end

	return true
end

--- @param filelist SrcFileEntry[]
function Db:upsert_filelist(filelist)
	for _, file in ipairs(filelist) do
		local success = self:upsert_src_file(file)
		if not success then
			logger.error("[db.upsert_filelist] Failed to upsert file list")
			return false
		end
	end

	return true
end

-- Upserts a single function def entry into the database
--- @param def FunctionDefEntry
function Db:upsert_function_def(def)
	if not self.db then
		logger.error("[db.upsert_function_def] Database not initialized")
		return false
	end

	local sql = [[
        INSERT INTO function_defs (file, name, start_line, end_line)
        VALUES (?, ?, ?, ?)
        ON CONFLICT(file, name) DO UPDATE SET
            start_line = excluded.start_line,
            end_line = excluded.end_line
        WHERE file = ? AND name = ?
    ]]

	local success = self.db:eval(sql, {
		-- For the INSERT VALUES clause
		def.file,
		def.name,
		def.start_line,
		def.end_line,

		-- For the WHERE clause
		def.file,
		def.name,
	})

	if not success then
		logger.error("[db.upsert_function_def] Failed to upsert function: " .. def.name .. " for file: " .. def.file)
		return false
	end

	return true
end

-- Wraps the given function in a sqlite transaction
---@param fn function()
function Db:with_transaction(fn)
	self.db:execute("BEGIN")
	local success, result = pcall(fn)
	self.db:execute("END")

	if not success then
		logger.error(result)
		return false
	end
	return true
end

--- Updates the dastabase with the contents of the `fnlist`
--- Note that this function early terminates of any of the entry upsert fails.
--- This behavior is only suitable when run inside a transaction.
--- @param fnlist FunctionDefEntry[]
function Db:upsert_fnlist(fnlist)
	for _, def in ipairs(fnlist) do
		local success = self:upsert_function_def(def)
		if not success then
			logger.error("[db.upsert_fnlist] Failed to upsert function def list")
			return false
		end
	end

	return true
end

function Db:close()
	self.db:close()
end

function Db:find_fn_def_by_name(partial_fn_name)
	local sql = [[
		SELECT * FROM function_defs WHERE name LIKE ?
    ]]

	local wildcard_name = "%" .. partial_fn_name .. "%"

	local result = self.db:eval(sql, {
		wildcard_name,
	})

	-- We're expecting the query to return a list of FunctionDefEntry.
	-- If we get a boolean back instead, we consider the operation to have failed.
	if type(result) == "boolean" then
		return nil
	end

	---@cast result FunctionDefEntry
	return result
end

return Db
