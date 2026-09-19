#!/bin/bash
set -u

main=$(git -C "${CLAUDE_PROJECT_DIR:-$PWD}" worktree list --porcelain | sed -n '1s/^worktree //p')
[ -n "$main" ] || { echo "worktreeHook: not inside the neon repository" >&2; exit 1; }
input=$(cat)

die() { echo "worktreeHook: $*" >&2; exit 1; }

create() {
	local name w branch
	name=$(printf '%s' "$input" | jq -r '.name // empty')
	[ -n "$name" ] || die "no worktree name in the hook input"
	case "$name" in *[!A-Za-z0-9._-]*) die "worktree name '$name' has characters outside [A-Za-z0-9._-]" ;; esac
	w="$(dirname "$main")/neon-wt-$name"
	branch="wt/$name"
	if [ -d "$w" ]; then
		printf '%s\n' "$w"
		return
	fi
	if git -C "$main" show-ref --verify --quiet "refs/heads/$branch"; then
		git -C "$main" worktree add "$w" "$branch" >&2 || die "git worktree add $w $branch failed"
	else
		git -C "$main" worktree add -b "$branch" "$w" main >&2 || die "git worktree add -b $branch $w main failed"
	fi
	mkdir -p "$w/deps"
	ln -s ../../yoga/deps/yoga "$w/deps/yoga"
	printf '%s\n' "$w"
}

remove() {
	local w dirty kept ahead branch
	w=$(printf '%s' "$input" | jq -r '.worktree_path // empty')
	[ -n "$w" ] || die "no worktree_path in the hook input"
	[ "$w" != "$main" ] || die "refusing to remove the main checkout"
	[ -d "$w" ] || die "$w does not exist"
	dirty=$(git -C "$w" status --porcelain)
	[ -z "$dirty" ] || die "$w has uncommitted or untracked files, kept:
$dirty"
	kept=$(git -C "$w" status --porcelain --ignored | sed -n 's/^!! //p' | grep -v -e '^out/' -e '^deps/')
	[ -z "$kept" ] || die "$w holds ignored files outside out/ and deps/, kept:
$kept"
	ahead=$(git -C "$w" log --oneline main..HEAD)
	[ -z "$ahead" ] || die "$w has commits missing from main, kept:
$ahead"
	branch=$(git -C "$w" symbolic-ref -q --short HEAD || true)
	[ -L "$w/deps/yoga" ] && unlink "$w/deps/yoga"
	rmdir "$w/deps" 2>/dev/null || true
	git -C "$main" worktree remove --force "$w" >&2 || die "git worktree remove $w failed"
	if [ -n "$branch" ]; then git -C "$main" branch -d "$branch" >&2 || die "branch $branch not deleted"; fi
}

case "${1:-}" in
	create) create ;;
	remove) remove ;;
	*) die "usage: worktreeHook.sh create|remove (hook JSON on stdin)" ;;
esac
