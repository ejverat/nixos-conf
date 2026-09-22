-- Entry point. LazyVim used to require config.options / config.autocmds /
-- config.keymaps itself; now the bootstrap does it explicitly.
require("config.options")
require("config.lazy")
require("config.autocmds")
require("config.keymaps")
