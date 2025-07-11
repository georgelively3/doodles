#!/bin/bash

# Check if all 4 arguments are provided
if [ $# -ne 4 ]; then
    echo "Usage: $0 <productName> <imageName> <testEngine> <fabId>"
    echo "Example: $0 MyProduct myapp junit fab123"
    exit 1
fi

# Assign arguments to variables
productName="$1"
imageName="$2"
testEngine="$3"
fabId="$4"

# Get the script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
pdmPath="$SCRIPT_DIR/pdm"

# Create pdm directory at the root of the project
if [ ! -d "$pdmPath" ]; then
    mkdir -p "$pdmPath"
    echo "Created pdm directory at: $pdmPath"
fi

 Create images file
echo -n "$imageName" > "$pdmPath/images"
echo "" >> "$pdmPath/images"
echo "Created images file"

# Create containers file
echo -n "$imageName" > "$pdmPath/containers"
echo "" >> "$pdmPath/containers"
echo "Created containers file"

# Create test_engine file
echo -n "$testEngine" > "$pdmPath/test_engine"
echo "" >> "$pdmPath/test_engine"
echo "Created test_engine file"

# Create run file
cat > "$pdmPath/run_$imageName" << 'EOF'
-p 8080:8080
$PDMREPO/${PREFIX}$imageName:latest
EOF
echo "Created run_$imageName file"

# Create spam.xml file
cat > "$pdmPath/spam.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<product id="$productName" name="$productName" xmlns="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="spam-product.xsd">
  <fab id="$fabId" name="$fabId" direction="outbound" FABtype="Web UI"></fab>
</product>
EOF
echo "Created spam.xml file"

echo "PDM structure created successfully!"
echo "Files created in: $pdmPath"
