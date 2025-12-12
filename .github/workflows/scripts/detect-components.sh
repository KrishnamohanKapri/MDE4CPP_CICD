#!/bin/bash
# Component Detection Script
# Maps changed file paths to component names

set -e

# Get changed files from git diff
if [ -n "$GITHUB_BASE_REF" ]; then
    # PR: compare against base branch
    BASE_REF="${GITHUB_BASE_REF}"
    HEAD_REF="${GITHUB_HEAD_REF:-$GITHUB_SHA}"
    
    # Fetch the base branch first to ensure it's available
    git fetch origin "${BASE_REF}:refs/remotes/origin/${BASE_REF}" 2>/dev/null || \
    git fetch origin "${BASE_REF}" 2>/dev/null || true
    
    # Try multiple diff patterns to handle different git configurations
    CHANGED_FILES=$(git diff --name-only "origin/${BASE_REF}...${HEAD_REF}" 2>/dev/null || \
                    git diff --name-only "${BASE_REF}...${HEAD_REF}" 2>/dev/null || \
                    git diff --name-only "origin/${BASE_REF}..${HEAD_REF}" 2>/dev/null || \
                    git diff --name-only "${BASE_REF}..${HEAD_REF}" 2>/dev/null || \
                    echo "")
else
    # Push: compare against previous commit
    CHANGED_FILES=$(git diff --name-only HEAD~1 HEAD)
fi

# If no changes, exit
if [ -z "$CHANGED_FILES" ]; then
    echo ""
    exit 0
fi

# Component mapping: path pattern -> component name
declare -A COMPONENT_MAP

# Infrastructure
COMPONENT_MAP["src/common/abstractDataTypes"]="abstract-data-types"
COMPONENT_MAP["src/util"]="util"
COMPONENT_MAP["src/common/pluginFramework"]="plugin-framework"
COMPONENT_MAP["src/common/persistence"]="persistence"

# Generators
COMPONENT_MAP["generator/ecore4CPP"]="ecore4cpp-generator"
COMPONENT_MAP["generator/UML4CPP"]="uml4cpp-generator"
COMPONENT_MAP["generator/fUML4CPP"]="fuml4cpp-generator"

# Core Models
COMPONENT_MAP["src/ecore"]="ecore"
COMPONENT_MAP["src/uml/types"]="types"
COMPONENT_MAP["src/uml/uml"]="uml"
COMPONENT_MAP["src/fuml"]="fuml"
COMPONENT_MAP["src/pscs"]="pscs"
COMPONENT_MAP["src/pssm"]="pssm"

# OCL
COMPONENT_MAP["src/ocl/oclModel"]="ocl-model"
COMPONENT_MAP["src/ocl/oclParser"]="ocl-parser"

# Reflection
COMPONENT_MAP["src/common/ecoreReflection"]="ecore-reflection"
COMPONENT_MAP["src/common/primitivetypesReflection"]="primitivetypes-reflection"
COMPONENT_MAP["src/common/umlReflection"]="uml-reflection"

# Profiles
COMPONENT_MAP["src/common/standardProfile"]="standard-profile"
COMPONENT_MAP["src/common/UML4CPPProfile"]="uml4cpp-profile"

# Application
COMPONENT_MAP["src/common/FoundationalModelLibrary"]="foundational-model-library"

# Gradle Plugins (affects all components)
COMPONENT_MAP["gradlePlugins"]="all"

# Docker (affects all components)
COMPONENT_MAP["docker"]="all"

# Track detected components
declare -A DETECTED_COMPONENTS

# Process each changed file
while IFS= read -r file; do
    # Skip generated files and build artifacts
    if [[ "$file" == *"/src_gen/"* ]] || \
       [[ "$file" == *"/build/"* ]] || \
       [[ "$file" == *"/.cmake/"* ]] || \
       [[ "$file" == *"/application/"* ]] || \
       [[ "$file" == "*.dll" ]] || \
       [[ "$file" == "*.jar" ]] || \
       [[ "$file" == "*.a" ]]; then
        continue
    fi
    
    # Check each path pattern
    for path_pattern in "${!COMPONENT_MAP[@]}"; do
        if [[ "$file" == "$path_pattern"* ]]; then
            component="${COMPONENT_MAP[$path_pattern]}"
            
            # Special handling for "all" components
            if [ "$component" = "all" ]; then
                # Return all components
                echo "abstract-data-types util plugin-framework persistence ecore4cpp-generator uml4cpp-generator fuml4cpp-generator ecore types uml fuml pscs pssm ocl-model ocl-parser ecore-reflection primitivetypes-reflection uml-reflection standard-profile uml4cpp-profile foundational-model-library"
                exit 0
            fi
            
            DETECTED_COMPONENTS["$component"]=1
            break
        fi
    done
done <<< "$CHANGED_FILES"

# Output unique components
if [ ${#DETECTED_COMPONENTS[@]} -eq 0 ]; then
    echo ""
else
    # Sort components for consistent output
    printf '%s\n' "${!DETECTED_COMPONENTS[@]}" | sort | tr '\n' ' ' | sed 's/ $//'
fi

