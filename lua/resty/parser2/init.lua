local kv = require("resty.parser2.key_value")
local mu = require("resty.parser2.method_url")
local by = require("resty.parser2.body")

local M = {}
M.__index = M

M.STATE_START = 1
M.STATE_VARIABLE = kv.STATE_VARIABLE -- 2
M.STATE_DELIMITER = 3
M.STATE_METHOD_URL = mu.STATE_METHOD_URL -- 4
M.STATE_HEADERS_QUERY = kv.STATE_HEADERS_QUERY -- 5
M.STATE_BODY = by.STATE_BODY -- 6

---is a token_start for a new starting rest call
local token_DELIMITER = "###"
---is the token for comments
local token_COMMENT = "#"

---token_end is optional, is it necessary if the buffer contains more rows
---otherwise is the end of the buffer the end of parsing
-- local token_END = "---"

local function ignore_line(line)
	if vim.startswith(line, token_DELIMITER) then
		return false
	-- comment
	elseif vim.startswith(line, token_COMMENT) then
		return true
	-- empty line
	elseif line == "" or vim.trim(line) == "" then
		return true
	else
		return false
	end
end

local function parse_delimiter(p, line)
	if not vim.startswith(line, token_DELIMITER) then
		return nil
	end

	p.current_state = M.STATE_DELIMITER
	return true
end

--[[ 

states: start, gvariable, delimiter, method_url, lvariable, headers_query, body, error
comment == ignore

-- global variable
variable -> variable		*

start -> delimiter		*
start -> method_url		*

delimiter -> variable		*
delimiter -> method_url		*

-- local variable
variable -> variable		*
variable -> delimiter		*
variable -> method_url		*

method_url-> headers_query	*
method_url-> body		*
method_url-> end

headers_query -> headers_query	*
headers_query -> body		*
headers_query -> end

body -> body			*
body -> end

]]

local state_machine = {
	[M.STATE_START] = {
		to = function(p, line)
			if parse_delimiter(p, line) or mu.parse_method_url(p, line) then
				return true
			end
		end,
	},
	[M.STATE_VARIABLE] = {
		to = function(p, line)
			if kv.parse_variable(p, line) or parse_delimiter(p, line) or mu.parse_method_url(p, line) then
				return true
			end
		end,
	},
	[M.STATE_DELIMITER] = {
		to = function(p, line)
			if kv.parse_variable(p, line) or mu.parse_method_url(p, line) then
				return true
			end
		end,
	},
	[M.STATE_METHOD_URL] = {
		to = function(p, line)
			if kv.parse_headers_query(p, line) or by.parse_body(p, line) then
				return true
			end
		end,
	},
	[M.STATE_HEADERS_QUERY] = {
		to = function(p, line)
			if kv.parse_headers_query(p, line) or by.parse_body(p, line) then
				return true
			end
		end,
	},
	[M.STATE_BODY] = {
		to = function(p, line)
			if by.parse_body(p, line) then
				return true
			end
		end,
	},
}

local function input_to_lines(input)
	if type(input) == "table" then
		return input
	elseif type(input) == "string" then
		return vim.split(input, "\n")
	else
		error("only string or string array are supported as input. Got: " .. type(input))
	end
end

M.new = function()
	local p = {
		current_state = M.STATE_START,
		readed_lines = 1,
		duration = 0,
		body_is_ready = false,
		global_variables = {},
		request = {},
		errors = {},
	}
	return setmetatable(p, M)
end

function M:has_errors()
	return self.errors ~= nil and #self.errors > 0
end

function M:add_error(message)
	table.insert(self.errors, {
		col = 0,
		lnum = self.readed_lines,
		severity = vim.diagnostic.severity.ERROR,
		message = message,
	})
	return self
end

function M.find_req_def(lines, selected, readed_lines)
	readed_lines = readed_lines or 1

	local bad_selected = false
	if readed_lines > selected then
		selected = readed_lines
		bad_selected = true
	end

	local start_req_def = selected

	while true do
		local line = lines[start_req_def]
		if not line then
			start_req_def = start_req_def + 1
			break
		elseif vim.startswith(line, token_DELIMITER) then
			if bad_selected then
				return 0, 0
			end
			break
		elseif start_req_def == readed_lines then
			break
		end
		start_req_def = start_req_def - 1
	end

	local end_req_def = selected + 1
	while true do
		local line = lines[end_req_def]
		if not line or vim.startswith(line, token_DELIMITER) then
			end_req_def = end_req_def - 1
			break
		end
		end_req_def = end_req_def + 1
	end

	return start_req_def, end_req_def
end

---Entry point, the parser
---@param input string | { }
---@param selected number
function M:parse(input, selected)
	local lines = input_to_lines(input)
	if selected > #lines then
		return self:add_error("the selected row: " .. selected .. " is greater then the given rows: " .. #lines)
	end

	-- parse global variables
	while true do
		local line = lines[self.readed_lines]
		if not line then
			self.readed_lines = self.readed_lines - 1
			break
		elseif kv.parse_variable(self, line) or ignore_line(line) then
			self.readed_lines = self.readed_lines + 1
		else
			break
		end
	end

	-- parse request definition
	local start_req_def, end_req_def = M.find_req_def(lines, selected, self.readed_lines)
	if start_req_def == 0 and end_req_def == 0 then
		return self:add_error("the selected row: " .. selected .. " is not in a request definition")
	end

	self.readed_lines = start_req_def

	while true do
		local line = lines[self.readed_lines]
		if not ignore_line(line) and not state_machine[self.current_state].to(self, line) then
			error(
				"unspupported state: " .. self.current_state .. " in line: " .. line .. " (" .. self.readed_lines .. ")"
			)
		end

		if self.readed_lines == end_req_def then
			break
		end
		self.readed_lines = self.readed_lines + 1
	end

	if not self.request.method or not self.request.url then
		return self:add_error("a valid request expect at least a url")
	end

	return self
end

return M
