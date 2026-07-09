# Neovim config tasks.

# Run the test suite under headless Neovim (plenary's busted harness).
# Exits non-zero on any failure, so it drops straight into CI or a pre-push hook.
# Run one file with: make test FILE=tests/terms_spec.lua
FILE ?= tests/

.PHONY: test
test:
	nvim --headless -u tests/minimal_init.lua \
		-c "PlenaryBustedDirectory $(FILE) { minimal_init = 'tests/minimal_init.lua' }"
