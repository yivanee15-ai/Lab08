# Lab08 — Coupling Network（clock gating / SEC）

交付檔：`LAB8_DESIGN.v`（含 `cg_en` 與 `GATED_OR`）、`LAB8_DESIGN_wocg.v`（由腳本自動產生，除 gating 外逐行相同）。

> **重要聲明**：這個環境沒有 VCS / Design Compiler / PrimeTime / JasperGold。
> 功能是用 iverilog 驗證（RTL 三種模式＋gate-level）；面積與功耗是用 yosys＋翻轉次數做的**代理估計**，只適合拿來比較版本間的相對好壞，
> 絕對數字、timing（15 ns）、10 % 省電門檻、JG SEC 都必須在課程環境實跑確認。

## 1. Spec 整理

| 項目 | 內容 |
|---|---|
| 輸入 | `in_valid` 連續 97 拍：第 1 拍 `task_num`(`in_data[0]`)，接著 A、B（各 16 拍、8-bit），F1、H1、F2、H2（各 16 拍、4-bit），皆 raster-scan |
| 輸出 | `out_valid` 連續 32 拍：OUT_A 16 拍、OUT_B 16 拍（12-bit，backward 高 4 bit 為 0）；無效時 `out_data` = 0 |
| 限制 | 週期固定 15 ns、latency ≤ 200、面積 ≤ 600000、不可用 memory / DesignWare IP、合成不可有 latch（gating latch 除外）、cg 省電 ≥ 10 % |
| 分數 | Total Latency × (gated Power)² × Area |

共用定義（M 為被乘的矩陣，全部無號）：`X = (F × M) % 15 + 1`（1..15）、`Y = (H × M) % 256`。

**Task 0（forward）**
1. `X1,Y1` 由 (F1,H1,A)；`Mid_B = (X1 ∘ B) ^ Y1`（12-bit）
2. `X2,Y2` 由 (F2,H2,Mid_B)；`OUT_A = (X2 ∘ A) ^ Y2`，`OUT_B = Mid_B`

**Task 1（backward）**
1. `X2,Y2` 由 (F2,H2,B)；`Mid_A = (A ^ Y2) / X2`（整數除法）
2. `X1,Y1` 由 (F1,H1,Mid_A)；`OUT_A = Mid_A`，`OUT_B = (B ^ Y1) / X1`

### 小例子（`python3 golden/example.py`）
A = 1..16、B = 10,20,…,160、F1 = I、H1 = 2I、F2 = 列交換矩陣、H2 = 全 1。

Forward：`X1 = A%15+1`（第一列 2 3 4 5）、`Y1 = 2A`（2 4 6 8）→ `Mid_B` 第一列 = (2·10)^2, (3·20)^4, (4·30)^6, (5·40)^8 = **22 56 126 192**；
`X2` 第一列 10 5 5 15、`Y2` 第一列 216 96 130 224 → `OUT_A` 第一列 = (10·1)^216, (5·2)^96, (5·3)^130, (15·4)^224 = **210 106 141 220**；`OUT_B = Mid_B`。

Backward：`X2` 第一列 6 1 11 6、`Y2` 第一列 24 64 104 144 → `Mid_A` 第一列 = (1^24)/6, (2^64)/1, (3^104)/11, (4^144)/6 = **4 66 9 24**；
`X1` 第一列 5 7 10 10、`Y1` 第一列 8 132 18 48 → `OUT_B` 第一列 = (10^8)/5, (20^132)/7, (30^18)/10, (40^48)/10 = **0 20 1 2**。

### 我對 spec 模糊處的判斷
- **Latency = 1**：`out_valid` 在 `in_valid` 落下後的下一個 clock edge 才升起。若提早一拍，波形上會與 `in_valid` 重疊半個週期（常見的 pattern 會判 overlap），所以不採用。這是不違規的最小值。
- 除法為整數（無條件捨去）；除數 X 永遠 ≥ 1。
- 資料暫存器沒有 reset（輸出與控制暫存器有）。每個值在同一筆 pattern 內都是先寫後讀，輸出不會出現 X（gate-level 模擬已確認）。若 JG 或助教要求全部 reset，再加上即可，只增加面積。

## 2. Pattern 與驗證

