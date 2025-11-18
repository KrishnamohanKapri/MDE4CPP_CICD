#!/bin/bash
# Prerequisites Check Script for MDE4CPP Setup

echo "=== MDE4CPP Prerequisites Check ==="
echo ""

# Check Java
echo "Checking Java..."
if command -v java &> /dev/null; then
    JAVA_VERSION=$(java -version 2>&1 | head -n 1)
    echo "✓ Java found: $JAVA_VERSION"
    if command -v javac &> /dev/null; then
        echo "✓ javac found"
        # Try to find JAVA_HOME
        if [ -n "$JAVA_HOME" ]; then
            echo "  JAVA_HOME: $JAVA_HOME"
        else
            JAVA_PATH=$(readlink -f $(which java) 2>/dev/null)
            if [ -n "$JAVA_PATH" ]; then
                JAVA_HOME_CANDIDATE=$(echo $JAVA_PATH | sed 's:/bin/java::')
                echo "  Suggested JAVA_HOME: $JAVA_HOME_CANDIDATE"
            fi
        fi
    else
        echo "✗ javac not found (need JDK, not just JRE)"
    fi
else
    echo "✗ Java not found"
    echo "  Install with: sudo apt-get install openjdk-21-jdk"
fi
echo ""

# Check CMake
echo "Checking CMake..."
if command -v cmake &> /dev/null; then
    CMAKE_VERSION=$(cmake --version | head -n 1)
    echo "✓ $CMAKE_VERSION"
else
    echo "✗ CMake not found"
    echo "  Install with: sudo apt-get install cmake"
fi
echo ""

# Check MinGW-w64
echo "Checking MinGW-w64..."
if command -v x86_64-w64-mingw32-g++ &> /dev/null; then
    MINGW_VERSION=$(x86_64-w64-mingw32-g++ --version | head -n 1)
    echo "✓ $MINGW_VERSION"
else
    echo "✗ MinGW-w64 not found"
    echo "  Install with: sudo apt-get install mingw-w64 g++-mingw-w64-x86-64 gcc-mingw-w64-x86-64"
fi
echo ""

# Check Eclipse
echo "Checking Eclipse..."
ECLIPSE_FOUND=false
ECLIPSE_PATH=""

# Check in current working directory
if [ -d "./eclipse" ] && [ -f "./eclipse/eclipse" ]; then
    ECLIPSE_FOUND=true
    ECLIPSE_PATH="./eclipse"
# Check in parent directory
elif [ -d "../eclipse" ] && [ -f "../eclipse/eclipse" ]; then
    ECLIPSE_FOUND=true
    ECLIPSE_PATH="../eclipse"
fi

if [ "$ECLIPSE_FOUND" = true ]; then
    ECLIPSE_ABS_PATH=$(cd "$ECLIPSE_PATH" && pwd)
    echo "✓ Eclipse found in $ECLIPSE_ABS_PATH"
    if [ -x "$ECLIPSE_PATH/eclipse" ]; then
        echo "  Eclipse is executable"
    else
        echo "⚠ Eclipse found but is not executable"
        echo "  Fix with: chmod +x $ECLIPSE_PATH/eclipse"
    fi
else
    echo "✗ Eclipse not found in current directory or parent directory"
    echo "  Run install_dependencies.sh to install Eclipse"
    echo "  Or download from: https://www.eclipse.org/downloads/packages/release/2025-06"
    echo "  Or: https://www.eclipse.org/downloads/packages/release/2024-06"
fi
echo ""

# Check MDE4CPP repository
echo "Checking MDE4CPP repository..."
if [ -d "MDE4CPP" ] && [ -f "MDE4CPP/setenv.default" ]; then
    echo "✓ MDE4CPP repository found"
    if [ -f "MDE4CPP/application/tools/gradlew" ]; then
        if [ -x "MDE4CPP/application/tools/gradlew" ]; then
            echo "✓ gradlew is executable"
        else
            echo "⚠ gradlew exists but is not executable"
            echo "  Fix with: chmod +x MDE4CPP/application/tools/gradlew"
        fi
    else
        echo "⚠ gradlew not found (expected after cloning)"
    fi
else
    echo "✗ MDE4CPP repository not found"
    echo "  Clone with: git clone https://github.com/MDE4CPP/MDE4CPP.git"
fi
echo ""

echo "=== Check Complete ==="