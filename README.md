# herdr-profiles

Ba bộ profile Claude Code, OpenAI Codex, và opencode để điều phối multi-agent bên trong [Herdr](https://herdr.dev)
(terminal multiplexer cho coding agent). Mô hình: **1 Lead điều phối, 1
implementer duy nhất được sửa code, peer sinh ra ad-hoc để phản biện**, cộng
một **Supervisor** read-only đứng ngoài soi anti-pattern.

## Ý tưởng cốt lõi

- **Single-writer**: mỗi feature chỉ có đúng 1 agent (implementer) có quyền
  edit, chạy trong worktree riêng. Không bao giờ có 2 đứa cùng ghi 1 checkout.
- **Lead không code**: Lead bị chặn quyền `Edit`/`Write` bằng
  permissions, chỉ điều phối qua CLI `herdr`. Gọi là "Lead" chứ không phải
  "root orchestrator" vì khi xưng hô với agent nó tự giải thích được vai —
  không phải định nghĩa "root là gì" trước mỗi lần nói chuyện.
- **Cấm polling**: Lead chờ **event**, không chờ đồng hồ. Plugin
  `attention-broker` đánh thức nó đúng một lần khi seat khác xong hoặc kẹt.
  Mỗi lần đọc thừa là context của Lead bị đốt, mà Lead compact giữa chừng là
  mất cả phòng.
- **Cấm goal, cấm skill, cấm sub-agent**: ba đường khác nhau dẫn về cùng một
  chỗ vỡ — runtime tự re-enter thread, hoặc seat tự mở pane riêng.
- **Implementer không biết nó bị điều khiển**: env `HERDR_*` bị strip, user
  settings/skills không load. Nó tưởng đang nói chuyện với người thật —
  Lead gõ lệnh vào pane của nó y như user gõ tay.
- **Instruction nằm trong system prompt, không dùng skill**: skill load vào
  conversation, compact là mất; system prompt (`--append-system-prompt`) sống
  qua compact.
- **1 protocol quản nhân sự duy nhất**: mọi vai bị deny tool spawn
  sub-agent built-in (`Task`/`Agent`/`task`). Mọi co-worker là full agent
  trong pane Herdr, không phải sub-agent. Trên sol-family phải patch model
  cache mới tắt được thật — xem [Sub-agent](#tắt-sub-agent-cho-thật).

## Cấu trúc file

| File | Vai trò |
| --- | --- |
| `orchestrator.sh` / `orchestrator.json` | Lead (Claude). Load full herdr instruction vào system prompt. Deny `Edit`/`Write`/`Task`/`Agent`/`Skill`, allow `Bash(herdr:*)` + lệnh đọc. |
| `implementer.sh` / `implementer.json` | Đứa duy nhất được edit. Strip toàn bộ env `HERDR_*`, `--setting-sources project,local` (bỏ user settings). `acceptEdits` + allowlist git/test/build rộng để không bị hỏi vặt. Deny `herdr`, `git push`. |
| `peer.sh` / `peer.json` | Reviewer/critic read-only. Chỉ `Read`/`Grep`/`git diff|log|show`. Deny edit, commit, herdr. |
| `codex-*.sh` / `codex-*.config.toml` | Ba profile tương ứng cho Codex CLI. Dùng named profile, sandbox và policy hook. |
| `install-codex.sh` | Link named profiles và policy hook vào `$CODEX_HOME` (mặc định `~/.codex`). |
| `hr` | Dispatcher: `hr claude\|codex\|opencode` chạy Lead tương ứng, `hr supervisor` chạy auditor. Không expose implementer/peer. |
| `herdr-profile-policy.py` | `PreToolUse` policy fail-closed: khóa edit/delegation/goal ở Lead/peer/supervisor, khóa `herdr` và `git push` ở implementer, giới hạn supervisor chỉ được lệnh `herdr` read-only. |
| `codex-supervisor.sh` / `codex-supervisor.config.toml` | Supervisor read-only, model rẻ. Đọc `supervisor-instructions.md`. Chỉ được `herdr` read-only + `notification show`. |
| `supervisor-instructions.md` | Catalog 14 anti-pattern + cách sweep và cách báo cáo. |
| `patch-model-cache.sh` | Tắt sub-agent ở tầng model catalog cho sol-family (`--check` / `--restore`). |
| `plugins/attention-broker/` | Herdr plugin: push event đánh thức Lead thay vì để Lead poll. |
| `opencode-plugins/herdr-no-subagent.js` | Chặn cứng tool `task` của opencode ở mọi session. |
| `install-opencode.sh` | Link plugin trên vào `~/.config/opencode/plugins`. |
| `opencode-orchestrator.sh` | opencode Lead. Đọc `herdr-instructions.md` lúc chạy, nhét vào `OPENCODE_CONFIG_CONTENT` (inline config, ưu tiên cao hơn project config). Deny `edit`/`task`/`skill`, allowlist bash hẹp. |
| `opencode-implementer.json` / `.sh` | opencode implementer (agent name `coder`). Static config không chứa herdr string: deny `herdr` + `git push` trong bash, tắt `bridgememory` MCP. Wrapper strip `HERDR_*` env. |
| `opencode-peer.json` / `.sh` | opencode peer reviewer (agent name `reviewer`). Static config không chứa herdr string: read-only bash + deny `edit`/`task`. Wrapper strip `HERDR_*` env. |
| `herdr-instructions.md` | Toàn bộ hướng dẫn dùng CLI `herdr` + quy ước điều phối (chi tiết bên dưới). Được nhét vào system prompt của Lead. |

### Model & effort per profile

Mỗi JSON set riêng `"model"` và `"effortLevel"` (values: `low`, `medium`,
`high`, `xhigh`, `max` — tương đương reasoning effort của codex):

| Profile | Model | Effort |
| --- | --- | --- |
| Lead | `fable` (Fable 5 — mạnh nhất) | `high` — phán đoán, challenge, quyết định điều phối |
| implementer | `claude-sonnet-4-6` | `medium` — đủ cho code casual |
| peer | `claude-sonnet-4-6` | `medium` — review, phản biện |

Feature khó thì nâng implementer: sửa JSON hoặc truyền `--model opus` khi
launch (wrapper nhận `"$@"`).

### Codex model & effort

Ba profile Codex mặc định dùng `gpt-5.6-sol`. Lead dùng `xhigh`; implementer
và peer dùng `medium`. Có thể override theo phiên bằng `--model` và
`--config model_reasoning_effort='"high"'`.

Codex không có permission JSON giống Claude Code. Bản Codex map quyền theo vai:

- Lead dùng `danger-full-access` + `approval_policy = "never"`, tương
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
~/.codex/herdr-supervisor.config.toml
~/.codex/herdr-profile-policy.py
```

Bước cuối installer chạy `patch-model-cache.sh` để tắt sub-agent ở tầng model
catalog — xem [Tắt sub-agent cho thật](#tắt-sub-agent-cho-thật).

Lần đầu chạy một profile, Codex sẽ báo hook chưa được trust. Mở `/hooks`, đọc
definition rồi trust `herdr-profile-policy.py`. Hook chưa được trust sẽ bị
Codex skip. Không giao việc cho Lead trước khi trust xong vì profile
này chạy `danger-full-access`; lúc đó instruction là hàng rào duy nhất.

## Cách chạy

```bash
# 1. Mở Herdr
herdr

# 2. Trong pane, chạy Lead
~/.herdr-profiles/orchestrator.sh

# Hoặc chạy Codex Lead
~/.herdr-profiles/codex-orchestrator.sh

# 3. Giao việc bằng ngôn ngữ thường
#    "Tạo worktree cho feature X, spawn implementer làm ..., xong gọi peer review"
```

### Alias `hr`

`hr` là dispatcher gọn cho ba Lead cộng Supervisor. Implementer/peer không
được expose — Lead spawn chúng qua CLI `herdr`, không chạy tay.

```bash
# Thêm vào ~/.zshrc (hoặc ~/.bashrc)
alias hr='~/.herdr-profiles/hr'
```

```bash
hr claude       # = orchestrator.sh
hr codex        # = codex-orchestrator.sh
hr opencode     # = opencode-orchestrator.sh
hr supervisor   # = codex-supervisor.sh (read-only auditor)

hr claude --model opus   # arg thừa được forward xuống agent CLI
hr --help
```

Lead tự làm phần còn lại: tạo worktree, split pane (`--no-focus` nên
không giật focus của bạn), chạy `implementer.sh` trong worktree, gửi task,
chờ hoàn thành, spawn peer review, đọc report, báo lại.

Muốn can thiệp trực tiếp: click sang pane implementer và gõ tay — nó không
phân biệt được bạn với Lead.

## Luồng hoạt động

```text
User ──nói chuyện──> Lead (pane gốc, không edit được)
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

1. Lead mở seat bằng `herdr agent start`, chờ status `idle`
   (agent đã mở tới prompt).
2. Gửi task bằng `herdr pane run` — text + Enter, giọng user bình thường,
   không nhắc gì tới Herdr/orchestration.
3. Chờ `working` → chờ hoàn thành. **Quan trọng**: pane nền báo `done`, pane
   đang được user nhìn báo `idle` — cả hai đều nghĩa là xong, phải chấp nhận
   cả hai, không thì treo chờ vô hạn.
4. Nếu `blocked`: implementer đang hỏi. Lead đọc pane, trả lời như
   user; không trả lời được thì chuyển câu hỏi cho user thật.
5. Kết quả bàn giao qua **file** (`.herdr-handoff/<topic>.md` trong worktree),
   không scrape scrollback — `pane read` bị cắt dòng, mất thông tin.

## Quy ước điều phối (nằm trong `herdr-instructions.md`)

- **Giao việc bằng câu hỏi mở, cấm pre-solve**: Lead không tự giải rồi hỏi
  co-worker "đúng hay sai". Giao đề mở, để co-worker tự lập position, nghe
  xong mới challenge. Pre-solve biến agent mạnh thành máy xác nhận.
- **Scout chỉ được dẫn đường**: model rẻ đi trinh sát chỉ được trả về pointer
  (file, symbol, "chỗ này có vẻ impact lớn — cần verify"), không được kết
  luận. Kết luận phải do agent đủ mạnh sở hữu hoặc Lead tự kiểm chứng.
- **Run lock**: mỗi thời điểm chỉ 1 agent được quyền chạy test/lệnh đụng môi
  trường chung (server, port, DB). Lead trao quyền rõ ràng trong prompt.
  Chạy song song → môi trường nát → red test giả.
- **Balloon-pattern guard**: foundation yếu mà implementer đắp mutex,
  heuristic, retry, special-case lên rồi khen đẹp → dừng feature, báo user
  xử foundation trước.
- **Đặt tên plan lớn**: plan nhiều session có tên riêng (vd "plan bigbang")
  để human và agent reference thống nhất, khỏi tả lại từ đầu.
- **Fail 2 lần thì escalate**: implementer trượt cùng task 2 lần → không retry
  nữa, gom report + transcript, tóm tắt cho user thật và chờ chỉ đạo.
- **Owner boundary**: scope đã có owner thì Lead không đọc chồng lên. Trả lời
  decision gate ≠ lấy lại quyền sở hữu. Hỏi "còn gì trước handback" là
  supervision; đọc diff của owner trước handback là shadowing.
- **Dựng lại phòng sau compact một lần** từ `herdr agent list` + artifact bền,
  không bulk-read mọi seat, không replay lịch sử hội thoại.

## Attention: Lead không được poll

Đây là lỗi đắt nhất trong phòng, và là lý do plugin `attention-broker` tồn
tại. Mỗi `agent wait` / `agent get` / `pane read` thừa là context của Lead bị
đốt vào state không đổi — Lead compact giữa chừng là mất cả phòng.

Ba quy tắc nằm trong `herdr-instructions.md`:

- **Per-seat, không global timer.** Mỗi seat có attention point riêng, wake kế
  tiếp là cái sớm nhất. Không chờ dài trên implementer khi peer sắp trả lời.
- **Timeout không phải thông tin.** Wait hết giờ chỉ nghĩa là event chưa xảy
  ra. Không phải progress, không phải failure, **không phải lý do báo user**.
  Cấm `agent get` sau timeout để xác nhận không có gì đổi.
- **10 phút là trần, không phải default.** Quá trần thì phải lấy **thông tin
  mới** trước khi chờ tiếp. Status không đổi / process còn sống / terminal có
  chữ chạy đều không tính. Activity ≠ convergence.

### Plugin attention-broker

Đảo chiều: Herdr bắn event, plugin đẩy đúng một prompt vào pane Lead.

```bash
herdr plugin link ~/.herdr-profiles/plugins/attention-broker
herdr pane rename <lead-pane-id> "Lead"    # plugin tìm Lead theo tên seat
```

Persist trước khi gửi, gửi fail thì giữ queue và retry khi Lead `idle`, dedupe
theo `event:workspace:pane:status`, state namespace theo session socket.

Fork từ prototype của tác giả Herdr, khác 3 điểm: chạy được trên macOS, sanitize
tên seat trước khi nó vào prompt của Lead (tên seat do `pane rename` sinh ra —
user-controlled, bản gốc nhét thẳng vào `pane run`), và queue lại thay vì
`exit 0` im lặng khi không tìm thấy Lead. Chi tiết:
`plugins/attention-broker/README.md`.

## Cấm goal

Codex có feature `goals` (`codex features list` → stable, mặc định **bật**;
DB `~/.codex/goals_1.sqlite`, bảng `thread_goals` với `objective`, `status`,
`token_budget`). Agent tự set goal → runtime tự re-enter thread theo lịch của
nó tới khi objective xong.

Trong phòng có seat sống, đó chính là poll loop tự sinh: Lead bị đánh thức
liên tục, đọc state không đổi, đốt context, không hội tụ. Chặn 3 tầng:

- `[features] goals = false` trong cả 4 profile Codex.
- Policy hook deny mọi tool tên `goal`/`goals`/`set_goal`/`update_goal`.
- Instruction cấm thẳng, kèm lý do (rule sống qua compact, câu dặn thì không).

## Tắt sub-agent cho thật

`[features] multi_agent = false` **không đủ** trên sol-family. Mỗi entry model
trong catalog cache mang key riêng `multi_agent_version`, và giá trị per-model
đó thắng feature flag:

```
gpt-5.6-sol      v2      gpt-5.5              (không có key)
gpt-5.6-terra    v2      gpt-5.4              (không có key)
gpt-5.6-luna     v1      gpt-5.3-codex        (không có key)
```

```bash
./patch-model-cache.sh            # set về null, giống model đời cũ
./patch-model-cache.sh --check    # soi state, exit 1 nếu còn model bật
./patch-model-cache.sh --restore  # hoàn nguyên từ bản backup pristine
```

Catalog là **cache** — cockpit local-access refetch nó. Chạy lại sau mỗi lần
update Codex hoặc refresh model. `install-codex.sh` gọi sẵn ở bước cuối.

opencode thì khác đường: `agent.<name>.permission.task = "deny"` chỉ phủ agent
mình tự định nghĩa, mà opencode luôn merge global config và project config có
thể bật lại. Chặn cứng bằng plugin `tool.execute.before` throw — chạy cho mọi
session bất kể agent hay config layer nào:

```bash
./install-opencode.sh                  # link herdr-no-subagent.js
OPENCODE_ALLOW_TASK=1 opencode         # escape hatch, per-session
```

Plugin đặt **cạnh** `herdr-agent-state.js` chứ không sửa file đó: file kia do
`herdr integration install opencode` quản, sửa vào là mất khi update.

## Supervisor

Auditor read-only đứng ngoài, model rẻ (`gpt-5.4-mini`), soi phòng và báo
anti-pattern cho **người thật**.

```bash
hr supervisor
```

Không do Lead spawn — nó audit Lead, nên Lead không được nắm lifecycle của nó.
Policy hook giới hạn nó ở allowlist `herdr` read-only (`agent list/get/read`,
`pane list/get/read`, `api snapshot`, `plugin log`) cộng `notification show`
làm kênh báo cáo duy nhất. `agent start`, `pane run`, `pane close` đều bị deny.

Context của supervisor là đồ bỏ — đó chính là lý do nó gánh được việc quan sát
lặp lại mà Lead không gánh nổi.

14 anti-pattern trong `supervisor-instructions.md`, xếp theo mức tốn kém:

| # | Pattern | Dấu hiệu |
| --- | --- | --- |
| 1 | Lead polling | đọc lặp cùng 1 seat, không có quyết định xen giữa |
| 2 | Lead set goal | có objective/self-continuation đang chạy |
| 3 | Lead ghi repo | edit tool, `sed -i`, redirect, `tee`, `git commit` |
| 4 | 2 writable owner | 2 seat implementer cùng `cwd` hoặc cùng file |
| 5 | Shadowing | Lead mở file / chạy test của owner |
| 6 | Pre-solve | prompt dạng "đúng không?", "A hay B?" (A,B của Lead) |
| 7 | Rò blind-implementer | `herdr`/`pane`/`orchestrat`/`Lead` vào pane impl |
| 8 | Vỡ run-lock | 2 seat cùng chạy test / server |
| 9 | Balloon | mutex/retry/special-case chồng lên base chưa sửa |
| 10 | Retry loop | giao lại lần 3 sau 2 lần fail (phải escalate ở lần 2) |
| 11 | Sub-agent / skill | seat tự spawn hoặc load skill điều khiển phòng |
| 12 | Seat mồ côi / kẹt | `blocked` lâu không ai trả lời, handback không ai lấy |
| 13 | Status theater | output chỉ có "vẫn đang chạy" |
| 14 | Trùng tên seat | 2 seat sống cùng tên → lệnh theo tên resolve loạn |

Nó **chỉ báo, không sửa**: không nhắn seat, không trả lời agent `blocked`,
không chỉnh Lead. Người quyết.

## Skills — không dùng, ở mọi vai

Hai lý do:

- **Skill chết khi compact.** Nó nạp vào conversation, không phải system
  prompt. Lead dựa vào skill sẽ quên protocol giữa chừng mà không tự biết.
  Đây là lý do instruction nằm ở `--append-system-prompt` /
  `developer_instructions` ngay từ đầu.
- **Skill điều khiển phòng bị kế thừa xuống seat.** Pane con load được skill
  đó thì nó tự mở pane của riêng nó — topology không còn khớp thực tế, Lead
  không thấy, không chờ, không đóng được đám owner đó. Mất luôn single-writer.

### Mức chặn không đều giữa 3 CLI

| CLI | Cơ chế | Kín? |
| --- | --- | --- |
| Claude | deny tool `Skill` + `--setting-sources project,local` (verify: cắt sạch `~/.claude/skills` và plugin skills) | kín |
| opencode | `permission.skill: deny` ở cả 3 agent | kín |
| Codex | hook deny `skills.list`/`skills.read` + instruction + read-only sandbox | **một phần** |

Codex không có tool `Skill` đơn lẻ: skill filesystem được đọc qua chính file
`SKILL.md` như file thường, chỉ skill provider-backed mới đi qua
`skills.list`/`skills.read`. Nên với Codex, đường filesystem chỉ chặn được
bằng instruction (Lead) và read-only sandbox (peer/supervisor). Implementer
Codex vẫn đọc được `SKILL.md` nếu repo có — chấp nhận được vì nó mù herdr,
skill điều khiển phòng không tới tay nó.

Hệ quả phụ vẫn giữ: implementer/peer không bao giờ thấy skill `herdr` → premise
"không biết bị điều khiển" kín.

## opencode

### Model & effort per profile

Cả 3 profile dùng `opencode/deepseek-v4-flash-free` (DeepSeek V4
Flash qua OpenCode Zen, free tier). opencode dùng `variant` thay vì
`effortLevel`:

| Profile | Model | Variant |
| --- | --- | --- |
| Lead | `opencode/deepseek-v4-flash-free` | `high` — phán đoán, challenge, điều phối |
| implementer | `opencode/deepseek-v4-flash-free` | `medium` — code casual |
| peer | `opencode/deepseek-v4-flash-free` | `medium` — review, phản biện |

### opencode permission model

opencode không có sandbox mode hay profile file như Codex. Thay vào đó:

- **Agent config** trong JSON (`agent.<name>.permission`) với rule `allow`/`ask`/`deny`.
- **Last-match wins**: `*` (catch-all) để đầu, rule cụ thể để sau — rule cuối cùng khớp thắng.
- **`--auto`** tự duyệt mọi `ask` permission; explicit `deny` vẫn enforce.

Map theo vai:

- **Lead**: `edit: deny`, `task: deny` (chặn sub-agent), `skill: deny`,
  bash chỉ được `herdr *` + git read-only + cat/ls/grep.
- **Implementer**: `* : allow`, rồi `task: deny` + `skill: deny`, bash deny
  `herdr`/`herdr *`/`git push`. Catch-all `*` phải đứng **đầu**: opencode là
  last-match-wins, deny đặt trước `*: allow` sẽ bị chính nó ghi đè.
- **Peer**: `* : deny`, whitelist read + git read-only bash.

### Instruction của Lead

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
- Lead chạy `bypassPermissions`: không hỏi permission, deny rules
  vẫn enforce (đã test: tool `Write` bị loại khỏi session). Nhưng Bash thì
  không giới hạn — nó có thể ghi file qua shell redirection. Đường này chỉ
  chặn được bằng instruction ("mọi thay đổi repo đi qua implementer"), nên
  chỉ dùng bypass trên máy local tự giám sát, không dùng nơi có credentials
  production.
- Codex Lead dùng full access để CLI `herdr` kết nối runtime mà không
  bị sandbox chặn. Giống Claude `bypassPermissions`, policy hook chặn tool edit
  nhưng lệnh `herdr` vẫn có quyền điều khiển pane; chỉ dùng sau khi review và
  trust hook.
- Named profile Codex overlay lên user config. `multi_agent`, `goals`, memories
  và web search được tắt trong từng profile, nhưng Codex hiện không có
  equivalent tổng quát của Claude `--setting-sources project,local` để bỏ mọi
  user skill. Tool `Skill` bị deny qua hook thay vì bị cắt ở tầng loader.
- `patch-model-cache.sh` sửa một **cache** (`cockpit-local-access-model-catalog.json`).
  Cockpit local-access refetch nó, và lúc đó `multi_agent_version` quay lại. Chạy
  `--check` sau mỗi lần update Codex; đây là mitigation, không phải fix vĩnh viễn.
  Fix thật phải đến từ upstream cho phép override per-model.
- Supervisor chỉ **quan sát**, và nó suy ra anti-pattern từ scrollback +
  snapshot. Nó không thấy được reasoning của Lead, nên polling ẩn (Lead nghĩ
  nhiều mà không gọi lệnh) nằm ngoài tầm. Model rẻ cũng nghĩa là tỉ lệ báo nhầm
  cao hơn — đọc nó như tín hiệu, không phải phán quyết.
- Plugin `attention-broker` tìm Lead theo **tên seat**. Đổi tên pane hoặc chạy
  2 seat cùng tên `Lead` là nó không resolve được; bản này queue lại và log
  warning thay vì im lặng, nhưng vẫn cần bạn sửa tên.
- opencode implementer/peer dùng `OPENCODE_CONFIG` (giữa global và project
  trong precedence). Không có cơ chế tương đương `--setting-sources
  project,local` — không thể cắt toàn bộ global config. `bridgememory` MCP bị
  tắt trong config nhưng project config có thể re-enable nó. Dùng trong
  worktree của project thường không có bridgememory → an toàn trong thực tế.
- opencode không có model variant "xhigh" — Lead dùng `high` (tier
  cao nhất thực tế cho DeepSeek V4 Flash qua OpenCode Zen). Nếu model không hỗ
  trợ thinking/reasoning variant, opencode sẽ fallback hoặc ignore nó.
- `opencode/deepseek-v4-flash-free` có rate limit của free tier
  OpenCode Zen. Nếu bị throttle, thay bằng `opencode/deepseek-v4-flash`
  (paid) hoặc model khác bằng cách sửa model trong 3 file config.
