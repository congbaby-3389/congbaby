#!/usr/bin/env bash
# =============================================================
#  GitHub 通用推送脚本 — 代理环境 / SSH / HTTPS Token 三模式
#  =============================================================
#  用法:
#    # 方式1: SSH (推荐，一次配置永久有效)
#    bash github_push.sh --method ssh
#
#    # 方式2: HTTPS + Token
#    export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
#    bash github_push.sh --method token
#
#    # 方式3: 仅使用代理推送 (Token 从环境变量读取)
#    bash github_push.sh --method token --proxy http://127.0.0.1:7897
#
#    # 完整参数
#    bash github_push.sh \
#      --method token \
#      --user congbaby-3389 \
#      --repo congbaby \
#      --branch main \
#      --proxy http://127.0.0.1:7897 \
#      --message "feat: update profile"
# =============================================================
set +e

# ── 颜色 ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

log()  { echo -e "  ${NC}$*"; }
info() { echo -e "  ${CYAN}[INFO]${NC}  $*"; }
ok()   { echo -e "  ${GREEN}[OK]${NC}    $*"; }
warn() { echo -e "  ${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "  ${RED}[ERROR]${NC} $*"; }
die()  { err "$1"; echo ""; exit 1; }

# ── 默认参数 ──────────────────────────────────────────────────
METHOD="ssh"
GITHUB_USER=""
REPO_NAME=""
BRANCH="main"
COMMIT_MSG=""
PROXY_URL=""
TARGET_DIR="."
FORCE_MODE="rebase"  # rebase | force-with-lease | force | safe

# ── 帮助 ──────────────────────────────────────────────────────
usage() {
  echo ""
  echo -e "  ${BOLD}GitHub 通用推送脚本${NC}"
  echo ""
  echo "  用法: bash github_push.sh [选项]"
  echo ""
  echo "  选项:"
  echo "    --method <ssh|token>         认证方式 (默认: ssh)"
  echo "    --user <username>            GitHub 用户名"
  echo "    --repo <repo>                仓库名"
  echo "    --branch <branch>            分支名 (默认: main)"
  echo "    --proxy <url>                代理地址 (如 http://127.0.0.1:7897)"
  echo "    --message <msg>              Commit 信息"
  echo "    --dir <path>                 项目目录 (默认: 当前目录)"
  echo "    --force <mode>               冲突处理方式:"
  echo "                                  rebase  - rebase 合并无关历史 (默认, 安全)"
  echo "                                  merge   - merge 合并无关历史"
  echo "                                  force-with-lease - 安全强制推送"
  echo "                                  force   - 强制覆盖 (危险!)"
  echo "                                  safe    - 仅快进推送，冲突时报错"
  echo "    --ssh-key <path>             SSH 私钥路径 (默认: ~/.ssh/github_<user>)"
  echo "    --setup-ssh                  仅生成并配置 SSH 密钥，不推送"
  echo "    --help                       显示此帮助"
  echo ""
  echo "  环境变量:"
  echo "    GITHUB_TOKEN                 个人访问 Token (method=token 时必需)"
  echo ""
  echo "  示例:"
  echo "    bash github_push.sh --method ssh --user congbaby-3389 --repo congbaby"
  echo "    bash github_push.sh --method token --proxy http://127.0.0.1:7897"
  exit 0
}

# ── 参数解析 ──────────────────────────────────────────────────
while [[ $# -gt 0 ]]; do
  case "$1" in
    --method) METHOD="$2"; shift 2 ;;
    --user) GITHUB_USER="$2"; shift 2 ;;
    --repo) REPO_NAME="$2"; shift 2 ;;
    --branch) BRANCH="$2"; shift 2 ;;
    --proxy) PROXY_URL="$2"; shift 2 ;;
    --message) COMMIT_MSG="$2"; shift 2 ;;
    --dir) TARGET_DIR="$2"; shift 2 ;;
    --force) FORCE_MODE="$2"; shift 2 ;;
    --ssh-key) SSH_KEY="$2"; shift 2 ;;
    --setup-ssh) SETUP_SSH_ONLY=true; shift ;;
    --help) usage ;;
    *) die "未知参数: $1" ;;
  esac
