# AKS Bicep — Export & Decompile from Azure

Convert an existing AKS deployment to Bicep by exporting an ARM template and decompiling it.

---

## Step 1 — Export the ARM Template

### Option A: Azure Portal
1. Navigate to your AKS cluster in the portal
2. **Automation** → **Export template**
3. Click **Download** and unzip — use `template.json`

### Option B: Azure CLI
```bash
# Export the full resource group as an ARM template
az group export \
  --name <your-resource-group> \
  --resource-ids $(az aks show --name <aks-name> \
                               --resource-group <rg-name> \
                               --query id -o tsv) \
  > aks-export.json
```

---

## Step 2 — Decompile to Bicep

```bash
az bicep decompile -f ./exports/aks-export.json
```

This produces `aks-export.bicep` alongside the JSON file.

> **Note:** Decompilation is best-effort. The generated file will likely need
> manual fixes — especially around `$schema`, resource scopes, and
> runtime-only resources such as `/machines` entries, which should be removed.

---

## Common Error

```
Unable to find a template property named $schema
```
The exported file is a raw API resource object, not an ARM template.
Re-export using **Option A or B** above to get a properly structured template.
