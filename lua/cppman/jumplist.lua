local M = {}

---@alias Jump { page_id: string, cursor: [integer, integer] }
---@alias JumpStack Jump[]
---@alias JumpList { current_pos: integer, stack: JumpStack}

---@type JumpList
M.jumplist = {current_pos = 0, stack = {}}

M.reset = function()
    M.jumplist = {current_pos = 0, stack = {}}
end

---@param current_page string | nil
M.add_current_pos = function(current_page)
    if M.jumplist.current_pos ~= 0 then
        M.jumplist.stack = vim.list_slice(M.jumplist.stack, 1, M.jumplist.current_pos)
    end
    if not current_page then
        return
    end
    M.jumplist.current_pos = M.jumplist.current_pos + 1
    vim.list_extend(M.jumplist.stack, {{page_id = current_page, cursor = vim.api.nvim_win_get_cursor(0)}})
end

M.update_current_pos = function()
    if M.jumplist.current_pos == 0 then
        return
    end
    M.jumplist.stack[M.jumplist.current_pos].cursor = vim.api.nvim_win_get_cursor(0)
end

---@return Jump | nil
M.current = function()
    if M.jumplist.current_pos == 0 then
        return nil
    end
    return M.jumplist.stack[M.jumplist.current_pos]
end

---@return Jump | nil
M.back = function()
    if M.jumplist.current_pos <= 1 then
        return nil
    end
    M.jumplist.current_pos = M.jumplist.current_pos - 1
    return M.current()
end

---@return Jump | nil
M.forward = function()
    if M.jumplist.current_pos == #M.jumplist.stack then
        return nil
    end
    M.jumplist.current_pos = M.jumplist.current_pos + 1
    return M.current()
end

return M