done

# ── 进入项目目录 ──────────────────────────────────────────────
TARGET_DIR="$(cd "$TARGET_DIR" && pwd)" || die "无法进入目录: $TARGET_DIR"
cd "$TARGET_DIR" || die "无法进入目录"

# ── 自动检测 GitHub 用户/仓库 ─────────────────────────────────
if [[ -z "$GITHUB_USER" ]]; then
  GITHUB_USER=$(git config user.name 2>/dev/null || echo "")
fi
if [[ -z "$REPO_NAME" ]]; then
  REPO_NAME=$(basename "$TARGET_DIR")
fi
if [[ -z "$COMMIT_MSG" ]]; then
  COMMIT_MSG="feat: update $(date '+%Y-%m-%d %H:%M')"
fi
if [[ -z "$SSH_KEY" ]]; then
  SSH_KEY="$HOME/.ssh/github_${GITHUB_USER}"
fi

echo ""
echo -e "  ${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${BOLD}║        GitHub 通用推送脚本                            ║${NC}"
echo -e "  ${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
info "参数概览:"
info "  认证方式: ${BOLD}${METHOD}${NC}"
info "  用户/仓库: ${GITHUB_USER}/${REPO_NAME}"
info "  分支: ${BRANCH}"
info "  目录: ${TARGET_DIR}"
[[ -n "$PROXY_URL" ]] && info "  代理: ${PROXY_URL}"
echo ""

