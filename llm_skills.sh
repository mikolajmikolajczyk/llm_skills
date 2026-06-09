#!/usr/bin/env bash
set -euo pipefail

# llm_skills — install and manage LLM skills from local or remote repos
#
# Sources:
#   1. Local skills in this repo (same directory as this script)
#   2. Remote repos cached in ~/.local/share/llm_skills/repos/
#
# Skills are installed as symlinks into:
#   - ~/.agents/skills/<name>/         (global)
#   - <project>/.agents/skills/<name>/ (project)

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CACHE_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/llm_skills/repos"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BOLD='\033[1m'
RESET='\033[0m'

die() { echo -e "${RED}error:${RESET} $*" >&2; exit 1; }
info() { echo -e "${GREEN}•${RESET} $*"; }
warn() { echo -e "${YELLOW}•${RESET} $*"; }

usage() {
    cat <<'EOF'
Usage: llm_skills <command> [args]

Commands:
  list                          List available skills (local + cached)
  install <skill> [target]      Install skill via symlink
  uninstall <skill> [target]    Remove installed skill symlink
  fetch <url>                   Clone/fetch remote skill repo into cache
  update                        Pull latest for all cached repos
  sync [project-path]           Install skills from .agents/skillfile
  search <pattern>              Search skills by name/description

Targets:
  --global                      Install to ~/.agents/skills/ (default)
  --project <path>              Install to <path>/.agents/skills/

Examples:
  llm_skills list
  llm_skills install radicle --global
  llm_skills install radicle --project ~/src/synthmate
  llm_skills fetch https://github.com/user/skills.git
  llm_skills fetch rad:z3Tr6bC7ctEg2EHmLvknUr29mEDLH
  llm_skills sync ~/src/synthmate
EOF
}

# --- Skill discovery ---

# Find a skill directory by name across all sources.
# Returns the path to the skill dir, or empty string.
find_skill() {
    local name="$1"

    # Check local repo first
    if [[ -f "$SCRIPT_DIR/$name/SKILL.md" ]]; then
        echo "$SCRIPT_DIR/$name"
        return
    fi

    # Check cached remote repos
    if [[ -d "$CACHE_DIR" ]]; then
        for repo_dir in "$CACHE_DIR"/*/; do
            [[ -d "$repo_dir" ]] || continue
            if [[ -f "${repo_dir}${name}/SKILL.md" ]]; then
                echo "${repo_dir}${name}"
                return
            fi
        done
    fi
}

# List all available skills across all sources
list_skills() {
    echo -e "${BOLD}Local skills:${RESET}"
    local found=0
    for dir in "$SCRIPT_DIR"/*/; do
        [[ -d "$dir" ]] || continue
        local name
        name="$(basename "$dir")"
        if [[ -f "$dir/SKILL.md" ]]; then
            local desc
            desc=$(awk '/^description:/{
                sub(/^description: */, "")
                if ($0 == ">" || $0 == "|") { getline; sub(/^ +/, ""); }
                print; exit
            }' "$dir/SKILL.md")
            echo -e "  ${GREEN}${name}${RESET}  ${desc}"
            found=1
        fi
    done
    [[ $found -eq 0 ]] && echo "  (none)"

    if [[ -d "$CACHE_DIR" ]]; then
        for repo_dir in "$CACHE_DIR"/*/; do
            [[ -d "$repo_dir" ]] || continue
            local repo_name
            repo_name="$(basename "$repo_dir")"
            local repo_found=0
            for dir in "$repo_dir"/*/; do
                [[ -d "$dir" ]] || continue
                if [[ -f "$dir/SKILL.md" ]]; then
                    if [[ $repo_found -eq 0 ]]; then
                        echo ""
                        echo -e "${BOLD}Remote [$repo_name]:${RESET}"
                        repo_found=1
                    fi
                    local name desc
                    name="$(basename "$dir")"
                    desc=$(awk '/^description:/{
                        sub(/^description: */, "")
                        if ($0 == ">" || $0 == "|") { getline; sub(/^ +/, ""); }
                        print; exit
                    }' "$dir/SKILL.md")
                    echo -e "  ${GREEN}${name}${RESET}  ${desc}"
                fi
            done
        done
    fi
}

