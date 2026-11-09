#!/usr/bin/env bash
# 評分迴圈的一輪：固定鏡頭拍每個區塊 → Codex 只看圖評分 → eval/rNN.json
# 用法：tools/eval_round.sh <輪次>；只拍照：SHOTS_ONLY=1；只評分：JUDGE_ONLY=1；只拍部分區塊：AREAS="gate fog_heavy"
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"; cd "$ROOT"
N=$(printf 'r%02d' "$1"); OUT="$ROOT/eval/$N"; mkdir -p "$OUT"
# 區塊｜環境變數｜相機｜看向｜幀數｜給評審的說明
cat > "$OUT/areas.tsv" <<'T'
gate_outside	TIME=3	0,8,90	0,5,55	城門外的大道與城門樓、城牆正面
gate_passage	TIME=3 REL=1	0,1.8,64	0,3,50	從城外走進城門的門洞內部
wall_ground	TIME=3 REL=1	-34,3,64	-52,5,32	貼著城牆與塔樓的地面視角
town_overview	TIME=3	30,40,70	0,0,0	城鎮鳥瞰
street	TIME=3 REL=1	0,1.7,44	0,3,10	從南門往廣場的主街（玩家視角）
houses	TIME=3 REL=1	-14,1.7,30	-24,4,14	民房近景
plaza_fountain	TIME=3	5.5,2.4,16	0,3,8	廣場與噴水池
market	TIME=3	13.5,2.0,-1.5	4.5,1.6,3.5	市集攤位
keep	TIME=3	0,2.2,-13	0,8,-36	主堡正面
meadow	TIME=3 REL=1	18,2.5,88	45,3,110	城外草原與花叢
forest	TIME=3 REL=1	60,2,70	95,14,45	城外樹林
character	TIME=3 PLAYER=0,68 ATTACK_HOLD=0:0.45 REL=1	1.3,1.15,66.0	0,0.85,68	主角持劍揮砍的近景
fog_morning	TIME=3 FOG=1 REL=1	6,1.1,88	0,4,50	晨霧特效
fog_heavy	TIME=3 FOG=2	0,8,90	0,5,55	濃霧特效
T
if [ -z "${JUDGE_ONLY:-}" ]; then
  while IFS=$'\t' read -r a envs cam look desc; do
    if [ -n "${AREAS:-}" ] && ! [[ " $AREAS " == *" $a "* ]]; then continue; fi
    env $envs "$ROOT/tools/shot.sh" "eval_tmp" "$cam" "$look" 240 2>&1 | grep -E "SCRIPT ERROR|SHADER ERROR" | head -3
    mv "$ROOT/shots/eval_tmp.png" "$OUT/$a.png"
  done < "$OUT/areas.tsv"
fi
[ -n "${SHOTS_ONLY:-}" ] && exit 0
list=""; imgs=()
while IFS=$'\t' read -r a envs cam look desc; do
  list="$list
- $a：$desc"; imgs+=(-i "$OUT/$a.png")
done < "$OUT/areas.tsv"
PROMPT="$(cat eval/rubric.md)

附圖依序是這些區塊：$list

請只回傳一段 JSON（不要 markdown 圍欄、不要其他文字），格式：
{\"areas\":{\"<區塊>\":{\"score\":<0-10，可到小數一位>,\"issues\":[\"依嚴重度排序、看得見且具體的問題（在畫面哪裡、什麼問題）\"],\"fix\":\"最值得先做的一項改善\"}},\"overall\":<平均>}
不要因為看不到前後比較就給中間分，直接依錨點判斷。"
timeout 900 codex exec -s read-only --skip-git-repo-check -C /tmp -o "$ROOT/eval/$N.json" "$PROMPT" "${imgs[@]}" < /dev/null > "$OUT/codex.log" 2>&1
python3 - "$ROOT/eval/$N.json" <<'P'
import json,sys
d=json.load(open(sys.argv[1]))
for k,v in d["areas"].items(): print(f"{v['score']:>4} {k:15} {v['fix']}")
print("overall",d.get("overall"), "min",min(v["score"] for v in d["areas"].values()))
P
