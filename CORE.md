# Cốt lõi thiết kế — port sang agent CLI bất kỳ

Tài liệu này tách phần bất biến của mô hình 3-profile khỏi chi tiết Claude
Code, để cấu hình lại cho Codex (hoặc tool khác). 8 bất biến, tool chỉ là
chi tiết triển khai.

## 1. Ba vai, một protocol

- **Root/orchestrator**: điều phối, **bị chặn edit bằng permission** (không
  phải bằng lời dặn), chỉ được gọi CLI `herdr`.
- **Implementer**: **duy nhất được edit**. 1 đứa / 1 feature / 1 worktree.
- **Peer**: read-only, sinh ra ad-hoc để review/phản biện, xong việc đóng
  pane.
- Root bị **tắt cơ chế sub-agent nội bộ** của tool (Claude: deny
  `Task`/`Agent`) — herdr là kênh quản nhân sự duy nhất, không chạy 2
  protocol điều phối song song.

## 2. Instruction của root nằm ở tầng sống qua compact

Không dùng skill hay bất kỳ cơ chế nào nạp instruction vào conversation —
compact là mất, root "quên" protocol giữa chừng mà không tự biết.
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
- Root viết prompt **giọng user thường**, không nhắc herdr/pane/agent.
  Implementer `blocked` (hỏi lại) → root trả lời nhập vai user; không trả
  lời được thì chuyển câu hỏi cho user thật.

## 4. Hàng rào bằng config, không bằng văn

Mọi cấm đoán là permission rule trong profile, không phải câu dặn trong
prompt: root không edit, peer không edit/commit, implementer không
`git push`/không gọi `herdr`. Lời dặn drift sau compact; rule thì không.

## 5. Model/effort per vai

- Root: model mạnh + effort cao — việc của nó là phán đoán, challenge,
  quyết định điều phối.
- Implementer/peer: vừa đủ cho casual; nâng theo độ khó feature bằng flag
  lúc launch, không hardcode.

## 6. Quy tắc điều phối của root

Nhét chung vào instruction của root:

- **Giao đề mở, cấm pre-solve**: không tự giải rồi hỏi co-worker
  "đúng/sai true/false" — biến agent mạnh thành máy xác nhận. Để co-worker
  tự lập position, nghe xong mới challenge.
- **Scout chỉ trả pointer**: model rẻ đi trinh sát chỉ được chỉ đường
  (file, symbol, "chỗ này nghi impact lớn — cần verify"), không được kết
  luận. Kết luận phải do agent đủ mạnh sở hữu hoặc root tự kiểm chứng;
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

## 7. Mỗi profile = một lệnh launch

- Claude: không có named profile → wrapper script ghép
  `--settings` + `--setting-sources` + `--append-system-prompt` + strip env.
- Codex: profile hiện là file riêng `$CODEX_HOME/<name>.config.toml`, được
  chọn bằng `codex --profile <name>`. Vẫn cần wrapper mỏng để strip env ở
  implementer/peer và nạp instruction root từ file.

## 8. Đi từ từ

Chạy feature nhỏ trước, quan sát root sai chỗ nào, vá instruction, lặp lại.
Chưa dựng monitor thường trực hay negotiation contract khi vòng cơ bản chưa
mượt. Transparent, không blackbox: mỗi thứ cài thêm phải nói rõ nó affect
gì.

## Bảng quy đổi Claude ↔ Codex

| Thứ | Claude Code | Codex |
| --- | --- | --- |
| Profile | `--settings x.json` + wrapper | `$CODEX_HOME/<name>.config.toml` + `--profile x` |
| Effort | `"effortLevel"` (`low..max`) | `model_reasoning_effort` |
| Chặn edit | permissions deny `Edit`/`Write` | read-only sandbox + `PreToolUse` hook |
| Cắt user skills | `--setting-sources project,local` | kiểm tra AGENTS.md/config không nhắc herdr |
| Instruction root | `--append-system-prompt` | wrapper set `developer_instructions` |
| Tắt sub-agent | deny `Task`/`Agent` | `[features] multi_agent = false` + hook |

**Nguyên tắc verify**: mọi key/flag đánh dấu *verify* phải check bằng
`codex --help` / docs bản đang cài, không tin trí nhớ model — bài học từ vụ
`MAX_THINKING_TOKENS` vs `effortLevel`.
