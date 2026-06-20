#!/usr/bin/env bash
# =============================================================
# congbaby GitHub Profile - 一键推送脚本
# One-click push script for congbaby GitHub profile
#
# 用法 / Usage:
#   1. 先在 GitHub 创建同名仓库 congbaby-3389/congbaby（公开，不要加任何初始文件）
#      Create a public repo named "congbaby" under congbaby-3389, NO README/gitignore
#   2. 设置你的 Token / Set your PAT:
#      export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
#   3. 运行此脚本 / Run:
#      bash push_to_github.sh
# =============================================================

set -euo pipefail

# ── 配置 / Config ──────────────────────────────────────────
GITHUB_USER="congbaby-3389"         # GitHub 用户名
REPO_NAME="congbaby"                # 仓库名（与用户名同名才是 Profile README）
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 颜色输出 / Color output ────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; PURPLE='\033[0;35m'; NC='\033[0m'
info()  { echo -e "${CYAN}[INFO]${NC}  $*"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $*"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $*"; }
error() { echo -e "${RED}[ERROR]${NC} $*"; exit 1; }

echo -e "${PURPLE}"
echo "  ╔══════════════════════════════════════╗"
echo "  ║    congbaby GitHub Profile Pusher    ║"
echo "  ╚══════════════════════════════════════╝"
echo -e "${NC}"

# ── 检查 Token ─────────────────────────────────────────────
# Check if GITHUB_TOKEN is set
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo -e "${YELLOW}请输入你的 GitHub Personal Access Token (repo 权限):${NC}"
  echo -e "${YELLOW}Enter your GitHub PAT (needs repo permission):${NC}"
  read -rs GITHUB_TOKEN
  echo ""
fi
[[ -z "$GITHUB_TOKEN" ]] && error "Token 不能为空 / Token cannot be empty"

# ── 检查依赖 / Check dependencies ──────────────────────────
for cmd in git curl; do
  command -v "$cmd" &>/dev/null || error "缺少命令: $cmd / Missing command: $cmd"
done
ok "依赖检查通过 / Dependencies OK"

# ── 通过 API 创建仓库（若不存在）/ Create repo via API ────
info "检查仓库是否存在... / Checking if repo exists..."
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}")

if [[ "$HTTP_STATUS" == "404" ]]; then
  info "仓库不存在，正在创建... / Repo not found, creating..."
  CREATE_RESP=$(curl -s -w "\n%{http_code}" \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    "https://api.github.com/user/repos" \
    -d "{
      \"name\": \"${REPO_NAME}\",
      \"description\": \"🏠 congbaby's GitHub Profile — 恋家工程师 × AI × Security × Full-Stack\",
      \"private\": false,
      \"auto_init\": false
    }")
  CREATE_STATUS=$(echo "$CREATE_RESP" | tail -1)
  if [[ "$CREATE_STATUS" == "201" ]]; then
    ok "仓库创建成功！ / Repo created!"
    # Wait for GitHub to fully initialize
    # 等待 GitHub 初始化
    sleep 2
  else
    error "仓库创建失败 (HTTP $CREATE_STATUS) / Repo creation failed\n$(echo "$CREATE_RESP" | head -1)"
  fi
elif [[ "$HTTP_STATUS" == "200" ]]; then
  ok "仓库已存在 / Repo already exists"
else
  error "API 请求失败 (HTTP $HTTP_STATUS) / API request failed"
fi

# ── 初始化本地 git / Init local git ──────────────────────
cd "$SCRIPT_DIR"
info "初始化 Git 仓库... / Initializing git repo..."

if [[ -d ".git" ]]; then
  warn ".git 目录已存在，将重置远程 / .git exists, resetting remote"
else
  git init
  ok "Git 初始化完成 / Git initialized"
fi

# 设置 Git 用户信息 / Set git identity
git config user.name  "${GITHUB_USER}"
git config user.email "${GITHUB_USER}@users.noreply.github.com"

# 设置远程地址（含 Token）/ Set remote with token
REMOTE_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_URL"
ok "远程仓库设置完成 / Remote set"

# ── 生成 README.md ─────────────────────────────────────────
info "生成 README.md..."
cat > "$SCRIPT_DIR/README.md" << 'READMEEOF'
<div align="center">

<!-- 古风美女头像 -->
<img src="./avatar.svg" width="160" height="160" style="border-radius:50%;border:3px solid #7c3aed;" alt="congbaby avatar"/>

# 👋 Hi, I'm **congbaby**

### 🏠 恋家工程师 · Full-Stack × AI × Security

