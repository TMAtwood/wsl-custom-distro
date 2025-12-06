#!/bin/bash
# Git configuration script
# Usage: setup-git-config.sh [credential_helper]
# If no credential helper specified, defaults to "store"

CRED_HELPER="${1:-store}"

# Core settings for line endings and case sensitivity
git config --global core.autocrlf false
git config --global core.ignorecase false
git config --global core.editor nano
git config --global core.pager delta

# Credentials and authentication
git config --global credential.helper "$CRED_HELPER"
git config --global credential.https://github.com.provider github

# Git LFS (Large File Storage) configuration
git config --global filter.lfs.clean "git-lfs clean -- %f"
git config --global filter.lfs.process "git-lfs filter-process"
git config --global filter.lfs.required true
git config --global filter.lfs.smudge "git-lfs smudge -- %f"

# Initialization and security
git config --global http.sslVerify true
git config --global init.defaultBranch main
git config --global safe.directory /home/linuxbrew/.linuxbrew

# Color output for better terminal display
git config --global color.ui true

# Diff tooling - Delta as default pager, VS Code as visual tool
git config --global diff.tool delta
git config --global diff.colorWords true
git config --global difftool.delta.cmd "delta \"\$LOCAL\" \"\$REMOTE\""
git config --global difftool.prompt false
git config --global difftool.vscode.cmd "code --wait --diff \"\$LOCAL\" \"\$REMOTE\""

# Better merge conflict display (shows base, ours, theirs)
git config --global merge.conflictstyle diff3

# Performance optimizations for rebasing and pulling
git config --global branch.autoSetupMerge true
git config --global branch.autSetupRebase always
git config --global commit.verbose true
git config --global fetch.prune true
git config --global pull.rebase true
git config --global rebase.autostash true

# Remember resolved merge conflicts to auto-resolve them in the future
git config --global rerere.enabled true
# Safety settings for pushing code
git config --global push.default current
git config --global push.followTags true

# Pretty log output with branch/tag decorations
git config --global log.decorate short

# Show untracked files in git status
git config --global status.showUntrackedFiles all

# Useful command aliases for common workflows
git config --global alias.amend "commit --amend --no-edit"
git config --global alias.contributors "shortlog -sn"
git config --global alias.last "log -1 HEAD"
git config --global alias.unstage "reset HEAD --"
git config --global alias.wip "!git add -A && git commit -m \"WIP\""
