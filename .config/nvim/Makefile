# Neovim config tasks.

# Run the test suite under headless Neovim (plenary's busted harness).
# Exits non-zero on any failure, so it drops straight into CI or a pre-push hook.
# Run one file with: make test FILE=tests/terms_spec.lua
# Another nvim (e.g. a nix build's): make test NVIM_BIN=/path/to/bin/nvim
FILE ?= tests/
NVIM_BIN ?= $(shell command -v nvim)

# Each spec file runs in its own nvim: the same one (plenary would pick the
# unwrapped binary under nix), without the VIM/VIMRUNTIME an enclosing nvim's
# terminal exports, which point at that nvim's runtime rather than this one's.
.PHONY: test
test:
	env -u VIM -u VIMRUNTIME $(NVIM_BIN) --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory $(FILE) { minimal_init = 'tests/minimal_init.lua', nvim_cmd = '$(NVIM_BIN)' }"
