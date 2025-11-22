# App-GTWay-Apps Isolation - Quick Reference

## What Changed?

`app-gtway-apps` is now **self-contained** with all helpers and configs locally available.

### New Structure

```
app-gtway-apps/
├── helpers/              ← Local Azure/Logging helpers (NEW)
├── config/               ← Local config & parameters (ENHANCED)
├── creds/                ← Credentials directory (NEW)
├── logs/                 ← Local execution logs (NEW)
├── docs/                 ← Isolation documentation (NEW)
└── scripts/              ← Updated to use local paths
```

### Key Files Added/Updated

| What | Where | Purpose |
|------|-------|---------|
| azure-login.sh | helpers/ | Authenticate to Azure |
| logging.sh | helpers/ | Centralized logging |
| parameters-dev.json | config/ | Environment config |
| ISOLATION_GUIDE.md | docs/ | Full isolation guide |
| ISOLATION_SUMMARY.md | root | This implementation |
| .gitignore | root | Security (no creds in git) |

## Two Deployment Modes

### Mode 1: Isolated (No IaC-CLI Needed)

```bash
cd app-gtway-apps

# Setup credentials (one-time)
cp ../../iac-cli/creds/azure-credentials-dev.cred creds/

# Setup infrastructure state (one-time)
mkdir -p config/.generated
cp ../../iac-cli/config/.generated/generated-infra-dev.json config/.generated/

# Deploy
./scripts/build-push-nbrly.sh dev latest
./scripts/deploy-apps-nbrly.sh dev latest
./scripts/configure-routing-nbrly.sh
```

### Mode 2: Integrated (With IaC-CLI)

```bash
# Deploy infrastructure
cd iac-cli/scripts && ./00-deploy-all.sh

# Deploy applications (auto-finds IaC configs)
cd ../../app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
./scripts/deploy-apps-nbrly.sh dev latest
```

**Both modes work the same - scripts auto-detect config location!**

## Smart Configuration Resolution

```
Scripts check:
1️⃣ Local config: app-gtway-apps/config/.generated/ ✓
   ↓ (if not found)
2️⃣ IaC config: ../../iac-cli/config/.generated/ ✓
   ↓ (if not found)
3️⃣ Exit with error ✗
```

## Setup Instructions

### Isolated Setup

```bash
# 1. Get infrastructure details from team
scp team@server:generated-infra-dev.json app-gtway-apps/config/.generated/

# 2. Get credentials
cp ~/azure-credentials-dev.cred app-gtway-apps/creds/

# 3. Deploy apps
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
```

### From IaC Deployment

```bash
# Infrastructure deployed? Apps auto-discover config
cd app-gtway-apps
./scripts/build-push-nbrly.sh dev latest
```

## Security

✅ **Credentials** (`.cred` files) - Not committed to git  
✅ **State files** (`generated-infra-dev.json`) - Not committed to git  
✅ **Logs** (`.log` files) - Not committed to git  
✅ **`.gitignore`** - Automatically excludes sensitive files  

## Documentation

| Document | Content |
|----------|---------|
| `ISOLATION_GUIDE.md` | Complete isolation guide |
| `config/README.md` | Configuration setup |
| `creds/README.md` | Credentials setup |
| `logs/README.md` | Log management |

## Commands

### Build & Push Images

```bash
./scripts/build-push-nbrly.sh dev latest
./scripts/build-push-bloom.sh dev latest
```

### Deploy Applications

```bash
./scripts/deploy-apps-nbrly.sh dev latest
./scripts/deploy-apps-bloom.sh dev latest
```

### Configure Routing

```bash
./scripts/configure-routing-nbrly.sh
./scripts/configure-routing-bloom.sh
```

### View Logs

```bash
tail -f logs/build-push-nbrly-dev-*.log
```

## Verification

✅ Helper scripts exist and are executable:
```bash
ls -la helpers/*.sh
# Should show: azure-login.sh, logging.sh
```

✅ All scripts use local paths:
```bash
grep SCRIPT_DIR scripts/build-push-nbrly.sh
# Should show: SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

✅ Configuration directories exist:
```bash
ls -ld config creds logs docs
# Should show all 4 directories
```

## Troubleshooting

**"Configuration file not found"**
→ Copy infrastructure state: `cp ../../iac-cli/config/.generated/generated-infra-dev.json config/.generated/`

**"Credentials not found"**
→ Copy credentials: `cp ../../iac-cli/creds/azure-credentials-dev.cred creds/`

**"azure-login.sh not found"**
→ Helpers are local now: `helpers/azure-login.sh` (not `iac-cli/scripts/helpers/`)

## Benefits

🎯 **Portable** - Move `app-gtway-apps/` anywhere  
🎯 **Independent** - No `iac-cli` required  
🎯 **Shareable** - Distribute to other teams  
🎯 **Backward Compatible** - Still works with `iac-cli`  
🎯 **Secure** - Credentials never in git  
🎯 **Flexible** - Multiple deployment modes  

## Important Notes

- ✅ Fully backward compatible - existing workflows unchanged
- ✅ No breaking changes - all scripts work as before
- ✅ Auto-fallback - intelligently discovers config location
- ✅ Self-contained - can operate without `iac-cli`

---

**For complete details, see**: `ISOLATION_GUIDE.md`  
**Implementation date**: November 18, 2025
