#!/usr/bin/env bash
# =============================================================
# congbaby GitHub Profile - 一键推送脚本 (简化稳健版)
# 用法:
#   export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
#   bash push_to_github_simple.sh
# =============================================================

# 不用 set -e，手动控制错误处理，更清晰
set +e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${NC}$*"; }
info() { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "  ${RED}[ERROR]${NC} $*"; }

die() {
  err "$1"
  echo ""
  exit 1
}

# ── 配置 ──────────────────────────────────────────────────────
GITHUB_USER="congbaby-3389"
REPO_NAME="congbaby"
COMMIT_MSG="feat: update congbaby profile 💜"

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║   congbaby GitHub Profile - 推送脚本 (简化稳健版)    ║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ══ 第 1 步：检查 Token ══════════════════════════════════════
info "步骤 1/6：检查 GitHub Token..."

if [[ -z "${GITHUB_TOKEN:-}" ]]; then
  echo ""
  warn "未找到 GITHUB_TOKEN 环境变量"
  echo ""
  echo -e "  ${YELLOW}请先设置 Token：${NC}"
  echo -e "    ${CYAN}export GITHUB_TOKEN=ghp_你的token${NC}"
  echo ""
  echo -e "  ${YELLOW}Token 获取地址：${NC}"
  echo -e "    ${CYAN}https://github.com/settings/tokens/new${NC}"
  echo -e "    ${YELLOW}（勾选 repo 权限，然后点 Generate token）${NC}"
  echo ""
  die "Token 未设置"
fi

# 验证 Token：用文件方式，完全避免变量捕获问题
info "  正在验证 Token（访问 api.github.com）..."
AUTH_BODY=$(mktemp)
AUTH_ERR=$(mktemp)

# 超时 15 秒，避免卡死
HTTP_CODE=$(curl -s --connect-timeout 10 --max-time 15 \
  -o "$AUTH_BODY" \
  -w "%{http_code}" \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  "https://api.github.com/user" 2>"$AUTH_ERR")

CURL_EXIT=$?

if [[ $CURL_EXIT -ne 0 ]]; then
  CURL_ERR=$(cat "$AUTH_ERR")
  rm -f "$AUTH_BODY" "$AUTH_ERR"
  echo ""
  warn "curl 命令执行失败（退出码 $CURL_EXIT）"
  echo -e "  ${YELLOW}可能原因：${NC}"
  echo -e "    ${YELLOW}1. 网络不通（国内可能需要代理/加速器访问 GitHub API）${NC}"
  echo -e "    ${YELLOW}2. Token 格式错误（是否包含换行或空格？）${NC}"
  echo -e "  ${YELLOW}curl 错误: ${NC}$CURL_ERR"
  echo ""
  # 不致命，提示用户可以跳过验证
  echo -e "  ${YELLOW}是否跳过 Token 验证，直接尝试 git push？${NC}"
  echo -e "  ${CYAN}输入 y 跳过，输入 n 退出: ${NC}"
  read -r SKIP_AUTH
  if [[ "$SKIP_AUTH" != "y" && "$SKIP_AUTH" != "Y" ]]; then
    die "已取消"
  fi
  warn "已跳过 Token 验证，继续..."
else
  # curl 成功，检查 HTTP 状态码
  # 去掉可能的换行/回车符
  HTTP_CODE=$(echo "$HTTP_CODE" | tr -dc '0-9')
  if [[ "$HTTP_CODE" != "200" ]]; then
    ERR_MSG=$(grep -o '"message":"[^"]*"' "$AUTH_BODY" 2>/dev/null | head -1 | cut -d'"' -f4)
    rm -f "$AUTH_BODY" "$AUTH_ERR"
    echo ""
    err "Token 验证失败（HTTP $HTTP_CODE）"
    [[ -n "$ERR_MSG" ]] && echo -e "  ${RED}GitHub 返回: ${NC}$ERR_MSG"
    echo ""
    echo -e "  ${YELLOW}常见原因：${NC}"
    echo -e "    ${YELLOW}1. Token 已过期或被撤销${NC}"
    echo -e "    ${YELLOW}2. Token 权限不足（需要勾选 repo 权限）${NC}"
    echo -e "    ${YELLOW}3. Token 格式错误（是否复制完整？）${NC}"
    echo ""
    die "Token 无效，请重新生成"
  fi

  # 解析用户名
  AUTH_LOGIN=$(grep -o '"login":"[^"]*"' "$AUTH_BODY" 2>/dev/null | head -1 | cut -d'"' -f4)
  rm -f "$AUTH_BODY" "$AUTH_ERR"

  if [[ -z "$AUTH_LOGIN" ]]; then
    warn "无法解析 GitHub 用户名，但 Token 似乎有效，继续..."
  else
    ok "Token 有效！用户: $AUTH_LOGIN"
    # 检查用户名是否匹配
    if [[ "$AUTH_LOGIN" != "$GITHUB_USER" ]]; then
      warn "Token 所属用户是 '$AUTH_LOGIN'，但目标仓库是 '$GITHUB_USER'"
      warn "Token 需要是 $GITHUB_USER 账户的，或者你拥有推送权限"
      echo -e "  ${CYAN}是否继续？(y/n): ${NC}"
      read -r CONFIRM
      [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]] && die "已取消"
    fi
  fi
