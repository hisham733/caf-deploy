# CAF on Windows

The deployment is built for Linux, but works on Windows via **WSL 2** + **Docker Desktop**. This is the recommended approach.

---

## Option 1: WSL 2 + Docker Desktop (Recommended)

### Prerequisites

1. Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/)
2. During install, enable **WSL 2 backend**
3. Install a Linux distro (e.g., Ubuntu) from Microsoft Store
4. Open your WSL 2 terminal (Ubuntu) and continue with the standard Linux steps:

```bash
# Inside WSL 2 Ubuntu terminal

# 1. Install git if missing
sudo apt update && sudo apt install -y git

# 2. Clone frappe_docker
git clone https://github.com/frappe/frappe_docker.git
cd frappe_docker

# 3. Clone caf-deploy and copy config files
git clone https://github.com/hisham733/caf-deploy.git ~/caf-deploy
cp ~/caf-deploy/compose.override.yaml .
cp ~/caf-deploy/.env.example .env

# 4. Edit .env
nano .env

# 5. Deploy
cp ~/caf-deploy/deploy.sh .
./deploy.sh

# 6. Access at http://localhost:8080
```

All steps are identical to the Linux guide — WSL 2 provides full Linux compatibility.

### Tips

- Files are at `\\wsl.localhost\Ubuntu\home\<user>\frappe_docker\` if you want to edit them from Windows apps
- Docker volumes are managed by Docker Desktop; data persists across WSL restarts
- Use `docker compose` from the WSL terminal, not PowerShell

---

## Option 2: Git Bash (Without WSL)

If you cannot use WSL, you can use Git Bash (comes with Git for Windows).

### Prerequisites

- Install [Docker Desktop for Windows](https://docs.docker.com/desktop/setup/install/windows-install/) with **Hyper-V backend**
- Install [Git for Windows](https://git-scm.com/downloads/win) (includes Git Bash)

### Steps in Git Bash

```bash
# 1. Clone frappe_docker
git clone https://github.com/frappe/frappe_docker.git
cd frappe_docker

# 2. Clone caf-deploy
git clone https://github.com/hisham733/caf-deploy.git
cd caf-deploy

# Copy files back to frappe_docker
cp compose.override.yaml ../frappe_docker/
cp .env.example ../frappe_docker/.env
cp deploy.sh ../frappe_docker/
cd ../frappe_docker

# 3. Edit .env (use notepad or VS Code)
notepad .env

# 4. Run deploy.sh
./deploy.sh

# 5. Access at http://localhost:8080
```

### Tips for Git Bash

- `nano` is not available; use `notepad .env` or edit with VS Code
- `~` resolves to `C:\Users\<username>`
- All `docker compose` commands work the same way
- If `./deploy.sh` fails with permission errors, run `chmod +x deploy.sh`

---

## Limitations on Windows

- All paths inside Docker containers are Linux paths — no Windows path issues
- File permissions inside the container are not affected by Windows ACLs
- `bench` commands work identically
- The only difference is how you access your terminal and edit files

---

## Accessing the Site

Once running, open `http://localhost:8080` in your Windows browser — same as Linux.

Login: `Administrator` / `admin`
