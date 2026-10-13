# `light update`: git pull + config clean-up + lightd reload. Sourced by bin/light before
# common.sh, so it works even when config.sh is broken. Written for macOS's bash 3.2.
#
# Safety: fast-forward only (never a merge, rebase, reset or --force); local changes to
# tracked files are stashed, never dropped or popped; untracked and ignored files
# (probe/results) are never touched.
#
# Test hooks: LIGHT_UPDATE_NO_RELOAD=1 skips the lightd reload; LIGHT_UPDATE_BACKOFF sets
# the first retry wait in seconds (default 2, doubling).

up_say() { printf '%s\n' "$*"; }
up_die() { printf 'light update: %s\n' "$*" >&2; exit 1; }
ug() { git -C "$UP_REPO" "$@"; }   # git in the clone, wherever this was run from
up_log() {
    local home="${LIGHT_HOME:-$HOME/.lighting}"
    mkdir -p "$home" 2>/dev/null && printf '%s %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$home/lightd.log"
}

light_update() {  # light_update [--after-pull <oldrev> [stash-name]]
    local self="$1" proto repo
    shift
    proto="$(cd "$(dirname "$self")/.." && pwd)"
    command -v git >/dev/null 2>&1 || up_die "git isn't installed (xcode-select --install)."
    repo="$(git -C "$proto" rev-parse --show-toplevel 2>/dev/null)" \
        || up_die "$proto isn't inside a git clone, so there's nothing to pull."
    UP_REPO="$repo"
    if [ "$1" = --after-pull ]; then
        up_after_pull "$proto" "$repo" "$2" "$3"
    else
        up_pull "$self" "$repo"
    fi
}

# Phase 1, the old version of this script: fetch, check, stash, fast-forward, then exec the new one.
up_pull() {
    local self="$1" repo="$2" branch upstream old target i wait stash_name="" ident=""
    branch="$(ug symbolic-ref --short -q HEAD)" \
        || up_die "the clone isn't on a branch (detached HEAD). Check out your branch first; nothing was changed."
    upstream="$(ug rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)" \
        || up_die "branch $branch has no upstream to pull from (git branch --set-upstream-to=origin/$branch). Nothing was changed."
    old="$(ug rev-parse HEAD)"
    up_say "Repo: $repo (branch $branch, from $upstream)"

    # Network errors: 3 attempts, waiting 2 s then 4 s.
    wait="${LIGHT_UPDATE_BACKOFF:-2}"
    for i in 1 2 3; do
        ug fetch --quiet && break
        [ $i = 3 ] && up_die "git fetch failed 3 times (network?). Nothing was changed; try again later."
        up_say "  fetch failed; retrying in ${wait}s ($i of 3)"
        sleep "$wait"; wait=$(( wait * 2 ))
    done
    target="$(ug rev-parse '@{u}')"

    if [ "$target" = "$old" ] || ug merge-base --is-ancestor "$target" "$old"; then
        up_say "  already up to date with $upstream."
    elif ! ug merge-base --is-ancestor "$old" "$target"; then
        up_die "your branch and $upstream have diverged (local commits that aren't upstream), so this
can't be a fast-forward. Nothing was changed: no stash, no pull, config left as it is.
See them with: git -C $repo log --oneline $upstream..HEAD"
    else
        # Local changes to tracked files: stash them (never dropped or popped here).
        ug update-index -q --refresh >/dev/null 2>&1
        if ! ug diff --quiet || ! ug diff --cached --quiet; then
            stash_name="light update $(date '+%Y-%m-%d %H:%M')"
            # git stash needs an identity; don't fail on a Mac where none is configured.
            ug config user.email >/dev/null 2>&1 || ident="-c user.name=light-update -c user.email=light-update@localhost"
            ug $ident stash push --quiet -m "$stash_name" \
                || up_die "git stash failed; nothing was pulled and your changes are where they were."
            up_say "  Your local changes to tracked files are saved in the stash \"$stash_name\"."
            up_say "  See them: git -C $repo stash list   and   git -C $repo stash show -p stash@{0}"
            up_say "  (Untracked files such as probe/results were not touched.)"
        fi
        ug merge --ff-only --quiet "$target" \
            || up_die "the fast-forward to $upstream failed. Your files are as they were${stash_name:+, with your changes in the stash \"$stash_name\"}."
    fi
    # The pull may have changed this very script: run the new version for the rest.
    exec bash "$self" update --after-pull "$old" "$stash_name"
}

# Phase 2, the new version: migrate the config, reload lightd, report.
up_after_pull() {
    local proto="$1" repo="$2" old="$3" stash_name="$4" new commits mig changed=0 home pid
    home="${LIGHT_HOME:-$HOME/.lighting}"
    new="$(git -C "$repo" rev-parse HEAD)"; [ -n "$old" ] || old="$new"
    up_say ""
    if [ "$old" = "$new" ]; then
        up_say "Code: no new commits (at $(git -C "$repo" log -1 --format='%h %s' HEAD))."
    else
        changed=1
        commits="$(git -C "$repo" log --oneline "$old..$new")"
        up_say "Code: $(git -C "$repo" rev-parse --short "$old") → $(git -C "$repo" rev-parse --short "$new"), $(printf '%s\n' "$commits" | wc -l | tr -d ' ') commit(s):"
        printf '%s\n' "$commits" | sed 's/^/  /'
    fi

    up_say ""
    mig="$(bash "$proto/lib/config_migrate.sh")" || up_say "  (the config clean-up failed; config.sh was left as it is)"
    printf '%s\n' "$mig"
    printf '%s\n' "$mig" | grep -q '^  backup: ' && changed=1

    up_say ""
    local reloaded=no
    if [ "$changed" = 0 ]; then
        up_say "lightd: nothing changed, so it was left running as it is."
    elif [ "${LIGHT_UPDATE_NO_RELOAD:-0}" = 1 ]; then
        up_say "lightd: not reloaded (LIGHT_UPDATE_NO_RELOAD=1)."
    elif [ -f "$HOME/Library/LaunchAgents/com.lighting.lightd.plist" ]; then
        up_say "lightd: reloading the launchd agent (install.sh)..."
        local out rc
        out="$(LIGHT_MIGRATED=1 bash "$proto/install.sh" 2>&1)"; rc=$?
        printf '%s\n' "$out" | sed 's/^/  /'
        if [ $rc = 0 ]; then reloaded=yes; else up_say "  install.sh failed (exit $rc): run $proto/install.sh yourself and read its error."; fi
        up_say "lightd: reloaded=$reloaded"
    else
        pid="$(cat "$home/state/lightd.pid" 2>/dev/null)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            up_say "lightd: running in a Terminal (pid $pid), not under launchd. Restart it there"
            up_say "  (Ctrl-C, then $proto/bin/lightd) so it picks up the new code and config."
        else
            up_say "lightd: not running and no launchd agent installed; start it with $proto/install.sh or $proto/bin/lightd."
        fi
    fi
    [ -n "$stash_name" ] && up_say "" && up_say "Reminder: your earlier local changes are in the stash \"$stash_name\" (git -C $repo stash list)."
    up_log "light update: $(git -C "$repo" rev-parse --short "$old")..$(git -C "$repo" rev-parse --short "$new"), lightd reloaded=$reloaded${stash_name:+, stashed \"$stash_name\"}"
    return 0
}