# --- Install / uninstall ---

resolve_target() {
    local target_type="${1:-global}"
    local target_path="${2:-}"

    if [[ "$target_type" == "global" ]]; then
        echo "$HOME/.agents/skills"
    elif [[ "$target_type" == "project" ]]; then
        [[ -n "$target_path" ]] || die "project path required"
        echo "$target_path/.agents/skills"
    else
        die "unknown target: $target_type"
    fi
}

install_skill() {
    local name="$1"
    local target_type="${2:-global}"
    local target_path="${3:-}"

    local skill_dir
    skill_dir="$(find_skill "$name")"
    [[ -n "$skill_dir" ]] || die "skill '$name' not found. Run 'llm_skills list' to see available skills."

    local target
    target="$(resolve_target "$target_type" "$target_path")"
    local link="$target/$name"

    mkdir -p "$target"

    if [[ -L "$link" ]]; then
        local existing
        existing="$(readlink -f "$link")"
        if [[ "$existing" == "$(readlink -f "$skill_dir")" ]]; then
            info "$name already installed at $link"
            return
        fi
        warn "replacing existing symlink: $link -> $existing"
        rm "$link"
    elif [[ -e "$link" ]]; then
        die "$link exists and is not a symlink. Remove manually to proceed."
    fi

    ln -s "$skill_dir" "$link"
    info "installed $name -> $link"
}

uninstall_skill() {
    local name="$1"
    local target_type="${2:-global}"
    local target_path="${3:-}"

    local target
    target="$(resolve_target "$target_type" "$target_path")"
    local link="$target/$name"

    if [[ -L "$link" ]]; then
        rm "$link"
        info "uninstalled $name from $target"
    elif [[ -e "$link" ]]; then
        die "$link exists but is not a symlink. Remove manually."
    else
        warn "$name not installed at $target"
    fi
}

# --- Remote repos ---

# Generate a stable directory name for a remote URL
repo_cache_name() {
    local url="$1"
    # Use basename of URL without .git, plus short hash for uniqueness
    local base
    base="$(basename "$url" .git)"
    local hash
    hash="$(echo -n "$url" | sha256sum | head -c 8)"
    echo "${base}-${hash}"
}

is_radicle_rid() {
    [[ "$1" =~ ^rad: ]] || [[ "$1" =~ ^rad:// ]]
}

fetch_repo() {
    local url="$1"
    local cache_name
    cache_name="$(repo_cache_name "$url")"
    local repo_path="$CACHE_DIR/$cache_name"

    mkdir -p "$CACHE_DIR"

    if [[ -d "$repo_path" ]]; then
        info "updating cached repo: $cache_name"
        if is_radicle_rid "$url"; then
            (cd "$repo_path" && rad sync --fetch 2>/dev/null || true)
            (cd "$repo_path" && git pull --rebase 2>/dev/null || true)
        else
            (cd "$repo_path" && git pull --rebase 2>/dev/null || true)
        fi
    else
        info "cloning $url -> $repo_path"
        if is_radicle_rid "$url"; then
            rad clone "$url" "$repo_path"
        else
            git clone "$url" "$repo_path"
        fi
    fi

    # Show what skills are available
    local count=0
    for dir in "$repo_path"/*/; do
        [[ -f "$dir/SKILL.md" ]] && count=$((count + 1))
    done
    info "cached repo has $count skill(s)"
}

update_all() {
    [[ -d "$CACHE_DIR" ]] || { warn "no cached repos"; return; }

    for repo_dir in "$CACHE_DIR"/*/; do
        [[ -d "$repo_dir" ]] || continue
        local name
        name="$(basename "$repo_dir")"
        info "updating $name..."
        (cd "$repo_dir" && git pull --rebase 2>/dev/null || true)
    done
}

# --- Skillfile sync ---

# .agents/skillfile format:
#   <skill-name>  [git-url-or-rid]  [--project|--global]
#
# Example:
#   radicle  https://github.com/user/llm_skills.git
#   custom   rad:z3Tr6bC7ctEg2EHmLvknUr29mEDLH

sync_skillfile() {
    local project_path="${1:-.}"
    local skillfile="$project_path/.agents/skillfile"

    [[ -f "$skillfile" ]] || die "no skillfile at $skillfile"

    info "syncing from $skillfile"

    while IFS= read -r line; do
        # Skip comments and blank lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// /}" ]] && continue

        local skill_name repo_url target_type option
        local -a fields
        read -r -a fields <<< "$line"
        skill_name="${fields[0]}"
        repo_url=""
        target_type="project"

        for option in "${fields[@]:1}"; do
            case "$option" in
                --global) target_type="global" ;;
                --project) target_type="project" ;;
                *)
                    if [[ -z "$repo_url" ]]; then
                        repo_url="$option"
                    else
                        die "unknown option in skillfile for '$skill_name': $option"
                    fi
                    ;;
            esac
        done

        # Fetch repo if URL provided
        if [[ -n "$repo_url" ]]; then
            fetch_repo "$repo_url"
        fi

        # Install skill
        if [[ "$target_type" == "global" ]]; then
            install_skill "$skill_name" "global"
        else
            install_skill "$skill_name" "project" "$project_path"
        fi
    done < "$skillfile"
}