fi

echo ""

# ══ 第 2 步：检查依赖 ════════════════════════════════════════
info "步骤 2/6：检查依赖..."
MISSING=0
for cmd in git curl; do
  if ! command -v "$cmd" >/dev/null 2>&1; then
    err "缺少命令: $cmd"
    MISSING=1
  fi
done
[[ $MISSING -eq 1 ]] && die "请先安装缺少的命令"
ok "依赖检查通过（git $(git --version | awk '{print $3}' 2>/dev/null || echo 'unknown')）"
echo ""

# ══ 第 3 步：初始化 git ═══════════════════════════════════════
info "步骤 3/6：初始化本地 git 仓库..."

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$SCRIPT_DIR" || die "无法进入脚本目录"

if [[ ! -d .git ]]; then
  git init -b main
  ok "git 仓库初始化完成（分支: main）"
else
  ok "git 仓库已存在"
fi
echo ""

# ══ 第 4 步：配置 git 用户信息 ══════════════════════════════════
info "步骤 4/6：配置 git 用户信息..."

# 尝试从 Token 验证结果或 git config 获取用户名
CURRENT_USER=$(git config user.name 2>/dev/null || echo "")
CURRENT_EMAIL=$(git config user.email 2>/dev/null || echo "")

if [[ -z "$CURRENT_USER" || -z "$CURRENT_EMAIL" ]]; then
  echo -e "  ${YELLOW}git 用户信息未配置，请输入：${NC}"
  [[ -z "$CURRENT_USER" ]] && read -rp "  用户名: " CURRENT_USER
  [[ -z "$CURRENT_EMAIL" ]] && read -rp "  邮箱: " CURRENT_EMAIL
  git config user.name "$CURRENT_USER"
  git config user.email "$CURRENT_EMAIL"
fi
ok "git 用户: $CURRENT_USER <$CURRENT_EMAIL>"
echo ""

# ══ 第 5 步：生成 README.md ════════════════════════════════════
info "步骤 5/6：生成 README.md..."

cat > README.md << 'READMEEOF'
<div align="center">

#  👋 我是 congbaby

<img src="avatar.svg" alt="avatar" width="120" height="120" style="border-radius:50%; border:3px solid #7c3aed;">

### 🏠 职业恋家工程师 · 安全 & AI 交叉领域

