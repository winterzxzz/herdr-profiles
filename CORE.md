# Cốt lõi thiết kế — port sang agent CLI bất kỳ

Tài liệu này tách phần bất biến của mô hình profile khỏi chi tiết Claude
Code, để cấu hình lại cho Codex (hoặc tool khác). 11 bất biến, tool chỉ là
chi tiết triển khai.

## 1. Ba vai trong phòng + một auditor ngoài

- **Lead**: điều phối, **bị chặn edit bằng permission** (không phải bằng lời
  dặn), chỉ được gọi CLI `herdr`. Trước gọi là "root orchestrator" — đổi tên
  vì "Lead" tự giải thích được vai khi xưng hô, không phải định nghĩa "root
  là gì" cho agent nghe.
- **Implementer**: **duy nhất được edit**. 1 đứa / 1 feature / 1 worktree.
- **Peer**: read-only, sinh ra ad-hoc để review/phản biện, xong việc đóng
  pane.
- **Supervisor** *(tùy chọn, đứng ngoài)*: read-only, model rẻ, quan sát
  phòng và báo anti-pattern cho **người thật** qua `herdr notification show`.
  Không do Lead spawn — nó audit Lead, nên Lead không được nắm lifecycle của
  nó. Kênh duy nhất là notification; policy hook chặn mọi lệnh `herdr` gây
  biến đổi.
- Mọi vai bị **tắt cơ chế sub-agent nội bộ** của tool — herdr là kênh quản
  nhân sự duy nhất, không chạy 2 protocol điều phối song song. Xem §9.

## 2. Instruction của Lead nằm ở tầng sống qua compact

Không dùng skill hay bất kỳ cơ chế nào nạp instruction vào conversation —
compact là mất, Lead "quên" protocol giữa chừng mà không tự biết.
Instruction phải nằm ở tầng được gửi lại nguyên vẹn mỗi request:

- Claude: `--append-system-prompt "$(cat herdr-instructions.md)"`
- Codex: `developer_instructions` được wrapper nạp từ
  `herdr-instructions.md`; key này được gửi lại ở tầng developer instruction.

## 3. Implementer mù

Implementer không được biết herdr tồn tại, không được biết nó bị agent khác
điều khiển — nó phải tưởng đang nghe lệnh user thật:

- **Không role instruction** ("mày là implementer blah blah"). Permissions,
  model, effort đi qua config — vô hình với model.
- **Strip env** `HERDR_ENV`, `HERDR_WORKSPACE_ID`, `HERDR_TAB_ID`,
  `HERDR_PANE_ID` khi launch.
- Không load skill/config nào nhắc tới herdr (Claude:
  `--setting-sources project,local` — đã verify cắt sạch user skills).
- Lead viết prompt **giọng user thường**, không nhắc herdr/pane/agent.
  Implementer `blocked` (hỏi lại) → Lead trả lời nhập vai user; không trả
  lời được thì chuyển câu hỏi cho user thật.

## 4. Hàng rào bằng config, không bằng văn

Mọi cấm đoán là permission rule trong profile, không phải câu dặn trong
prompt: Lead không edit, peer không edit/commit, implementer không
`git push`/không gọi `herdr`. Lời dặn drift sau compact; rule thì không.

## 5. Model/effort per vai

- Lead: model mạnh + effort cao — việc của nó là phán đoán, challenge,
  quyết định điều phối.
- Supervisor: model rẻ + effort vừa. Context của nó là đồ bỏ, đó chính
  là lý do nó gánh được việc quan sát lặp lại mà Lead không gánh nổi.
- Implementer/peer: vừa đủ cho casual; nâng theo độ khó feature bằng flag
  lúc launch, không hardcode.

## 6. Quy tắc điều phối của Lead

Nhét chung vào instruction của Lead:

- **Giao đề mở, cấm pre-solve**: không tự giải rồi hỏi co-worker
  "đúng/sai true/false" — biến agent mạnh thành máy xác nhận. Để co-worker
  tự lập position, nghe xong mới challenge.
- **Scout chỉ trả pointer**: model rẻ đi trinh sát chỉ được chỉ đường
  (file, symbol, "chỗ này nghi impact lớn — cần verify"), không được kết
  luận. Kết luận phải do agent đủ mạnh sở hữu hoặc Lead tự kiểm chứng;
  kiểm chứng đắt hơn tự tra thì bỏ scout.