# ══════════════════════════════════════════════════════════════
# 步骤 1: 配置代理
# ══════════════════════════════════════════════════════════════
configure_proxy() {
  if [[ -z "$PROXY_URL" ]]; then
    # 没有代理，清除残留
    warn "未配置代理，清除已有代理设置..."
    git config --unset http.proxy 2>/dev/null || true
    git config --unset https.proxy 2>/dev/null || true
    unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY 2>/dev/null || true
    return
  fi

  info "配置代理: $PROXY_URL"

  # git 代理
  git config http.proxy "$PROXY_URL"
  git config https.proxy "$PROXY_URL"

  # 环境变量代理
  export http_proxy="$PROXY_URL"
  export https_proxy="$PROXY_URL"
  export HTTP_PROXY="$PROXY_URL"
  export HTTPS_PROXY="$PROXY_URL"
  export no_proxy=""
  export NO_PROXY=""

  # 验证代理连通性
  info "  验证代理连通性 (github.com)..."
  PROXY_CHECK=$(curl -s --connect-timeout 5 --max-time 10 \
    --proxy "$PROXY_URL" \
    -o /dev/null -w "%{http_code}" \
    "https://github.com" 2>&1)

  if [[ "$PROXY_CHECK" =~ ^(200|301|302)$ ]]; then
    ok "  代理连通正常"
  else
    warn "  代理连通性检查返回 ${PROXY_CHECK}，继续尝试..."
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 2: 初始化 git 仓库
# ══════════════════════════════════════════════════════════════
init_git_repo() {
  info "检查 git 仓库..."

  if [[ ! -d .git ]]; then
    warn "未找到 .git 目录，初始化新仓库..."
    git init
    git checkout -b "$BRANCH" 2>/dev/null || git symbolic-ref HEAD "refs/heads/$BRANCH"
    ok "git 仓库初始化完成 (分支: $BRANCH)"
  else
    ok "git 仓库已存在"

    # 确保在正确分支
    CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")
    if [[ "$CURRENT_BRANCH" != "$BRANCH" ]]; then
      info "  切换到 $BRANCH 分支..."
      git checkout "$BRANCH" 2>/dev/null || git checkout -b "$BRANCH" 2>/dev/null || warn "  无法切换分支"
    fi
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 3: SSH 方式 — 配置密钥
# ══════════════════════════════════════════════════════════════
setup_ssh() {
  info "SSH 密钥配置"

  if [[ -f "$SSH_KEY" ]]; then
    ok "SSH 密钥已存在: $SSH_KEY"
  else
    info "  生成新 Ed25519 密钥..."
    ssh-keygen -t ed25519 -C "${GITHUB_USER}@github" -f "$SSH_KEY" -N "" 2>&1
    if [[ $? -ne 0 ]]; then
      die "SSH 密钥生成失败"
    fi
    ok "SSH 密钥已生成"
  fi

  # 显示公钥
  PUB_KEY="${SSH_KEY}.pub"
  echo ""
  echo -e "  ${YELLOW}${BOLD}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "  ${YELLOW}  📋 请将以下公钥添加到 GitHub:${NC}"
  echo -e "  ${CYAN}  https://github.com/settings/ssh/new${NC}"
  echo ""
  cat "$PUB_KEY" 2>/dev/null | sed 's/^/  /'
  echo ""
  echo -e "  ${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""

  # 配置 SSH config
  SSH_CONFIG="$HOME/.ssh/config"
  mkdir -p "$(dirname "$SSH_CONFIG")"

  # 检查是否已有 github.com 配置
  if grep -q "Host github.com" "$SSH_CONFIG" 2>/dev/null; then
    warn "SSH config 中已有 github.com 配置，跳过"
  else
    info "  添加 SSH config (端口 443 防墙)..."
    cat >> "$SSH_CONFIG" << SSHEOF

# GitHub — 使用 443 端口 (防墙)
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ${SSH_KEY}
    StrictHostKeyChecking no
SSHEOF
    ok "SSH config 已更新 (ssh.github.com:443)"
  fi

  # 如果只是配置 SSH，到此结束
  if [[ "$SETUP_SSH_ONLY" == "true" ]]; then
    echo ""
    echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
    echo -e "  ${GREEN}${BOLD}║   SSH 配置完成！请将上面的公钥添加到 GitHub        ║${NC}"
    echo -e "  ${GREEN}${BOLD}║   然后运行: bash github_push.sh --method ssh --user ${GITHUB_USER} --repo ${REPO_NAME}${NC}"
    echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
    echo ""
    exit 0
  fi

  # 测试 SSH 连接
  info "  测试 SSH 连接..."
  SSH_TEST=$(ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 -T git@github.com 2>&1)
  SSH_EXIT=$?

  if [[ "$SSH_TEST" == *"successfully authenticated"* ]]; then
    ok "  SSH 连接成功！用户: $(echo "$SSH_TEST" | grep -oP '(?<=Hi ).*(?=!)')"
  else
    echo ""
    warn "SSH 连接测试未通过 (退出码 $SSH_EXIT)"
    echo -e "  ${YELLOW}常见原因:${NC}"
    echo -e "  ${YELLOW}  1. 公钥尚未添加到 GitHub${NC}"
    echo -e "  ${YELLOW}  2. 网络需要代理 (SSH 不走 HTTP 代理)${NC}"
    echo -e "  ${YELLOW}  3. 22 和 443 端口都被墙${NC}"
    echo ""
    echo -e "  ${CYAN}是否改用 Token 方式？(y/n): ${NC}"
    read -r USE_TOKEN
    if [[ "$USE_TOKEN" == "y" || "$USE_TOKEN" == "Y" ]]; then
      METHOD="token"
      warn "已切换到 Token 方式"
    else
      die "SSH 连接失败，已取消"
    fi
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 4: Token 方式 — 检查 Token
# ══════════════════════════════════════════════════════════════
check_token() {
  if [[ -z "${GITHUB_TOKEN:-}" ]]; then
    echo ""
    warn "未找到 GITHUB_TOKEN 环境变量"
    echo ""
    echo -e "  ${YELLOW}请设置 Token：${NC}"
    echo -e "    ${CYAN}export GITHUB_TOKEN=ghp_你的token${NC}"
    echo ""
    echo -e "  ${YELLOW}获取 Token: ${NC}https://github.com/settings/tokens/new"
    echo -e "  ${YELLOW}(勾选 repo 权限)${NC}"
    echo ""
    die "Token 未设置"
  fi

  info "验证 GitHub Token..."

  if [[ -n "$PROXY_URL" ]]; then
    CURL_PROXY="--proxy $PROXY_URL"
  else
    CURL_PROXY=""
  fi

  HTTP_CODE=$(curl -s $CURL_PROXY --connect-timeout 10 --max-time 15 \
    -o /dev/null -w "%{http_code}" \
    -H "Authorization: token ${GITHUB_TOKEN}" \
    "https://api.github.com/user" 2>/dev/null)

  if [[ "$HTTP_CODE" == "200" ]]; then
    ok "Token 有效"
  else
    err "Token 验证失败 (HTTP $HTTP_CODE)"
    die "请检查 Token 是否正确或已过期"
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 5: 配置 Remote
# ══════════════════════════════════════════════════════════════
setup_remote() {
  info "配置远程仓库..."

  if [[ "$METHOD" == "ssh" ]]; then
    REMOTE_URL="git@github.com:${GITHUB_USER}/${REPO_NAME}.git"
  else
    REMOTE_URL="https://${GITHUB_USER}:${GITHUB_TOKEN}@github.com/${GITHUB_USER}/${REPO_NAME}.git"
  fi

  if git remote | grep -q "^origin$"; then
    git remote set-url origin "$REMOTE_URL"
    ok "已更新 origin: ${METHOD}://"
  else
    git remote add origin "$REMOTE_URL"
    ok "已添加 origin: ${METHOD}://"
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 6: 提交变更
# ══════════════════════════════════════════════════════════════
commit_changes() {
  info "添加并提交变更..."

  git add -A

  if git diff --cached --quiet 2>/dev/null; then
    warn "没有新的变更需要提交，跳过 commit"
    SKIP_COMMIT=true
  else
    git commit -m "$COMMIT_MSG"
    if [[ $? -eq 0 ]]; then
      ok "commit 完成: $COMMIT_MSG"
    else
      warn "commit 失败或无变更"
      SKIP_COMMIT=true
    fi
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 7: 推送 (核心 — 处理多种冲突)
# ══════════════════════════════════════════════════════════════
push_with_retry() {
  info "推送到 GitHub..."

  # 先获取远程信息
  git fetch origin "$BRANCH" 2>/dev/null
  FETCH_OK=$?

  # 检查是否有没有共同祖先的情况
  if [[ $FETCH_OK -eq 0 ]]; then
    LOCAL_HASH=$(git rev-parse HEAD 2>/dev/null)
    REMOTE_HASH=$(git rev-parse "origin/$BRANCH" 2>/dev/null)
  fi

  PUSH_RESULT=1
  RETRY=0
  MAX_RETRIES=3

  while [[ $PUSH_RESULT -ne 0 && $RETRY -lt $MAX_RETRIES ]]; do
    if [[ $RETRY -gt 0 ]]; then
      WAIT=$((RETRY * 2))
      warn "  第 $RETRY 次重试，等待 ${WAIT} 秒..."
      sleep "$WAIT"
    fi

    PUSH_OUTPUT=$(git push origin "$BRANCH" 2>&1)
    PUSH_RESULT=$?

    # 推送成功
    if [[ $PUSH_RESULT -eq 0 ]]; then
      ok "  push 成功!"
      break
    fi

    # 非快进错误 → 自动处理
    if echo "$PUSH_OUTPUT" | grep -q "non-fast-forward"; then
      warn "  远程有更新，需要合并..."

      case "$FORCE_MODE" in
        rebase)
          info "  尝试 rebase (--allow-unrelated-histories)..."
          if git pull origin "$BRANCH" --rebase --allow-unrelated-histories 2>/dev/null; then
            ok "  rebase 成功，重新推送..."
          else
            warn "  rebase 失败，尝试 merge..."
            git pull origin "$BRANCH" --no-rebase --allow-unrelated-histories 2>/dev/null || true
          fi
          ;;
        merge)
          info "  尝试 merge (--allow-unrelated-histories)..."
          git pull origin "$BRANCH" --no-rebase --allow-unrelated-histories 2>/dev/null || true
          ;;
        force-with-lease)
          warn "  使用 --force-with-lease 推送..."
          git push origin "$BRANCH" --force-with-lease 2>&1
          PUSH_RESULT=$?
          break
          ;;
        force)
          warn "  ⚠️ 使用 --force 强制覆盖远程..."
          git push origin "$BRANCH" --force 2>&1
          PUSH_RESULT=$?
          break
          ;;
        safe)
          err "  远程有冲突，safe 模式不自动处理"
          echo -e "  ${YELLOW}  请手动 git pull 或指定 --force rebase${NC}"
          die "推送失败 (safe mode)"
          ;;
      esac
      RETRY=$((RETRY + 1))
      continue
    fi

    # 不相关历史错误
    if echo "$PUSH_OUTPUT" | grep -q "unrelated histories"; then
      warn "  本地与远程历史不相关，尝试 rebase..."
      git pull origin "$BRANCH" --rebase --allow-unrelated-histories 2>/dev/null || \
        git pull origin "$BRANCH" --no-rebase --allow-unrelated-histories 2>/dev/null
      RETRY=$((RETRY + 1))
      continue
    fi

    # 其他错误
    err "  push 失败: $PUSH_OUTPUT"
    RETRY=$((RETRY + 1))
  done

  if [[ $PUSH_RESULT -ne 0 ]]; then
    echo ""
    err "  ❌ push 失败 (退出码 $PUSH_RESULT, 已重试 $((RETRY)) 次)"
    echo ""
    echo -e "  ${YELLOW}常见原因:${NC}"
    echo -e "  ${YELLOW}  1. 认证失败 (Token 过期 / SSH 密钥未添加)${NC}"
    echo -e "  ${YELLOW}  2. 网络/代理不通${NC}"
    echo -e "  ${YELLOW}  3. 远程仓库不存在${NC}"
    echo -e "  ${YELLOW}  4. 权限不足${NC}"
    echo ""
    die "推送失败"
  fi
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 步骤 8: 清理凭据
# ══════════════════════════════════════════════════════════════
cleanup() {
  info "清理凭据..."

  # Token 方式：清除 remote URL 中的 Token
  if [[ "$METHOD" == "token" ]]; then
    git remote set-url origin "https://github.com/${GITHUB_USER}/${REPO_NAME}.git"
    ok "已清除 remote URL 中的 Token"
  fi

  # 清除 git 代理
  git config --unset http.proxy 2>/dev/null || true
  git config --unset https.proxy 2>/dev/null || true

  # 清除环境变量代理
  unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY no_proxy NO_PROXY 2>/dev/null || true

  ok "凭据和代理配置已清除"
  echo ""
}

# ══════════════════════════════════════════════════════════════
# 主流程
# ══════════════════════════════════════════════════════════════
configure_proxy
init_git_repo

if [[ "$METHOD" == "ssh" ]]; then
  setup_ssh
else
  check_token
fi

setup_remote
commit_changes
push_with_retry
cleanup

# ── 成功 ──────────────────────────────────────────────────────
echo -e "  ${GREEN}${BOLD}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "  ${GREEN}${BOLD}║   🎉 推送成功！                                    ║${NC}"
echo -e "  ${GREEN}${BOLD}╚══════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "  ${CYAN}仓库: ${NC}https://github.com/${GITHUB_USER}/${REPO_NAME}"
echo -e "  ${CYAN}分支: ${NC}${BRANCH}"
echo -e "  ${CYAN}方式: ${NC}${METHOD}"
echo ""
