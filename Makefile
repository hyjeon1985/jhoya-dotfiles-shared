.PHONY: install uninstall doctor sync-git-identity-gh fix-root-home-bridge root-home-bridge-status remove-root-home-bridge

install:
	./scripts/install.sh

uninstall:
	./scripts/uninstall.sh

doctor:
	./scripts/doctor.sh

sync-git-identity-gh:
	./scripts/sync_git_identity_from_gh.sh

fix-root-home-bridge:
	./scripts/fix_root_home_bridge.sh apply

root-home-bridge-status:
	./scripts/fix_root_home_bridge.sh status

remove-root-home-bridge:
	./scripts/fix_root_home_bridge.sh remove