- **Run lock**: mỗi thời điểm 1 agent được chạy test/lệnh đụng env chung
  (server, port, DB). Trao quyền rõ trong prompt. Chạy song song → env nát
  → red test giả.
- **Balloon guard**: foundation yếu mà implementer đắp mutex/heuristic/
  retry/special-case lên rồi khen đẹp → dừng feature, báo user xử
  foundation trước.
- **idle và done đều là xong**: pane nền báo `done`, pane đang được nhìn
  báo `idle` — chờ đúng 1 status là treo vô hạn.
- **Handoff qua file** (`.herdr-handoff/<topic>.md` trong worktree), không
  scrape scrollback — `pane read` cắt dòng, mất thông tin.
- **Fail 2 lần → escalate**: gom report + transcript, tóm tắt cho user
  thật, chờ chỉ đạo. Không tự làm thay.
- **Đặt tên plan lớn** (vd "plan bigbang") để human và agent reference
  thống nhất.
- **Owner boundary**: scope đã có owner thì Lead không đọc chồng lên — không
  tái chẩn đoán, không chạy test của owner, không viết patch cạnh tranh. Trả
  lời decision gate ≠ lấy lại quyền sở hữu. Hỏi "đã hội tụ tới đâu, còn gì
  trước handback" là supervision; đọc diff của owner trước handback là
  shadowing.
- **Continuity qua compact**: giữ bản đồ gọn (tên seat, `terminal_id`, scope,
  attention point kế tiếp). Sau compact/restart, dựng lại phòng **một lần**
  từ `herdr agent list` + artifact bền, không bulk-read mọi seat.
- **Provenance của evidence**: owner là đứa duy nhất chạy test cho scope của
  nó và báo cái nó **tự quan sát**. Advisory seat đọc report chứ không rerun
  để xác nhận lại.

## 7. Attention: cấm polling

Đây là lỗi đắt nhất trong phòng. Mỗi lần đọc thừa là context của Lead bị đốt,
và Lead compact giữa chừng là mất phòng.

- **Per-seat, không global timer**: mỗi seat có attention point riêng; wake kế
  tiếp là cái sớm nhất. Không bao giờ chờ dài trên implementer khi peer có thể
  trả lời sớm hơn.
- **Timeout không phải thông tin**: wait hết giờ chỉ nghĩa là event chưa xảy
  ra. Không phải progress, không phải failure, **không phải lý do báo user**.
  Cấm `agent get` sau timeout để xác nhận không có gì đổi.
- **10 phút là trần, không phải default**: quá 10 phút không quan sát được gì
  mới trên một seat thì **phải lấy thông tin mới** trước khi chờ tiếp — delta
  tiến độ có giới hạn, checkpoint lifecycle, hoặc quyết định continuity.
  Status không đổi / process còn sống / terminal có chữ chạy **không tính**.
  Activity ≠ convergence.
- **Event-driven thay poll**: plugin `attention-broker` push một prompt
  `HERDR_ATTENTION_EVENT` vào pane Lead khi seat khác `idle`/`done`/`blocked`.
  Persist trước khi gửi, gửi fail thì giữ queue, retry khi Lead `idle`.

## 8. Cấm goal, cấm skill

Hai cơ chế khác nhau, cùng một hậu quả: phá invariant của phòng.

- **Goal** (Codex `goals`, DB `~/.codex/goals_1.sqlite`, bảng `thread_goals`):
  runtime tự re-enter thread theo lịch của nó tới khi objective xong. Trong
  phòng có seat sống, đó chính là poll loop tự sinh — đốt context, đọc state
  không đổi, không hội tụ. Tắt bằng `[features] goals = false` **và** cấm
  trong instruction; hook deny thêm mọi tool tên goal.
- **Skill**: skill nạp vào conversation → compact là mất → Lead quên protocol
  giữa chừng mà không tự biết. Tệ hơn: skill dạy điều khiển phòng bị **kế
  thừa xuống seat**, seat tự mở pane riêng → topology không còn khớp thực tế,
  mất luôn single-writer. Protocol phải nằm ở tầng system prompt đúng vì lý do
  này.

  Mức chặn **không đều giữa 3 CLI**:
  - Claude: deny tool `Skill` — kín, cộng `--setting-sources project,local`
    cắt sạch user/plugin skills.
  - opencode: `permission.skill: deny` — kín.
  - Codex: **chỉ chặn được một phần**. Không có tool `Skill` đơn lẻ; skill
    filesystem đọc qua chính `SKILL.md` như file thường. Hook deny
    `skills.list`/`skills.read` (đường provider-backed), còn đường filesystem
    chỉ chặn bằng instruction + read-only sandbox ở vai không phải implementer.
    Implementer đọc được `SKILL.md` nếu repo có — nhưng nó mù herdr nên skill
    điều khiển phòng không tới tay nó.