| 檔案 | 用途 |
|---|---|
| `golden/golden.py` | Python golden model，產生 `input.txt` / `output.txt`（前 12 筆為全 0、全最大、F=0、H=0 等邊界，兩種 task 各一） |
| `00_TESTBED/PATTERN.v` | 讀檔驅動；**內含另一份獨立的 Verilog golden**，與 Python 結果互相比對；檢查 reset 值、`out_data`=0、valid 不重疊、latency ≤ 200、恰好 32 拍、輸入間隔 2~5 拍；無效輸入與 F/H 的高 4 bit 餵 X |
| `scripts/sim.sh` | 同一份設計跑三種模式：wocg、cg_en=0、cg_en=1 |
| `scripts/lockstep.sh` | 簡易 SEC：gated 與 wocg 兩份設計餵**完全隨機、不守協定**的 `in_valid`/`in_data`（`cg_en` 也隨機變），逐拍比對輸出 |
| `scripts/eval.sh` | yosys 合成成通用閘 → 帶延遲的 gate-level 模擬（同一個 PATTERN）→ 面積／翻轉功耗代理 |

最終版結果：三種模式各 5000 筆全過；gate-level（wocg 與 cg）全過；lockstep 40 萬拍、88339 個輸出拍一致。

## 3. 版本演進（代理數字，僅供相對比較）

| 版本 | 重點 | Latency | 面積 | 能量/拍 (cg) | cg 省電 | Latency×P²×A（相對） |
|---|---|---|---|---|---|---|
| v1 naive | 全存、輸入完才算（`%`、`/` 直接寫），每個矩陣一個 gate | 33 | 306.7k | 93.1 | 66 % | **87.8** |
| v3 | latency 1；逐元素原地更新、單一寫入匯流排、每個 word 一個 gate；mod 15 改 end-around-carry | 1 | 186.5k | 155.9 | 35 % | 4.53 |
| v4 | 閒置運算單元 operand isolation、讀取 mux 凍結、寫入匯流排逐列隔離 | 1 | 191.7k | 100.4 | 46 % | 1.93 |
| v5 | X 單元改平衡式 carry-save 樹 | 1 | 190.4k | 100.8 | 46 % | 1.94 |
| v6 | forward 的 X、Y 同拍計算（運算拍數減半）— **失敗的嘗試** | 1 | 194.3k | 103.3 | 45 % | 2.07 |
| v7 | 兩級 pipeline：第 1 級算 X/Y 存入 P，第 2 級乘／除；forward、backward 都只算一趟 | 1 | 200.3k | 75.4 | 54 % | 1.14 |
| **v8（交付）** | 每兩個 word 共用一個 gate（41 → 25 個 gating cell） | 1 | 197.9k | 73.2 | 55 % | **1.06** |

- v1 → v8 約 83 倍，其中 33 倍來自 latency，其餘來自 P²×A。
- v5 在代理中沒有差別；保留是因為真實 cell library 有 full adder，carry-save 樹應該較小。這點我沒有量到，只是推論。
- v6 把 X → 乘法器 → XOR 串成一條長組合路徑，glitch 變多，功耗沒降；v7 用 pipeline register 切斷後才真的降下來，邏輯深度也從 98 降到 64 級。
- v2 是空號：原本想做的「全 shift register」版本沒有實作，理由見第 5 節。

## 4. 最終架構（v8）

計數器 `k` = task 拍之後的拍數（0..127），`k[6:4]` 即階段：0 A、1 B、2 F1、3 H1、4 F2、5 H2、6 OUT_A、7 OUT_B。

**儲存（518 個 flop）**
- `WA`、`WB`：各 16 個 12-bit word `{hi[3:0], lo[7:0]}`，原地更新。
  forward：`WA` = A → OUT_A，`WB` = B → Mid_B。backward：`WA` = {F2, A → Mid_A}，`WB` = {F1, B}。
- `HS`：4 列 × 16 bit 的係數列，以 nibble shift 寫入。forward 放 F1／F2 列，backward 放 H1。
- `s`（3-nibble shift）＋ `h`（4-nibble hold）：正在接收的 H 列。
- `P` = {X, Y, 元素}：兩級之間的 pipeline register（20 bit）。

**每拍處理一個元素**
- 第 1 級：讀運算元矩陣的一整行（4 個 word）與要更新的元素，算出 `X`、`Y` 存入 `P`。
- 第 2 級：forward `word ← (P.X × P.el) ^ P.Y`；backward `word ← (P.el ^ P.Y) / P.X`，OUT_B 則直接送到 `out_data`。

| | 第 1 級 (k) | 第 2 級寫入 (k) |
|---|---|---|
| forward Mid_B | 52..67 | 53..68 |
| forward OUT_A | 84..99 | 85..100 |
| backward Mid_A | 84..99 | 85..100 |
| backward OUT_B | 108、112..126 | 直接輸出 112..127 |