![Profile Views](https://komarev.com/ghpvc/?username=congbaby-3389&color=7c3aed&style=flat-square)
![GitHub Followers](https://img.shields.io/github/followers/congbaby-3389?style=flat-square&color=7c3aed)
![GitHub stars](https://img.shields.io/github/stars/congbaby-3389?style=flat-square&color=f472b6)

---

## 🛠️ 技术栈

![Python](https://img.shields.io/badge/Python-3776AB?style=flat-square&logo=python&logoColor=white)
![Go](https://img.shields.io/badge/Go-00ADD8?style=flat-square&logo=go&logoColor=white)
![Java](https://img.shields.io/badge/Java-ED8B00?style=flat-square&logo=openjdk&logoColor=white)
![TypeScript](https://img.shields.io/badge/TypeScript-3178C6?style=flat-square&logo=typescript&logoColor=white)
![React](https://img.shields.io/badge/React-20232a?style=flat-square&logo=react&logoColor=61DAFB)
![Vue](https://img.shields.io/badge/Vue.js-35495E?style=flat-square&logo=vuedotjs&logoColor=4FC08D)
![PyTorch](https://img.shields.io/badge/PyTorch-EE4C2C?style=flat-square&logo=pytorch&logoColor=white)
![Frida](https://img.shields.io/badge/Frida-6AD0F0?style=flat-square&logo=gnu-bash&logoColor=white)
![IDA Pro](https://img.shields.io/badge/IDA%20Pro-000000?style=flat-square&logo=windows&logoColor=white)
![Docker](https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white)
![Linux](https://img.shields.io/badge/Linux-FCC624?style=flat-square&logo=linux&logoColor=black)
![Android](https://img.shields.io/badge/Android-3DDC84?style=flat-square&logo=android&logoColor=white)

---

## 📊 GitHub 统计

<p align="center">
  <img src="https://github-readme-stats.vercel.app/api?username=congbaby-3389&show_icons=true&theme=tokyonight&hide_border=true&bg_color=0d0d14&title_color=7c3aed&icon_color=f472b6&text_color=a78bfa" height="180"/>
  <img src="https://github-readme-stats.vercel.app/api/top-langs/?username=congbaby-3389&layout=compact&theme=tokyonight&hide_border=true&bg_color=0d0d14&title_color=7c3aed&text_color=a78bfa" height="180"/>
</p>

<p align="center">
  <img src="https://streak-stats.denolab.com/?user=congbaby-3389&theme=tokyonight&hide_border=true&background=0d0d14&ring=7c3aed&fire=f472b6&currStreakLabel=a78bfa" height="180"/>
</p>

---

## 🔗 找到我

[![GitHub](https://img.shields.io/badge/GitHub-181717?style=flat-square&logo=github&logoColor=white)](https://github.com/congbaby-3389)
[![Email](https://img.shields.io/badge/Email-D14836?style=flat-square&logo=gmail&logoColor=white)](mailto:congbaby@example.com)

---

<p align="center">
  <i>「代码是诗，漏洞是韵脚，我在二进制的江湖里，寻找归属。」</i>
</p>

</div>
READMEEOF

ok "README.md 生成完成"
echo ""

# ══ 第 6 步：提交并推送 ════════════════════════════════════════
info "步骤 6/6：提交并推送到 GitHub..."

# 添加所有文件
git add -A

# 检查是否有变更需要提交
if git diff --cached --quiet 2>/dev/null; then
  warn "没有新的变更需要提交，跳过 commit"
else
  git commit -m "$COMMIT_MSG"
  if [[ $? -ne 0 ]]; then
    err "git commit 失败"
    echo -e "  ${YELLOW}可能原因：${NC}"
    echo -e "    ${YELLOW}1. GPG 签名失败（可运行 git config commit.gpgsign false 关闭）${NC}"
    echo -e "    ${YELLOW}2. 没有变更需要提交${NC}"
    die "commit 失败"
  fi
  ok "commit 完成"
fi
echo ""

# 设置 remote（含 Token，push 后清除）
REMOTE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"

# 检查是否已存在 remote
if git remote | grep -q "^origin$"; then
  git remote set-url origin "$REMOTE_URL"
  ok "已更新 remote 'origin' URL"
else
  git remote add origin "$REMOTE_URL"
  ok "已添加 remote 'origin'"
fi

# 尝试创建仓库（忽略失败，仓库可能已存在）
info "  尝试创建远程仓库（若已存在则忽略）..."
CREATE_BODY='{"name":"congbaby","description":"congbaby GitHub Profile","private":false}'
curl -s --connect-timeout 10 --max-time 15 \
  -X POST \
  -H "Authorization: token ${GITHUB_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$CREATE_BODY" \
  "https://api.github.com/user/repos" >/dev/null 2>&1
# 不检查创建结果，push 时会明确报错
echo ""

# Push！
info "  正在 push 到 main 分支..."
git push -u origin main --force-with-lease 2>&1
PUSH_RESULT=$?

# 清除 remote URL 中的 Token（安全）
git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
ok "已清除 remote URL 中的 Token"

if [[ $PUSH_RESULT -ne 0 ]]; then
  echo ""
  err "git push 失败（退出码 $PUSH_RESULT）"
  echo ""
  echo -e "  ${YELLOW}常见原因：${NC}"
  echo -e "    ${YELLOW}1. 仓库不存在，且自动创建失败（手动去 GitHub 创建同名仓库）${NC}"
  echo -e "    ${YELLOW}2. Token 没有 repo 权限${NC}"
  echo -e "    ${YELLOW}3. 网络问题（国内可能需要代理）${NC}"
  echo -e "    ${YELLOW}4. 分支名不是 main（运行 git branch -M main 修正）${NC}"
  echo ""
  die "推送失败"
fi

echo ""
echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}${BOLD}║   🎉 推送成功！                                  ║${NC}"
echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}仓库地址: ${NC}https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo -e "  ${CYAN}Profile 页: ${NC}https://github.com/${GITHUB_USER}"
echo -e "  ${YELLOW}（Profile README 通常在 30 秒内生效，刷新看看）${NC}"
echo ""
