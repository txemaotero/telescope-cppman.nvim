---This file defines all the utilities to open and manage cppman buffers and windows
local Job = require "plenary.job"
local utils = require "cppman.utils"
local jumplist = require "cppman.jumplist"

local M = {}

---Maps cppman page names to buffers
---@type table<string, integer>
local pages_ids_buffs = {}

---@return string | nil
local function get_current_buf_page_id()
    return utils.find_key_by_value(pages_ids_buffs, vim.api.nvim_get_current_buf())
end

---Attach autocmds to cppman buffers. Current operations:
---  + BufDelete: remove bufnr from pages_ids_buffs
---@param bufnr integer
local function set_cppman_buf_autocmds(bufnr)
    vim.api.nvim_create_autocmd({"BufDelete"}, {
        buffer = bufnr,
        callback = function(_)
            local page_id = utils.find_key_by_value(pages_ids_buffs, bufnr)
            if page_id then
                pages_ids_buffs[page_id] = nil
            end
        end
    })
end

---@param bufnr integer
local function set_cppman_buf_keymaps(bufnr)
    vim.keymap.set("n", "q", ":q!<cr>", { silent = true, buffer = bufnr })

    vim.keymap.set("n", "<CR>", M._open_page_under_cursor, { silent = true, buffer = bufnr })
    vim.keymap.set("n", "K", M._open_page_under_cursor, { silent = true, buffer = bufnr })
    vim.keymap.set("n", "<C-]>", M._open_page_under_cursor, { silent = true, buffer = bufnr })

    vim.keymap.set("n", "<C-O>", M._go_previous_page, { silent = true, buffer = bufnr })
    vim.keymap.set("n", "<C-T>", M._go_previous_page, { silent = true, buffer = bufnr })

    vim.keymap.set("n", "<C-I>", M._go_next_page, { silent = true, buffer = bufnr })
end

--- Creates, if it doesn't exist already, a buffer to contain the given page
---@param page_id string
---@alias BufResult {bufnr: integer, existed: boolean}
---@return BufResult
local function get_cppman_buf(page_id)
    if pages_ids_buffs[page_id] ~= nil then
        return {bufnr = pages_ids_buffs[page_id], existed = true};
    end
    local cppman_bufnr = vim.api.nvim_create_buf(true, false)
    pages_ids_buffs[page_id] = cppman_bufnr
    set_cppman_buf_keymaps(cppman_bufnr)
    set_cppman_buf_autocmds(cppman_bufnr)
    return {bufnr = cppman_bufnr, existed = false};
end

---@param bufnr integer
local function open_and_focus_cppman_win(bufnr)
    local win = utils.get_win_with_buf(bufnr)
    if win then
        vim.api.nvim_set_current_win(win)
    elseif vim.bo.filetype ~= "cppman" then
        vim.api.nvim_open_win(bufnr, true, {split = "above", win = 0, style = "minimal"})
    elseif vim.bo.filetype == "cppman" then
        vim.api.nvim_set_current_buf(bufnr)
    end
end

local function prepare_buf_to_write(bufnr)
    vim.bo[bufnr].ro = false
    vim.bo[bufnr].ma = true
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, true, {})
end

local function make_buf_readonly(bufnr)
    vim.bo[bufnr].ro = true
    vim.bo[bufnr].ma = false
    vim.bo[bufnr].mod = false
end

---@param bufnr integer
M.set_buf_type = function(bufnr)
    vim.bo[bufnr].keywordprg = "cppman"
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].filetype = "cppman"
end

---@param content string[]
---@param bufnr integer
---@param winid integer
local function write_cppman_content(content, bufnr, winid)
    prepare_buf_to_write(bufnr)
    vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, content)
    make_buf_readonly(bufnr)
    M.set_buf_type(bufnr)
    vim.api.nvim_win_set_cursor(winid, {1,0})
end

---@param page_name string
M.load_cppman_page = function(page_name, bufnr, winid)
    local win_width = vim.api.nvim_win_get_width(winid) - 2
    Job:new({
        command = "cppman",
        args = { page_name, "--force-columns", tostring(win_width) },
        on_exit = function(j, _)
            local result = j:result()
            if #result == 0 then
                result = { "No documentation found for " .. page_name }
            end
            vim.schedule(function()
                write_cppman_content(result, bufnr, winid)
            end)
        end,
    }):start()
end

---@param name string
---@return boolean
local function is_valid_page(name)
    local cmd = 'cppman -f "' .. name .. '"'
    local output = vim.fn.system(cmd)
    if vim.v.shell_error ~= 0 then
        return false
    end

    if output:match("^error") then
        return false
    end

    local first_line = output:match("^(.-)\n")
    if first_line then
        local identifier = first_line:match("^(.-) %- ")
        return identifier or false
    end

    return false
end

---@param page_id string
local function open_page_id(page_id)
    local bufRes = get_cppman_buf(page_id)
    open_and_focus_cppman_win(bufRes.bufnr)
    if not bufRes.existed then
        M.load_cppman_page(page_id, 0, 0)
    end
    utils.go_normal_mode()
end

---Opens the page with the given name if it is found by cppman
---@param page_name string
M.enter_cppman = function(page_name)
    if not is_valid_page(page_name) then
        vim.notify("Cppman page not found: " .. page_name)
        return
    end
    jumplist.reset()
    open_page_id(page_name)
    jumplist.add_current_pos(get_current_buf_page_id())
end

---Clears the input str (that can be the WORD under the cursor) so it's more
---likely to have a matching page, e.g., removes templates parameters...
---@param str string
---@return string
local function preprocess_name(str)
    str = string.gsub(str, "<[^>]+>", "")
    str = string.gsub(str, "<", "")
    str = string.gsub(str, ">", "")
    return str
end

M._open_page_under_cursor = function ()
    local page_name = preprocess_name(vim.fn.expand('<cWORD>'))
    if not is_valid_page(page_name) then
        vim.notify("Cppman page not found: " .. page_name)
        return
    end
    jumplist.update_current_pos()
    open_page_id(page_name)
    jumplist.add_current_pos(get_current_buf_page_id())
end

M._go_previous_page = function ()
    jumplist.update_current_pos()
    local previous = jumplist.back()
    if not previous then
        return
    end
    open_page_id(previous.page_id)
    vim.api.nvim_win_set_cursor(0, previous.cursor)
end

M._go_next_page = function ()
    jumplist.update_current_pos()
    local next = jumplist.forward()
    if not next then
        return
    end
    open_page_id(next.page_id)
    vim.api.nvim_win_set_cursor(0, next.cursor)
end

---@return string[]
M.available_cppmans = function()
    local cmd = "python3 -c \"import cppman.main; print('\\n'.join([i[1] for i in cppman.main.Cppman()._search_keyword('')]))\""
    local output = vim.fn.system(cmd)
    local items = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(items, line)
    end
    return items
end

return M