輸出從 k = 96 開始，所以最後一列是邊輸出邊算完的；每個元素都在被讀出前至少 11 拍寫好。

**利用到的規律**
- `2⁴ ≡ 1 (mod 15)`：12-bit 數的 mod 15 等於三個 nibble 相加；乘 2 等於 4-bit 旋轉。X 單元因此只需要 4-bit 的 end-around-carry 加法，不需要 18-bit 乘加再取餘數（單獨合成約小 4 倍）。把常數 1 當成一個加數，結果自然落在 1..15，不必再修正。
- `Y` 只取 mod 256，所以 Mid_B 只有低 8 bit 進乘法器。
- 四個矩陣階段都是 16 拍，列的節奏固定，所有讀寫位址都直接由 `k` 解碼，不需要狀態機。
- forward 不需要保存 F1/H1，backward 需要：所以 backward 把 F1、F2 塞進 `WB`、`WA` 用不到的高 4 bit，只多用 64 個 flop（`HS`），而 forward 把這 64 個 flop 拿來暫存 F 列。

**Clock gating**
- 25 個 `GATED_OR`：`WA`/`WB` 每兩個 word 一個（16 個）、`HS` 每列一個（4 個）、`s`、`h`、`P`、輸出、task 各一個。
- 所有 sleep 訊號只由暫存器（`run`、`k`、task）決定，**不直接用 `in_valid`/`in_data`**：輸入在半週期才到，直接拿去控制 latch 會晚一拍。
- 每個 gated 暫存器的資料 enable 就是 sleep 的反相，所以 `cg_en = 0` 時行為完全相同。

## 5. 關於「多用 shift register、讓每個暫存器每拍都有事做」

我照這個方向評估過，結論是**在這題的評分下不划算**，所以只用在小的地方（`s`、`HS` 的列內 shift，省掉寫入解碼）。

- 用 ring shift register 存 `WA`/`WB` 可以省掉讀取 mux、hold mux、位址解碼，我估面積最多省 17 % 左右。
- 但 384 個 flop 每拍都要打 clock、資料也每拍翻轉。代理中 v8 的 wocg（所有 flop 每拍都打 clock，但資料不動）就已經是 163.8，gated 是 73.2；ring 版還要再加資料翻轉，估計 ≥ 200。
- 分數是 P² × A：功耗約 2.7 倍 → P² 約 7.5 倍，遠大於省下的面積。
- 另外 ring 必須持續轉動才能維持對齊，幾乎沒有可以 gate 的時間，10 % 省電門檻也有風險。

這個判斷建立在代理的功耗模型上，ring 版本我沒有實際寫出來量。

## 6. 回到課程環境後要確認的事

1. **Timing**：v8 最長路徑是 `P → XOR → 8/4 除法器 → 寫入`，以及 `讀取 mux → X 單元 → P`。代理顯示 64 級通用閘，我判斷 15 ns 足夠，但沒有 DC 的數字。
2. **PTPX 省電比例**：代理是 55 %，離 10 % 門檻很遠，但請實跑。
3. **JG SEC**：lockstep 模擬一致，但不是形式證明。若因為未 reset 的暫存器出現 CEX，把儲存暫存器加上 reset 即可。
4. **Gating 扇出**：每個 gate 帶 24 個 flop。若 gate-level 出現 spec 第 32 點說的 X，改回每個 word 一個 gate（`rtl/v7_pipe_cg.v`）。
5. **Pair gating 的效益**（v7 → v8，代理約 7 %）取決於真實 `GATED_OR` 與 flop 的 clock 功耗比，請用 PTPX 比較 v7 與 v8 再決定。

## 7. 使用方式

```bash
scripts/sim.sh LAB8_DESIGN.v 5000        # RTL：wocg / cg_en=0 / cg_en=1
scripts/lockstep.sh LAB8_DESIGN.v        # gated vs wocg 隨機激勵逐拍比對
scripts/eval.sh rtl/v8_pair_cg.v 60      # 面積／功耗代理（需要 yosys、iverilog）
python3 scripts/mk_wocg.py LAB8_DESIGN.v LAB8_DESIGN_wocg.v   # 修改後重新產生 wocg
```

課程環境中把 `00_TESTBED/PATTERN.v`、`golden/golden.py` 產生的 `input.txt`/`output.txt` 放進 `01_RTL` 即可用 VCS 跑；`TESTBED.v` 以 `+define+CG` 選擇有無 `cg_en`。
