from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import subprocess
import paramiko
import os
from datetime import datetime
from dotenv import load_dotenv

load_dotenv()

app = FastAPI(
    title="PatchGuard API",
    description="Automated Linux Security Patch Management",
    version="1.0.0"
)

# Allow PWA to call the API
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["*"],
    allow_headers=["*"],
)

# Serve static files (PWA)
app.mount("/static", StaticFiles(directory="src/static"), name="static")

# ── Config ────────────────────────────────────────────────────────────────────
SSH_USER    = os.getenv("SSH_USER", "raylab")
SSH_KEY     = os.getenv("SSH_KEY_PATH", "/home/raymond/.ssh/patch_key")
SSH_TIMEOUT = int(os.getenv("SSH_TIMEOUT", "10"))
SERVERS     = {
    "srv-patch":  "localhost",
    "srv-cible1": os.getenv("SERVER_1", "192.168.56.101"),
    "srv-cible2": os.getenv("SERVER_2", "192.168.56.102"),
    "srv-cible3": os.getenv("SERVER_3", "192.168.56.103"),
}
INVENTORY   = os.getenv("ANSIBLE_INVENTORY")
PB_CHECK    = os.getenv("ANSIBLE_PLAYBOOK_CHECK")
PB_APPLY    = os.getenv("ANSIBLE_PLAYBOOK_APPLY")
AUDIT_SH    = os.getenv("SCRIPT_AUDIT")

# ── Helper : run SSH command on a remote server ───────────────────────────────
def ssh_run(host: str, command: str) -> dict:
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=host,
            username=SSH_USER,
            key_filename=SSH_KEY,
            timeout=SSH_TIMEOUT
        )
        stdin, stdout, stderr = client.exec_command(command)
        output = stdout.read().decode().strip()
        error  = stderr.read().decode().strip()
        client.close()
        return {"success": True, "output": output, "error": error}
    except Exception as e:
        return {"success": False, "output": "", "error": str(e)}

# ── Helper : run local command ────────────────────────────────────────────────
def local_run(command: str) -> dict:
    try:
        result = subprocess.run(
            command, shell=True,
            capture_output=True, text=True, timeout=600
        )
        return {
            "success": result.returncode == 0,
            "output": result.stdout.strip(),
            "error":  result.stderr.strip()
        }
    except subprocess.TimeoutExpired:
        return {"success": False, "output": "", "error": "Command timed out"}
    except Exception as e:
        return {"success": False, "output": "", "error": str(e)}

# ════════════════════════════════════════════════════════════════════════════
# ROUTES
# ════════════════════════════════════════════════════════════════════════════

# ── Root : serve PWA ──────────────────────────────────────────────────────────
@app.get("/")
async def root():
    return FileResponse("src/templates/index.html")

# ── Health check ──────────────────────────────────────────────────────────────
@app.get("/api/health")
async def health():
    return {
        "status": "ok",
        "version": "1.0.0",
        "timestamp": datetime.now().isoformat()
    }

# ── Get status of all servers ─────────────────────────────────────────────────
@app.get("/api/status")
async def get_status():
    results = {}
    for name, host in SERVERS.items():
        if host == "localhost":
            r = local_run("uptime && df -h / | tail -1 && free -m | grep Mem")
        else:
            r = ssh_run(host, "uptime && df -h / | tail -1 && free -m | grep Mem")
        results[name] = {
            "host":    host,
            "online":  r["success"],
            "data":    r["output"],
            "checked": datetime.now().isoformat()
        }
    return {"servers": results, "timestamp": datetime.now().isoformat()}

# ── Get patch count for each server ──────────────────────────────────────────
@app.get("/api/patches")
async def get_patches():
    results = {}
    cmd = "apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0"
    for name, host in SERVERS.items():
        if host == "localhost":
            r = local_run(cmd)
        else:
            r = ssh_run(host, cmd)
        count = 0
        if r["success"] and r["output"].isdigit():
            count = int(r["output"])
        results[name] = {
            "host":    host,
            "patches": count,
            "checked": datetime.now().isoformat()
        }
    return {"patches": results, "timestamp": datetime.now().isoformat()}

# ── Get Lynis hardening index ─────────────────────────────────────────────────
@app.get("/api/lynis")
async def get_lynis():
    results = {}
    cmd = "grep 'hardening_index' /var/log/lynis-report.dat 2>/dev/null | cut -d'=' -f2 || echo 0"
    for name, host in SERVERS.items():
        if host == "localhost":
            r = local_run(cmd)
        else:
            r = ssh_run(host, cmd)
        score = 0
        if r["success"] and r["output"].isdigit():
            score = int(r["output"])
        results[name] = {
            "host":  host,
            "score": score,
            "max":   100
        }
    return {"lynis": results, "timestamp": datetime.now().isoformat()}

# ── Get cron logs ─────────────────────────────────────────────────────────────
@app.get("/api/logs")
async def get_logs(lines: int = 50):
    r = local_run(f"tail -{lines} /var/log/patch-manager-cron.log 2>/dev/null || echo 'No logs found'")
    return {
        "logs":      r["output"].split("\n"),
        "lines":     lines,
        "timestamp": datetime.now().isoformat()
    }

# ── Run Ansible check (read-only) ─────────────────────────────────────────────
@app.post("/api/ansible/check")
async def ansible_check():
    r = local_run(f"ansible-playbook -i {INVENTORY} {PB_CHECK}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Run Ansible apply patches ─────────────────────────────────────────────────
@app.post("/api/ansible/apply")
async def ansible_apply():
    r = local_run(f"ansible-playbook -i {INVENTORY} {PB_APPLY}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Run manual audit ──────────────────────────────────────────────────────────
@app.post("/api/audit")
async def run_audit():
    r = local_run(f"sudo {AUDIT_SH}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }
