local sqlite = require("sqlite.db")
local sqlite_clib = require("sqlite.defs")
local gp = require("gp")
local u = require("gp.utils")
local logger = require("gp.logger")

-- Describes files we've scanned previously to produce the list of symbols
---@class SrcFileEntry
---@field id number: unique id
---@field filename string: path relative to the git/project root
---@field file_size number: -- zie of the file at last scan in bytes
---@field filetype string: filetype as reported by neovim at last scan
---@field mod_time number: last file modification time reported by the os at last scan
---@field last_scan_time number: unix time stamp indicating when the last scan of this file was made
---@field generation? number: For internal use - garbage collection

-- Describes where each of the functions are in the project
---@class SymbolDefEntry
---@field id number: unique id
---@field file string: Which file is the symbol defined?
---@field name string: Name of the symbol
---@field type string: type of the symbol
---@field start_line number: Which line in the file does the definition start?
---@field end_line number: Which line in the file does the definition end?
---@field generation? number: For internal use - garbage collection

---@class Db
---@field db sqlite_db
local Db = {}

--- @return Db
Db._new = function(db)
	return setmetatable({ db = db }, { __index = Db })
end

--- Opens and/or creates a SQLite database for storing symbol definitions.
-- @return Db|nil A new Db object if successful, nil if an error occurs
-- @side-effect Creates .gp directory and database file if they don't exist
-- @side-effect Logs errors if unable to locate project root or create directory
function Db.open()
	local git_root = u.git_root_from_cwd()
	if git_root == "" then
		logger.error("[db.open] Unable to locate project root")
		return nil
	end

	local db_file = u.path_join(git_root, ".gp/index.sqlite")
	if not u.ensure_parent_path_exists(db_file) then
		logger.error("[db.open] Unable create directory for db file: " .. db_file)
		return nil
	end

	---@type sqlite_db
	local db = sqlite({
		uri = db_file,

		-- The `metadata` table is a simple KV store
		metadata = {
			id = true,
			key = { type = "text", required = true, unique = true },
			value = { type = "luatable", required = true },
		},

		-- The `src_files` table stores a list of known src files and the last time they were scanned
		src_files = {
			id = true,
			filename = { type = "text", required = true }, -- relative to the git/project root
			file_size = { type = "integer", required = true }, -- size of the file at last scan
			filetype = { type = "text", required = true }, -- filetype as reported by neovim at last scan
			mod_time = { type = "integer", required = true }, -- file mod time reported by the fs at last scan
			last_scan_time = { type = "integer", required = true }, -- unix timestamp
			generation = { type = "integer" }, -- for garbage collection
		},

		symbols = {
			id = true,
			file = { type = "text", require = true, reference = "src_files.filename", on_delete = "cascade" },
			name = { type = "text", required = true },
			type = { type = "text", required = true },
			start_line = { type = "integer", required = true },
			end_line = { type = "integer", required = true },
			generation = { type = "integer" }, -- for garbage collection
		},

		opts = { keep_open = true },
	})

	db:eval("CREATE UNIQUE INDEX IF NOT EXISTS idx_src_files_filename ON src_files (filename);")
	db:eval("CREATE UNIQUE INDEX IF NOT EXISTS idx_symbol_file_n_name ON symbols (file, name);")

	return Db._new(db)
end