# --- Search ---

search_skills() {
    local pattern="$1"
    local found=0

    # Search local
    for dir in "$SCRIPT_DIR"/*/; do
        [[ -f "$dir/SKILL.md" ]] || continue
        local name
        name="$(basename "$dir")"
        if [[ "$name" == *"$pattern"* ]] || grep -qil "$pattern" "$dir/SKILL.md" 2>/dev/null; then
            echo -e "  ${GREEN}${name}${RESET} (local)"
            found=1
        fi
    done

    # Search cached
    if [[ -d "$CACHE_DIR" ]]; then
        for repo_dir in "$CACHE_DIR"/*/; do
            [[ -d "$repo_dir" ]] || continue
            for dir in "$repo_dir"/*/; do
                [[ -f "$dir/SKILL.md" ]] || continue
                local name
                name="$(basename "$dir")"
                if [[ "$name" == *"$pattern"* ]] || grep -qil "$pattern" "$dir/SKILL.md" 2>/dev/null; then
                    echo -e "  ${GREEN}${name}${RESET} ($(basename "$repo_dir"))"
                    found=1
                fi
            done
        done
    fi

    [[ $found -eq 1 ]] || warn "no skills matching '$pattern'"
}

# --- Main ---

cmd="${1:-}"
shift || true

case "$cmd" in
    list|ls)
        list_skills
        ;;
    install)
        [[ -n "${1:-}" ]] || die "skill name required"
        skill_name="$1"; shift
        target_type="global"
        target_path=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --global)  target_type="global"; shift ;;
                --project) target_type="project"; target_path="${2:-}"; shift 2 || die "project path required" ;;
                *) die "unknown option: $1" ;;
            esac
        done
        install_skill "$skill_name" "$target_type" "$target_path"
        ;;
    uninstall|rm)
        [[ -n "${1:-}" ]] || die "skill name required"
        skill_name="$1"; shift
        target_type="global"
        target_path=""
        while [[ $# -gt 0 ]]; do
            case "$1" in
                --global)  target_type="global"; shift ;;
                --project) target_type="project"; target_path="${2:-}"; shift 2 || die "project path required" ;;
                *) die "unknown option: $1" ;;
            esac
        done
        uninstall_skill "$skill_name" "$target_type" "$target_path"
        ;;
    fetch|add)
        [[ -n "${1:-}" ]] || die "URL or RID required"
        fetch_repo "$1"
        ;;
    update|pull)
        update_all
        ;;
    sync)
        sync_skillfile "${1:-.}"
        ;;
    search)
        [[ -n "${1:-}" ]] || die "search pattern required"
        search_skills "$1"
        ;;
    help|--help|-h|"")
        usage
        ;;
    *)
        die "unknown command: $cmd. Run 'llm_skills help' for usage."
        ;;
esac
