# 🚀 GitHub 推送完全指南

> **适用场景**: Windows 代理环境 · 墙内网络 · GitHub 认证 · 常见报错排查
>
> 📅 最后更新: 2026-06-20

---

## 📋 目录

1. [快速开始](#-快速开始)
2. [两种认证方式](#-两种认证方式)
3. [代理配置](#-代理配置)
4. [常见报错与解决](#-常见报错与解决)
5. [完整流程回顾](#-完整流程回顾)
6. [命令速查表](#-命令速查表)

---

## ⚡ 快速开始

### 一键推送（推荐）

```bash
# SSH 方式（一次配置，永久使用）
bash github_push.sh --method ssh --user 你的用户名 --repo 仓库名

# Token 方式（需要先设置环境变量）
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
bash github_push.sh --method token --proxy http://127.0.0.1:7897
```

### 仅配置 SSH 密钥（不推送）

```bash
bash github_push.sh --setup-ssh --user 你的用户名
```

---

## 🔐 两种认证方式

### 方式 1: SSH（推荐 👍）

**优点**: 一次配置永久有效，无需记 Token，安全性高
**缺点**: 端口 22/443 可能被墙

#### 生成密钥

```bash
ssh-keygen -t ed25519 -C "你的用户名@github" -f ~/.ssh/github_你的用户名
```

#### 配置 SSH (~/.ssh/config)

```bash
Host github.com
    HostName ssh.github.com
    Port 443
    User git
    IdentityFile ~/.ssh/github_你的用户名
    StrictHostKeyChecking no
```

> 💡 **为什么用 443 端口？** `ssh.github.com` 用 443 端口替代 22，大部分防火墙放行 HTTPS 443 端口，能绕过 SSH 端口封锁。

#### 添加公钥到 GitHub

1. 查看公钥: `cat ~/.ssh/github_你的用户名.pub`
2. 打开 https://github.com/settings/ssh/new
3. 粘贴公钥，保存

#### 测试连接

```bash
ssh -T git@github.com
# 成功 → "Hi 你的用户名! You've successfully authenticated..."
```

---

### 方式 2: HTTPS + Personal Access Token

**优点**: 走 HTTP 代理，不受端口封锁
**缺点**: Token 有有效期，需定期更换

#### 获取 Token

1. 打开 https://github.com/settings/tokens/new
2. Note: 随便填（如 `push script`）
3. Expiration: 选一个有效期
4. 勾选 **`repo`** 权限（完整仓库访问）
5. 点击 **Generate token**
6. 复制 `ghp_...` 开头的 Token（**只显示一次！**）

#### 使用 Token

```bash
# 方式 A: 环境变量（推荐）
export GITHUB_TOKEN=ghp_xxxxxxxxxxxxxxxx
bash github_push.sh --method token

# 方式 B: 直接嵌入 URL
git remote set-url origin "https://用户名:ghp_xxxx@github.com/用户名/仓库.git"
git push origin main
# ⚠️ push 后记得清除 Token！
git remote set-url origin "https://github.com/用户名/仓库.git"
```

> ⚠️ **安全提醒**: 推送完成后立即清除 remote URL 中的 Token，避免泄露。

---

## 🌐 代理配置

### 为什么需要代理？

国内网络访问 GitHub 不稳定，需要通过代理（如 Clash/Clash Verge/V2Ray）。

本脚本默认代理地址: `http://127.0.0.1:7897`

### 手动配置代理

```bash
# Git 代理
git config http.proxy http://127.0.0.1:7897
git config https.proxy http://127.0.0.1:7897

# 环境变量（curl 等工具使用）
export http_proxy=http://127.0.0.1:7897
export https_proxy=http://127.0.0.1:7897

# 清除代理
git config --unset http.proxy
git config --unset https.proxy
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
```

### 验证代理连通性

```bash
curl --proxy http://127.0.0.1:7897 -I https://github.com
# HTTP/2 200 → 代理正常
```

---

## 🔧 常见报错与解决

### 1️⃣ `fatal: Authentication failed`

```
remote: Invalid username or token.
Password authentication is not supported for Git operations.
```

**原因**: 密码认证已被 GitHub 禁用（2021年起）

**解决**:
- ✅ 使用 **Personal Access Token** 代替密码
- ✅ 或改用 **SSH** 认证

---

### 2️⃣ `fatal: refusing to merge unrelated histories`

```
From https://github.com/user/repo
 * branch            main       -> FETCH_HEAD
fatal: refusing to merge unrelated histories
```

**原因**: 本地仓库和远程仓库没有共同的提交历史（通常是本地 `git init` + 远程 `Initial commit` 各生成了一个根提交）

**解决**:

```bash
# 方案 A: Rebase（推荐，保持线性历史）
git pull origin main --rebase --allow-unrelated-histories

# 方案 B: Merge（保留双方历史）
git pull origin main --no-rebase --allow-unrelated-histories

# 然后再正常推送
git push origin main
```

---

### 3️⃣ `! [rejected] main -> main (non-fast-forward)`

```
 ! [rejected]        main -> main (non-fast-forward)
hint: Updates were rejected because the tip of your current branch is behind
```

**原因**: 远程分支有本地没有的新提交

**解决**:

```bash
# 安全流程
git pull origin main --rebase
git push origin main

# ⚠️ 如果你确认远程内容可以丢弃（如远程是空的/废弃的）
git push origin main --force-with-lease
```

---

### 4️⃣ SSH 连接超时

```
ssh: connect to host github.com port 22: Connection timed out
```

**原因**: SSH 22 端口被墙

**解决**:

```bash
# 方案 A: 用 HTTPS 443 端口 SSH
# 编辑 ~/.ssh/config
Host github.com
    HostName ssh.github.com
    Port 443
    User git

# 方案 B: 改用 Token + HTTPS 代理
export GITHUB_TOKEN=ghp_xxxx
bash github_push.sh --method token --proxy http://127.0.0.1:7897
```

---

### 5️⃣ HTTP 403 / Token 无效

```json
{"message": "Bad credentials", "documentation_url": "..."}
```

**解决**:
- Token 是否过期？→ 重新生成
- Token 是否复制完整？→ 检查以 `ghp_` 开头
- Token 是否有 `repo` 权限？→ 重新生成时勾选

---

## 📖 完整流程回顾

以下是我们今天实际操作的全过程（代理环境 + HTTPS Token）：

```
┌─────────────────────────────────────────────────┐
│  1. 检查本地状态                                  │
│     git status → 6 commits 待推送                 │
│     git log origin/main..HEAD → 确认提交列表       │
└──────────────┬──────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────┐
│  2. SSH 认证尝试 (失败)                           │
│     ❌ 22 端口 SSH 超时                           │
│     ❌ 443 端口 SSH 也超时                         │
│     → 网络完全封锁，只能用 HTTPS + 代理            │
└──────────────┬──────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────┐
│  3. Token 认证                                   │
│     ✅ 获取 GitHub Personal Access Token          │
│     ✅ 配置代理 git config http.proxy             │
│     ✅ 设置 remote URL (含 Token)                  │
└──────────────┬──────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────┐
│  4. 推送被拒 (non-fast-forward)                   │
│     ❌ 远程有一个无关的 Initial commit             │
│     → rebase --allow-unrelated-histories         │
└──────────────┬──────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────┐
│  5. Rebase 合并历史                               │
│     ✅ git pull --rebase --allow-unrelated-...    │
│     ✅ 6 个本地提交 rebase 到远程之上               │
│     ✅ git push origin main → 成功！               │
│     output: b3675b6..29b203b  main -> main       │
└──────────────┬──────────────────────────────────┘
               ▼
┌─────────────────────────────────────────────────┐
│  6. 安全清理                                      │
│     ✅ 移除 remote URL 中的 Token                  │
│     ✅ 清除 git 代理配置                           │
│     ✅ Profile 生效: github.com/congbaby-3389     │
└─────────────────────────────────────────────────┘
```

---

## 📟 命令速查表

### 日常推送

```bash
# 走脚本（推荐）
bash github_push.sh --method ssh

# 手动 HTTPS + Token
export GITHUB_TOKEN=ghp_xxxx
git add -A
git commit -m "更新"
git push origin main
```

### 诊断命令

```bash
# 查看本地与远程差异
git log origin/main..HEAD

# 查看远程 URL
git remote -v

# 查看当前代理配置
git config --get http.proxy

# 测试 SSH 连接
ssh -vT git@github.com

# 测试 Token 有效性
curl -H "Authorization: token ghp_xxxx" https://api.github.com/user
```

### 修复命令

```bash
# 修复无关历史
git pull origin main --rebase --allow-unrelated-histories

# 修复非快进冲突
git fetch origin main && git rebase origin/main

# 安全强制推送（确认远程无人push的情况下）
git push origin main --force-with-lease

# 重置 remote
git remote remove origin
git remote add origin git@github.com:用户名/仓库.git
```

### 清理命令

```bash
# 清除 Token（如果嵌在 URL 里）
git remote set-url origin https://github.com/用户名/仓库.git

# 清除所有代理
git config --unset http.proxy
git config --unset https.proxy
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
```

---

## 📁 相关文件

| 文件 | 说明 |
|------|------|
| [github_push.sh](github_push.sh) | 通用推送脚本（支持 SSH / Token / 代理） |
| `~/.ssh/config` | SSH 配置文件（443 端口） |
| `~/.ssh/github_*` | SSH 密钥对 |

---

> 💡 **一句话总结**: SSH 行就用 SSH，SSH 被墙就用 Token + 代理。推送遇到冲突先 `rebase`，不要直接 `force`。

---

🤖 本文档由 Claude Code 在实战推送过程中生成，记录了从 **认证→代理→冲突解决→推送→清理** 的完整流程。
