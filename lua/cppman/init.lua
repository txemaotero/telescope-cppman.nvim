local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require "telescope.config".values
local previewers = require "telescope.previewers"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local Job = require "plenary.job"
local utils = require "cppman.utils"
local jumplist = require "cppman.jumplist"

local M = {}

---@type table<string, integer>
local pages_ids_buffs = {}

---@return string | nil
local function get_current_buf_page_id()
    return utils.find_key_by_value(pages_ids_buffs, vim.api.nvim_get_current_buf())
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

local function prepare_buf_to_write()
    vim.bo.ro = false
    vim.bo.ma = true
    vim.api.nvim_buf_set_lines(0, 0, -1, true, {})
end

---@param page_name string
local function write_cppman_to_buffer(page_name)
    local win_width = vim.api.nvim_win_get_width(0) - 2
    local cmd = string.format([[0r! cppman --force-columns %d '%s']], win_width, page_name)
    vim.cmd(cmd)
    utils.go_normal_mode()
end

local function make_buf_readonly()
    vim.bo.ro = true
    vim.bo.ma = false
    vim.bo.mod = false
end

---@param bufnr integer
local function set_buf_type(bufnr)
    vim.bo[bufnr].keywordprg = "cppman"
    vim.bo[bufnr].buftype = "nofile"
    vim.bo[bufnr].filetype = "cppman"
end

---@param page_name string
local function load_cppman_page(page_name)
    prepare_buf_to_write()
    write_cppman_to_buffer(page_name)
    make_buf_readonly()
    set_buf_type(0)
    vim.api.nvim_win_set_cursor(0, {1,0})
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
        load_cppman_page(page_id)
    else
        utils.go_normal_mode()
    end
end

---Opens the page with the given name if it is found by cppman
---@param page_name string
local function enter_cppman(page_name)
    if not is_valid_page(page_name) then
        vim.notify("Cppman page not found: " .. page_name)
        return
    end
    jumplist.reset()
    open_page_id(page_name)
    jumplist.add_current_pos(get_current_buf_page_id())
end

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
local available_cppmans = function()
    local cmd = "python3 -c \"import cppman.main; print('\\n'.join([i[1] for i in cppman.main.Cppman()._search_keyword('')]))\""
    local output = vim.fn.system(cmd)
    local items = {}
    for line in output:gmatch("[^\r\n]+") do
        table.insert(items, line)
    end
    return items
end

M.telescope_cppman = function(opts)
    opts = opts or {}
    local finder = finders.new_table {
        results = available_cppmans(),
        entry_maker = opts.entry_maker or function(entry)
            return {
                value = entry,
                display = entry,
                ordinal = entry,
            }
        end,
    }

    pickers.new(opts, {
        debounce = 100,
        prompt_title = "cppman",
        finder = finder,
        previewer = previewers.new_buffer_previewer {
            define_preview = function(self, entry, status)
                if not entry then return end

                local columns = vim.api.nvim_win_get_width(status.preview_win) - 2 -- Get the preview width
                if entry.bufnr then
                    set_buf_type(entry.bufnr)
                end

                Job:new({
                    command = "cppman",
                    args = { entry.value, "--force-columns", tostring(columns) },
                    on_exit = function(j, _)
                        local result = j:result()
                        if #result == 0 then
                            result = { "No documentation found for " .. entry.value }
                        end
                        vim.schedule(function()
                            vim.api.nvim_buf_set_lines(self.state.bufnr, 0, -1, false, result)
                            set_buf_type(self.state.bufnr)
                        end)
                    end,
                }):start()
            end,
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function ()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    enter_cppman(selection.value)
                end
            end)
            return true
        end,
    }):find()
end

M.telescope_cppman_current_word = function(opts)
    opts = opts or {}
    opts.default_text = vim.fn.expand("<cword>")
    M.telescope_cppman(opts)
end

return M