--- Gathers information on a file to populate most of a SrcFileEntry.
--- @return SrcFileEntry|nil
function Db.collect_src_file_data(relative_path)
	local uv = vim.uv or vim.loop

	-- Construct the full path to the file
	local proj_root = u.git_root_from_cwd()
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
        INSERT INTO src_files (filename, file_size, filetype, mod_time, last_scan_time, generation)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(filename) DO UPDATE SET
            file_size = excluded.file_size,
            filetype = excluded.filetype,
            mod_time = excluded.mod_time,
            last_scan_time = excluded.last_scan_time,
            generation = excluded.generation
        WHERE filename = ?
    ]]

	local success = self.db:eval(sql, {
		-- For the INSERT VALUES clause
		file.filename,
		file.file_size,
		file.filetype,
		file.mod_time,
		file.last_scan_time,
		file.generation or -1,

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

-- Upserts a single symbol entry into the database
--- @param def SymbolDefEntry
function Db:upsert_symbol(def)
	if not self.db then
		logger.error("[db.upsert_symbol] Database not initialized")
		return false
	end

	---WARNING: Do not use ORM here.
	-- This function can be called a lot during a full index rebuild.
	-- Using the ORM here can cause a 100% slowdown.
	local sql = [[
        INSERT INTO symbols (file, name, type, start_line, end_line, generation)
        VALUES (?, ?, ?, ?, ?, ?)
        ON CONFLICT(file, name) DO UPDATE SET
			type = excluded.type,
            start_line = excluded.start_line,
            end_line = excluded.end_line,
			generation = excluded.generation
        WHERE file = ? AND name = ?
    ]]

	local success = self.db:eval(sql, {
		-- For the INSERT VALUES clause
		def.file,
		def.name,
		def.type,
		def.start_line,
		def.end_line,
		def.generation or -1,

		-- For the WHERE clause
		def.file,
		def.name,
	})

	if not success then
		logger.error("[db.upsert_symbol] Failed to upsert symbol: " .. def.name .. " for file: " .. def.file)
		return false
	end

	return true
end

-- Wraps the given function in a sqlite transaction
---@param fn function()
function Db:with_transaction(fn)
	local success, result

	success = self.db:execute("BEGIN")
	if not success then
		logger.error("[db.with_transaction] Unable to start transaction")
		return false
	end

	success, result = pcall(fn)
	if not success then
		logger.error("[db.with_transaction] fn return false")
		logger.error(result)

		success = self.db:execute("ROLLBACK")
		if not success then
			logger.error("[db.with_transaction] Rollback failed")
		end
		return false
	end

	success = self.db:execute("COMMIT")
	if not success then
		logger.error("[db.with_transaction] Unable to end transaction")
		return false
	end

	return true
end

--- @param symbols_list SymbolDefEntry[]
function Db:upsert_and_clean_symbol_list_for_file(src_rel_path, symbols_list)
	-- Generate a random generation ID for all tne newly updated/refreshed items
	local generation = u.random_8byte_int()
	for _, item in ipairs(symbols_list) do
		item.generation = generation
	end

	-- Upsert all entries
	local success = self:upsert_symbol_list(symbols_list)
	if not success then
		return success
	end

	-- Remove all symbols in the file that does not hav the new generation ID
	-- Those symbols are not present in the newly generated list and should be removed.
	success = self.db:eval([[DELETE from symbols WHERE file = ? and generation != ? ]], { src_rel_path, generation })
	if not success then
		logger.error("[db.insert_and_clean_symbol_list_for_file] Unable to clean up garbage")
		return success
	end

	return true
end

--- Updates the dastabase with the contents of the `symbols_list`
--- Note that this function early terminates if any of the entry upsert fails.
--- This behavior is only suitable when run inside a transaction.
--- @param symbols_list SymbolDefEntry[]
function Db:upsert_symbol_list(symbols_list)
	for _, def in ipairs(symbols_list) do
		local success = self:upsert_symbol(def)
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

function Db:find_symbol_by_name(partial_fn_name)
	local sql = [[
		SELECT * FROM symbols WHERE name LIKE ?
    ]]

	local wildcard_name = "%" .. partial_fn_name .. "%"

	local result = self.db:eval(sql, {
		wildcard_name,
	})

	-- We're expecting the query to return a list of SymbolDefEntry.
	-- If we get a boolean back instead, we consider the operation to have failed.
	if type(result) == "boolean" then
		return nil
	end

	---@cast result SymbolDefEntry
	return result
end

function Db:find_symbol_by_file_n_name(rel_path, full_fn_name)
	local sql = [[
		SELECT * FROM symbols WHERE file = ? AND name = ?
    ]]

	local result = self.db:eval(sql, {
		rel_path,
		full_fn_name,
	})

	-- We're expecting the query to return a list of SymbolDefEntry.
	-- If we get a boolean back instead, we consider the operation to have failed.
	if type(result) == "boolean" then
		return nil
	end

	---@cast result SymbolDefEntry[]
	if #result > 1 then
		logger.error(
			string.format(
				"[Db.find_symbol_by_file_n_name] Found more than 1 result for: '%s', '%s'",
				rel_path,
				full_fn_name
			)
		)
	end

	return result[1]
end

-- Removes a single entry from the src_files table given a relative file path
-- Note that related entries in the symbols table will be removed via CASCADE.
---@param src_filepath string
function Db:remove_src_file_entry(src_filepath)
	local sql = [[
		DELETE FROM src_files WHERE filename = ?
    ]]

	local result = self.db:eval(sql, {
		src_filepath,
	})

	return result
end

function Db:clear()
	self.db:eval("DELETE FROM symbols")
	self.db:eval("DELETE FROM src_files")
end

-- Gets the value of a key from the metadata table
---@param keyname string
---@return any
function Db:get_metadata(keyname)
	local result = self.db.metadata:where({ key = keyname })
	if result then
		return result.value
	end
end

-- Sets the value of a key in the metadata table
-- WARNING: value cannot be of a number type
---@param keyname string
---@param value any
function Db:set_metadata(keyname, value)
	-- The sqlite.lua plugin doesn't seem to like having numbers stored in the a field
	-- marked as the "luatable" or "json" type.
	-- If we store a number into the value field, sqlite.lua will throw a parse error on get.
	if type(value) == "number" then
		error("database metadata table doesn't not support storing a number as a root value")
	end
	return self.db.metadata:update({ where = { key = keyname }, set = { value = value } })
end

return Db
