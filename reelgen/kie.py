"""Kie.ai client: upload files, run any /jobs/createTask model (GPT Image 2, Gemini TTS, ...) and Suno, in parallel.

Each job: {"name", "kind": "task"|"suno", "body": {...createTask body...} | "prompt": str, "ext": "png"}
The API key is read from KIE_API_KEY (or the older kieapikey) environment variable.
"""
import base64, json, os, sys, time, urllib.request
from concurrent.futures import ThreadPoolExecutor

KEY = os.environ.get("KIE_API_KEY") or os.environ.get("kieapikey") or ""
BASE = "https://api.kie.ai/api/v1"


def call(method, url, body=None):
    req = urllib.request.Request(
        url if url.startswith("http") else BASE + url, method=method,
        data=json.dumps(body).encode() if body else None,
        headers={"Authorization": f"Bearer {KEY}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=120) as r:
        return json.load(r)


def upload(path):
    mime = "image/png" if path.endswith(".png") else "image/jpeg"
    b64 = base64.b64encode(open(path, "rb").read()).decode()
    r = call("POST", "https://kieai.redpandaai.co/api/file-base64-upload", {
        "base64Data": f"data:{mime};base64,{b64}", "uploadPath": "images/reel",
        "fileName": os.path.basename(path)})
    return r["data"]["downloadUrl"]


def credits():
    return call("GET", "/chat/credit")["data"]


def task(job, out):
    r = call("POST", "/jobs/createTask", job["body"])
    if r.get("code") != 200:
        raise RuntimeError(f"create: {r}")
    tid = r["data"]["taskId"]
    t0 = time.time()
    while True:
        time.sleep(6)
        d = call("GET", f"/jobs/recordInfo?taskId={tid}")["data"]
        if d["state"] == "success":
            url = json.loads(d["resultJson"])["resultUrls"][0]
            path = os.path.join(out, f"{job['name']}.{job.get('ext', url.rsplit('.', 1)[-1].split('?')[0])}")
            urllib.request.urlretrieve(url, path)
            return f"{path} ({time.time() - t0:.0f}s)"
        if d["state"] == "fail":
            raise RuntimeError(f"{d.get('failCode')} {d.get('failMsg')}")


def suno(job, out):
    r = call("POST", "/generate", {"prompt": job["prompt"], "customMode": False, "instrumental": True,
                                   "model": "V4_5", "callBackUrl": "https://example.com/noop"})
    if r.get("code") != 200:
        raise RuntimeError(f"suno create: {r}")
    tid = r["data"]["taskId"]
    while True:
        time.sleep(8)
        d = call("GET", f"/generate/record-info?taskId={tid}")["data"]
        if d["status"] == "SUCCESS":
            paths = []
            for i, s in enumerate(d["response"]["sunoData"]):
                p = os.path.join(out, f"{job['name']}_{i}.mp3")
                urllib.request.urlretrieve(s["audioUrl"], p); paths.append(p)
            return ", ".join(paths)
        if "FAIL" in d["status"] or "ERROR" in d["status"]:
            raise RuntimeError(f"suno: {d}")


def run_jobs(jobs, out):
    """Run jobs in parallel; returns {name: path or None}. Prints credits spent."""
    os.makedirs(out, exist_ok=True)
    before = credits(); results = {}
    with ThreadPoolExecutor(12) as ex:
        futs = {j["name"]: ex.submit(suno if j["kind"] == "suno" else task, j, out) for j in jobs}
        for n, f in futs.items():
            try:
                results[n] = f.result(); print(f"  {n} -> {results[n]}", flush=True)
            except Exception as e:
                results[n] = None; print(f"  {n} FAILED {e}", flush=True)
    after = credits()
    print(f"  kie credits {before} -> {after} (spent {before - after:.2f})")
    return results


if __name__ == "__main__":
    run_jobs(json.load(open(sys.argv[1])), sys.argv[2])
