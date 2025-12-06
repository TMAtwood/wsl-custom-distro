# Git Config Prompt + SSH Key Migration Setup

## Objective

1. Add bashrc logic that prompts for git user name and email if not configured globally
2. Add SSH key migration from Windows .ssh folder if WSL .ssh folder is empty or missing id_rsa

## Completed Tasks

- [x] Add git user config prompt to Dockerfile bashrc

## In Progress Tasks

### 3. Add SSH key migration logic to bashrc

- [ ] Add logic to detect Windows username from /mnt/c/Users
- [ ] Check if /home/${USER}/.ssh/id_rsa exists
- [ ] If missing, copy all files from Windows .ssh folder
- [ ] Set proper permissions (chmod +x, then chmod 600)
- [ ] Provide user feedback on what was copied

## Implementation Details

**SSH Migration Flow:**

1. Check if /home/${USER}/.ssh/id_rsa exists
2. If not, find Windows username by listing /mnt/c/Users
3. Copy all files from /mnt/c/Users/[USERNAME]/.ssh to /home/${USER}/.ssh
4. Apply permissions: chmod +x then chmod 600
5. Confirm operation to user

**Finding Windows Username:**

- List /mnt/c/Users and find first user directory (skip System accounts)
- Or use a heuristic to find the most likely user directory

## Notes

- Will be added to bashrc, runs on shell startup
- Non-fatal operation (won't break shell if files don't exist)
- Symlink approach considered but direct copy is simpler and more reliable
