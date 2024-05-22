local exec = require("resty.exec")

local M = {}

local function get_or_create_buffer_with_win(name)
	local output = name or "response"
	local bufnr = nil

	for _, id in ipairs(vim.api.nvim_list_bufs()) do
		if vim.api.nvim_buf_get_name(id):find(output) then
			bufnr = id
		end
	end

	if not bufnr then
		bufnr = vim.api.nvim_create_buf(false, false)
		vim.api.nvim_buf_set_name(bufnr, output)
		vim.api.nvim_set_option_value("buftype", "nofile", { buf = bufnr })
		vim.api.nvim_set_option_value("filetype", "json", { buf = bufnr })
		vim.api.nvim_buf_set_option(bufnr, "swapfile", false)
		vim.api.nvim_buf_set_option(bufnr, "buflisted", false)
	end

	-- window
	local winnr
	for _, id in ipairs(vim.api.nvim_list_wins()) do
		if vim.api.nvim_win_get_buf(id) == bufnr then
			winnr = id
		end
	end

	if not winnr then
		vim.cmd("vsplit")
		vim.cmd(string.format("buffer %d", bufnr))
		vim.cmd("wincmd r")
		winnr = vim.api.nvim_get_current_win()
	end

	vim.api.nvim_set_current_win(winnr)
	-- Delete buffer content
	vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, {})

	return bufnr
end

--[[ local function get_buf_context(bufnr)
	-- read the complete buffer
	local context = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	-- convert the full input of the buffer into a (json) line
	local json = table.concat(context, "")
	return json
end ]]

function M:show_meta()
	if M.meta then
		vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, {
			"Request: "
				.. self.req_def.name
				.. " ["
				.. self.req_def.start_at
				.. " - "
				.. self.req_def.end_at
				.. "] duration: "
				.. self.duration
				.. " ms >> response Status: "
				.. self.response.status,
			"",
		})
	end
end

function M:show_body()
	if M.body then
		local b = vim.split(self.response.body, "\n")
		for _, r in ipairs(b) do
			vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, { r })
		end
	end
end

function M:show_headers()
	if M.headers then
		vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, self.response.headers)
	end
end

function M:show()
	self:show_meta()
	self:show_body()

	vim.api.nvim_buf_set_lines(self.bufnr, -1, -1, false, { "" })
	self:show_headers()

	vim.api.nvim_win_set_buf(0, M.bufnr)
	vim.api.nvim_win_set_cursor(0, { 1, 0 })
end

function M:refresh()
	-- Delete buffer content
	vim.api.nvim_buf_set_lines(M.bufnr, 0, -1, false, {})
	M:show()
end

M.new = function(req_def, response, duration)
	local bufnr = get_or_create_buffer_with_win()

	M.req_def = req_def
	M.response = response
	M.body_filtered = response.body
	M.duration = duration
	M.bufnr = bufnr

	M.body = true
	M.headers = true
	M.meta = true

	return M
end

-- add key-mapping for using jq for the json-body
-- ----------------------------------------------
vim.keymap.set("n", "b", function()
	M.body = not M.body
	M:refresh()
end, { silent = true, buffer = M.bufnr, desc = "toggle for body" })

vim.keymap.set("n", "m", function()
	M.meta = not M.meta
	M:refresh()
end, { silent = true, buffer = M.bufnr, desc = "toggle for meta" })

vim.keymap.set("n", "h", function()
	M.headers = not M.headers
	M:refresh()
end, { silent = true, buffer = M.bufnr, desc = "toggle for headers" })

vim.keymap.set("n", "f", function()
	if M.body then
		--get_buf_context(bufnr)
		exec.jq(M.bufnr, M.body_filtered)
	end
end, { silent = true, buffer = M.bufnr, desc = "format the json output with jq" })

vim.keymap.set("n", "ff", function()
	if M.body then
		local jq_filter = vim.fn.input("Filter: ")
		if jq_filter == "" then
			return
		end

		--get_buf_context(bufnr)
		exec.jq(M.bufnr, M.body_filtered, jq_filter)
	end
end, { silent = true, buffer = M.bufnr, desc = "format the json output with jq with a given query" })

vim.keymap.set("n", "fr", function()
	if M.body then
		M.body_filtered = M.response.body
		M:refresh()
	end
end, { silent = true, buffer = M.bufnr, desc = "reset the current filtered body" })
return M
