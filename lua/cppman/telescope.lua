local pickers = require "telescope.pickers"
local finders = require "telescope.finders"
local conf = require "telescope.config".values
local previewers = require "telescope.previewers"
local actions = require "telescope.actions"
local action_state = require "telescope.actions.state"
local cppman = require "cppman.core"


local M = {}

M.telescope_cppman = function(opts)
    opts = opts or {}
    local finder = finders.new_table {
        results = cppman.available_cppmans(),
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
                if not entry then
                    return
                end
                cppman.load_cppman_page(entry.value, self.state.bufnr, status.preview_win)
            end,
        },
        sorter = conf.generic_sorter(opts),
        attach_mappings = function(prompt_bufnr, _)
            actions.select_default:replace(function ()
                actions.close(prompt_bufnr)
                local selection = action_state.get_selected_entry()
                if selection then
                    cppman.enter_cppman(selection.value)
                end
            end)
            return true
        end,
    }):find()
end

return M
