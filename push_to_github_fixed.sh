#!/usr/bin/env bash
# =============================================================
# congbaby GitHub Profile - 一键推送脚本 (对抗测试修复版)
# Adversarial-testing fixed version
#
# 用法:
#   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
#   bash push_to_github_fixed.sh
# =============================================================

set -uo pipefail
trap 'echo -e "\033[0;31m[ERROR]\033[0m 第 $LINENO 行失败，脚本中止"; exit 1' ERR

# ── 配置 ──────────────────────────────────────────────────────
GITHUB_USER="congbaby-3389"
REPO_NAME="congbaby"
BRANCH="main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ── 颜色输出 ──────────────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; P='\033[0;35m'; NC='\033[0m'
info()  { echo -e "${C}[INFO]${NC}  $*"; }
ok()    { echo -e "${G}[OK]${NC}    $*"; }
warn()  { echo -e "${Y}[WARN]${NC}  $*"; }
die()   { echo -e "${R}[ERROR]${NC} $*"; exit 1; }

echo -e "${P}"
echo "  ╔══════════════════════════════════════════════╗"
echo "  ║   congbaby GitHub Profile - Fixed Pusher v2       ║"
echo "  ╚══════════════════════════════════════════════╝"
echo -e "${NC}"

# ══ 1. Token 检查 + 验证 ═══════════════════════════════
info "步骤 1/8：检查 GitHub Token..."

