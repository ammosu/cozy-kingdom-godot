"""概念圖 → Tripo image-to-model → 自動綁骨 → 套預設動作，輸出到 assets/glb/<角色>/<動作>.glb。

每一步的 task id 存在 assets/tripo/state.json，重跑會跳過已完成的步驟（下載失敗不必重花點數）。
角色並行送出，所以只記總點數（前後餘額差）；每步耗時寫到 assets/tripo/log.csv。

用法：.venv/bin/python tools/tripo_chars.py --dry-run | all | <角色> [<角色>...]
"""
import asyncio, csv, json, os, shutil, sys, time
from datetime import datetime
from pathlib import Path
from tripo3d import TripoClient

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "assets" / "tripo" / "state.json"
LOG = ROOT / "assets" / "tripo" / "log.csv"
RAW = ROOT / "assets" / "raw"
OUT = ROOT / "assets" / "glb"

# rig_version／spec：雙足用 v3.0 綁骨＋unreal spec（骨架名稱接近 UE Mannequin，方便 UE 重定向）；失敗時退回預設。
CHARS = {
    "hero": dict(image="concept/hero.png", rig_type="biped", anims=["idle", "walk", "run", "jump"]),
    "villager_badger": dict(image="concept/villager_badger.png", rig_type="biped", anims=["idle", "walk"]),
    "villager_heron": dict(image="concept/villager_heron.png", rig_type="biped", anims=["idle", "walk"]),
    "mount_elk": dict(image="concept/mount_elk.png", rig_type="quadruped", anims=["quadruped:walk"]),
}
FACE_LIMIT = 30000


def env():
    for line in (ROOT / ".env").read_text().splitlines():
        if "=" in line and not line.startswith("#"):
            k, v = line.split("=", 1)
            os.environ.setdefault(k.strip(), v.strip())


def load_state():
    return json.loads(STATE.read_text()) if STATE.exists() else {}


def save_state(s):
    STATE.write_text(json.dumps(s, indent=2, ensure_ascii=False))


async def step(client, label, start):
    t0 = time.time()
    task_id = await start()
    print(label, "task", task_id, flush=True)
    task = await client.wait_for_task(task_id, verbose=False)
    secs = time.time() - t0
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", newline="") as f:
        csv.writer(f).writerow([datetime.now().isoformat(timespec="seconds"), label, task_id, task.status, f"{secs:.0f}"])
    print(label, task.status, f"{secs:.0f}s", flush=True)
    return task_id, task


def ok(task):
    return "success" in str(task.status).lower()


async def download(client, task_id, dest: Path):
    task = await client.get_task(task_id)
    d = RAW / dest.parent.name / dest.stem
    d.mkdir(parents=True, exist_ok=True)
    files = await client.download_task_models(task, str(d))
    src = next(Path(p) for p in files.values() if p)
    dest.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(src, dest)
    print("saved", dest.relative_to(ROOT), flush=True)


async def build(client, name, cfg, state):
    s = state.setdefault(name, {})
    out = OUT / name
    if "model" not in s:
        tid, task = await step(client, f"{name}:model", lambda: client.image_to_model(
            str(ROOT / cfg["image"]), model_version=os.environ["TRIPO_MODEL_VERSION"],
            face_limit=FACE_LIMIT, texture=True, pbr=True))
        if not ok(task):
            raise SystemExit(f"{name} model failed")
        s["model"] = tid; save_state(state)
    if not (out / "model.glb").exists():
        await download(client, s["model"], out / "model.glb")
    if "rig" not in s:
        print(name, "riggable:", await client.check_riggable(s["model"]), flush=True)
        attempts = ([dict(model_version="v3.0-20260909", spec="unreal"), {}] if cfg["rig_type"] == "biped"
                        else [dict(model_version="v3.0-20260909", spec="tripo")])  # 四足要帶 v3.0＋spec，v1.0 回 Invalid input
        for kw in attempts:
            try:
                tid, task = await step(client, f"{name}:rig{'_' + kw['spec'] if kw else ''}", lambda kw=kw: client.rig_model(
                    s["model"], out_format="glb", rig_type=cfg["rig_type"], **kw))
            except Exception as e:  # API 不接受該版本／spec 時改用預設
                print(name, "rig attempt rejected:", e, flush=True)
                continue
            if ok(task):
                s["rig"] = tid; s["rig_kw"] = kw; save_state(state)
                break
        else:
            print(f"{name} rig failed on all attempts", flush=True)
            return
    if not (out / "rigged.glb").exists():
        await download(client, s["rig"], out / "rigged.glb")
    for anim in cfg["anims"]:
        key = "anim_" + anim
        fname = anim.split(":")[-1] + ".glb"
        if key not in s:
            tid, task = await step(client, f"{name}:{key}", lambda a=anim: client.retarget_animation(
                s["rig"], f"preset:{a}", out_format="glb", animate_in_place=True))
            if not ok(task):
                print(name, anim, "failed, skipping", flush=True)
                continue
            s[key] = tid; save_state(state)
        if not (out / fname).exists():
            await download(client, s[key], out / fname)


async def main():
    args = sys.argv[1:] or ["--dry-run"]
    names = list(CHARS) if args[0] in ("all", "--dry-run") else args
    if args[0] == "--dry-run":
        state = load_state()
        for n in names:
            c = CHARS[n]
            done = sorted(state.get(n, {}))
            print(f"{n:16} {c['image']:32} rig={c['rig_type']:9} anims={c['anims']} done={done}")
        print("估計：model ~20、rig ~25、每個動作 ~10 點")
        return
    env()
    state = load_state()
    async with TripoClient(api_key=os.environ["TRIPO_API_KEY"]) as client:
        before = (await client.get_balance()).balance
        print("balance", before, flush=True)
        # 角色之間並行送出，縮短總時間
        await asyncio.gather(*(build(client, n, CHARS[n], state) for n in names))
        after = (await client.get_balance()).balance
        print("balance", after, "spent", before - after, flush=True)


asyncio.run(main())
