# Multi-Workload and PDM Folder Creation Guide

This guide explains how to use the shell scripts to create MicroAG structures with multiple workloads and their corresponding PDM folders.

## Overview

The `create-multiple-workloads.sh` script automates the creation of:
- MicroAG directory structure with multiple workloads
- Helm charts for each workload
- Values files with workload-specific configurations
- BOM (Bill of Materials) and MAG files
- PDM folders for each workload repository

**Script Location:** [create-multiple-workloads.sh](https://bitbkt.mdtc.itp01.p.org.com/projects/PDM/repos/pdm_ba0270_ops/browse/create-multiple-workloads.sh)

## Prerequisites

- Bash shell environment (WSL, Git Bash, or Linux/Mac terminal)
- Access to Bitbucket repositories
- Proper file permissions for script execution

## Script Usage

### Syntax

```bash
./create-multiple-workloads.sh <branch> <bomName> <git-url1> [git-url2] [git-url3] ...
```

### Parameters

1. **`<branch>`** (required)
   - Git branch name to use for all repositories
   - Example: `develop`, `main`, `feature/my-feature`

2. **`<bomName>`** (required)
   - Custom name for the BOM folder (1-6 alphanumeric characters)
   - Used as the directory name under the organization folder
   - Example: `pdmexp`, `test01`, `app123`

3. **`<git-url1>` `<git-url2>` ...** (at least one required)
   - Bitbucket repository URLs in the format: `https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/<org>/<repo>.git`
   - All repositories must belong to the same organization and parent asset ID
   - Repository name format: `[product_]<parentAssetId>_<assetId>`

### Repository Naming Convention

Repository names must follow this pattern:
```
[product_]<parentAssetId>_<assetId>
```

Examples:
- `test_ab1234_cd5678` → product: `test`, parentAssetId: `ab1234`, assetId: `cd5678`
- `myapp_ab1234_ef9012` → product: `myapp`, parentAssetId: `ab1234`, assetId: `ef9012`
- `ab1234_xy3456` → product: (empty), parentAssetId: `ab1234`, assetId: `xy3456`

**Important:** All repositories in a single execution must:
- Have the same organization
- Have the same parentAssetId
- Have unique assetIds

## Example Usage

### Single Workload

```bash
./create-multiple-workloads.sh develop pdmexp \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/test_ab1234_cd5678.git
```

### Multiple Workloads

```bash
./create-multiple-workloads.sh develop pdmexp \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/test_ab1234_cd5678.git \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/test_ab1234_ef9012.git \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/test_ab1234_gh3456.git
```

## Generated Structure

The script creates the following directory structure:

```
<organization>/
  <bomName>/
    mag.yaml                          # MicroAG configuration
    bom/
      bom.yaml                        # Bill of Materials
    common/
      templates/
        certificate.yaml
    helm/                             # Base helm chart
      Chart.yaml
      templates/
        ...
    helm-<assetId1>/                  # Workload-specific helm chart
      Chart.yaml
      templates/
        deployment.yaml               # With <assetId>Svc references
        service.yaml
        configmap.yaml
        ...
    helm-<assetId2>/                  # Additional workload helm charts
      ...
    values/
      values-dev.yaml                 # With all workload service blocks
      values-preprod.yaml
      values-prod.yaml
    target/
      microAGTarget.json
```

### Generated Files Content

#### Values Files
Each values file (dev, preprod, prod) will contain service blocks for all workloads:

```yaml
#####################################################################
# cd5678 Service
#####################################################################
cd5678Svc:
  Id: cd5678
  TargetPort: 8081
  Image: test_ab1234_cd5678
  ImageTag: "latest"

#####################################################################
# ef9012 Service
#####################################################################
ef9012Svc:
  Id: ef9012
  TargetPort: 8082
  Image: test_ab1234_ef9012
  ImageTag: "latest"
```

**Note:** Target ports auto-increment starting at 8081 for each workload.

#### Helm Templates
Each workload's helm templates reference their specific service configuration:

```yaml
# In helm-cd5678/templates/deployment.yaml
name: {{ .Values.cd5678Svc.Id }}-{{ Values.AbbreviatedEnv }}
image: "{{ .Values.cd5678Svc.Image }}:{{ .Values.cd5678Svc.ImageTag }}"
containerPort: {{ .Values.cd5678Svc.TargetPort }}
```

#### MAG File
```yaml
mag:
  - name: "george~ab1234"
    type: "owned"
    description: "george ab1234"
    bomPath: "bom/bom.yaml"
    spamFolder: "spam"
    workloads:
      - name: "common"
      - name: "helm-cd5678"
        images:
          - "test_ab1234_cd5678"
      - name: "helm-ef9012"
        images:
          - "test_ab1234_ef9012"
```

## Placeholder Substitutions

The script replaces the following placeholders in template files:

| Placeholder | Replaced With | Scope |
|------------|---------------|-------|
| `<bomName>` | bomName parameter | All files |
| `<organization>` | Extracted from git URL | All files |
| `<parentAssetId>` | Extracted from repo name | All files |
| `<branch>` | branch parameter | All files |
| `<assetId>` | Extracted from repo name | Workload-specific files |
| `<repository>` | Full repository name | Workload-specific files |
| `<imageName>` | Same as repository | Workload-specific files |
| `<targetPort>` | Auto-incremented (8081, 8082, ...) | Values files |

## PDM Folder Creation

After creating the MicroAG structure, the script automatically executes `create-pdm-folder.sh` for each workload to generate PDM folders.

### What Gets Created

For each workload, a `pdm/` folder is created in the `helm-<assetId>/` directory containing:

- **images**: List of container images
- **containers**: Container names
- **test_engine**: Test framework identifier (e.g., cucumber)
- **run_<imageName>**: Docker run configuration with port mappings
- **mag**: MicroAG reference in format `<organization>~<bomName>`

These PDM folders are then:
1. Zipped into `<repository>-pdm.zip`
2. Moved to `/home/pdm/pdm-folder-zips/`
3. Original `pdm/` directory cleaned up

### create-pdm-folder.sh Arguments

The script is called with 6 arguments:
```bash
create-pdm-folder.sh <productName> <imageName> <testEngine> <repository> <bomName> <organization>
```

Example:
```bash
create-pdm-folder.sh product test_ab1234_cd5678 cucumber test_ab1234_cd5678 pdmexp george
```

## Interactive Prompts

### Overwrite Confirmation
The script handles directory creation intelligently:
- **Organization folder**: Created automatically if it doesn't exist, or reused if it does (no prompt)
- **BOM folder**: If it already exists, you'll be prompted:

```
Using existing organization directory: /path/to/organization
Warning: BOM directory already exists: /path/to/organization/bomName
Do you want to overwrite it? (y/N):
```

Type `y` and press Enter to overwrite the BOM folder, or `N` to abort. This allows teams to add multiple MicroAGs (different bomNames) under their existing organization without risk of overwriting other MicroAGs.

## Validation and Error Handling

The script validates:
- ✅ Correct number of arguments
- ✅ bomName is 1-6 alphanumeric characters
- ✅ Repository URLs match Bitbucket format
- ✅ Repository names contain parentAssetId and assetId
- ✅ All repositories have the same organization
- ✅ All repositories have the same parentAssetId
- ✅ Required template directories exist

## Troubleshooting

### Common Issues

1. **"bomName must be 1-6 alphanumeric characters"**
   - Ensure bomName only contains letters and numbers
   - Keep it 6 characters or less

2. **"Invalid Bitbucket URL format"**
   - Check URL follows: `https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/<org>/<repo>.git`
   - Ensure `.git` extension is present

3. **"Repository name does not contain at least two underscore-separated parts"**
   - Repository name must follow: `[product_]<parentAssetId>_<assetId>`
   - Must have at least 2 underscore-separated segments at the end

4. **"Mismatched organization" or "Mismatched parent asset ID"**
   - All repositories must belong to the same organization
   - All repositories must have the same parentAssetId

5. **"Sample directory not found"**
   - Ensure the `pdmex/pdm_pdmex_poc048_baseline_nodb/` directory exists in the same location as the script
   - Required subdirectories: `bom/`, `common/`, `helm/`, `helm-assetId/`, `values/`, `target/`, `spam/`

## Sample Templates

The script uses templates from the `pdmex/pdm_pdmex_poc048_baseline_nodb/` directory. To customize:

1. Edit files in `pdmex/pdm_pdmex_poc048_baseline_nodb/` to match your needs
2. Use placeholders (e.g., `<bomName>`, `<assetId>`) where substitution is needed
3. The script processes templates intelligently:
   - **bom.yaml**: Finds workload template marker (`helm-<assetId>`) and expands for each workload
   - **values files**: Finds template block between comment markers and expands with auto-incrementing ports
   - **Other files**: Global placeholders replaced consistently
4. The template approach preserves your custom structure - the script only does substitution, not restructuring

## Tips and Best Practices

1. **Test with one workload first** before creating multiple workloads
2. **Use descriptive bomNames** that identify the project (e.g., `pdmexp`, `webapp`)
3. **Keep assetIds unique** across all workloads in the same MicroAG
4. **Review generated files** before committing to git
5. **Backup existing directories** before overwriting
6. **Use consistent branch names** across environments (develop, staging, main)

## Support

For issues or questions:
1. Check the validation messages for specific error details
2. Review the generated output for warnings
3. Verify repository names and URLs match the expected format
4. Ensure all prerequisites are met
