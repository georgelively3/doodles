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
./create-multiple-workloads.sh <branch> <product> <bomName> <orgPrefix> <database> <s3> <git-url1> [git-url2] [git-url3] ...
```

### Parameters

1. **`<branch>`** (required)
   - Git branch name to use for all repositories
   - Example: `develop`, `main`, `feature/my-feature`

2. **`<product>`** (required)
   - Product name (used as root folder name)
   - Example: `myproduct`, `webapp`, `backend`
   - Previously called "organization" - this is what you communicate to users about their product

3. **`<bomName>`** (required)
   - Custom name for the BOM folder (1-6 alphanumeric characters)
   - Used as the directory name under the product folder
   - Example: `pdmexp`, `test01`, `app123`

4. **`<orgPrefix>`** (required)
   - Organization prefix, typically a 2-character string
   - Used in values files and other configurations
   - Example: `fm`, `ab`, `xy`

5. **`<database>`** (required)
   - Database configuration flag: `y` or `n`
   - `y` - Creates Aurora RDS configuration in BOM and adds database ConfigMap
   - `n` - No database resources

6. **`<s3>`** (required)
   - S3 bucket configuration flag: `y` or `n`
   - `y` - Creates S3 bucket configuration in BOM and adds S3 ConfigMap
   - `n` - No S3 resources

7. **`<git-url1>` `<git-url2>` ...** (at least one required)
   - Bitbucket repository URLs in the format: `https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/<org>/<repo>.git`
   - All repositories must have the same parent asset ID
   - Repository name format: `<parentAssetId>_<assetId>`

### Repository Naming Convention

Repository names must follow this pattern:
```
<parentAssetId>_<assetId>
```

Examples:
- `ab1234_cd5678` → parentAssetId: `ab1234`, assetId: `cd5678`
- `ab1234_ef9012` → parentAssetId: `ab1234`, assetId: `ef9012`
- `xy9999_mn3456` → parentAssetId: `xy9999`, assetId: `mn3456`

**Important:** All repositories in a single execution must:
- Have the same parentAssetId
- Have unique assetIds

## Example Usage

### Single Workload with Database Only

```bash
./create-multiple-workloads.sh develop myproduct pdmexp fm y n \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/ab1234_cd5678.git
```

### Multiple Workloads with Database and S3

```bash
./create-multiple-workloads.sh develop myproduct pdmexp fm y y \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/ab1234_cd5678.git \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/ab1234_ef9012.git \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/ab1234_gh3456.git
```

### No External Resources

```bash
./create-multiple-workloads.sh develop myproduct pdmexp fm n n \
  https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/ab1234_cd5678.git
```

## Generated Structure

The script creates the following directory structure:

```
<product>/
  <bomName>/
    mag.yaml                          # MicroAG configuration (from template)
    bom/
      bom.yaml                        # Bill of Materials (from template)
    common/
      templates/
        certificate.yaml
        db-configmap.yaml             # If database=y
        s3-configmap.yaml             # If s3=y
    helm/                             # Base helm chart
      Chart.yaml
      templates/
        ...
    helm-<assetId1>/                  # Workload-specific helm chart
      Chart.yaml
      templates/
        deployment.yaml               # With <assetId>Svc references and envFrom if db/s3
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
| `<organization>` | product parameter | All files |
| `<orgPrefix>` | orgPrefix parameter | All files |
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
- **mag**: MicroAG reference in format `<product>~<bomName>`

These PDM folders are then:
1. Zipped into `<repository>-pdm.zip`
2. Moved to `/home/pdm/pdm-folder-zips/`
3. Original `pdm/` directory cleaned up

### create-pdm-folder.sh Arguments

The script is called with 6 arguments:
```bash
create-pdm-folder.sh <productName> <imageName> <testEngine> <repository> <bomName> <orgPrefix>
```

Example:
```bash
create-pdm-folder.sh myproduct test_ab1234_cd5678 cucumber test_ab1234_cd5678 pdmexp george
```

## Interactive Prompts

### Overwrite Confirmation
The script handles directory creation intelligently:
- **Product folder**: Created automatically if it doesn't exist, or reused if it does (no prompt)
- **BOM folder**: If it already exists, you'll be prompted:

```
Using existing product directory: /path/to/product
Warning: BOM directory already exists: /path/to/product/bomName
Do you want to overwrite it? (y/N):
```

Type `y` and press Enter to overwrite the BOM folder, or `N` to abort. This allows teams to add multiple MicroAGs (different bomNames) under their existing product without risk of overwriting other MicroAGs.

## Validation and Error Handling

The script validates:
- ✅ Correct number of arguments (7)
- ✅ bomName is 1-6 alphanumeric characters
- ✅ orgPrefix is not empty
- ✅ database flag is 'y' or 'n'
- ✅ s3 flag is 'y' or 'n'
- ✅ Repository URLs match Bitbucket format
- ✅ Repository names contain parentAssetId and assetId
- ✅ All repositories have the same parentAssetId
- ✅ Required template directories exist

## Troubleshooting

### Common Issues

1. **"Usage: ./create-multiple-workloads.sh <branch> <product> <bomName> <orgPrefix> <database> <s3> <git-urls...>"**
   - Ensure you provide exactly 7 or more arguments
   - Arguments: branch, product, bomName, orgPrefix, database (y/n), s3 (y/n), followed by git URLs

2. **"bomName must be 1-6 alphanumeric characters"**
   - Ensure bomName only contains letters and numbers
   - Keep it 6 characters or less

3. **"orgPrefix cannot be empty"**
   - The 4th argument (orgPrefix) must be provided
   - Used to replace `<orgPrefix>` placeholder in templates

4. **"database must be 'y' or 'n'"** or **"s3 must be 'y' or 'n'"**
   - The 5th argument (database) must be either 'y' or 'n'
   - The 6th argument (s3) must be either 'y' or 'n'

5. **"Invalid Bitbucket URL format"**
   - Check URL follows: `https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/<org>/<repo>.git`
   - Ensure `.git` extension is present

6. **"Repository name does not contain at least two underscore-separated parts"**
   - Repository name must follow: `<parentAssetId>_<assetId>`
   - Must have at least 2 underscore-separated segments

7. **"Mismatched parent asset ID"**
   - All repositories must have the same parentAssetId

8. **"Sample directory not found"**
   - Ensure the `pdmex/pdm_pdmex_poc048_baseline_nodb/` directory exists in the same location as the script
   - Required subdirectories: `bom/`, `common/`, `helm/`, `helm-assetId/`, `values/`, `target/`, `spam/`, `mag.yaml`

### Database and S3 ConfigMap Integration

When `database=y`:
- `db-configmap.yaml` is created in `common/templates/`
- Each workload's `deployment.yaml` gets an `envFrom` section with database ConfigMap reference
- The `name:` field is indented 6 spaces under `configMapRef`

When `s3=y`:
- `s3-configmap.yaml` is created in `common/templates/`
- Each workload's `deployment.yaml` gets an `envFrom` section with S3 ConfigMap reference
- The `name:` field is indented 6 spaces under `configMapRef`

Both can be enabled simultaneously, resulting in two `envFrom` entries in each deployment.

## Sample Templates

The script uses templates from the `pdmex/pdm_pdmex_poc048_baseline_nodb/` directory. To customize:

1. Edit files in `pdmex/pdm_pdmex_poc048_baseline_nodb/` to match your needs
2. Use placeholders (e.g., `<bomName>`, `<assetId>`, `<organization>`, `<orgPrefix>`) where substitution is needed
3. The script processes templates intelligently:
   - **mag.yaml**: Copied from template with full placeholder substitution
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
