# Manifest Backup - Quick Reference

## 📦 What Gets Backed Up

All Container App YAML manifests before regeneration:
- `manifests/.generated/nbrly-nbapp1.yaml`
- `manifests/.generated/nbrly-nbapp2.yaml`
- `manifests/.generated/bloom-bmapp1.yaml`
- `manifests/.generated/bloom-bmapp2.yaml`

## 🕐 When Backups Happen

**Automatically** before manifest generation:
```bash
./scripts/helpers/generate-manifests.sh    # ← Triggers backup
./scripts/07-deploy-yaml.sh               # ← Triggers backup
```

## 📁 Where Backups Are Stored

```
manifests/.bak/<YYYYMMDD_HHMMSS>/
├── nbrly/
│   ├── nbapp1-containerapp.yaml
│   └── nbapp2-containerapp.yaml
└── bloom/
    ├── bmapp1-containerapp.yaml
    └── bmapp2-containerapp.yaml
```

**Example**: `manifests/.bak/20251122_211122/`

## 🔄 Restore from Backup

```bash
cd manifests

# 1. List backups
ls -lt .bak/

# 2. Restore
cp -r .bak/20251122_211122/nbrly/* nbrly/
cp -r .bak/20251122_211122/bloom/* bloom/
```

## 🧹 Cleanup Old Backups

```bash
cd manifests

# All backups
rm -rf .bak/*

# Older than 7 days
find .bak -type d -mindepth 1 -maxdepth 1 -mtime +7 -exec rm -rf {} +

# Specific backup
rm -rf .bak/20251122_211122
```

## ℹ️ Important Notes

- ✅ Automatic - no action needed
- ✅ Git-ignored - not committed
- ✅ Safe - only backs up if manifests exist
- ⚠️ Local only - manual cleanup recommended
- 📚 Full docs: `manifests/.bak/README.md`

## 🎯 Quick Commands

| Action | Command |
|--------|---------|
| List backups | `ls -lt manifests/.bak/` |
| Count backups | `ls manifests/.bak/ \| wc -l` |
| Latest backup | `ls -t manifests/.bak/ \| head -1` |
| Backup size | `du -sh manifests/.bak/` |
| Remove all | `rm -rf manifests/.bak/*` |

---

**Status**: ✅ Active  
**Location**: `manifests/.bak/`  
**Documentation**: `manifests/.bak/README.md`
