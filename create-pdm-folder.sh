#!/bin/bash

# Check if all 6 arguments are provided
if [ $# -ne 6 ]; then
    echo "Usage: $0 <productName> <imageName> <testEngine> <repository> <bomName> <organization>"
    echo "Example: $0 product myapp cucumber test_ab1234_cd5678 pdmexp george"
    exit 1
fi

# Assign arguments to variables
productName="$1"
imageName="$2"
testEngine="$3"
repository="$4"
bomName="$5"
organization="$6"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Create organization directory
orgPath="$SCRIPT_DIR/$organization"
if [ ! -d "$orgPath" ]; then
    mkdir -p "$orgPath"
    echo "Created organization directory: $orgPath"
else
    echo "Using existing organization directory: $orgPath"
fi

# Create repository directory
repoPath="$orgPath/$repository"
if [ -d "$repoPath" ]; then
    echo "Warning: Repository directory already exists: $repoPath"
    read -p "Do you want to overwrite it? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborting..."
        exit 1
    fi
    rm -rf "$repoPath"
fi

mkdir -p "$repoPath"
echo "Created repository directory: $repoPath"

# Copy sample contents to the new repository directory
samplePath="$SCRIPT_DIR/sample"
if [ ! -d "$samplePath" ]; then
    echo "Error: Sample directory not found at: $samplePath"

# Create pdm directory
pdmPath="$SCRIPT_DIR/pdm"
if [ ! -d "$pdmPath" ]; then
    mkdir -p "$pdmPath"
    echo "Created pdm directory: $pdmPath"
else
    echo "Using existing pdm directory: $pdmPath"
fi

# Create images file
echo "$imageName" > "$pdmPath/images"
echo "Created file: $pdmPath/images"

# Create containers file
echo "$imageName" > "$pdmPath/containers"
echo "Created file: $pdmPath/containers"

# Create test_engine file
echo "$testEngine" > "$pdmPath/test_engine"
echo "Created file: $pdmPath/test_engine"

# Create run_<imageName> file
runFileName="run_$imageName"
cat > "$pdmPath/$runFileName" << EOF
-p 8080:8080
$repository\${PREFX}\$$imageName:latest
EOF
echo "Created file: $pdmPath/$runFileName"

# Create mag file
echo "$organization~$bomName" > "$pdmPath/mag"
echo "Created file: $pdmPath/mag"

echo ""
echo "✅ PDM folder structure created successfully!"
echo "Location: $pdmPath"