## 9. Giết sub-agent phải đúng tầng

`[features] multi_agent = false` **không đủ** trên sol-family. Mỗi entry model
trong catalog cache mang key riêng `multi_agent_version` (`"v2"` cho
`gpt-5.6-sol` và `gpt-5.6-terra`, `"v1"` cho `gpt-5.6-luna`) và giá trị
per-model đó thắng feature flag.

- Codex: `./patch-model-cache.sh` set `multi_agent_version = null` cho các
  model đó — đúng shape của model đời cũ (gpt-5.5 trở xuống) vốn không có key
  này. Catalog là **cache**, bị refetch → phải chạy lại sau update/refresh.
  `--check` để soi, `--restore` để hoàn nguyên.
- opencode: `agent.<name>.permission.task = "deny"` chỉ phủ agent do mình
  định nghĩa; global config luôn merge và project config có thể bật lại.
  Chặn cứng bằng plugin `tool.execute.before` throw — chạy cho mọi session bất
  kể agent/config layer nào.
- Claude: deny `Task`/`Agent`/`Skill` trong permissions.

## 10. Mỗi profile = một lệnh launch

- Claude: không có named profile → wrapper script ghép
  `--settings` + `--setting-sources` + `--append-system-prompt` + strip env.
- Codex: profile hiện là file riêng `$CODEX_HOME/<name>.config.toml`, được
  chọn bằng `codex --profile <name>`. Vẫn cần wrapper mỏng để strip env ở
  implementer/peer và nạp instruction Lead từ file.

## 11. Đi từ từ

Chạy feature nhỏ trước, quan sát Lead sai chỗ nào, vá instruction, lặp lại.
Chưa dựng monitor thường trực hay negotiation contract khi vòng cơ bản chưa
mượt. Transparent, không blackbox: mỗi thứ cài thêm phải nói rõ nó affect
gì.

## Bảng quy đổi Claude ↔ Codex ↔ opencode

| Thứ | Claude Code | Codex | opencode |
| --- | --- | --- | --- |
| Profile | `--settings x.json` + wrapper | `$CODEX_HOME/<name>.config.toml` + `--profile x` | `OPENCODE_CONFIG` (file) hoặc `OPENCODE_CONFIG_CONTENT` (inline) + `--agent <name>` |
| Effort | `"effortLevel"` (`low..max`) | `model_reasoning_effort` | `agent.<name>.variant` (`minimal`/`low`/`medium`/`high`/`max`) |
| Chặn edit | permissions deny `Edit`/`Write` | Lead: `PreToolUse` hook; peer: read-only sandbox + hook | `agent.<name>.permission.edit: deny` |
| Cắt user skills | `--setting-sources project,local` | kiểm tra AGENTS.md/config không nhắc herdr | không có equivalent; tắt riêng từng MCP nguy hiểm (bridgememory) trong OPENCODE_CONFIG |
| Instruction Lead | `--append-system-prompt` | wrapper set `developer_instructions` | `agent.herdr-orchestrator.prompt` trong `OPENCODE_CONFIG_CONTENT` (runtime-built, thắng project config) |
| Tắt sub-agent | deny `Task`/`Agent`/`Skill` | `[features] multi_agent = false` + hook **+ `patch-model-cache.sh`** (per-model `multi_agent_version` thắng feature flag) | `permission.task: deny` **+ plugin `tool.execute.before` throw** (config layer nào cũng bypass được rule) |
| Tắt goal | không có cơ chế tương đương | `[features] goals = false` + hook deny tool goal | không có cơ chế tương đương |

**Nguyên tắc verify**: mọi key/flag đánh dấu *verify* phải check bằng
`codex --help` / docs bản đang cài, không tin trí nhớ model — bài học từ vụ
`MAX_THINKING_TOKENS` vs `effortLevel`.