[![GitHub followers](https://img.shields.io/github/followers/congbaby-3389?style=flat-square&color=a78bfa&labelColor=1a1a2e)](https://github.com/congbaby-3389)
[![Profile Views](https://komarev.com/ghpvc/?username=congbaby-3389&style=flat-square&color=7c3aed)](https://github.com/congbaby-3389)

</div>

---

```bash
❯ whoami
> congbaby · 恋家工程师 · AI × Security × Full-Stack
❯ cat interests.txt
> 🏠 在家写代码 · 🤖 搞 AI · 🔐 挖洞 · 🍜 煮泡面
❯ echo $CURRENT_VIBE
> "窝在被窝里 debug，幸福指数 MAX"
```

---

## 🛠 Tech Stack

**Frontend**  
![Vue](https://img.shields.io/badge/Vue_3-4FC08D?style=flat-square&logo=vue.js&logoColor=white)
![React](https://img.shields.io/badge/React-61DAFB?style=flat-square&logo=react&logoColor=black)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=flat-square&logo=typescript&logoColor=white)
![Tailwind](https://img.shields.io/badge/Tailwind-06B6D4?style=flat-square&logo=tailwindcss&logoColor=white)

**Backend**  
![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![Go](https://img.shields.io/badge/Go-00ADD8?style=flat-square&logo=go&logoColor=white)
![Java](https://img.shields.io/badge/Java-ED8B00?style=flat-square&logo=openjdk&logoColor=white)
![Node.js](https://img.shields.io/badge/Node.js-339933?style=flat-square&logo=nodedotjs&logoColor=white)

**AI / ML**  
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?style=flat-square&logo=pytorch&logoColor=white)
![LangChain](https://img.shields.io/badge/LangChain-1C3C3C?style=flat-square&logo=langchain&logoColor=white)

**Security & Reverse**  
![Frida](https://img.shields.io/badge/Frida-purple?style=flat-square)
![IDA Pro](https://img.shields.io/badge/IDA_Pro-gray?style=flat-square)
![Burp Suite](https://img.shields.io/badge/Burp_Suite-FF6633?style=flat-square&logo=burpsuite&logoColor=white)

**DevOps**  
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black)

---

## 📊 GitHub Stats

<div align="center">

![GitHub Stats](https://github-readme-stats.vercel.app/api?username=congbaby-3389&show_icons=true&theme=tokyonight&hide_border=true&bg_color=0d0d14&title_color=a78bfa&icon_color=67e8f9&text_color=94a3b8&ring_color=7c3aed)

![Top Langs](https://github-readme-stats.vercel.app/api/top-langs/?username=congbaby-3389&layout=compact&theme=tokyonight&hide_border=true&bg_color=0d0d14&title_color=a78bfa&text_color=94a3b8)

![Streak](https://github-readme-streak-stats.herokuapp.com/?user=congbaby-3389&theme=tokyonight&hide_border=true&background=0d0d14&ring=7c3aed&fire=f472b6&currStreakLabel=a78bfa)

</div>

---

## 🌸 Featured Projects

| Project | Description | Stars |
|---------|-------------|-------|
| 🛡 [homeguard-ai](https://github.com/congbaby-3389) | 家庭网络安全 AI 监控 | ⭐ |
| 🔬 [frida-studio](https://github.com/congbaby-3389) | 可视化 Frida 调试 IDE | ⭐ |
| 🤖 [llm-proxy](https://github.com/congbaby-3389) | 多模型 LLM 统一网关 | ⭐ |
| 📝 [cong-blog](https://github.com/congbaby-3389) | Vue3 + Go 极简博客 | ⭐ |

---

<div align="center">

> *"The best place to write code is home,*  
> *the best time is always now."*  
> — congbaby，窝在被窝里

**[🌐 主页](https://congbaby-3389.github.io/congbaby)** · Made with ♥ and ☕

</div>
READMEEOF

ok "README.md 生成完成 / README.md generated"

# ── 暂存所有文件 / Stage all files ───────────────────────
info "暂存文件... / Staging files..."
git add .
git status --short

# ── 提交 / Commit ─────────────────────────────────────────
info "提交... / Committing..."
git commit -m "✨ feat: congbaby profile — 古风二次元美女头像 + 暗黑主页

- 添加 SVG 古风美女头像 (avatar.svg)
- 暗黑二次元风格主页 (index.html)
- GitHub 统计卡片 / 技术栈 / 项目展示
- 鼠标粒子特效 + 打字机终端动画
- 完整 README.md (Profile README)" 2>/dev/null || true

# ── 推送 / Push ───────────────────────────────────────────
info "推送到 GitHub... / Pushing to GitHub..."
git branch -M "$BRANCH"
git push -u origin "$BRANCH" --force

ok "🎉 推送完成！/ Push complete!"
echo ""
echo -e "${PURPLE}  ┌─────────────────────────────────────────────┐${NC}"
echo -e "${PURPLE}  │  仓库地址 / Repo URL:                        │${NC}"
echo -e "${CYAN}  │  https://github.com/${GITHUB_USER}/${REPO_NAME}         │${NC}"
echo -e "${PURPLE}  │  主页预览 / Profile:                          │${NC}"
echo -e "${CYAN}  │  https://github.com/${GITHUB_USER}               │${NC}"
echo -e "${PURPLE}  └─────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${GREEN}  ✓ Profile README 已激活（同名仓库自动生效）${NC}"
echo -e "${GREEN}  ✓ Profile README activated (same-name repo auto-detected)${NC}"
