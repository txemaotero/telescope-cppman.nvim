return require("telescope").register_extension {
    setup = function(ext_config, config)
    end,
    exports = {
        cppman = require("cppman").telescope_cppman
    },
}
