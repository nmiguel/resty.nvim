local curl = require("plenary.curl")
local parser = require("resty.parser")

local M = {}

_Last_req_def = nil

local print_response_to_new_buf = function(req_def, response, duration)
	local buf = vim.api.nvim_create_buf(true, true)
	vim.api.nvim_set_option_value("buftype", "nofile", { buf = buf })
	-- vim.api.nvim_buf_set_name(buf, "Resty.http")
	vim.api.nvim_set_option_value("filetype", "json", { buf = buf })

	vim.api.nvim_buf_set_lines(buf, 0, -1, false, {
		"Request: "
			.. req_def.name
			.. " ["
			.. req_def.start_at
			.. " - "
			.. req_def.end_at
			.. "] duration: "
			.. duration
			.. " ms >> response Status: "
			.. response.status,
		"",
	})

	local body = vim.split(response.body, "\n")
	for _, r in ipairs(body) do
		vim.api.nvim_buf_set_lines(buf, -1, -1, false, { r })
	end

	vim.api.nvim_buf_set_lines(buf, -1, -1, false, { "" })
	vim.api.nvim_buf_set_lines(buf, -1, -1, false, response.headers)

	vim.api.nvim_win_set_buf(0, buf)
	vim.api.nvim_win_set_cursor(0, { vim.api.nvim_buf_line_count(buf), 0 })
end

local exec_curl = function(req_def)
	local start_time = os.clock()
	local response = curl.request(req_def.req)
	local duration = os.clock() - start_time

	local microseconds = math.floor((duration - math.floor(duration)) * 1000000)
	local milliseconds = math.floor(duration * 1000) + microseconds

	_Last_req_def = req_def

	print_response_to_new_buf(req_def, response, milliseconds)
end

M.last = function()
	if _Last_req_def then
		exec_curl(_Last_req_def)
	else
		error("No last request found. Run first [Resty run]")
	end
end

M.run = function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), true)
	local definitions = parser.parse(lines)

	local row = vim.api.nvim_win_get_cursor(0)[1]
	local found_def

	for _, d in pairs(definitions) do
		if d.start_at <= row and d.end_at >= row then
			found_def = d
			break
		end
	end

	assert(found_def, "The cursor position: " .. row .. " is not in a valid range for a request definition")

	exec_curl(found_def)
end

M.view = function()
	local lines = vim.api.nvim_buf_get_lines(0, 0, vim.api.nvim_buf_line_count(0), true)
	local req_defs = parser.parse(lines)

	-- load the view and execute the selection
	require("resty.select").view({}, req_defs, function(def)
		exec_curl(def)
	end)
end

return M