# 从环境变量读取，没有则交互式输入
if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  # 尝试从 git credential 读取
  GITHUB_TOKEN=$(git credential fill 2>/dev/null <<< "protocol=https
host=github.com
" | sed -n 's/^password //p' || true)
  if [[ -z "$GITHUB_TOKEN" ]]; then
    echo -e "${Y}未找到 GITHUB_TOKEN，请粘贴你的 PAT (repo 权限):${NC}"
    # 兼容 pipe 场景：若 stdin 不是 tty，直接从 /dev/tty 读（需用户手动运行）
    if [[ -t 0 ]]; then
      read -rs GITHUB_TOKEN < /dev/tty
    else
      echo -e "${R}错误：非交互式环境，请先 export GITHUB_TOKEN${NC}"
      echo -e "${R}Error: non-interactive shell, please set GITHUB_TOKEN first${NC}"
      exit 1
    fi
    echo ""
  fi
fi
[[ -z "$GITHUB_TOKEN" ]] && die "Token 不能为空"

# 验证 Token 有效性 + 获取真实用户名
info "验证 Token 有效性..."

AUTH_BODY=$(mktemp)

# 用文件存放 status code，完全避免变量捕获问题
STATUS_FILE=$(mktemp)
curl -s \
  -o "$AUTH_BODY" \
  -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/user" > "$STATUS_FILE"

AUTH_STATUS=$(cat "$STATUS_FILE" | tr -d '\n\r ')
rm -f "$STATUS_FILE"

info "  [调试] HTTP 状态码: '$AUTH_STATUS'"

if [[ "$AUTH_STATUS" != "200" ]]; then
  ERR_MSG=$(cat "$AUTH_BODY" 2>/dev/null | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
  rm -f "$AUTH_BODY"
  die "Token 无效或已过期 (HTTP: $AUTH_STATUS)${ERR_MSG:+: $ERR_MSG}"
fi

AUTH_LOGIN=$(grep -o '"login":"[^"]*"' "$AUTH_BODY" | head -1 | cut -d'"' -f4)
rm -f "$AUTH_BODY"

if [[ -z "$AUTH_LOGIN" ]]; then
  die "无法解析 GitHub 用户名，Token 可能权限不足（或网络异常）"
fi

ok "Token 有效！用户: $AUTH_LOGIN"

# 检查 Token 是否有 repo 权限（通过尝试访问私有信息）
SCOPE_CHECK=$(curl -s -I \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/user/repos?per_page=1" \
  | grep -i "x-oauth-scopes:" | head -1)
info "Token 权限范围: ${SCOPE_CHECK:-（无法检测，继续）}"

# ══ 2. 检查依赖 ══════════════════════════════════════════
info "步骤 2/8：检查依赖..."
for cmd in git curl; do
  command -v "$cmd" >/dev/null 2>&1 || die "缺少命令: $cmd"
done
ok "依赖检查通过 (git $(git --version | awk '{print $3}'))"

# ══ 3. 创建仓库（若不存在）══════════════════════════════════
info "步骤 3/8：检查仓库 ${GITHUB_USER}/${REPO_NAME}..."

# 用正确的 URL（注意：GitHub API 返回 404 表示仓库不存在）
HTTP_STATUS=$(curl -s -o /dev/null -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/repos/${GITHUB_USER}/${REPO_NAME}")

if [[ "$HTTP_STATUS" == "404" ]]; then
  info "仓库不存在，正在创建..."
  # 用 jq 安全构造 JSON（无可 fallback 到手工转义）
  if command -v jq >/dev/null 2>&1; then
    CREATE_BODY=$(jq -n \
      --arg name "$REPO_NAME" \
      --arg desc "congbaby GitHub Profile" \
      '{name: $name, description: $desc, private: false, auto_init: false}')
  else
    # 手工 JSON：description 中避免单引号，用 jq 或手动转义
    CREATE_BODY="{\"name\":\"${REPO_NAME}\",\"description\":\"congbaby GitHub Profile\",\"private\":false,\"auto_init\":false}"
  fi
  # 创建仓库：用临时文件分离 body 和 status code
  CREATE_BODY_TMP=$(mktemp)
  CREATE_STATUS=$(curl -s -w "%{http_code}" \
    -X POST \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    -H "Accept: application/vnd.github.v3+json" \
    -H "Content-Type: application/json" \
    -d "$CREATE_BODY" \
    -o "$CREATE_BODY_TMP" \
    "https://api.github.com/user/repos")
  if [[ "$CREATE_STATUS" == "201" ]]; then
    ok "仓库创建成功！"
    rm -f "$CREATE_BODY_TMP"
    sleep 3  # GitHub 一致性延迟
  else
    ERR_MSG=$(cat "$CREATE_BODY_TMP" 2>/dev/null | grep -o '"message":"[^"]*"' | head -1 | cut -d'"' -f4)
    rm -f "$CREATE_BODY_TMP"
    die "仓库创建失败 (HTTP $CREATE_STATUS)${ERR_MSG:+: $ERR_MSG}"
  fi
elif [[ "$HTTP_STATUS" == "200" ]]; then
  ok "仓库已存在"
else
  die "API 请求失败 (HTTP $HTTP_STATUS)"
fi

# ══ 4. 初始化本地 git ═════════════════════════════════════
cd "$SCRIPT_DIR"
info "步骤 4/8：初始化 Git..."

NEED_INIT=false
if [[ ! -d ".git" ]]; then
  NEED_INIT=true
  # Git 2.28+ 支持 --initial-branch
  if git --version | grep -q "version 2\.[28-9][0-9]*\(\| version [3-9]"; then
    git init --initial-branch="$BRANCH"
  else
    git init
    git checkout -b "$BRANCH" 2>/dev/null || true
  fi
  ok "Git 初始化完成 (branch: $BRANCH)"
else
  warn ".git 已存在，复用"
fi

git config user.name  "congbaby"
git config user.email "congbaby@users.noreply.github.com"

# ══ 5. 生成 README.md ══════════════════════════════════════
info "步骤 5/8：生成 README.md..."
cat > "$SCRIPT_DIR/README.md" << 'READMEEOF'
<div align="center">

<img src="./avatar.svg" width="160" height="160" style="border-radius:50%;border:3px solid #7c3aed;" alt="congbaby avatar"/>

# 👋 Hi, I'm **congbaby**

### 🏠 恋家工程师 · Full-Stack × AI × Security

![GitHub followers](https://img.shields.io/github/followers/congbaby-3389?style=flat-square&color=a78bfa&labelColor=1a1a2e)
![Profile Views](https://komarev.com/ghpvc/?username=congbaby-3389&style=flat-square&color=7c3aed)

</div>

---

```bash
$ whoami
> congbaby · 恋家工程师 · AI × Security × Full-Stack
$ cat interests.txt
> 🏠 在家写代码 · 🤖 搞 AI · 🔐 挖洞 · 🍜 煮泡面
$ echo $CURRENT_VIBE
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
![LangChain](https://img.shields.io/badge/LangChain-1C3C3C?style=flat-square)

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

![Top Languages](https://github-readme-stats.vercel.app/api/top-langs/?username=congbaby-3389&layout=compact&theme=tokyonight&hide_border=true&bg_color=0d0d14&title_color=a78bfa&text_color=94a3b8)

![Streak](https://streak-stats.denolab.com/?user=congbaby-3389&theme=tokyonight&hide_border=true&background=0d0d14&ring=7c3aed&fire=f472b6&currStreakLabel=a78bfa)

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

ok "README.md 生成完成"

# ══ 6. 暂存文件 ═══════════════════════════════════════════
info "步骤 6/8：暂存文件..."
git add .
STAGED=$(git diff --cached --name-only)
if [[ -z "$STAGED" ]]; then
  warn "没有文件变更，跳过提交"
else
  git status --short
  # ══ 7. 提交 ═══════════════════════════════════════════════
  info "步骤 7/8：提交..."
  COMMIT_MSG="feat: congbaby profile — 古风二次元美女头像 + 暗黑主页

- 添加 SVG 古风美女头像 (avatar.svg)
- 暗黑二次元风格主页 (index.html)
- GitHub 统计卡片 / 技术栈 / 项目展示
- 鼠标粒子特效 + 打字机终端动画
- 完整 README.md (Profile README)"
  if ! git commit -m "$COMMIT_MSG"; then
    die "提交失败（可能是签名/GPG 配置问题）"
  fi
  ok "提交完成"
fi

# ══ 8. 推送（Token 不写入 .git/config）══════════════════════
info "步骤 8/8：推送到 GitHub..."

# 设置不含 Token 的 remote URL（仅用于 git 引用）
REMOTE_PLAIN="https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
git remote remove origin 2>/dev/null || true
git remote add origin "$REMOTE_PLAIN"

# 确保分支名
git branch -M "$BRANCH" 2>/dev/null || true

# 检查是否有 commit 可推送
if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
  die "没有可推送的提交，请检查 git log"
fi

# 用含 Token 的 URL 直接推送（不写入 config）
PUSH_URL="https://${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
info "正在 push（Token 未写入 .git/config）..."
if git push "$PUSH_URL" "refs/heads/${BRANCH}:refs/heads/${BRANCH}" --force-with-lease 2>&1; then
  ok "推送成功！"
else
  warn "force-with-lease 失败，尝试普通强制推送..."
  if git push "$PUSH_URL" "$BRANCH" --force 2>&1; then
    ok "推送成功（强制）！"
  else
    die "推送失败（请检查 Token 权限和网络连接）"
  fi
fi

# 清理：确认 remote URL 不含 Token
FINAL_REMOTE=$(git remote get-url origin 2>/dev/null || echo "")
if [[ "$FINAL_REMOTE" == *"$GITHUB_TOKEN"* ]]; then
  warn "检测到 remote URL 中含 Token，正在清除..."
  git remote set-url origin "$REMOTE_PLAIN"
fi
ok "Remote URL 已清理（不含 Token）"

# ══ 完成 ═══════════════════════════════════════════════════
echo ""
echo -e "${P}  ┌─────────────────────────────────────────────┐${NC}"
echo -e "${P}  │  仓库地址:                                    │${NC}"
echo -e "${C}  │  https://github.com/${GITHUB_USER}/${REPO_NAME}         │${NC}"
echo -e "${P}  │  Profile:                                     │${NC}"
echo -e "${C}  │  https://github.com/${GITHUB_USER}               │${NC}"
echo -e "${P}  └─────────────────────────────────────────────┘${NC}"
echo ""
echo -e "${G}  ✓ Profile README 已激活！${NC}"
echo -e "${G}  ✓ Profile README activated!${NC}"
echo ""
echo -e "${Y}  ⚠️  请手动清除环境变量: unset GITHUB_TOKEN${NC}"
