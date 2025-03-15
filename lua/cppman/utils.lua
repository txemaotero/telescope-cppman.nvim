local M = {}

---@generic K
---@generic V
---@param t table<K, V>
---@param target_value V
---@return K | nil
M.find_key_by_value = function(t, target_value)
    for key, value in pairs(t) do
        if value == target_value then
            return key
        end
    end
    return nil
end

---Get a window id that display the buffer with the given number
---@param bufnr integer
---@return integer | nil
M.get_win_with_buf = function(bufnr)
    if bufnr == nil then
        return nil
    end
    local open_wins = vim.api.nvim_list_wins()
    for _, w in ipairs(open_wins) do
        local bufnr_in_win = vim.api.nvim_win_get_buf(w)
        if bufnr_in_win == bufnr then
            return w
        end
    end
    return nil
end

M.go_normal_mode = function()
    vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes('<C-c>', true, false, true), 'n', true)
end

return M
