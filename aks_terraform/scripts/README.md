# Create terraform state storage



The script will create an AZ Storage account and an AZ blob storage to store the terraform remote state and its lock. Storing the state remotely enables team work and CI/CD for your Infrastrucure as Code (IaC)

Variables:

```
STATE_RG="aks-tf-state-rg"
STATE_LOCATION="eastus"
CONTAINER_NAME="tfstate"
STORAGE_ACCOUNT_NAME= < randomly build > # less than 3-24 characters, must be unique
```



Creating storage account: akstfstate37ec108a

```
az storage account create --name akstfstate37ec108a \
  --resource-group aks-tf-state-rg \
  --location eastus \
  --sku Standard_ZRS --kind StorageV2 \
  --https-only true --min-tls-version TLS1_2 \
  --allow-blob-public-access false \
  --tags managed-by=terraform purpose=tf-state \
  --output none
```

Enabling blob versioning is mandatory for IaC history:

```
az storage account blob-service-properties update \
  --account-name akstfstate37ec108a \
  --resource-group aks-tf-state-rg \
  --enable-versioning true \
  --output none
```

Creating blob container: tfstate

```
az storage container create --name tfstate \
 --account-name akstfstate37ec108a \
 --auth-mode login \
 --output none
```

Granting Storage Blob Data Contributor to current user...

```
az role assignment create --role 'Storage Blob Data Contributor' \
  --assignee <userID> \
  --scope /subscriptions/<suscriptionID>/resourceGroups/aks-tf-state-rg/providers/Microsoft.Storage/storageAccounts/akstfstate37ec108a \
  --output none
```

