#!/bin/bash

# Check if at least 6 arguments are provided (branch + bomName + organization + database flag + s3 flag + at least one git URL)
if [ $# -lt 6 ]; then
    echo "Usage: $0 <branch> <bomName> <organization> <database> <s3> <git-url1> [git-url2] [git-url3] ..."
    echo "Example: $0 develop pdmexp george y n https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/raj_ab1234_cd3456.git https://bitbkt.mdtc.itp01.p.fhlmc.com/scm/george/raj_ab1234_ef7890.git"
    echo "Note: bomName must be 6 alphanumeric characters or less"
    echo "Note: organization is the Bitbucket organization/project key"
    echo "Note: database must be 'y' or 'n' (creates Aurora RDS configuration)"
    echo "Note: s3 must be 'y' or 'n' (creates S3 bucket configuration)"
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

# Assign organization from third argument and validate
organization="$1"
shift  # Remove the third argument (organization) from the argument list

# Validate organization (alphanumeric, may contain hyphens/underscores)
if [[ -z "$organization" ]]; then
    echo "Error: organization cannot be empty"
    exit 1
fi

# Assign database flag from fourth argument and validate
database="$1"
shift  # Remove the fourth argument (database) from the argument list

# Validate database flag
if [[ ! "$database" =~ ^[yYnN]$ ]]; then
    echo "Error: database must be 'y' or 'n'. Got: '$database'"
    exit 1
fi

# Normalize to lowercase
database="${database,,}"

# Assign s3 flag from fifth argument and validate
s3="$1"
shift  # Remove the fifth argument (s3) from the argument list

# Validate s3 flag
if [[ ! "$s3" =~ ^[yYnN]$ ]]; then
    echo "Error: s3 must be 'y' or 'n'. Got: '$s3'"
    exit 1
fi

# Normalize to lowercase
s3="${s3,,}"

# Arrays to store parsed information from all git URLs
declare -a assetIds
declare -a repositories
declare -a products
declare -a gitUrls
parentAssetId=""

echo "Organization: $organization"
echo "Parsing ${#@} git repositories..."
echo ""

# First pass: Parse all git URLs and validate consistency
counter=1
for gitUrl in "$@"; do
    echo "Parsing repository $counter: $gitUrl"
    
    # Extract repository name from Bitbucket URL
    if [[ "$gitUrl" =~ https://bitbkt\.mdtc\.itp01\.p\.fhlmc\.com/scm/([^/]+)/([^/]+)\.git$ ]]; then
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
    
    # Validate that all repositories have the same parentAssetId
    if [ $counter -eq 1 ]; then
        parentAssetId="$parentId"
        echo "  Parent Asset ID: $parentAssetId"
    else
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
    
    # If database flag is 'y', inject database snippets into deployment.yaml
    if [ "$database" == "y" ]; then
        deploymentFile="$helmDir/templates/deployment.yaml"
        
        if [ -f "$deploymentFile" ]; then
            # Inject annotations snippet at end of spec.template.metadata.annotations
            annotationsSnippet="$SCRIPT_DIR/pdmex/helm-snippets/postgres/deployment-annotations-snippet.yaml"
            
            if [ -f "$annotationsSnippet" ]; then
                # Find the annotations: line in template.metadata section (6 spaces)
                annotationsLine=$(grep -n "^      annotations:" "$deploymentFile" | head -1 | cut -d: -f1)
                
                if [ -n "$annotationsLine" ]; then
                    # Find the next line with 4 or 6 spaces at start after annotations (this marks end of annotations block)
                    # This will be either "spec:" or another metadata section
                    nextSectionLine=$(tail -n +$((annotationsLine + 1)) "$deploymentFile" | grep -n "^    [a-zA-Z]" | head -1 | cut -d: -f1)
                    
                    if [ -n "$nextSectionLine" ]; then
                        # Calculate actual line number in file
                        insertBeforeLine=$((annotationsLine + nextSectionLine))
                        tmpFile="${deploymentFile}.tmp"
                        
                        # Get content before the next section
                        head -n $((insertBeforeLine - 1)) "$deploymentFile" > "$tmpFile"
                        
                        # Append annotations snippet with proper indentation (8 spaces - same as other annotations)
                        while IFS= read -r line || [ -n "$line" ]; do
                            if [ -n "$line" ]; then
                                echo "        $line" >> "$tmpFile"
                            else
                                echo "" >> "$tmpFile"
                            fi
                        done < "$annotationsSnippet"
                        
                        # Append rest of file from next section line
                        tail -n +$insertBeforeLine "$deploymentFile" >> "$tmpFile"
                        
                        mv "$tmpFile" "$deploymentFile"
                    fi
                fi
            fi
        fi
    fi
    
    # Handle envFrom injection based on database and s3 flags
    # This logic runs after both database and s3 processing to handle all cases:
    # - database only: inject db-config-map only
    # - s3 only: inject s3-config-map only  
    # - both: inject both config maps
    # - neither: don't inject envFrom at all
    deploymentFile="$helmDir/templates/deployment.yaml"
    
    if [ -f "$deploymentFile" ]; then
        # Only inject envFrom if at least one of database or s3 is enabled
        if [ "$database" == "y" ] || [ "$s3" == "y" ]; then
            # Find the line after the last entry in the env section
            # We look for the line with "env:" first
            envLine=$(grep -n "^[[:space:]]*env:" "$deploymentFile" | head -1 | cut -d: -f1)
            
            if [ -n "$envLine" ]; then
                # Find the next top-level key after env section (like volumeMounts, resources, etc)
                # This will be at the same indentation level as "env:"
                nextSectionLine=$(tail -n +$((envLine + 1)) "$deploymentFile" | grep -n "^[[:space:]]\{10\}[a-zA-Z]" | head -1 | cut -d: -f1)
                
                if [ -n "$nextSectionLine" ]; then
                    # Calculate the line number where we should insert (right before next section)
                    insertLine=$((envLine + nextSectionLine - 1))
                    
                    tmpFile="${deploymentFile}.tmp"
                    
                    # Get content up to the insertion point
                    head -n "$insertLine" "$deploymentFile" > "$tmpFile"
                    
                    # Build and append envFrom section with correct indentation (10 spaces to match env)
                    echo "          envFrom:" >> "$tmpFile"
                    
                    # Add db-config-map if database flag is 'y'
                    if [ "$database" == "y" ]; then
                        echo "          - configMapRef:" >> "$tmpFile"
                        echo "              name: db-config-map" >> "$tmpFile"
                    fi
                    
                    # Add s3-config-map if s3 flag is 'y'
                    if [ "$s3" == "y" ]; then
                        echo "          - configMapRef:" >> "$tmpFile"
                        echo "              name: s3-config-map" >> "$tmpFile"
                    fi
                    
                    # Add a blank line for spacing
                    echo "" >> "$tmpFile"
                    
                    # Append rest of file from the next section
                    tail -n +$((insertLine + 1)) "$deploymentFile" >> "$tmpFile"
                    
                    mv "$tmpFile" "$deploymentFile"
                fi
            fi
        fi
    fi
    
    # Process S3-specific files if s3 flag is 'y'
    if [ "$s3" == "y" ]; then
        deploymentFile="$helmDir/templates/deployment.yaml"
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
    
    # If database flag is 'y', inject database configuration from module
    if [ "$database" == "y" ]; then
        echo "Adding Aurora RDS database configuration to bom.yaml..."
        
        # Check if envResources line exists
        envLine=$(grep -n "envResources:" "$bomYamlPath" | head -1 | cut -d: -f1)
        
        if [ -z "$envLine" ]; then
            # envResources doesn't exist, need to create it
            # Find contextVersion line to determine insertion point and indentation
            contextLine=$(grep -n "contextVersion:" "$bomYamlPath" | head -1 | cut -d: -f1)
            
            if [ -n "$contextLine" ]; then
                # Get the indentation of contextVersion line
                indentation=$(sed -n "${contextLine}p" "$bomYamlPath" | sed 's/\(^[[:space:]]*\).*/\1/')
                
                tmpFile="${bomYamlPath}.tmp"
                
                # Get content up to and including contextVersion line
                head -n "$contextLine" "$bomYamlPath" > "$tmpFile"
                
                # Add envResources line with same indentation as contextVersion
                echo "${indentation}envResources:" >> "$tmpFile"
                
                # Add rest of file after contextVersion line
                tail -n +$((contextLine + 1)) "$bomYamlPath" >> "$tmpFile"
                
                mv "$tmpFile" "$bomYamlPath"
                
                echo "Created envResources section in bom.yaml"
                
                # Update envLine for next step
                envLine=$(grep -n "envResources:" "$bomYamlPath" | head -1 | cut -d: -f1)
            else
                echo "Warning: contextVersion line not found in bom.yaml, cannot create envResources"
            fi
        fi
        
        if [ -n "$envLine" ]; then
            # Read the database snippet from the module
            dbSnippetPath="$SCRIPT_DIR/pdmex/helm-snippets/postgres/bom-snippet.yaml"
            
            if [ -f "$dbSnippetPath" ]; then
                # Create temp file
                tmpFile="${bomYamlPath}.tmp"
                
                # Get content before insertion point (envResources line)
                head -n "$envLine" "$bomYamlPath" > "$tmpFile"
                
                # Inject snippet once with bomName substitution
                sed "s/<bomName>/$bomName/g" "$dbSnippetPath" >> "$tmpFile"
                
                # Add rest of file after envResources line
                tail -n +$((envLine + 1)) "$bomYamlPath" >> "$tmpFile"
                
                # Replace original
                mv "$tmpFile" "$bomYamlPath"
                
                echo "Added Aurora RDS configuration for bomName: $bomName"
            else
                echo "Warning: Database snippet not found at $dbSnippetPath"
            fi
        else
            echo "Warning: Could not find or create envResources line in bom.yaml"
        fi
        
        # Copy database ConfigMap to common/templates
        dbConfigMapPath="$SCRIPT_DIR/pdmex/helm-snippets/postgres/db-configmap.yaml"
        commonTemplatesPath="$microAgPath/common/templates"
        
        if [ -f "$dbConfigMapPath" ]; then
            cp "$dbConfigMapPath" "$commonTemplatesPath/"
            echo "Copied db-configmap.yaml to common/templates/"
        else
            echo "Warning: db-configmap.yaml not found at $dbConfigMapPath"
        fi
    fi
    
    # If s3 flag is 'y', inject S3 configuration from module
    if [ "$s3" == "y" ]; then
        echo "Adding S3 bucket configuration to bom.yaml..."
        
        # Check if envResources line exists
        envLine=$(grep -n "envResources:" "$bomYamlPath" | head -1 | cut -d: -f1)
        
        if [ -z "$envLine" ]; then
            # envResources doesn't exist, need to create it
            # Find contextVersion line to determine insertion point and indentation
            contextLine=$(grep -n "contextVersion:" "$bomYamlPath" | head -1 | cut -d: -f1)
            
            if [ -n "$contextLine" ]; then
                # Get the indentation of contextVersion line
                indentation=$(sed -n "${contextLine}p" "$bomYamlPath" | sed 's/\(^[[:space:]]*\).*/\1/')
                
                tmpFile="${bomYamlPath}.tmp"
                
                # Get content up to and including contextVersion line
                head -n "$contextLine" "$bomYamlPath" > "$tmpFile"
                
                # Add envResources line with same indentation as contextVersion
                echo "${indentation}envResources:" >> "$tmpFile"
                
                # Add rest of file after contextVersion line
                tail -n +$((contextLine + 1)) "$bomYamlPath" >> "$tmpFile"
                
                mv "$tmpFile" "$bomYamlPath"
                
                echo "Created envResources section in bom.yaml"
                
                # Update envLine for next step
                envLine=$(grep -n "envResources:" "$bomYamlPath" | head -1 | cut -d: -f1)
            else
                echo "Warning: contextVersion line not found in bom.yaml, cannot create envResources"
            fi
        fi
        
        if [ -n "$envLine" ]; then
            # Read the S3 snippet from the module
            s3SnippetPath="$SCRIPT_DIR/pdmex/helm-snippets/s3/bom-snippet.yaml"
            
            if [ -f "$s3SnippetPath" ]; then
                # Create temp file
                tmpFile="${bomYamlPath}.tmp"
                
                # Get content before insertion point (envResources line)
                head -n "$envLine" "$bomYamlPath" > "$tmpFile"
                
                # Inject snippet once with bomName substitution
                sed "s/<bomName>/$bomName/g" "$s3SnippetPath" >> "$tmpFile"
                
                # Add rest of file after envResources line
                tail -n +$((envLine + 1)) "$bomYamlPath" >> "$tmpFile"
                
                # Replace original
                mv "$tmpFile" "$bomYamlPath"
                
                echo "Added S3 bucket configuration for bomName: $bomName"
            else
                echo "Warning: S3 snippet not found at $s3SnippetPath"
            fi
        else
            echo "Warning: Could not find or create envResources line in bom.yaml"
        fi
        
        # Copy S3 ConfigMap to common/templates
        s3ConfigMapPath="$SCRIPT_DIR/pdmex/helm-snippets/s3/s3-configmap.yaml"
        commonTemplatesPath="$microAgPath/common/templates"
        
        if [ -f "$s3ConfigMapPath" ]; then
            cp "$s3ConfigMapPath" "$commonTemplatesPath/"
            echo "Copied s3-configmap.yaml to common/templates/"
        else
            echo "Warning: s3-configmap.yaml not found at $s3ConfigMapPath"
        fi
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
    
    # If database flag is 'y', append database snippet to all values files
    if [ "$database" == "y" ]; then
        dbValuesSnippetPath="$SCRIPT_DIR/pdmex/helm-snippets/postgres/values-db-snippet.yaml"
        
        if [ -f "$dbValuesSnippetPath" ]; then
            echo "Appending database configuration to values files..."
            
            for valuesFile in "$microAgPath/values"/*.yaml; do
                if [ -f "$valuesFile" ]; then
                    # Append the snippet to the end of the file
                    cat "$dbValuesSnippetPath" >> "$valuesFile"
                    echo "  Appended to $(basename "$valuesFile")"
                fi
            done
        else
            echo "Warning: values-db-snippet.yaml not found at $dbValuesSnippetPath"
        fi
    fi
    
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
