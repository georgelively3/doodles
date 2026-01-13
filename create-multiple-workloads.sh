#!/bin/bash

# Check if at least 2 arguments are provided (branch + at least one git URL)
if [ $# -lt 2 ]; then
    echo "Usage: $0 <branch> <git-url1> [git-url2] [git-url3] ..."
    echo "Example: $0 develop https://bitbucket.com/scm/george/raj_ab1234_cd3456.git https://bitbucket.com/scm/george/raj_ab1234_ef7890.git"
    exit 1
fi

# Get the script directory (root of the project)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Assign branch from first argument
branch="$1"
shift  # Remove the first argument (branch) from the argument list

# Arrays to store parsed information from all git URLs
declare -a assetIds
declare -a repositories
declare -a products
organization=""
parentAssetId=""

echo "Parsing ${#@} git repositories..."
echo ""

# First pass: Parse all git URLs and validate consistency
counter=1
for gitUrl in "$@"; do
    echo "Parsing repository $counter: $gitUrl"
    
    # Extract organization and repository name from Bitbucket URL
    if [[ "$gitUrl" =~ https://bitbucket\.com/scm/([^/]+)/([^/]+)\.git$ ]]; then
        org="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        echo "Error: Invalid Bitbucket URL format: $gitUrl"
        echo "Expected format: https://bitbucket.com/scm/organization/repository.git"
        exit 1
    fi
    
    # Extract parentAssetId and assetId from repository name
    # Look for the last two underscore-separated parts (consistent with create-project-helms.sh)
    if [[ "$repo" =~ _([^_]+)_([^_]+)$ ]]; then
        parentId="${BASH_REMATCH[1]}"
        assetId="${BASH_REMATCH[2]}"
        # Extract product (everything before the last two underscore-separated parts)
        prod="${repo%_${parentId}_${assetId}}"
    else
        echo "Error: Repository name '$repo' does not contain at least two underscore-separated parts at the end"
        echo "Expected format: [product_]parentAssetId_assetId"
        exit 1
    fi
    
    # Validate that all repositories have the same organization and parentAssetId
    if [ $counter -eq 1 ]; then
        organization="$org"
        parentAssetId="$parentId"
        echo "  Organization: $organization"
        echo "  Parent Asset ID: $parentAssetId"
    else
        if [ "$org" != "$organization" ]; then
            echo "Error: Mismatched organization. Expected '$organization', got '$org'"
            exit 1
        fi
        if [ "$parentId" != "$parentAssetId" ]; then
            echo "Error: Mismatched parent asset ID. Expected '$parentAssetId', got '$parentId'"
            exit 1
        fi
    fi
    
    echo "  Product: $prod"
    echo "  Asset ID: $assetId"
    
    # Store information
    assetIds+=("$assetId")
    repositories+=("$repo")
    products+=("$prod")
    
    ((counter++))
done

echo ""
echo "=========================================="
echo "Creating MicroAG structure"
echo "=========================================="
echo "Organization: $organization"
echo "Parent Asset ID: $parentAssetId"
echo "Branch: $branch"
echo "Workloads: ${#assetIds[@]}"
for i in "${!assetIds[@]}"; do
    echo "  - ${assetIds[$i]} (${products[$i]})"
done
echo ""

# Create directory structure: organization/parentAssetId/
microAgPath="$SCRIPT_DIR/$organization/$parentAssetId"

if [ -d "$microAgPath" ]; then
    echo "Warning: MicroAG directory already exists: $microAgPath"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
    rm -rf "$microAgPath"
fi

mkdir -p "$microAgPath"
echo "Created MicroAG directory: $microAgPath"

# Copy entire sample directory structure as a base
echo ""
echo "Copying sample structure..."
samplePath="$SCRIPT_DIR/sample"
if [ ! -d "$samplePath" ]; then
    echo "Error: Sample directory not found at: $samplePath"
    exit 1
fi

# Copy all contents from sample (excluding helm-assetId template)
cp -r "$samplePath/bom" "$microAgPath/"
cp -r "$samplePath/common" "$microAgPath/"
cp -r "$samplePath/helm" "$microAgPath/"
cp -r "$samplePath/values" "$microAgPath/"
cp -r "$samplePath/target" "$microAgPath/"
echo "Copied base structure from sample (bom, common, helm, values, target)"

# Replace placeholders in base helm directory
find "$microAgPath/helm" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Replace placeholders in common directory
find "$microAgPath/common" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Create helm-<assetId> directory for each workload
echo ""
echo "Creating Helm chart directories for each workload..."
for i in "${!assetIds[@]}"; do
    assetId="${assetIds[$i]}"
    helmDir="$microAgPath/helm-$assetId"
    
    # Copy sample helm structure (use helm-assetId if it exists, otherwise helm)
    if [ -d "$samplePath/helm-assetId" ]; then
        sampleHelmPath="$samplePath/helm-assetId"
    else
        sampleHelmPath="$samplePath/helm"
    fi
    
    if [ ! -d "$sampleHelmPath" ]; then
        echo "Error: Sample helm directory not found at: $sampleHelmPath"
        exit 1
    fi
    
    cp -r "$sampleHelmPath" "$helmDir"
    echo "Created helm-$assetId directory"
    
    # Replace placeholders in helm files
    product="${products[$i]}"
    repo="${repositories[$i]}"
    imageName="$repo"
    
    find "$helmDir" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$assetId/g; s/<organization>/$organization/g; s/<repository>/$repo/g; s/<imageName>/$imageName/g; s/<branch>/$branch/g" {} \;
done

# Create mag.yaml file
echo ""
echo "Creating mag.yaml..."
magYamlPath="$microAgPath/mag.yaml"

cat > "$magYamlPath" << EOF
mag:
  - name: "$organization~$parentAssetId"
    type: "owned"
    description: "$organization $parentAssetId"
    bomPath: "bom/bom.yaml"
    spamFolder: "spam"
    workloads:
      - name: "common"
EOF

# Add each helm-<assetId> entry to mag.yaml
for i in "${!assetIds[@]}"; do
    assetId="${assetIds[$i]}"
    repo="${repositories[$i]}"
    imageName="$repo"
    
    cat >> "$magYamlPath" << EOF
      - name: "helm-$assetId"
        images:
          - "$imageName"
EOF
done

echo "Created mag.yaml with common + ${#assetIds[@]} workload entries"

# Create bom.yaml file
echo ""
echo "Creating bom.yaml..."
bomYamlPath="$microAgPath/bom/bom.yaml"

cat > "$bomYamlPath" << EOF
apiVersion: cyclonedx/v1.4
kind: BillOfMaterials
metadata:
  name: $parentAssetId
  version: "1.0.0"
  timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
spec:
  supportGroupId: $parentAssetId
  financeAppId: $parentAssetId
  bomFormat: CycloneDX
  specVersion: "1.4"
  serialNumber: "urn:uuid:$(uuidgen 2>/dev/null || echo "00000000-0000-0000-0000-000000000000")"
  version: 1
  metadata:
    timestamp: "$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    tools:
      - vendor: "Example Corp"
        name: "BOM Generator"
        version: "1.0.0"
    component:
      type: application
      name: $organization-$parentAssetId
      version: "1.0.0"
      description: "MicroAG application for $organization"
  components:
    - type: library
      name: spring-boot-starter-web
      version: "3.1.0"
      scope: required
      purl: "pkg:maven/org.springframework.boot/spring-boot-starter-web@3.1.0"
    - type: library
      name: spring-boot-starter-actuator
      version: "3.1.0"
      scope: required
      purl: "pkg:maven/org.springframework.boot/spring-boot-starter-actuator@3.1.0"
  workloadList:
  - name: common
    kind: helm
    workloadVersion: 'v1.0.1'
    deployFirst: true
    helm:
      chartRepoUrl: pdm-ba0270-ops
      chartPath: $organization/$parentAssetId/common
      chartVersion: "1.0.0"
      valuesPath: $organization/$parentAssetId/values/values-\$ENV.yaml
      revision: $branch
EOF

# Add each workload entry to bom.yaml (matching mag.yaml entries)
for i in "${!assetIds[@]}"; do
    assetId="${assetIds[$i]}"
    repo="${repositories[$i]}"
    
    cat >> "$bomYamlPath" << EOF
  - name: helm-$assetId
    kind: helm
    helm:
      chartName: $assetId-application
      chartPath: $organization/$repo/helm-$assetId
      chartVersion: "1.0.0"
      valuesPath: $organization/$repo/values/values-\$ENV.yaml
      revision: $branch
EOF
done

echo "Created bom.yaml with common + ${#assetIds[@]} workload entries"

# Replace placeholders in configuration files (following create-project-helms.sh pattern)
echo ""
echo "Replacing placeholder values in files..."

# Replace in bom directory
find "$microAgPath/bom" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Replace in values directory
find "$microAgPath/values" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Replace in target directory
find "$microAgPath/target" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

echo "Replaced placeholders:"
echo "  <parentAssetId> -> $parentAssetId"
echo "  <organization> -> $organization"
echo "  <branch> -> $branch"
echo ""
echo "Per-workload replacements:"
for i in "${!assetIds[@]}"; do
    echo "  helm-${assetIds[$i]}:"
    echo "    <assetId> -> ${assetIds[$i]}"
    echo "    <repository> -> ${repositories[$i]}"
    echo "    <imageName> -> ${repositories[$i]}"
done

# Copy values files from sample
echo ""
echo "Creating values files..."
sampleValuesPath="$SCRIPT_DIR/sample/values"
if [ -d "$sampleValuesPath" ]; then
    cp -r "$sampleValuesPath"/* "$microAgPath/values/"
    
    # Process each values file to expand workload templates
    for valuesFile in "$microAgPath/values"/*.yaml; do
        if [ -f "$valuesFile" ]; then
            echo "Processing $(basename "$valuesFile")..."
            
            # Create a temporary file
            tmpFile="${valuesFile}.tmp"
            
            # Extract the template block
            templateStart=$(grep -n "# workload service values template" "$valuesFile" | cut -d: -f1)
            templateEnd=$(grep -n "# end of workload service values template" "$valuesFile" | cut -d: -f1)
            
            if [ -n "$templateStart" ] && [ -n "$templateEnd" ]; then
                # Get content before template
                head -n $((templateStart - 1)) "$valuesFile" > "$tmpFile"
                
                # Extract template content (between the comment markers, excluding the markers themselves)
                templateContent=$(sed -n "$((templateStart + 2)),$((templateEnd - 2))p" "$valuesFile")
                
                # Generate a block for each workload
                targetPort=8081
                for i in "${!assetIds[@]}"; do
                    assetId="${assetIds[$i]}"
                    repo="${repositories[$i]}"
                    imageName="$repo"
                    
                    # Add header comment for this workload
                    echo "#####################################################################" >> "$tmpFile"
                    echo "# $assetId Service" >> "$tmpFile"
                    echo "#####################################################################" >> "$tmpFile"
                    
                    # Replace placeholders in template and append
                    echo "$templateContent" | sed "s/<assetId>/$assetId/g; s/<imageName>/$imageName/g; s/<targetPort>/$targetPort/g" >> "$tmpFile"
                    
                    # Add separator between workloads (except after last one)
                    if [ $i -lt $((${#assetIds[@]} - 1)) ]; then
                        echo "" >> "$tmpFile"
                    fi
                    
                    ((targetPort++))
                done
                
                # Get content after template
                tail -n +$((templateEnd + 1)) "$valuesFile" >> "$tmpFile"
                
                # Replace original file with processed file
                mv "$tmpFile" "$valuesFile"
            else
                echo "  Warning: Template markers not found in $(basename "$valuesFile")"
            fi
            
            # Replace other placeholders in values files
            sed -i "s/<parentAssetId>/$parentAssetId/g; s/<product>/$product/g; s/<branch>/$branch/g" "$valuesFile"
        fi
    done
    
    echo "Created values files: $(ls "$microAgPath/values")"
else
    echo "Warning: Sample values directory not found, skipping values file creation"
fi

# Copy target files from sample
echo ""
echo "Creating target configuration..."
sampleTargetPath="$SCRIPT_DIR/sample/target"
if [ -d "$sampleTargetPath" ]; then
    cp -r "$sampleTargetPath"/* "$microAgPath/target/"
    
    # Replace placeholders in target files
    find "$microAgPath/target" -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -exec sed -i "s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<product>/$product/g; s/<branch>/$branch/g" {} \;
    
    echo "Created target files: $(ls "$microAgPath/target")"
else
    echo "Warning: Sample target directory not found, skipping target file creation"
fi

echo ""
echo "=========================================="
echo "MicroAG structure created successfully!"
echo "=========================================="
echo "Path: $microAgPath"
echo ""
echo "Structure:"
echo "$organization/"
echo "  $parentAssetId/"
echo "    mag.yaml (with common + ${#assetIds[@]} workloads)"
echo "    bom/"
echo "      bom.yaml (with common + ${#assetIds[@]} workloads)"
echo "    common/"
echo "      templates/"
echo "    helm/"
for assetId in "${assetIds[@]}"; do
    echo "    helm-$assetId/"
done
echo "    values/"
echo "    target/"
echo ""
echo "🎉 All workloads configured successfully!"
