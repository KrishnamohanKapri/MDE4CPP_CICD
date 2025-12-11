#!/bin/bash
# Dependency Resolution Script
# Resolves build order including downstream dependencies

set -e

# Input: space-separated list of changed components
CHANGED_COMPONENTS="$1"

if [ -z "$CHANGED_COMPONENTS" ]; then
    echo ""
    exit 0
fi

# Dependency map: component -> space-separated list of dependencies
declare -A DEPENDENCIES

# Infrastructure (no dependencies)
DEPENDENCIES["abstract-data-types"]=""
DEPENDENCIES["util"]=""
DEPENDENCIES["plugin-framework"]="abstract-data-types util"
DEPENDENCIES["persistence"]="abstract-data-types util"

# Generators (depend on infrastructure)
DEPENDENCIES["ecore4cpp-generator"]="abstract-data-types util plugin-framework persistence"
DEPENDENCIES["uml4cpp-generator"]="abstract-data-types util plugin-framework persistence ecore4cpp-generator"
DEPENDENCIES["fuml4cpp-generator"]="abstract-data-types util plugin-framework persistence ecore4cpp-generator uml4cpp-generator"

# Core Models (depend on generators and each other)
DEPENDENCIES["ecore"]="ecore4cpp-generator"
DEPENDENCIES["types"]="ecore"
DEPENDENCIES["uml"]="ecore types"
DEPENDENCIES["fuml"]="ecore types uml"
DEPENDENCIES["pscs"]="ecore types uml fuml"
DEPENDENCIES["pssm"]="ecore types uml fuml pscs"

# OCL (depends on ecore)
DEPENDENCIES["ocl-model"]="ecore"
DEPENDENCIES["ocl-parser"]="ecore"

# Reflection (depend on core models)
DEPENDENCIES["ecore-reflection"]="ecore"
DEPENDENCIES["primitivetypes-reflection"]="ecore"
DEPENDENCIES["uml-reflection"]="ecore uml ecore-reflection primitivetypes-reflection"

# Profiles (depend on uml)
DEPENDENCIES["standard-profile"]="uml"
DEPENDENCIES["uml4cpp-profile"]="uml"

# Application (depends on uml and fuml)
DEPENDENCIES["foundational-model-library"]="uml fuml"

# Downstream dependencies: components that depend on this component
declare -A DOWNSTREAM

# Build downstream map
for component in "${!DEPENDENCIES[@]}"; do
    deps="${DEPENDENCIES[$component]}"
    for dep in $deps; do
        if [ -z "${DOWNSTREAM[$dep]}" ]; then
            DOWNSTREAM["$dep"]="$component"
        else
            DOWNSTREAM["$dep"]="${DOWNSTREAM[$dep]} $component"
        fi
    done
done

# Function to get all downstream components recursively
get_all_downstream() {
    local comp="$1"
    local result="$comp"
    local visited="$comp"
    
    # Get direct downstream
    local downstream="${DOWNSTREAM[$comp]}"
    
    if [ -n "$downstream" ]; then
        for ds in $downstream; do
            # Avoid cycles
            if [[ ! " $visited " =~ " $ds " ]]; then
                visited="$visited $ds"
                # Recursively get downstream of downstream
                local ds_result=$(get_all_downstream "$ds")
                result="$result $ds_result"
            fi
        done
    fi
    
    echo "$result"
}

# Collect all components that need to be built (changed + downstream)
declare -A ALL_COMPONENTS

# Process each changed component
for component in $CHANGED_COMPONENTS; do
    # Get all downstream components
    all_affected=$(get_all_downstream "$component")
    
    for comp in $all_affected; do
        ALL_COMPONENTS["$comp"]=1
    done
done

# Build order: topological sort
# Simple approach: sort by dependency depth
declare -A DEPTH

# Calculate depth for each component
calculate_depth() {
    local comp="$1"
    
    if [ -n "${DEPTH[$comp]}" ]; then
        return
    fi
    
    local deps="${DEPENDENCIES[$comp]}"
    local max_depth=0
    
    if [ -n "$deps" ]; then
        for dep in $deps; do
            calculate_depth "$dep"
            local dep_depth="${DEPTH[$dep]}"
            if [ "$dep_depth" -ge "$max_depth" ]; then
                max_depth=$((dep_depth + 1))
            fi
        done
    fi
    
    DEPTH["$comp"]=$max_depth
}

# Calculate depths for all components we need to build
for component in "${!ALL_COMPONENTS[@]}"; do
    calculate_depth "$component"
done

# Sort components by depth, then alphabetically
sorted_components=$(for comp in "${!ALL_COMPONENTS[@]}"; do
    echo "${DEPTH[$comp]} $comp"
done | sort -n -k1,1 -k2,2 | awk '{print $2}')

# Output as space-separated list
echo "$sorted_components" | tr '\n' ' ' | sed 's/ $//'

