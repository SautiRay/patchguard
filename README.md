# 🛡️ PatchGuard

> **Automated Linux Security Patch Management System**

[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Python](https://img.shields.io/badge/Python-3.10+-blue.svg)](https://python.org)
[![Ansible](https://img.shields.io/badge/Ansible-2.14+-red.svg)](https://ansible.com)
[![Ubuntu](https://img.shields.io/badge/Ubuntu-22.04_LTS-orange.svg)](https://ubuntu.com)
[![Status](https://img.shields.io/badge/Status-Active-brightgreen.svg)]()

PatchGuard is an open source system that **automatically detects, applies and reports security patches** on Linux servers — with zero manual intervention and zero license cost.

Originally developed as a final-year project (TFE) at EICP Namur (2025–2026) based on issues observed during the internship chez ATD Quart Monde (Brussels).

---

## 📋 Table of Contents

- [The Problem](#-the-problem)
- [The Solution](#-the-solution)
- [Architecture](#-architecture)
- [Tech Stack](#-tech-stack)
- [Features](#-features)
- [Quick Start](#-quick-start)
- [Project Structure](#-project-structure)
- [Test Results](#-test-results)
- [Roadmap](#-roadmap)
- [Author](#-author)
- [License](#-license)

---

## ❌ The Problem

At **ATD Quart Monde** (Brussels), a non-profit working with people in poverty:

- Security updates were done **manually** by a single volunteer
- **No automatic alerts** when vulnerabilities were detected
- **No traceability** of actions performed
- **Bus factor = 1** — everything depended on one person
- Risk of **GDPR non-compliance** (Art. 32)

---

## ✅ The Solution

PatchGuard automates the entire security patch lifecycle:

```
06:00  →  Lynis audit on all servers
07:00  →  Automatic e-mail notification (alerts or OK report)
03:00  →  Ansible applies patches (Sunday only)
01:00  →  Log cleanup (monthly)
```

**No human intervention required.**

---

## 🏗️ Architecture


![PatchGuard Architecture](https://raw.githubusercontent.com/SautiRay/patchguard/main/docs/architecture.png) 


- **Topology** : Star — centralized management from srv-patch
- **Network** : VirtualBox Host-Only (192.168.56.x)
- **Authentication** : SSH ed25519 keys (passwordless)
- **Compliance** : ISO 27001 · NIST CSF · CIS Controls v8 · GDPR Art.32

---

## 🧰 Tech Stack

| Component | Technology | Version |
|-----------|-----------|---------|
| OS | Ubuntu LTS | 22.04 |
| Virtualization | VirtualBox + WSL2 | 7.x |
| Security audit | Lynis | 3.x |
| Patch deployment | Ansible | 2.14+ |
| Notifications | Postfix + Gmail SMTP | 3.6+ |
| Scheduling | Cron | native |
| Scripting | Bash | 5.x |
| Network config | Netplan | native |

**License cost : 0 €** — 100% open source

---

## ✨ Features

- 🔍 **Automated daily security audit** via Lynis on all target servers
- 🔧 **Automatic patch deployment** via Ansible playbooks (idempotent)
- 📧 **E-mail notifications** — alert or OK report via Postfix/Gmail
- 📊 **Real-time dashboard** — server status in terminal
- 📝 **Full logging** — timestamped journal of all actions
- 🔄 **Cron scheduling** — fully automated, no human intervention
- 🔒 **Least privilege** — sudo limited to specific commands only
- 📋 **Compliance** — ISO 27001, NIST CSF, CIS Controls v8, GDPR

---

## 🚀 Quick Start

### Prerequisites

```bash
# On srv-patch (Ubuntu 22.04 LTS)
sudo apt update
sudo apt install -y lynis ansible postfix git python3 python3-pip
```

### Installation

```bash
# Clone the repository
git clone https://github.com/SautiRay/patchguard.git
cd patchguard

# Create project structure
sudo mkdir -p /opt/patch-manager/{scripts,ansible,rapports}

# Copy scripts
sudo cp src/scripts/*.sh /opt/patch-manager/scripts/
sudo cp src/ansible/* /opt/patch-manager/ansible/

# Make scripts executable
sudo chmod +x /opt/patch-manager/scripts/*.sh
```

### Configuration

```bash
# 1. Edit inventory with your server IPs
nano src/ansible/inventaire.ini

# 2. Copy SSH key to each target server
ssh-copy-id -i ~/.ssh/patch_key.pub raylab@192.168.56.101
ssh-copy-id -i ~/.ssh/patch_key.pub raylab@192.168.56.102
ssh-copy-id -i ~/.ssh/patch_key.pub raylab@192.168.56.103

# 3. Test connectivity
ansible -i src/ansible/inventaire.ini serveurs_cibles -m ping
```

### Start

```bash
# Start cron service
sudo service cron start

# Launch dashboard
/opt/patch-manager/scripts/dashboard.sh

# Manual audit
sudo /opt/patch-manager/scripts/audit.sh

# Manual patch deployment
ansible-playbook -i src/ansible/inventaire.ini src/ansible/appliquer_correctifs.yml
```

---

## 📁 Project Structure

```
patchguard/
├── src/
│   ├── api/                    # FastAPI backend (v1.1 - coming soon)
│   │   ├── main.py
│   │   └── requirements.txt
│   ├── scripts/                # Bash automation scripts
│   │   ├── audit.sh            # Daily Lynis audit
│   │   ├── notification.sh     # Email notifications
│   │   └── dashboard.sh        # Real-time terminal dashboard
│   ├── ansible/                # Ansible playbooks
│   │   ├── inventaire.ini      # Server inventory
│   │   ├── verifier_correctifs.yml   # Read-only check
│   │   └── appliquer_correctifs.yml  # Apply patches
│   ├── templates/              # PWA HTML templates (v1.1)
│   └── static/                 # CSS, JS, manifest.json (v1.1)
├── grafana/                    # Grafana dashboards (v1.1)
├── prometheus/                 # Prometheus config (v1.1)
├── docs/                       # Documentation
├── docker-compose.yml          # One-command deployment (v1.1)
├── .env.example                # Environment variables template
├── LICENSE                     # MIT License
└── README.md
```

---

## 🧪 Test Results

All 11 unit tests + 1 integration test passed successfully.

| Test | Description | Result |
|------|-------------|--------|
| T01 | Network connectivity between VMs | ✅ Pass |
| T02-T03 | Lynis audit — before / after comparison | ✅ Pass |
| T04-T06 | Ansible playbooks (check + apply + reboot) | ✅ Pass |
| T07 | Real-time dashboard | ✅ Pass |
| T08-T09 | Postfix notifications (no alert / with alert) | ✅ Pass |
| T10 | Cron automatic scheduling | ✅ Pass |
| **T11** | **Full integration test — complete cycle** | ✅ **Pass** |

**T11 result** : 24 pending patches detected → applied automatically → 0 patches remaining · Lynis Hardening Index 62/100

---

## 💰 Financial Impact

| | PatchGuard | Commercial alternatives |
|--|--|--|
| Tenable Nessus Pro | — | 4 000–8 000 €/yr |
| Red Hat Ansible Automation | — | 15 000–20 000 €/yr |
| Splunk Enterprise | — | 5 000–15 000 €/yr |
| **Total** | **0 € license** | **29 500–52 000 €/yr** |

**Savings for ATD Quart Monde : up to 51 000 €/year**

---

## 🗺️ Roadmap

### Version 1.0 — Current ✅
- [x] Automated Lynis audit
- [x] Ansible patch deployment
- [x] Email notifications via Postfix
- [x] Real-time terminal dashboard
- [x] Full cron scheduling
- [x] 11 tests passed

### Version 1.1 — In Progress 🔄
- [x] REST API (Python FastAPI)
- [x] PWA web interface (HTML/CSS/JS)
- [ ] Grafana + Prometheus dashboards
- [ ] Docker Compose deployment
- [ ] JWT authentication

### Version 2.0 — Planned 📋
- [ ] Multi-tenant support
- [ ] Windows Server support (WinRM)
- [ ] Cloud deployment (AWS/OVH)
- [ ] AWX web interface
- [ ] CVSS score filtering (debsecan)

---

## 👤 Author

**Sauti RAYMOND**
- 📧 info.sautiray.it@gmail.com
- 🎓 Bachelier en Informatique et Systèmes — EICPN 2025–2026
- 💼 Open to opportunities in Linux / Windows Administration · DevOps · Cybersecurity,IT Support /HelpDesk 

---

## 📄 License

This project is licensed under the **MIT License** — see the [LICENSE](LICENSE) file for details.

---

*PatchGuard — Making Linux security patch management simple, automated and affordable.*
