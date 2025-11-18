# Cross-Compilation Implementation Documentation

## Table of Contents

- [Executive Summary](#executive-summary)
  - [Objective](#objective)
  - [Key Achievement](#key-achievement)
  - [Result](#result)
- [Architecture Overview](#architecture-overview)
  - [Build System](#build-system)
  - [Configuration](#configuration)
  - [Build Flow](#build-flow)
- [Implementation Details](#implementation-details)
  - [3.1 Configuration Layer](#31-configuration-layer)
  - [3.2 Environment Setup](#32-environment-setup)
  - [3.3 Gradle Plugin Changes](#33-gradle-plugin-changes)
  - [3.4 Dependency Build Scripts](#34-dependency-build-scripts)
  - [3.5 CMake Template Changes](#35-cmake-template-changes)
  - [3.6 OCL Parser Manual CMakeLists](#36-ocl-parser-manual-cmakelists)
  - [3.7 Stereotype Implementation Fix](#37-stereotype-implementation-fix)
  - [3.8 Build Script Enhancement](#38-build-script-enhancement)
- [Issues Encountered and Fixes](#issues-encountered-and-fixes)
  - [Issue 1: CMake Not Detecting Cross-Compilation](#issue-1-cmake-not-detecting-cross-compilation)
  - [Issue 2: ANTLR4 DLL Import/Export Errors](#issue-2-antlr4-dll-importexport-errors)
  - [Issue 3: Missing Symbol Exports in Base Libraries](#issue-3-missing-symbol-exports-in-base-libraries)
  - [Issue 4: Stereotype Linker Errors](#issue-4-stereotype-linker-errors)
  - [Issue 5: CMake Cache Conflicts](#issue-5-cmake-cache-conflicts)
- [Testing and Verification](#testing-and-verification)
  - [Test Procedure](#test-procedure)
  - [Verification Checklist](#verification-checklist)
  - [Success Criteria](#success-criteria)
- [Usage Instructions](#usage-instructions)
  - [Prerequisites](#prerequisites)
  - [Building for Windows (Cross-Compilation)](#building-for-windows-cross-compilation)
  - [Building for Linux (Native)](#building-for-linux-native)
- [Technical Notes](#technical-notes)
  - [MinGW Toolchain](#mingw-toolchain)
  - [CMake Cross-Compilation](#cmake-cross-compilation)
  - [Windows DLL Symbol Export](#windows-dll-symbol-export)
  - [Static vs. Shared Libraries](#static-vs-shared-libraries)
  - [CMake Cache Management](#cmake-cache-management)
- [File Summary](#file-summary)
  - [Modified Files](#modified-files)
- [Conclusion](#conclusion)

---

## Executive Summary

### Objective
Enable cross-compilation from Linux to Windows, allowing the MDE4CPP project to generate Windows binaries (`.dll`, `.exe`) on a Linux build system.

### Key Achievement
A single configuration toggle (`CROSS_COMPILE_WINDOWS`) in `MDE4CPP_Generator.properties` controls the entire build target, seamlessly switching between Linux and Windows binary generation.

### Result
Successfully generates Windows binaries (`.dll`, `.exe`) on Linux using the MinGW cross-compilation toolchain, with all dependencies (ANTLR4, Xerces) properly configured for cross-compilation.

---

## Architecture Overview

### Build System
- **Gradle**: Build automation and task orchestration
- **CMake**: Build system generator for C++ projects
- **MinGW**: Cross-compilation toolchain (`x86_64-w64-mingw32-gcc/g++`)

### Configuration
- **Central Configuration**: `MDE4CPP_Generator.properties`
  - Single toggle: `CROSS_COMPILE_WINDOWS=true/false`
  - Controls compiler selection, CMake flags, and build artifacts

### Build Flow
1. **Generation**: Acceleo templates generate C++ code and CMakeLists.txt
2. **Compilation**: CMake configures build with cross-compiler settings
3. **Linking**: Static/dynamic libraries linked to produce Windows binaries

---

## Implementation Details

### 3.1 Configuration Layer

**File**: `MDE4CPP_Generator.properties`

**Change**: Added cross-compilation toggle
```properties
# Cross-compilation to Windows (only effective when building on Linux)
# Set to 'true' to generate Windows binaries (.dll, .exe) on Linux
# Set to 'false' or leave unset for normal Linux build (.so, ELF binaries)
CROSS_COMPILE_WINDOWS=true
```

**Purpose**: Central configuration point for cross-compilation mode

---

### 3.2 Environment Setup

**File**: `setenv`

**Changes**:
- Read `CROSS_COMPILE_WINDOWS` from `MDE4CPP_Generator.properties`
- Set `CC=x86_64-w64-mingw32-gcc` when cross-compilation is enabled
- Set `CXX=x86_64-w64-mingw32-g++` when cross-compilation is enabled
- Set `MAKE=make` (standard make works with cross-compilers)

**Key Code** (lines ~33-50):
```bash
# Cross-compilation to Windows configuration
# Read CROSS_COMPILE_WINDOWS from MDE4CPP_Generator.properties
if [ -f "$MDE4CPP_HOME/MDE4CPP_Generator.properties" ]; then
    CROSS_COMPILE_WINDOWS=$(grep -i "^CROSS_COMPILE_WINDOWS" "$MDE4CPP_HOME/MDE4CPP_Generator.properties" | cut -d'=' -f2 | tr -d ' ' | tr -d '\r')
fi
# Default to false if not found in file
if [ -z "$CROSS_COMPILE_WINDOWS" ]; then
    CROSS_COMPILE_WINDOWS=false
fi
# Set cross-compiler when cross-compilation is enabled
if [ "$CROSS_COMPILE_WINDOWS" = "true" ]; then
    export CC=x86_64-w64-mingw32-gcc
    export CXX=x86_64-w64-mingw32-g++
    export MAKE=make
fi
```

**Purpose**: Configure cross-compiler environment variables that CMake will detect

---

### 3.3 Gradle Plugin Changes

#### File: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/GradlePropertyAnalyser.java`

**Changes**:
- Added `isCrossCompileWindowsRequested(Project project)` method
- Reads from Gradle properties (environment variable `ORG_GRADLE_PROJECT_CROSS_COMPILE_WINDOWS`) or falls back to `MDE4CPP_Generator.properties` file

**Key Code**:
```java
/**
 * Checks if cross-compilation to Windows is requested
 *
 * @param project current project instance contains existing properties
 * @return {@code true} if cross-compilation to Windows is requested, otherwise {@code false}
 */
static boolean isCrossCompileWindowsRequested(Project project)
{
    // First check Gradle property (from ORG_GRADLE_PROJECT_CROSS_COMPILE_WINDOWS environment variable)
    if (project.hasProperty("CROSS_COMPILE_WINDOWS"))
    {
        String value = project.property("CROSS_COMPILE_WINDOWS").toString();
        return "true".equalsIgnoreCase(value.trim());
    }

    // Fall back to reading MDE4CPP_Generator.properties file
    String mde4CppRoot = System.getenv("MDE4CPP_HOME");
    if (mde4CppRoot != null && !mde4CppRoot.isEmpty())
    {
        Properties prop = new Properties();
        try
        {
            String configFilePath = mde4CppRoot + File.separator + "MDE4CPP_Generator.properties";
            File configFile = new File(configFilePath);
            if (configFile.exists())
            {
                FileInputStream stream = new FileInputStream(configFile);
                prop.load(stream);
                stream.close();
                String value = prop.getProperty("CROSS_COMPILE_WINDOWS");
                if (value != null)
                {
                    return "true".equalsIgnoreCase(value.trim());
                }
            }
        }
        catch (IOException e)
        {
            // Silently fail - properties file is optional
        }
    }

    return false;
}
```

**Purpose**: Detect cross-compilation mode in Java Gradle plugin code

---

#### File: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/CommandBuilder.java`

**Changes**:
- Modified `getCMakeCommand()` method signature to accept `Project` parameter
- Added logic to append `-DCMAKE_SYSTEM_NAME=Windows` when cross-compiling on Linux

**Key Code**:
```java
static List<String> getCMakeCommand(BUILD_MODE buildMode, File projectFolder, Project project)
{
    List<String> commandList = CommandBuilder.initialCommandList();
    String cmakeCmd = "cmake -G \"" + getCMakeGenerator() + "\" -D CMAKE_BUILD_TYPE=" + buildMode.getName();

    // Add cross-compilation flag if cross-compiling to Windows on Linux
    if (!isWindowsSystem() && GradlePropertyAnalyser.isCrossCompileWindowsRequested(project))
    {
        cmakeCmd += " -DCMAKE_SYSTEM_NAME=Windows";
    }

    cmakeCmd += " " + projectFolder.getAbsolutePath();
    commandList.add(cmakeCmd);
    return commandList;
}
```

**Purpose**: Pass cross-compilation flag to CMake to ensure correct system detection

---

#### File: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/MDE4CPPCompile.java`

**Changes**:
- Updated call to `CommandBuilder.getCMakeCommand()` to pass `Project` instance

**Key Code**:
```java
List<String> command = CommandBuilder.getCMakeCommand(buildMode, projectFolderFile, getProject());
```

**Purpose**: Enable cross-compilation detection in the compile task

---

### 3.4 Dependency Build Scripts

#### File: `src/common/persistence/build.gradle` (Xerces C++)

**Changes**:
- Read `CROSS_COMPILE_WINDOWS` from `MDE4CPP_Generator.properties`
- Add `-DCMAKE_SYSTEM_NAME=Windows` to CMake command when cross-compiling
- Use `"Unix Makefiles"` generator when cross-compiling on Linux
- Pass `CC` and `CXX` environment variables to CMake
- Copy `.dll` files to `application/lib` when cross-compiling (instead of `.so`)

**Key Code**:
```gradle
def crossCompileWindows = false
// Read CROSS_COMPILE_WINDOWS from MDE4CPP_Generator.properties
def mde4CppHome = System.getenv("MDE4CPP_HOME")
if (mde4CppHome) {
    def propsFile = new File(mde4CppHome, "MDE4CPP_Generator.properties")
    if (propsFile.exists()) {
        def props = new Properties()
        propsFile.withInputStream { props.load(it) }
        crossCompileWindows = "true".equalsIgnoreCase(props.getProperty("CROSS_COMPILE_WINDOWS", "false").trim())
    }
}

task compileXerces(type: Exec) {
    // ... existing setup ...
    
    def cmakeGenerator = crossCompileWindows ? "Unix Makefiles" : "MinGW Makefiles"
    def cmakeArgs = [
        "-G", cmakeGenerator,
        "-DCMAKE_BUILD_TYPE=Release",
        sourceDir.absolutePath
    ]
    
    if (crossCompileWindows) {
        cmakeArgs.add(0, "-DCMAKE_SYSTEM_NAME=Windows")
        environment.putAll(System.getenv())
    }
    
    commandLine cmakeArgs
    // ... rest of task ...
    
    doLast {
        if (crossCompileWindows) {
            // Copy .dll files for Windows
            copy {
                from "${buildDir}/src/xerces-c-3.2.5/Build/Windows/VC15/x64/Release"
                into "${project.rootProject.projectDir}/application/lib"
                include "*.dll"
            }
        } else {
            // Copy .so files for Linux
            // ... existing code ...
        }
    }
}
```

**Purpose**: Cross-compile Xerces C++ dependency to Windows DLL

---

#### File: `src/common/parser/build.gradle` (ANTLR4 C++ Runtime)

**Changes**:
- Read `CROSS_COMPILE_WINDOWS` from `MDE4CPP_Generator.properties`
- Add `-DCMAKE_SYSTEM_NAME=Windows` to CMake command when cross-compiling
- Add `-DANTLR_BUILD_SHARED=OFF -DANTLR_BUILD_STATIC=ON` for static library build
- Add `-DANTLR_BUILD_TESTS=OFF` to disable tests
- Use `"Unix Makefiles"` generator when cross-compiling on Linux
- Pass `CC` and `CXX` environment variables to CMake
- Copy static `.a` library when cross-compiling (instead of `.so`)
- Update output definitions for static library

**Key Code**:
```gradle
def crossCompileWindows = false
// Read CROSS_COMPILE_WINDOWS from MDE4CPP_Generator.properties
def mde4CppHome = System.getenv("MDE4CPP_HOME")
if (mde4CppHome) {
    def propsFile = new File(mde4CppHome, "MDE4CPP_Generator.properties")
    if (propsFile.exists()) {
        def props = new Properties()
        propsFile.withInputStream { props.load(it) }
        crossCompileWindows = "true".equalsIgnoreCase(props.getProperty("CROSS_COMPILE_WINDOWS", "false").trim())
    }
}

task compileAntlr4(type: Exec) {
    // ... existing setup ...
    
    def cmakeGenerator = crossCompileWindows ? "Unix Makefiles" : "MinGW Makefiles"
    def cmakeArgs = [
        "-G", cmakeGenerator,
        "-DCMAKE_BUILD_TYPE=Release",
        sourceDir.absolutePath
    ]
    
    if (crossCompileWindows) {
        cmakeArgs.add(0, "-DCMAKE_SYSTEM_NAME=Windows")
        cmakeArgs.addAll([
            "-DANTLR_BUILD_SHARED=OFF",
            "-DANTLR_BUILD_STATIC=ON",
            "-DANTLR_BUILD_TESTS=OFF"
        ])
        environment.putAll(System.getenv())
    }
    
    commandLine cmakeArgs
    // ... rest of task ...
    
    doLast {
        if (crossCompileWindows) {
            // Copy static .a library for Windows
            copy {
                from "${buildDir}/src/antlr4/runtime/Cpp/dist"
                into "${project.rootProject.projectDir}/application/lib"
                include "*.a"
            }
        } else {
            // Copy .so files for Linux
            // ... existing code ...
        }
    }
}
```

**Purpose**: Cross-compile ANTLR4 as static library to avoid DLL import/export issues

---

### 3.5 CMake Template Changes

**Files Modified**:
- `generator/ecore4CPP/ecore4CPP.generator/src/ecore4CPP/generator/main/generateBuildFile.mtl`
- `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/configuration/generateCMakeFiles.mtl`
- `generator/fUML4CPP/fUML4CPP.generator/src/fUML4CPP/generator/main/build_files/generateExecutionCMakeFile.mtl`
- `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/main_application/generateMainApplicationCMakeFile.mtl`

**Changes**:
1. **Updated Windows Detection**:
   ```cmake
   IF(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND WIN32))
       # Windows (native or cross-compiled)
       [generateCMakeFindLibraryCommands('', 'lib')/]
   ELSEIF(APPLE)
       [generateCMakeFindLibraryCommands('.dylib', 'bin')/]
   ELSEIF(UNIX)
       # Linux, BSD, Solaris, Minix
       [generateCMakeFindLibraryCommands('.so', 'bin')/]
   ELSE()
       [generateCMakeFindLibraryCommands('', 'lib')/]
   ENDIF()
   ```

2. **Added Windows Symbol Export**:
   ```cmake
   # Export all symbols for Windows DLLs (needed for cross-compilation)
   # This ensures virtual functions from base classes are visible when linking
   IF(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND WIN32))
       SET_TARGET_PROPERTIES(${PROJECT_NAME} PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS TRUE)
   ENDIF()
   ```

**Purpose**: Generate correct CMakeLists.txt that:
- Detects Windows correctly (including cross-compiled)
- Searches for `.dll` files in `lib` folder for Windows
- Exports all symbols from DLLs to ensure virtual functions are visible

---

### 3.6 OCL Parser Manual CMakeLists

**File**: `src/ocl/oclParser/CMakeLists.txt`

**Changes**:
- Updated library finding logic for Windows cross-compilation
- Look for static ANTLR4 library (`.a`) in `application/lib/` when cross-compiling
- Added `ADD_DEFINITIONS(-DANTLR4CPP_STATIC)` to ensure ANTLR4 headers use static linkage

**Key Code**:
```cmake
# Find ANTLR4 library
IF(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND WIN32))
    # Windows: Look for static library (.a) when cross-compiling
    FIND_LIBRARY(ANTLR4_LIBRARY
        NAMES antlr4-runtime
        PATHS ${CMAKE_SOURCE_DIR}/../../application/lib
        NO_DEFAULT_PATH
    )
    ADD_DEFINITIONS(-DANTLR4CPP_STATIC)
ELSE()
    # Linux: Look for shared library (.so)
    FIND_LIBRARY(ANTLR4_LIBRARY
        NAMES antlr4-runtime
        PATHS ${CMAKE_SOURCE_DIR}/../../application/lib
        NO_DEFAULT_PATH
    )
ENDIF()
```

**Purpose**: Link against static ANTLR4 library when cross-compiling to Windows

---

### 3.7 Stereotype Implementation Fix

**File**: `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/helpers/setGetHelper.mtl`

**Changes**:
- Removed `[if (not aClass.oclIsKindOf(Stereotype))]` condition that excluded Stereotype classes
- Now generates `get/set/add/remove/unset` method implementations for all classes, including Stereotypes

**Key Code** (before):
```mtl
[template public generateeGetSetImpl(aClass : Class)]
[if (not aClass.oclIsKindOf(Stereotype))]
//Get
[aClass.generateGetImplementation()/]
// ... rest of methods ...
[/if]
[/template]
```

**Key Code** (after):
```mtl
[template public generateeGetSetImpl(aClass : Class)]
//Get
[aClass.generateGetImplementation()/]

//Set
[aClass.generateSetImplementation()/]

//Add
[aClass.generateAddImplementation()/]

//Unset
[aClass.generateUnSetImplementation()/]

//Remove
[aClass.generateRemoveImplementation()/]
[/template]
```

**Purpose**: Fix linker errors for Stereotype classes (e.g., `UML4CPPProfile::DoNotGenerateImpl`) that were missing method implementations on Windows

---

### 3.8 Build Script Enhancement

**File**: `buildAll.sh`

**Changes**:
- Added `clean_cmake_cache()` function
- Removes `.cmake` directories, `CMakeCache.txt` files, `CMakeFiles` directories, and `src_gen` directories
- Explicitly preserves `application/lib` and `application/bin` directories
- Called automatically before each build

**Key Code**:
```bash
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
    
    # Similar blocks for CMakeCache.txt, CMakeFiles, and src_gen directories
    # ...
    
    if [ $cleaned_count -eq 0 ]; then
        echo "  No cache files found to clean."
    else
        echo "  Cleaned $cleaned_count cache directories/files."
    fi
    echo ""
}

# Clean CMake cache files before building
clean_cmake_cache
```

**Purpose**: Ensure fresh builds when switching between `CROSS_COMPILE_WINDOWS=true` and `false`, preventing CMake cache conflicts

---

## Issues Encountered and Fixes

### Issue 1: CMake Not Detecting Cross-Compilation

**Problem**: CMake continued to use Linux settings even when cross-compilers (`x86_64-w64-mingw32-gcc/g++`) were set via `CC`/`CXX` environment variables.

**Root Cause**: CMake needs explicit system name specification via `CMAKE_SYSTEM_NAME` for cross-compilation detection.

**Solution**: Added `-DCMAKE_SYSTEM_NAME=Windows` flag to all CMake commands when cross-compiling.

**Files Modified**:
- `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/CommandBuilder.java`
- `src/common/persistence/build.gradle`
- `src/common/parser/build.gradle`

---

### Issue 2: ANTLR4 DLL Import/Export Errors

**Problem**: ANTLR4 compilation failed with errors like:
```
error: definition of static data member 'antlr4::CommonTokenFactory::DEFAULT' of dllimport'd class
```

**Root Cause**: ANTLR4's source code has issues with DLL import/export declarations for static members when building as a shared library.

**Solution**: Build ANTLR4 as a static library (`-DANTLR_BUILD_SHARED=OFF -DANTLR_BUILD_STATIC=ON`) when cross-compiling, and link statically in dependent projects.

**Files Modified**:
- `src/common/parser/build.gradle`
- `src/ocl/oclParser/CMakeLists.txt`

---

### Issue 3: Missing Symbol Exports in Base Libraries

**Problem**: Virtual functions from base classes were not exported in Windows DLLs, causing linker errors when linking against the DLLs.

**Root Cause**: Windows DLLs require explicit symbol export declarations. Without them, virtual functions from base classes are not visible to dependent libraries.

**Solution**: Added `WINDOWS_EXPORT_ALL_SYMBOLS TRUE` CMake property to all shared library targets when building for Windows.

**Files Modified**:
- `generator/ecore4CPP/ecore4CPP.generator/src/ecore4CPP/generator/main/generateBuildFile.mtl`
- `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/configuration/generateCMakeFiles.mtl`
- `generator/fUML4CPP/fUML4CPP.generator/src/fUML4CPP/generator/main/build_files/generateExecutionCMakeFile.mtl`

---

### Issue 4: Stereotype Linker Errors

**Problem**: Linker errors for missing `get`, `set`, `add`, `remove`, `unset` method implementations in Stereotype classes (e.g., `UML4CPPProfile::DoNotGenerateImpl`).

**Root Cause**: The Acceleo template `setGetHelper.mtl` explicitly excluded Stereotype classes from method generation.

**Solution**: Removed the `[if (not aClass.oclIsKindOf(Stereotype))]` condition to ensure all classes, including Stereotypes, get method implementations.

**Files Modified**:
- `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/helpers/setGetHelper.mtl`

---

### Issue 5: CMake Cache Conflicts

**Problem**: Switching between `CROSS_COMPILE_WINDOWS=true` and `false` caused build failures due to stale CMake cache files containing incorrect compiler settings.

**Root Cause**: CMake caches configuration in `CMakeCache.txt` and `.cmake` directories. When switching build targets, the cache retains old settings.

**Solution**: Added `clean_cmake_cache()` function in `buildAll.sh` to automatically clean all CMake cache files before each build.

**Files Modified**:
- `buildAll.sh`

---

## Testing and Verification

### Test Procedure

1. **Linux Build Test**:
   ```bash
   # Set CROSS_COMPILE_WINDOWS=false in MDE4CPP_Generator.properties
   source setenv
   ./application/tools/gradlew generateAll compileAll
   # Verify: application/bin contains .so files
   ```

2. **Windows Cross-Compilation Test**:
   ```bash
   # Set CROSS_COMPILE_WINDOWS=true in MDE4CPP_Generator.properties
   source setenv
   ./application/tools/gradlew generateAll compileAll
   # Verify: application/bin contains .dll and .exe files
   ```

3. **Switch Test**:
   ```bash
   # Build Linux, then switch to Windows
   # Set CROSS_COMPILE_WINDOWS=false → build
   # Set CROSS_COMPILE_WINDOWS=true → build (should clean cache and rebuild)
   ./buildAll.sh
   ```

### Verification Checklist

- [ ] `application/bin` contains correct binary types (`.so` for Linux, `.dll`/`.exe` for Windows)
- [ ] `application/lib` contains correct library types (`.so` for Linux, `.dll`/`.a` for Windows)
- [ ] All modules compile without errors
- [ ] All modules link successfully
- [ ] No CMake cache conflicts when switching modes
- [ ] Dependencies (ANTLR4, Xerces) build correctly for target platform

### Success Criteria

- ✅ All modules compile and link successfully
- ✅ Correct binary types generated for target platform
- ✅ No linker errors or missing symbols
- ✅ Clean switching between Linux and Windows builds

---

## Usage Instructions

### Prerequisites

1. **Install MinGW Cross-Compilation Toolchain**:
   ```bash
   # On Debian/Ubuntu:
   sudo apt-get install mingw-w64
   
   # Verify installation:
   x86_64-w64-mingw32-gcc --version
   x86_64-w64-mingw32-g++ --version
   ```

2. **Set Environment**:
   ```bash
   source setenv
   ```

### Building for Windows (Cross-Compilation)

1. **Configure**:
   ```bash
   # Edit MDE4CPP_Generator.properties
   CROSS_COMPILE_WINDOWS=true
   ```

2. **Build**:
   ```bash
   # Option 1: Automated build script
   ./buildAll.sh
   
   # Option 2: Manual steps
   source setenv
   ./application/tools/gradlew generateAll
   ./application/tools/gradlew compileAll
   ./application/tools/gradlew src:buildOCLAll
   ```

3. **Verify Output**:
   ```bash
   # Check for Windows binaries
   ls -la application/bin/*.dll
   ls -la application/bin/*.exe
   ```

### Building for Linux (Native)

1. **Configure**:
   ```bash
   # Edit MDE4CPP_Generator.properties
   CROSS_COMPILE_WINDOWS=false
   ```

2. **Build**:
   ```bash
   ./buildAll.sh
   ```

3. **Verify Output**:
   ```bash
   # Check for Linux binaries
   ls -la application/bin/*.so
   ```

---

## Technical Notes

### MinGW Toolchain

- **Required Tools**: `x86_64-w64-mingw32-gcc`, `x86_64-w64-mingw32-g++`
- **Installation**: Package `mingw-w64` on Debian/Ubuntu systems
- **Purpose**: Provides Windows-compatible compiler and linker on Linux

### CMake Cross-Compilation

- **System Detection**: CMake detects cross-compilation via `CMAKE_SYSTEM_NAME=Windows` flag
- **Compiler Detection**: CMake automatically detects cross-compiler from `CC`/`CXX` environment variables
- **Generator**: Use `"Unix Makefiles"` generator when cross-compiling on Linux (not `"MinGW Makefiles"`)

### Windows DLL Symbol Export

- **Requirement**: Windows DLLs must explicitly export symbols for external linkage
- **Solution**: `WINDOWS_EXPORT_ALL_SYMBOLS TRUE` CMake property automatically exports all symbols
- **Impact**: Ensures virtual functions from base classes are visible when linking

### Static vs. Shared Libraries

- **ANTLR4**: Built as static library (`.a`) to avoid DLL import/export issues
- **Xerces**: Built as shared library (`.dll`) for Windows
- **MDE4CPP Libraries**: Built as shared libraries (`.dll`) for Windows

### CMake Cache Management

- **Problem**: CMake caches configuration, causing conflicts when switching build targets
- **Solution**: `buildAll.sh` automatically cleans cache files before each build
- **Preserved**: `application/lib` and `application/bin` are never cleaned

---

## File Summary

### Modified Files

1. **Configuration**:
   - `MDE4CPP_Generator.properties` - Added `CROSS_COMPILE_WINDOWS` toggle

2. **Environment**:
   - `setenv` - Added cross-compiler environment variable setup

3. **Gradle Plugins**:
   - `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/GradlePropertyAnalyser.java` - Added cross-compilation detection
   - `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/CommandBuilder.java` - Added CMake cross-compilation flag
   - `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/MDE4CPPCompile.java` - Updated to pass Project instance

4. **Dependency Builds**:
   - `src/common/persistence/build.gradle` - Xerces cross-compilation support
   - `src/common/parser/build.gradle` - ANTLR4 static library cross-compilation

5. **CMake Templates**:
   - `generator/ecore4CPP/ecore4CPP.generator/src/ecore4CPP/generator/main/generateBuildFile.mtl`
   - `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/configuration/generateCMakeFiles.mtl`
   - `generator/fUML4CPP/fUML4CPP.generator/src/fUML4CPP/generator/main/build_files/generateExecutionCMakeFile.mtl`
   - `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/main_application/generateMainApplicationCMakeFile.mtl`

6. **Manual CMakeLists**:
   - `src/ocl/oclParser/CMakeLists.txt` - Static ANTLR4 linking for Windows

7. **Generator Templates**:
   - `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/helpers/setGetHelper.mtl` - Stereotype method generation

8. **Build Scripts**:
   - `buildAll.sh` - Added CMake cache cleanup function

---

## Conclusion

The cross-compilation implementation successfully enables building Windows binaries (`.dll`, `.exe`) on Linux using a single configuration toggle. All dependencies are properly configured, and the build system automatically handles compiler selection, CMake configuration, and symbol export requirements. The implementation is robust, with automatic cache cleanup preventing conflicts when switching between build targets.

