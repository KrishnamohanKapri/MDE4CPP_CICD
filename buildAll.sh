#!/bin/bash
# Sequential build script for MDE4CPP
# This script runs generateAll, compileAll, and buildOCLAll tasks sequentially
# to ensure proper build order and avoid race conditions
#
# Prerequisites:
# - Run install_dependencies.sh to install system dependencies
# - Run check_prerequisites.sh to verify prerequisites
# - Ensure setenv file exists in the project directory
#
# Usage: ./buildAll.sh (run from MDE4CPP_CrossPlatform directory)

set -e  # Exit on any error

# Check if setenv exists in current directory
if [ ! -f "setenv" ]; then
    echo "ERROR: setenv file not found in the project directory."
    echo "Please ensure setenv file exists in the current directory."
    echo "You can copy setenv.default and configure it, or create setenv based on your setup."
    exit 1
fi

# Source setenv file
# Note: We need to source only the environment variables, not execute the interactive parts
# The setenv file ends with 'bash' which starts an interactive shell - we skip that
echo "Sourcing setenv..."
# Extract only export statements and source them, skipping cd/gradlew/bash commands
# This prevents the script from hanging on the interactive 'bash' command at the end
while IFS= read -r line; do
    # Skip comments, empty lines, cd commands, gradlew commands, and bash command
    if [[ "$line" =~ ^[[:space:]]*export ]] && [[ ! "$line" =~ ^[[:space:]]*# ]]; then
        eval "$line" 2>/dev/null || true
    fi
done < <(sed '/^cd \.\/gradlePlugins$/,$d' setenv)

# Use hardcoded gradlew path
GRADLEW="./application/tools/gradlew"

if [ ! -f "$GRADLEW" ]; then
    echo "Error: gradlew not found at $GRADLEW"
    echo "Please ensure you're running this script from the MDE4CPP_CrossPlatform directory."
    exit 1
fi

# Publish gradle plugins if needed (this is normally done in setenv)
# Do this after GRADLEW is defined so we can use it
if [ -d "gradlePlugins" ]; then
    echo "Publishing MDE4CPP Gradle plugins..."
    (./application/tools/gradlew publishMDE4CPPPluginsToMavenLocal >/dev/null 2>&1 || true)
fi

# Function to clean CMake cache files and build artifacts
# Preserves application/lib and application/bin directories
clean_cmake_cache() {
    echo "Cleaning CMake cache files and build artifacts..."
    echo "----------------------------------------"
    
    local cleaned_count=0
    
    # Find and remove all .cmake directories (excluding application/lib and application/bin)
    while IFS= read -r -d '' dir; do
        # Skip if inside application/lib or application/bin
        if [[ "$dir" != *"/application/lib"* ]] && [[ "$dir" != *"/application/bin"* ]]; then
            echo "  Removing: $dir"
            rm -rf "$dir"
            ((cleaned_count++))
        fi
    done < <(find . -type d -name ".cmake" -print0 2>/dev/null)
    
    # Find and remove all CMakeCache.txt files
    while IFS= read -r -d '' file; do
        if [[ "$file" != *"/application/lib"* ]] && [[ "$file" != *"/application/bin"* ]]; then
            echo "  Removing: $file"
            rm -f "$file"
            ((cleaned_count++))
        fi
    done < <(find . -type f -name "CMakeCache.txt" -print0 2>/dev/null)
    
    # Find and remove all CMakeFiles directories
    while IFS= read -r -d '' dir; do
        if [[ "$dir" != *"/application/lib"* ]] && [[ "$dir" != *"/application/bin"* ]]; then
            echo "  Removing: $dir"
            rm -rf "$dir"
            ((cleaned_count++))
        fi
    done < <(find . -type d -name "CMakeFiles" -print0 2>/dev/null)
    
    # Find and remove all src_gen directories (for fresh code generation)
    while IFS= read -r -d '' dir; do
        if [[ "$dir" != *"/application/lib"* ]] && [[ "$dir" != *"/application/bin"* ]]; then
            echo "  Removing: $dir"
            rm -rf "$dir"
            ((cleaned_count++))
        fi
    done < <(find . -type d -name "src_gen" -print0 2>/dev/null)
    
    if [ $cleaned_count -eq 0 ]; then
        echo "  No cache files found to clean."
    else
        echo "  Cleaned $cleaned_count cache directories/files."
    fi
    echo ""
}

echo "=========================================="
echo "MDE4CPP Sequential Build Script"
echo "=========================================="
echo ""

# Clean CMake cache files before building
clean_cmake_cache

# Step 1: Generate all models
echo "Step 1/3: Running generateAll..."
echo "----------------------------------------"
if ! "$GRADLEW" generateAll; then
    echo ""
    echo "ERROR: generateAll failed!"
    exit 1
fi
echo "✓ generateAll completed successfully"
echo ""

# Step 2: Compile all generated code
echo "Step 2/3: Running compileAll..."
echo "----------------------------------------"
if ! "$GRADLEW" compileAll; then
    echo ""
    echo "ERROR: compileAll failed!"
    exit 1
fi
echo "✓ compileAll completed successfully"
echo ""

# Step 3: Build OCL components
echo "Step 3/3: Running src:buildOCLAll..."
echo "----------------------------------------"
if ! "$GRADLEW" src:buildOCLAll; then
    echo ""
    echo "ERROR: src:buildOCLAll failed!"
    exit 1
fi
echo "✓ src:buildOCLAll completed successfully"
echo ""

echo "=========================================="
echo "BUILD SUCCESSFUL - All tasks completed!"
echo "=========================================="
