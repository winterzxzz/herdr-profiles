# herdr-profiles

Ba bộ 3 profile Claude Code, OpenAI Codex, và opencode để điều phối multi-agent bên trong [Herdr](https://herdr.dev)
(terminal multiplexer cho coding agent). Mô hình: **1 root orchestrator điều
phối, 1 implementer duy nhất được sửa code, peer sinh ra ad-hoc để phản biện**.

## Ý tưởng cốt lõi

- **Single-writer**: mỗi feature chỉ có đúng 1 agent (implementer) có quyền
  edit, chạy trong worktree riêng. Không bao giờ có 2 đứa cùng ghi 1 checkout.
- **Root không code**: orchestrator bị chặn quyền `Edit`/`Write` bằng
  permissions, chỉ điều phối qua CLI `herdr`.
- **Implementer không biết nó bị điều khiển**: env `HERDR_*` bị strip, user
  settings/skills không load. Nó tưởng đang nói chuyện với người thật —
  orchestrator gõ lệnh vào pane của nó y như user gõ tay.
- **Instruction nằm trong system prompt, không dùng skill**: skill load vào
  conversation, compact là mất; system prompt (`--append-system-prompt`) sống
  qua compact.
- **1 protocol quản nhân sự duy nhất**: root bị deny luôn tool spawn
  sub-agent built-in (`Task`/`Agent`). Mọi co-worker là full agent trong pane
  Herdr, không phải sub-agent.

## Cấu trúc file

| File | Vai trò |
| --- | --- |
| `orchestrator.sh` / `orchestrator.json` | Root. Load full herdr instruction vào system prompt. Deny `Edit`/`Write`/`Task`/`Agent`, allow `Bash(herdr:*)` + lệnh đọc. |
| `implementer.sh` / `implementer.json` | Đứa duy nhất được edit. Strip toàn bộ env `HERDR_*`, `--setting-sources project,local` (bỏ user settings). `acceptEdits` + allowlist git/test/build rộng để không bị hỏi vặt. Deny `herdr`, `git push`. |
| `peer.sh` / `peer.json` | Reviewer/critic read-only. Chỉ `Read`/`Grep`/`git diff|log|show`. Deny edit, commit, herdr. |
| `codex-*.sh` / `codex-*.config.toml` | Ba profile tương ứng cho Codex CLI. Dùng named profile, sandbox và policy hook. |
| `install-codex.sh` | Link named profiles và policy hook vào `$CODEX_HOME` (mặc định `~/.codex`). |
| `herdr-profile-policy.py` | `PreToolUse` policy fail-closed: khóa edit/delegation ở root/peer, khóa `herdr` và `git push` ở implementer. |
| `opencode-orchestrator.sh` | opencode root. Đọc `herdr-instructions.md` lúc chạy, nhét vào `OPENCODE_CONFIG_CONTENT` (inline config, ưu tiên cao hơn project config). Deny `edit`/`task`/`skill`, allowlist bash hẹp. |
| `opencode-implementer.json` / `.sh` | opencode implementer (agent name `coder`). Static config không chứa herdr string: deny `herdr` + `git push` trong bash, tắt `bridgememory` MCP. Wrapper strip `HERDR_*` env. |
| `opencode-peer.json` / `.sh` | opencode peer reviewer (agent name `reviewer`). Static config không chứa herdr string: read-only bash + deny `edit`/`task`. Wrapper strip `HERDR_*` env. |
| `herdr-instructions.md` | Toàn bộ hướng dẫn dùng CLI `herdr` + quy ước điều phối (chi tiết bên dưới). Được nhét vào system prompt của orchestrator. |

### Model & effort per profile

Mỗi JSON set riêng `"model"` và `"effortLevel"` (values: `low`, `medium`,
`high`, `xhigh`, `max` — tương đương reasoning effort của codex):

| Profile | Model | Effort |
| --- | --- | --- |
| orchestrator | `fable` (Fable 5 — mạnh nhất) | `high` — phán đoán, challenge, quyết định điều phối |
| implementer | `claude-sonnet-4-6` | `medium` — đủ cho code casual |
| peer | `claude-sonnet-4-6` | `medium` — review, phản biện |

Feature khó thì nâng implementer: sửa JSON hoặc truyền `--model opus` khi
launch (wrapper nhận `"$@"`).

### Codex model & effort

Ba profile Codex mặc định dùng `gpt-5.6-sol`. Root dùng `xhigh`; implementer
và peer dùng `medium`. Có thể override theo phiên bằng `--model` và
`--config model_reasoning_effort='"high"'`.

Codex không có permission JSON giống Claude Code. Bản Codex map quyền theo vai:

- orchestrator dùng `danger-full-access` + `approval_policy = "never"`, tương
  đương `bypassPermissions` của Claude;
- implementer dùng `workspace-write` + `approval_policy = "never"`, tương
  đương `acceptEdits`; peer dùng `read-only`;
- `PreToolUse` hook để khóa command/tool theo vai và
  `[features] multi_agent = false` để Herdr là protocol nhân sự duy nhất.

## Cài cho Codex

Yêu cầu Codex CLI hỗ trợ named profile v2 và hooks (đã verify với
`codex-cli 0.144.5`). Clone repo đúng đường dẫn mà instruction mặc định dùng,
sau đó cài profile:

```bash
git clone https://github.com/winterzxzz/herdr-profiles ~/.herdr-profiles
cd ~/.herdr-profiles
./install-codex.sh
```

Installer chỉ tạo symlink sau, không thay `~/.codex/config.toml`:

```text
~/.codex/herdr-orchestrator.config.toml
~/.codex/herdr-implementer.config.toml
~/.codex/herdr-peer.config.toml
~/.codex/herdr-profile-policy.py
```

Lần đầu chạy một profile, Codex sẽ báo hook chưa được trust. Mở `/hooks`, đọc
definition rồi trust `herdr-profile-policy.py`. Hook chưa được trust sẽ bị
Codex skip. Không giao việc cho orchestrator trước khi trust xong vì profile
này chạy `danger-full-access`; lúc đó instruction là hàng rào duy nhất.

## Cách chạy

```bash
# 1. Mở Herdr
herdr

# 2. Trong pane, chạy orchestrator
~/.herdr-profiles/orchestrator.sh

# Hoặc chạy Codex orchestrator
~/.herdr-profiles/codex-orchestrator.sh

# 3. Giao việc bằng ngôn ngữ thường
#    "Tạo worktree cho feature X, spawn implementer làm ..., xong gọi peer review"
```

Orchestrator tự làm phần còn lại: tạo worktree, split pane (`--no-focus` nên
không giật focus của bạn), chạy `implementer.sh` trong worktree, gửi task,
chờ hoàn thành, spawn peer review, đọc report, báo lại.

Muốn can thiệp trực tiếp: click sang pane implementer và gõ tay — nó không
phân biệt được bạn với orchestrator.

## Luồng hoạt động

```text
User ──nói chuyện──> Orchestrator (pane gốc, không edit được)
                          │
                          ├─ herdr worktree ...        # checkout riêng cho feature
                          ├─ herdr pane split + run implementer.sh
                          │       │
                          │       └─> Implementer (edit trong worktree,
                          │           tưởng đang nghe lệnh user thật)
                          │
                          ├─ herdr wait agent-status ... --status done/idle
                          ├─ blocked? → đọc câu hỏi, trả lời nhập vai user
                          │
                          ├─ herdr pane split + run peer.sh
                          │       └─> Peer (read-only) review diff, ghi report ra file
                          │
                          └─ đọc file handoff, tổng hợp, báo user
```

### Vòng đời một task

1. Orchestrator split pane, launch `implementer.sh`, chờ status `idle`
   (agent đã mở tới prompt).
2. Gửi task bằng `herdr pane run` — text + Enter, giọng user bình thường,
   không nhắc gì tới Herdr/orchestration.
3. Chờ `working` → chờ hoàn thành. **Quan trọng**: pane nền báo `done`, pane
   đang được user nhìn báo `idle` — cả hai đều nghĩa là xong, phải chấp nhận
   cả hai, không thì treo chờ vô hạn.
4. Nếu `blocked`: implementer đang hỏi. Orchestrator đọc pane, trả lời như
   user; không trả lời được thì chuyển câu hỏi cho user thật.
5. Kết quả bàn giao qua **file** (`.herdr-handoff/<topic>.md` trong worktree),
   không scrape scrollback — `pane read` bị cắt dòng, mất thông tin.

## Quy ước điều phối (nằm trong `herdr-instructions.md`)

- **Giao việc bằng câu hỏi mở, cấm pre-solve**: root không tự giải rồi hỏi
  co-worker "đúng hay sai". Giao đề mở, để co-worker tự lập position, nghe
  xong mới challenge. Pre-solve biến agent mạnh thành máy xác nhận.
- **Scout chỉ được dẫn đường**: model rẻ đi trinh sát chỉ được trả về pointer
  (file, symbol, "chỗ này có vẻ impact lớn — cần verify"), không được kết
  luận. Kết luận phải do agent đủ mạnh sở hữu hoặc root tự kiểm chứng.
- **Run lock**: mỗi thời điểm chỉ 1 agent được quyền chạy test/lệnh đụng môi
  trường chung (server, port, DB). Root trao quyền rõ ràng trong prompt.
  Chạy song song → môi trường nát → red test giả.
- **Balloon-pattern guard**: foundation yếu mà implementer đắp mutex,
  heuristic, retry, special-case lên rồi khen đẹp → dừng feature, báo user
  xử foundation trước.
- **Đặt tên plan lớn**: plan nhiều session có tên riêng (vd "plan bigbang")
  để human và agent reference thống nhất, khỏi tả lại từ đầu.
- **Fail 2 lần thì escalate**: implementer trượt cùng task 2 lần → không retry
  nữa, gom report + transcript, tóm tắt cho user thật và chờ chỉ đạo.

## Skills

Cả 3 profile đều chạy `--setting-sources project,local` — đã verify thực tế:
flag này cắt toàn bộ user skills (`~/.claude/skills`) và plugin skills, chỉ
còn skill built-in của Claude Code. Nghĩa là:

- Implementer/peer không bao giờ thấy skill `herdr` → premise "không biết bị
  điều khiển" kín.
- Orchestrator không load skill `herdr` → không trùng/lệch với instruction
  trong system prompt, không mất khi compact.

## opencode

### Model & effort per profile

Cả 3 profile dùng `opencode/deepseek-v4-flash-free` (DeepSeek V4
Flash qua OpenCode Zen, free tier). opencode dùng `variant` thay vì
`effortLevel`:

| Profile | Model | Variant |
| --- | --- | --- |
| orchestrator | `opencode/deepseek-v4-flash-free` | `high` — phán đoán, challenge, điều phối |
| implementer | `opencode/deepseek-v4-flash-free` | `medium` — code casual |
| peer | `opencode/deepseek-v4-flash-free` | `medium` — review, phản biện |

### opencode permission model

opencode không có sandbox mode hay profile file như Codex. Thay vào đó:

- **Agent config** trong JSON (`agent.<name>.permission`) với rule `allow`/`ask`/`deny`.
- **Last-match wins**: `*` (catch-all) để đầu, rule cụ thể để sau — rule cuối cùng khớp thắng.
- **`--auto`** tự duyệt mọi `ask` permission; explicit `deny` vẫn enforce.

Map theo vai:

- **Orchestrator**: `edit: deny`, `task: deny` (chặn sub-agent), `skill: deny`,
  bash chỉ được `herdr *` + git read-only + cat/ls/grep.
- **Implementer**: `* : allow`, bash deny `herdr`/`herdr *`/`git push`.
- **Peer**: `* : deny`, whitelist read + git read-only bash.

### Instruction của orchestrator

opencode không có `--append-system-prompt` hay `developer_instructions`. Thay
vào đó:

- Wrapper đọc `herdr-instructions.md` lúc chạy, build JSON inline.
- Set `OPENCODE_CONFIG_CONTENT` (env var) chứa toàn bộ agent config bao gồm
  `prompt` = nội dung file.
- `OPENCODE_CONFIG_CONTENT` có precedence **cao hơn project config** (sau
  project trong loading order nhưng được merge last, nên thắng) — instruction
  không bị project config override.
- `agent.prompt` nằm ở tầng system prompt, sống qua context compaction.

### Implementer mù với opencode

opencode luôn merge global `~/.config/opencode/opencode.json`. Để chặn bleed:

1. `HERDR_*` env vars bị strip trong wrapper (giống Claude/Codex).
2. Implementer config định nghĩa agent tên `coder` (peer: `reviewer`) — không
   có herdr string nào trong file config, không có `agent.herdr-orchestrator`
   → instruction orchestrator không bao giờ load vào session implementer.
3. `mcp.bridgememory.enabled: false` trong implementer/peer config để tắt
   BridgeMemory (MCP có thể chứa herdr context trong memory). Merge lên trên
   global config, nên thắng trừ khi project config override.
4. Không có `--append-system-prompt` hay flag nào tương đương
   `--setting-sources project,local` của Claude để cắt toàn bộ global config.
   Giới hạn này được ghi nhận (xem mục "Giới hạn đã biết").

### Yêu cầu

- opencode ≥ 1.17.20 tại `~/.opencode/bin/opencode` (hoặc set `OPENCODE_BIN`).
- `OPENROUTER_API_KEY` đã được configure (qua `opencode providers login` hoặc
  env var).

### Cài và chạy

Không cần installer (khác với Codex). Wrapper tự tìm config file theo
đường dẫn tương đối từ vị trí của nó:

```bash
# Clone đúng đường dẫn mặc định
git clone https://github.com/winterzxzz/herdr-profiles ~/.herdr-profiles

# Chạy orchestrator trong Herdr pane
~/.herdr-profiles/opencode-orchestrator.sh

# Orchestrator sẽ spawn implementer/peer bằng
~/.herdr-profiles/opencode-implementer.sh
~/.herdr-profiles/opencode-peer.sh
```

Override binary path nếu cần:

```bash
OPENCODE_BIN=/usr/local/bin/opencode ~/.herdr-profiles/opencode-orchestrator.sh
```

## Giới hạn đã biết

- `orchestrator.sh` chạy ngoài Herdr sẽ tự từ chối điều khiển (check
  `HERDR_ENV=1`) — đúng thiết kế.
- Orchestrator chạy `bypassPermissions`: không hỏi permission, deny rules
  vẫn enforce (đã test: tool `Write` bị loại khỏi session). Nhưng Bash thì
  không giới hạn — nó có thể ghi file qua shell redirection. Đường này chỉ
  chặn được bằng instruction ("mọi thay đổi repo đi qua implementer"), nên
  chỉ dùng bypass trên máy local tự giám sát, không dùng nơi có credentials
  production.
- Codex orchestrator dùng full access để CLI `herdr` kết nối runtime mà không
  bị sandbox chặn. Giống Claude `bypassPermissions`, policy hook chặn tool edit
  nhưng lệnh `herdr` vẫn có quyền điều khiển pane; chỉ dùng sau khi review và
  trust hook.
- Named profile Codex overlay lên user config. `multi_agent`, memories và web
  search được tắt trong từng profile, nhưng Codex hiện không có equivalent tổng
  quát của Claude `--setting-sources project,local` để bỏ mọi user skill.
- opencode implementer/peer dùng `OPENCODE_CONFIG` (giữa global và project
  trong precedence). Không có cơ chế tương đương `--setting-sources
  project,local` — không thể cắt toàn bộ global config. `bridgememory` MCP bị
  tắt trong config nhưng project config có thể re-enable nó. Dùng trong
  worktree của project thường không có bridgememory → an toàn trong thực tế.
- opencode không có model variant "xhigh" — orchestrator dùng `high` (tier
  cao nhất thực tế cho DeepSeek V4 Flash qua OpenCode Zen). Nếu model không hỗ
  trợ thinking/reasoning variant, opencode sẽ fallback hoặc ignore nó.
- `opencode/deepseek-v4-flash-free` có rate limit của free tier
  OpenCode Zen. Nếu bị throttle, thay bằng `opencode/deepseek-v4-flash`
  (paid) hoặc model khác bằng cách sửa model trong 3 file config.
