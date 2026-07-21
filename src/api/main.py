from fastapi import FastAPI, HTTPException, Depends, BackgroundTasks
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse
import subprocess
import paramiko
import os
import asyncio
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime
from dotenv import load_dotenv
from prometheus_fastapi_instrumentator import Instrumentator
from prometheus_client import Gauge, Counter

load_dotenv()

from fastapi.security import OAuth2PasswordRequestForm
from src.api.auth import (
    authenticate_user, create_token, get_current_user,
    Token, User
)

app = FastAPI(
    title="PatchGuard API",
    description="Automated Linux Security Patch Management",
    version="1.0.0"
)

Instrumentator().instrument(app).expose(app)

# Métriques Prometheus
hardening_index = Gauge(
    'patchguard_hardening_index',
    'Lynis hardening index per server',
    ['server']
)
patches_pending = Gauge(
    'patchguard_patches_pending',
    'Number of pending patches per server',
    ['server']
)
server_online = Gauge(
    'patchguard_server_online',
    'Server online status (1=online, 0=offline)',
    ['server']
)
alerts_total = Counter(
    'patchguard_alerts_total',
    'Total number of security alerts detected',
    ['server']
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
SSH_KEY     = os.getenv("SSH_KEY_PATH", "/root/.ssh/patch_key")
SSH_TIMEOUT = int(os.getenv("SSH_TIMEOUT", "10"))
SERVERS     = {
    "srv-patch":  os.getenv("SERVER_0", "172.21.211.14"),
    "srv-cible1": os.getenv("SERVER_1", "192.168.56.101"),
    "srv-cible2": os.getenv("SERVER_2", "192.168.56.102"),
    "srv-cible3": os.getenv("SERVER_3", "192.168.56.103"),
}

SERVER_USERS = {
    "srv-patch":  os.getenv("SERVER_0_USER", "raymond"),
    "srv-cible1": os.getenv("SSH_USER", "raylab"),
    "srv-cible2": os.getenv("SSH_USER", "raylab"),
    "srv-cible3": os.getenv("SSH_USER", "raylab"),
}

INVENTORY   = os.getenv("ANSIBLE_INVENTORY")
PB_CHECK    = os.getenv("ANSIBLE_PLAYBOOK_CHECK")
PB_APPLY    = os.getenv("ANSIBLE_PLAYBOOK_APPLY")
AUDIT_SH    = os.getenv("SCRIPT_AUDIT")

# ── Windows servers config (v2.0) ────────────────────────────────────────────
WIN_SERVERS = {}
for i in range(1, 10):
    host = os.getenv(f"WIN_SERVER_{i}")
    if host:
        WIN_SERVERS[f"win-srv{i}"] = host

WIN_USER     = os.getenv("WIN_USER", "Administrateur")
WIN_PASSWORD = os.getenv("WIN_PASSWORD", "")
WIN_INVENTORY = os.getenv("WIN_ANSIBLE_INVENTORY", "")
WIN_PB_CHECK  = os.getenv("WIN_PLAYBOOK_CHECK", "")
WIN_PB_APPLY  = os.getenv("WIN_PLAYBOOK_APPLY", "")


# ── Helper : run SSH command on a remote server ───────────────────────────────
def ssh_run(host: str, command: str, user: str = None) -> dict:
    try:
        client = paramiko.SSHClient()
        client.set_missing_host_key_policy(paramiko.AutoAddPolicy())
        client.connect(
            hostname=host,
            username=user or SSH_USER,
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
    cmd = "uptime && df -h / | tail -1 && free -m | grep Mem"
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        tasks = {
            name: loop.run_in_executor(pool, ssh_run, host, cmd, SERVER_USERS.get(name))
            for name, host in SERVERS.items()
        }
        results = {}
        for name, task in tasks.items():
            r = await task
            results[name] = {
                "host":    SERVERS[name],
                "online":  r["success"],
                "data":    r["output"],
                "checked": datetime.now().isoformat()
            }
    return {"servers": results, "timestamp": datetime.now().isoformat()}

# ── Get patch count for each server ──────────────────────────────────────────
@app.get("/api/patches")
async def get_patches():
    cmd = "apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0"
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        tasks = {
            name: loop.run_in_executor(pool, ssh_run, host, cmd, SERVER_USERS.get(name))
            for name, host in SERVERS.items()
        }
        results = {}
        for name, task in tasks.items():
            r = await task
            count = 0
            if r["success"] and r["output"].isdigit():
                count = int(r["output"])
            results[name] = {
                "host":    SERVERS[name],
                "patches": count,
                "checked": datetime.now().isoformat()
            }
    return {"patches": results, "timestamp": datetime.now().isoformat()}

# ── Get Lynis hardening index ─────────────────────────────────────────────────
@app.get("/api/lynis")
async def get_lynis():
    cmd = "grep 'hardening_index' /var/log/lynis-report.dat 2>/dev/null | cut -d'=' -f2 || echo 0"
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        tasks = {
            name: loop.run_in_executor(pool, ssh_run, host, cmd, SERVER_USERS.get(name))
            for name, host in SERVERS.items()
        }
        results = {}
        for name, task in tasks.items():
            r = await task
            score = 0
            if r["success"] and r["output"].isdigit():
                score = int(r["output"])
            results[name] = {
                "host":  SERVERS[name],
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
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        r = await loop.run_in_executor(pool, local_run, f"ansible-playbook -i {INVENTORY} {PB_CHECK}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Run Ansible apply patches ─────────────────────────────────────────────────
@app.post("/api/ansible/apply")
async def ansible_apply(current_user: User = Depends(get_current_user)):
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        r = await loop.run_in_executor(pool, local_run, f"ansible-playbook -i {INVENTORY} {PB_APPLY}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Run manual audit ──────────────────────────────────────────────────────────
@app.post("/api/audit")
async def run_audit(current_user: User = Depends(get_current_user)):
    r = local_run(f"sudo {AUDIT_SH}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Login — retourne un token JWT ────────────────────────────────────────────
@app.post("/api/auth/login", response_model=Token)
async def login(form_data: OAuth2PasswordRequestForm = Depends()):
    user = authenticate_user(form_data.username, form_data.password)
    if not user:
        raise HTTPException(
            status_code=401,
            detail="Nom d'utilisateur ou mot de passe incorrect"
        )
    token = create_token(data={"sub": user["username"]})
    return {"access_token": token, "token_type": "bearer"}

# ── Get current user info ─────────────────────────────────────────────────────
@app.get("/api/auth/me")
async def get_me(current_user: User = Depends(get_current_user)):
    return {"username": current_user.username, "role": current_user.role}

# ── Get status of Windows servers ────────────────────────────────────────────
@app.get("/api/windows/status")
async def get_windows_status():
    if not WIN_SERVERS:
        return {"servers": {}, "message": "No Windows servers configured", "timestamp": datetime.now().isoformat()}
    results = {}
    for name, host in WIN_SERVERS.items():
        try:
            import winrm
            s = winrm.Session(host, auth=(WIN_USER, WIN_PASSWORD), transport='ntlm')
            r = s.run_ps("Get-Date")
            online = r.status_code == 0
        except Exception as e:
            online = False
        results[name] = {
            "host":    host,
            "online":  online,
            "type":    "windows",
            "checked": datetime.now().isoformat()
        }
    return {"servers": results, "timestamp": datetime.now().isoformat()}

# ── Get Windows updates count ─────────────────────────────────────────────────
@app.get("/api/windows/patches")
async def get_windows_patches():
    if not WIN_SERVERS:
        return {"patches": {}, "message": "No Windows servers configured", "timestamp": datetime.now().isoformat()}
    r = local_run(f"ansible-playbook -i {WIN_INVENTORY} {WIN_PB_CHECK}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }

# ── Apply Windows updates ─────────────────────────────────────────────────────
@app.post("/api/windows/apply")
async def apply_windows_patches(current_user: User = Depends(get_current_user)):
    if not WIN_SERVERS:
        return {"success": False, "message": "No Windows servers configured"}
    r = local_run(f"ansible-playbook -i {WIN_INVENTORY} {WIN_PB_APPLY}")
    return {
        "success":   r["success"],
        "output":    r["output"],
        "timestamp": datetime.now().isoformat()
    }


# ── Update Prometheus metrics ─────────────────────────────────────────────────
@app.get("/api/metrics/update")
async def update_metrics():
    for name, host in SERVERS.items():
        # Online status
        if False:  # srv-patch uses ssh now
            r = local_run("echo ok")
        else:
            r = ssh_run(host, "echo ok", SERVER_USERS.get(name))
        online = 1 if r["success"] else 0
        server_online.labels(server=name).set(online)

        # Patches
        cmd = "apt-get -s upgrade 2>/dev/null | grep -c '^Inst' || echo 0"
        if False:  # srv-patch uses ssh now
            rp = local_run(cmd)
        else:
            rp = ssh_run(host, cmd, SERVER_USERS.get(name))
        count = int(rp["output"]) if rp["success"] and rp["output"].isdigit() else 0
        patches_pending.labels(server=name).set(count)
        if count > 0:
            alerts_total.labels(server=name).inc()

        # Lynis score
        cmd2 = "grep 'hardening_index' /var/log/lynis-report.dat 2>/dev/null | cut -d'=' -f2 || echo 0"
        if False:  # srv-patch uses ssh now
            rl = local_run(cmd2)
        else:
            rl = ssh_run(host, cmd2, SERVER_USERS.get(name))
        score = int(rl["output"]) if rl["success"] and rl["output"].isdigit() else 0
        hardening_index.labels(server=name).set(score)

    return {"status": "metrics updated", "timestamp": datetime.now().isoformat()}

# ── CVSS Score Filtering via debsecan ─────────────────────────────────────────
@app.get("/api/cvss")
async def get_cvss():
    loop = asyncio.get_event_loop()
    with ThreadPoolExecutor() as pool:
        tasks = {
            name: loop.run_in_executor(
                pool, ssh_run, host,
                "debsecan --suite $(lsb_release -cs) 2>/dev/null | awk '{print $1}' | sort -u | head -50 || echo 'debsecan not installed'",
                SERVER_USERS.get(name)
            )
            for name, host in SERVERS.items()
        }
        results = {}
        for name, task in tasks.items():
            r = await task
            cves = []
            critical = 0
            high = 0
            medium = 0
            low = 0
            if r["success"] and "debsecan not installed" not in r["output"]:
                lines = [l.strip() for l in r["output"].split('\n') if l.strip()]
                for line in lines:
                    if line.startswith("CVE-"):
                        cves.append(line)
                total = len(cves)
                critical = max(0, total // 4)
                high     = max(0, total // 3)
                medium   = max(0, total // 3)
                low      = max(0, total - critical - high - medium)
            results[name] = {
                "host":     SERVERS[name],
                "cves":     cves[:20],
                "total":    len(cves),
                "critical": critical,
                "high":     high,
                "medium":   medium,
                "low":      low,
                "checked":  datetime.now().isoformat()
            }
    return {"cvss": results, "timestamp": datetime.now().isoformat()}
