#!/bin/bash

# Check if at least 3 arguments are provided (branch + bomName + at least one git URL)
if [ $# -lt 3 ]; then
    echo "Usage: $0 <branch> <bomName> <git-url1> [git-url2] [git-url3] ..."
    echo "Example: $0 develop pdmexp https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/raj_ab1234_cd3456.git https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/raj_ab1234_ef7890.git"
    echo "Note: bomName must be 6 alphanumeric characters or less"
    exit 1
fi

# Get the script directory (root of the project)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Assign branch from first argument
branch="$1"
shift  # Remove the first argument (branch) from the argument list

# Assign bomName from second argument and validate
bomName="$1"
shift  # Remove the second argument (bomName) from the argument list

# Validate bomName (6 alphanumeric characters or less)
if [[ ! "$bomName" =~ ^[a-zA-Z0-9]{1,6}$ ]]; then
    echo "Error: bomName must be 1-6 alphanumeric characters. Got: '$bomName'"
    exit 1
fi

# Arrays to store parsed information from all git URLs
declare -a assetIds
declare -a repositories
declare -a products
declare -a gitUrls
organization=""
parentAssetId=""

echo "Parsing ${#@} git repositories..."
echo ""

# First pass: Parse all git URLs and validate consistency
counter=1
for gitUrl in "$@"; do
    echo "Parsing repository $counter: $gitUrl"
    
    # Extract organization and repository name from Bitbucket URL
    if [[ "$gitUrl" =~ https://bitbkt\.mdtc\.itp01\.p\.fhlmc\.com/scm/([^/]+)/([^/]+)\.git$ ]]; then
        org="${BASH_REMATCH[1]}"
        repo="${BASH_REMATCH[2]}"
    else
        echo "Error: Invalid Bitbucket URL format: $gitUrl"
        echo "Expected format: https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/organization/repository.git"
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
    gitUrls+=("$gitUrl")
    assetIds+=("$assetId")
    repositories+=("$repo")
    products+=("$prod")
    
    ((counter++))
done

echo ""
echo "=========================================="
echo "Creating MicroAG structure"
echo "=========================================="
echo "BOM Name: $bomName"
echo "Organization: $organization"
echo "Parent Asset ID: $parentAssetId"
echo "Branch: $branch"
echo "Workloads: ${#assetIds[@]}"
for i in "${!assetIds[@]}"; do
    echo "  - ${assetIds[$i]} (${products[$i]})"
done
echo ""

# Create directory structure: organization/bomName/
orgPath="$SCRIPT_DIR/$organization"
microAgPath="$orgPath/$bomName"

# Create organization directory if it doesn't exist (no prompt)
if [ ! -d "$orgPath" ]; then
    mkdir -p "$orgPath"
    echo "Created organization directory: $orgPath"
else
    echo "Using existing organization directory: $orgPath"
fi

# Check if bomName directory already exists
if [ -d "$microAgPath" ]; then
    echo "Warning: BOM directory already exists: $microAgPath"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
    rm -rf "$microAgPath"
fi

mkdir -p "$microAgPath"
echo "Created BOM directory: $microAgPath"

# Copy entire sample directory structure as a base
echo ""
echo "Copying sample structure..."
samplePath="$SCRIPT_DIR/pdmex/pdm_pdmex_poc048_baseline_nodb"
if [ ! -d "$samplePath" ]; then
    echo "Error: Sample directory not found at: $samplePath"
    exit 1
fi

# Copy all contents from sample (excluding helm-assetId template)
cp -r "$samplePath/bom" "$microAgPath/"
cp -r "$samplePath/common" "$microAgPath/"
cp -r "$samplePath/helm" "$microAgPath/"
cp -r "$samplePath/spam" "$microAgPath/"
cp -r "$samplePath/values" "$microAgPath/"
cp -r "$samplePath/target" "$microAgPath/"
echo "Copied base structure from sample (bom, common, helm, spam, values, target)"

# Replace placeholders in base helm directory
find "$microAgPath/helm" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Replace placeholders in common directory
find "$microAgPath/common" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

# Replace placeholders in spam directory
find "$microAgPath/spam" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<repository>/$parentAssetId/g; s/<imageName>/$parentAssetId/g; s/<branch>/$branch/g" {} \;

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
    
    find "$helmDir" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<assetId>/$assetId/g; s/<organization>/$organization/g; s/<repository>/$repo/g; s/<imageName>/$imageName/g; s/<branch>/$branch/g" {} \;
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

# Process bom.yaml file from template
echo ""
echo "Creating bom.yaml..."
bomYamlPath="$microAgPath/bom/bom.yaml"

# The bom.yaml should already be copied from sample, now we need to expand the workload template
if [ -f "$bomYamlPath" ]; then
    # Look for the workload template marker (a line containing "- name: helm-<assetId>")
    templateLine=$(grep -n "name: helm-<assetId>" "$bomYamlPath" | head -1 | cut -d: -f1)
    
    if [ -n "$templateLine" ]; then
        # Create a temporary file
        tmpFile="${bomYamlPath}.tmp"
        
        # Get content before the workload template
        head -n $((templateLine - 1)) "$bomYamlPath" > "$tmpFile"
        
        # Find the end of the template block (next workload entry or end of file)
        # Extract from template line to end of file, then find where this template ends
        tailContent=$(tail -n +$templateLine "$bomYamlPath")
        
        # Count lines in template (find next "  - name:" at same indentation level or end)
        templateEndOffset=$(echo "$tailContent" | tail -n +2 | grep -n "^  - name:" | head -1 | cut -d: -f1)
        
        if [ -n "$templateEndOffset" ]; then
            # Template ends before next workload entry
            templateLines=$templateEndOffset
        else
            # Template goes to end of file
            templateLines=$(echo "$tailContent" | wc -l)
        fi
        
        # Extract the template content
        templateContent=$(echo "$tailContent" | head -n $templateLines)
        
        # Generate a block for each workload
        for i in "${!assetIds[@]}"; do
            assetId="${assetIds[$i]}"
            repo="${repositories[$i]}"
            
            # Replace placeholders in template and append
            echo "$templateContent" | sed "s/<assetId>/$assetId/g; s/<repository>/$repo/g; s/<imageName>/$repo/g" >> "$tmpFile"
        done
        
        # If there was content after the template, add it
        if [ -n "$templateEndOffset" ]; then
            tail -n +$((templateLine + templateLines)) "$bomYamlPath" >> "$tmpFile"
        fi
        
        # Replace original file with processed file
        mv "$tmpFile" "$bomYamlPath"
        
        echo "Expanded bom.yaml workload template for ${#assetIds[@]} workloads"
    else
        echo "Warning: No workload template marker found in bom.yaml (expected 'helm-<assetId>')"
    fi
else
    echo "Error: bom.yaml not found at $bomYamlPath"
    exit 1
fi

# Replace placeholders in configuration files
echo ""
echo "Replacing placeholder values in files..."

# Replace global placeholders in bom directory
# Note: bom.yaml template already processed, this handles remaining global placeholders
find "$microAgPath/bom" -type f \( -name "*.yaml" -o -name "*.yml" -o -name "*.json" -o -name "*.xml" -o -name "*.tpl" -o -name "*.txt" -o -name "*.md" \) -exec sed -i "s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<organization>/$organization/g; s/<branch>/$branch/g" {} \;

echo "Replaced global placeholders:"
echo "  <bomName> -> $bomName"
echo "  <parentAssetId> -> $parentAssetId"
echo "  <organization> -> $organization"
echo "  <branch> -> $branch"
echo ""
echo "Per-workload replacements (handled in template expansion):"
for i in "${!assetIds[@]}"; do
    echo "  helm-${assetIds[$i]}:"
    echo "    <assetId> -> ${assetIds[$i]}"
    echo "    <repository> -> ${repositories[$i]}"
    echo "    <imageName> -> ${repositories[$i]}"
done

# Copy values files from sample
echo ""
echo "Creating values files..."
sampleValuesPath="$SCRIPT_DIR/pdmex/pdm_pdmex_poc048_baseline_nodb/values"
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
            
            # Replace global placeholders in values files (organization, bomName, parentAssetId, branch)
            sed -i "s/<organization>/$organization/g; s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<product>/$product/g; s/<branch>/$branch/g" "$valuesFile"
            
            # Replace any remaining workload-specific placeholders that appear outside template blocks
            # Use first workload as default for any remaining placeholders (edge case handling)
            if [ ${#assetIds[@]} -gt 0 ]; then
                firstAssetId="${assetIds[0]}"
                firstRepo="${repositories[0]}"
                sed -i "s/<assetId>/$firstAssetId/g; s/<repository>/$firstRepo/g; s/<imageName>/$firstRepo/g; s/<targetPort>/8081/g" "$valuesFile"
            fi
        fi
    done
    
    echo "Created values files: $(ls "$microAgPath/values")"
else
    echo "Warning: Sample values directory not found, skipping values file creation"
fi

# Copy target files from sample
echo ""
echo "Creating target configuration..."
sampleTargetPath="$SCRIPT_DIR/pdmex/pdm_pdmex_poc048_baseline_nodb/target"
if [ -d "$sampleTargetPath" ]; then
    cp -r "$sampleTargetPath"/* "$microAgPath/target/"
    
    # Replace global placeholders in target files
    find "$microAgPath/target" -type f \( -name "*.json" -o -name "*.yaml" -o -name "*.yml" \) -exec sed -i "s/<organization>/$organization/g; s/<bomName>/$bomName/g; s/<parentAssetId>/$parentAssetId/g; s/<product>/$product/g; s/<branch>/$branch/g" {} \;
    
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
echo "  $bomName/"
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

# Execute create-pdm-folder.sh for each repository
echo ""
echo "=========================================="
echo "Creating PDM folders for each workload..."
echo "=========================================="

PDM_SCRIPT="$SCRIPT_DIR/create-pdm-folder.sh"

if [ -f "$PDM_SCRIPT" ]; then
    # Make sure create-pdm-folder.sh is executable
    chmod +x "$PDM_SCRIPT"
    
    # Create destination directory if it doesn't exist
    destDir="/home/pdm/pdm-folder-zips"
    if [ ! -d "$destDir" ]; then
        mkdir -p "$destDir"
        echo "Created destination directory: $destDir"
    fi
    
    # Execute for each repository
    for i in "${!assetIds[@]}"; do
        assetId="${assetIds[$i]}"
        repo="${repositories[$i]}"
        imageName="$repo"
        
        echo ""
        echo "[$((i+1))/${#assetIds[@]}] Creating PDM folder for $repo..."
        echo "----------------------------------------"
        
        # Create helm directory for this workload if it doesn't exist
        helmWorkloadPath="$microAgPath/helm-$assetId"
        if [ ! -d "$helmWorkloadPath" ]; then
            echo "Warning: helm-$assetId directory not found at $helmWorkloadPath"
            continue
        fi
        
        # Copy create-pdm-folder.sh to the helm workload directory
        cp "$PDM_SCRIPT" "$helmWorkloadPath/"
        
        # Navigate to the helm workload directory
        cd "$helmWorkloadPath"
        
        # Call create-pdm-folder.sh with mapped parameters
        # productName, imageName, testEngine, repository, bomName, organization
        if ./"create-pdm-folder.sh" "product" "$imageName" "cucumber" "$repo" "$bomName" "$organization"; then
            echo "✅ PDM structure created successfully for $repo"
            
            # Create zip file
            if [ -d "pdm" ]; then
                zipFileName="${repo}-pdm.zip"
                echo "Creating zip file: $zipFileName"
                
                if zip -r "$zipFileName" pdm/; then
                    echo "✅ Created zip file: $zipFileName"
                    
                    # Move zip file to destination directory
                    if mv "$zipFileName" "$destDir/"; then
                        echo "✅ Moved zip file to: $destDir/$zipFileName"
                    else
                        echo "❌ Failed to move zip file to: $destDir"
                    fi
                    
                    # Delete the pdm folder
                    echo "Cleaning up pdm folder..."
                    rm -rf pdm/
                    echo "✅ PDM folder deleted"
                else
                    echo "❌ Failed to create zip file"
                fi
            else
                echo "❌ PDM folder not found, skipping zip creation"
            fi
        else
            echo "❌ Failed to create PDM structure for $repo"
        fi
        
        # Clean up the copied script
        rm -f "create-pdm-folder.sh"
        
        # Return to script directory
        cd "$SCRIPT_DIR"
    done
    
    echo ""
    echo "=========================================="
    echo "✅ All PDM folders created!"
    echo "=========================================="
else
    echo "Warning: create-pdm-folder.sh not found at: $PDM_SCRIPT"
    echo "Skipping PDM folder creation"
fi
