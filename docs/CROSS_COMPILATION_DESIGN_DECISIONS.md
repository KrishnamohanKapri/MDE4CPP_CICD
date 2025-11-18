# Cross-Compilation Design Decisions Documentation

## Table of Contents

- [Introduction](#introduction)
- [Architecture Analysis](#architecture-analysis)
  - [2.1 Build System Architecture](#21-build-system-architecture)
  - [2.2 Key Challenge](#22-key-challenge)
- [Alternative Approaches Considered](#alternative-approaches-considered)
  - [Alternative 1: Environment Variables Only](#alternative-1-environment-variables-only)
  - [Alternative 2: Modify Templates Only](#alternative-2-modify-templates-only)
  - [Alternative 3: CMakeLists.txt Post-Processing](#alternative-3-cmakeliststxt-post-processing)
  - [Alternative 4: Separate Build Scripts](#alternative-4-separate-build-scripts)
  - [Alternative 5: Gradle Properties + Plugin Changes (CHOSEN)](#alternative-5-gradle-properties--plugin-changes-chosen)
- [Why Gradle Plugins Were Essential](#why-gradle-plugins-were-essential)
  - [4.1 The Compilation Layer Problem](#41-the-compilation-layer-problem)
  - [4.2 The Property Propagation Challenge](#42-the-property-propagation-challenge)
  - [4.3 The Template Generation Timing](#43-the-template-generation-timing)
  - [4.4 Why Not Just Environment Variables?](#44-why-not-just-environment-variables)
- [Design Decisions Breakdown](#design-decisions-breakdown)
  - [Decision 1: Store Configuration in MDE4CPP_Generator.properties](#decision-1-store-configuration-in-mde4cpp_generatorproperties)
  - [Decision 2: Read in setenv for Environment Setup](#decision-2-read-in-setenv-for-environment-setup)
  - [Decision 3: Read in Java Plugin for CMake Flags](#decision-3-read-in-java-plugin-for-cmake-flags)
  - [Decision 4: Update Templates to Check CMAKE_SYSTEM_NAME](#decision-4-update-templates-to-check-cmake_system_name)
  - [Decision 5: Add WINDOWS_EXPORT_ALL_SYMBOLS](#decision-5-add-windows_export_all_symbols)
  - [Decision 6: Build ANTLR4 as Static Library](#decision-6-build-antlr4-as-static-library)
- [Why This Approach Works](#why-this-approach-works)
  - [6.1 Single Source of Truth](#61-single-source-of-truth)
  - [6.2 Leverages Existing Infrastructure](#62-leverages-existing-infrastructure)
  - [6.3 Minimal Code Changes](#63-minimal-code-changes)
  - [6.4 Works at All Layers](#64-works-at-all-layers)
- [Trade-offs and Limitations](#trade-offs-and-limitations)
  - [Trade-off 1: Multiple Read Points](#trade-off-1-multiple-read-points)
  - [Trade-off 2: Requires Clean Builds](#trade-off-2-requires-clean-builds)
  - [Trade-off 3: Static ANTLR4 Library](#trade-off-3-static-antlr4-library)
- [Lessons Learned](#lessons-learned)
- [Future Improvements](#future-improvements)

---

## Introduction

### Problem Statement

The MDE4CPP project required the ability to cross-compile from Linux to Windows, generating Windows binaries (`.dll`, `.exe`) on a Linux build system. This capability is essential for:

- **Continuous Integration**: Building Windows binaries in Linux-based CI/CD pipelines
- **Development Efficiency**: Developers can build for multiple platforms from a single environment
- **Deployment Flexibility**: Generate platform-specific binaries without maintaining separate build environments

### Requirements

The implementation needed to meet several critical requirements:

1. **Single Toggle Control**: A single configuration setting should control the entire build target
2. **Minimal Changes**: The solution should integrate seamlessly with the existing build system
3. **First-Attempt Success**: The implementation must work correctly on the first build attempt
4. **Maintainability**: The solution should be easy to understand and maintain

### Constraints

The implementation was constrained by the existing build system architecture:

- **Gradle**: Build automation and task orchestration
- **CMake**: Build system generator for C++ projects
- **Acceleo Templates**: Model-to-text transformation for code generation
- **Java Plugins**: Custom Gradle plugins for build execution
- **Existing Infrastructure**: Must work with current project structure without major refactoring

---

## Architecture Analysis

### 2.1 Build System Architecture

The MDE4CPP build system follows a multi-layered architecture:

```
┌─────────────────────────────────────────────────────────────┐
│                    Gradle Build System                      │
│  (generateAll, compileAll, buildOCLAll tasks)              │
└───────────────────────┬─────────────────────────────────────┘
                        │
        ┌───────────────┴───────────────┐
        │                               │
┌───────▼────────┐            ┌────────▼────────┐
│  Acceleo       │            │  Java Plugin    │
│  Templates     │            │  (MDE4CPPCompile)│
│  (generateAll) │            │  (compileAll)    │
└───────┬────────┘            └────────┬────────┘
        │                               │
        │ Generates                     │ Executes
        │                               │
┌───────▼───────────────────────────────▼────────┐
│           CMakeLists.txt Files                  │
│  (Generated by templates, configured by plugin) │
└───────────────────────┬─────────────────────────┘
                        │
                        │ CMake generates
                        │
┌───────────────────────▼─────────────────────────┐
│              Make Build Files                   │
│         (Generated by CMake)                    │
└───────────────────────┬─────────────────────────┘
                        │
                        │ Make compiles
                        │
┌───────────────────────▼─────────────────────────┐
│            Binaries (.so, .dll, .exe)            │
└──────────────────────────────────────────────────┘
```

**Key Components**:

1. **Gradle**: Orchestrates the build process through tasks (`generateAll`, `compileAll`, `buildOCLAll`)
2. **Acceleo Templates**: Generate C++ source code and `CMakeLists.txt` files during `generateAll`
3. **Java Plugin (`MDE4CPPCompilePlugin`)**: Executes CMake commands during `compileAll`
   - Located in: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/`
   - Key classes: `MDE4CPPCompile.java`, `CommandBuilder.java`, `GradlePropertyAnalyser.java`
4. **CMake**: Generates platform-specific build files (Makefiles, Visual Studio projects, etc.)
5. **Make**: Compiles and links C++ code to produce binaries

**Build Flow**:
1. **Generation Phase** (`generateAll`): Acceleo templates generate C++ code and `CMakeLists.txt` files
2. **Compilation Phase** (`compileAll`): Java plugin executes CMake to configure and build projects
3. **Linking Phase**: CMake/Make links object files into shared libraries or executables

### 2.2 Key Challenge

The primary challenge was that CMake configuration occurs at **two distinct points** in the build process:

1. **Template Generation Time** (during `generateAll`):
   - Acceleo templates generate `CMakeLists.txt` files
   - Templates need to know the target platform to generate correct platform-specific logic
   - Example: Windows needs `.dll` file extensions, Linux needs `.so`

2. **Compilation Time** (during `compileAll`):
   - Java plugin constructs and executes CMake commands
   - CMake needs explicit flags to detect cross-compilation
   - Example: `-DCMAKE_SYSTEM_NAME=Windows` flag must be passed to CMake

**The Problem**: These two phases are separated, and information must flow from configuration → templates → plugin → CMake.

**The Solution**: A single configuration property (`CROSS_COMPILE_WINDOWS`) is read at multiple points:
- In `setenv` for environment setup (compiler selection)
- In Java plugin for CMake flag injection
- In templates (indirectly, via `CMAKE_SYSTEM_NAME` set by plugin)

---

## Alternative Approaches Considered

### Alternative 1: Environment Variables Only

**Approach**: Set `CC`, `CXX`, and `CMAKE_SYSTEM_NAME` environment variables in `setenv` only, relying on CMake's automatic detection.

**Implementation**:
```bash
# In setenv
export CC=x86_64-w64-mingw32-gcc
export CXX=x86_64-w64-mingw32-g++
export CMAKE_SYSTEM_NAME=Windows
```

**Pros**:
- Simple: No code changes required
- Minimal: Only environment setup needed
- Standard: Uses standard CMake cross-compilation approach

**Cons**:
- **CMake Detection Issues**: CMake's automatic cross-compilation detection is unreliable
  - CMake may not correctly identify Windows as the target system
  - May still generate Linux-specific build files
- **Template Generation**: Templates still generate Linux-specific `CMakeLists.txt`
  - Templates check `WIN32` variable, which is not set during cross-compilation
  - Generated files would have incorrect library extensions (`.so` instead of `.dll`)
- **No Conditional Logic**: Templates cannot conditionally generate Windows-specific code
  - Cannot add `WINDOWS_EXPORT_ALL_SYMBOLS` property
  - Cannot adjust library search paths for Windows

**Why Rejected**: Insufficient for the requirements. While environment variables work for compiler selection, they do not solve the template generation problem or ensure reliable CMake cross-compilation detection.

---

### Alternative 2: Modify Templates Only

**Approach**: Pass cross-compilation flag directly to Acceleo templates, allowing them to generate Windows-specific `CMakeLists.txt` from the start.

**Implementation**:
- Modify template engine to accept `CROSS_COMPILE_WINDOWS` property
- Templates check this property and generate Windows-specific code
- Example: `[if (isCrossCompileWindows)] ... [/if]`

**Pros**:
- **Correct Generation**: Templates generate correct `CMakeLists.txt` for Windows
- **Early Detection**: Platform is known at generation time
- **Clean Separation**: Generation logic handles platform differences

**Cons**:
- **Template Engine Changes**: Requires modifications to Acceleo template engine
  - Not a standard feature of Acceleo
  - Would require custom template engine extensions
- **Regeneration Required**: Changing the flag requires re-running `generateAll`
  - Cannot dynamically switch without regeneration
  - Defeats the purpose of a single toggle
- **Timing Issue**: Templates run before compilation, but CMake configuration happens during compilation
  - Still need to pass flags to CMake command
  - Does not solve the CMake command-line flag problem

**Why Rejected**: Too invasive and does not solve the complete problem. Would require template engine modifications and still leaves the CMake command-line flag issue unresolved.

---

### Alternative 3: CMakeLists.txt Post-Processing

**Approach**: Generate `CMakeLists.txt` files normally, then use scripts to modify them after generation to add Windows-specific logic.

**Implementation**:
```bash
# After generateAll
find . -name "CMakeLists.txt" -exec sed -i 's/\.so/.dll/g' {} \;
# Add Windows-specific properties via script
```

**Pros**:
- **No Template Changes**: Templates remain unchanged
- **Simple Concept**: Easy to understand the approach
- **Flexible**: Can modify any part of generated files

**Cons**:
- **Fragile**: String replacement is error-prone
  - May replace `.so` in comments or strings
  - Difficult to handle complex CMake logic
- **Maintenance Nightmare**: Scripts must be updated for every template change
  - Templates and scripts can drift out of sync
  - Hard to debug when things go wrong
- **Doesn't Solve Root Problem**: Still need to pass `-DCMAKE_SYSTEM_NAME=Windows` to CMake
  - Post-processing doesn't help with CMake command-line flags
  - CMake cache may still have incorrect settings

**Why Rejected**: Maintenance burden is too high, and it doesn't address the fundamental issue of CMake configuration.

---

### Alternative 4: Separate Build Scripts

**Approach**: Create separate Gradle tasks for cross-compilation (e.g., `generateAllWindows`, `compileAllWindows`), duplicating the build logic.

**Implementation**:
```gradle
task generateAllWindows {
    // Same as generateAll but with Windows flag
}

task compileAllWindows {
    // Same as compileAll but with Windows settings
}
```

**Pros**:
- **Clear Separation**: Explicit distinction between Linux and Windows builds
- **Easy to Understand**: Each task has a clear purpose
- **No Conditional Logic**: No need for if/else in build scripts

**Cons**:
- **Code Duplication**: Build logic must be duplicated
  - Violates DRY (Don't Repeat Yourself) principle
  - Changes must be made in multiple places
- **Maintenance Burden**: Two build paths to maintain
  - Bug fixes must be applied twice
  - Feature additions require updates to both paths
- **Doesn't Solve Template Issue**: Templates still need to know the target platform
  - Would still require template modifications
  - Or post-processing (see Alternative 3)

**Why Rejected**: Violates software engineering principles (DRY) and increases long-term maintenance costs without solving the core problem.

---

### Alternative 5: Gradle Properties + Plugin Changes (CHOSEN)

**Approach**: Store the cross-compilation setting in `MDE4CPP_Generator.properties`, read it in multiple places (`setenv`, Java plugin, build scripts), and pass the information through all layers of the build system.

**Implementation Overview**:

1. **Configuration Storage**: `MDE4CPP_Generator.properties`
   ```properties
   CROSS_COMPILE_WINDOWS=true
   ```

2. **Environment Setup**: `setenv` reads property and sets compiler
   ```bash
   if [ "$CROSS_COMPILE_WINDOWS" = "true" ]; then
       export CC=x86_64-w64-mingw32-gcc
       export CXX=x86_64-w64-mingw32-g++
   fi
   ```

3. **Plugin Detection**: Java plugin reads property and adds CMake flag
   ```java
   if (isCrossCompileWindowsRequested(project)) {
       cmakeCmd += " -DCMAKE_SYSTEM_NAME=Windows";
   }
   ```

4. **Template Logic**: Templates check `CMAKE_SYSTEM_NAME` (set by plugin)
   ```cmake
   IF(CMAKE_SYSTEM_NAME STREQUAL "Windows")
       # Windows-specific logic
   ENDIF()
   ```

**Pros**:
- **Single Source of Truth**: One configuration file controls everything
- **Works at All Layers**: Environment, plugin, templates all use the same setting
- **Minimal Code Changes**: Leverages existing infrastructure
- **Leverages Existing Mechanisms**: Uses property reading, CMake variables, etc.
- **Maintainable**: Clear flow of information through the system

**Cons**:
- **Multiple Read Points**: Configuration is read in several places
  - Mitigation: Single source of truth prevents drift
- **Requires Consistency**: All components must read the same property
  - Mitigation: Clear documentation and code structure

**Why Chosen**: Best balance of simplicity, effectiveness, and maintainability. Solves all aspects of the problem while minimizing code changes and leveraging existing infrastructure.

---

## Why Gradle Plugins Were Essential

### 4.1 The Compilation Layer Problem

**The Issue**: CMake commands are constructed dynamically in Java code during the compilation phase, not during template generation.

**Location**: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/CommandBuilder.java`

**Original Code** (before changes):
```java
static List<String> getCMakeCommand(BUILD_MODE buildMode, File projectFolder)
{
    List<String> commandList = CommandBuilder.initialCommandList();
    String cmakeCmd = "cmake -G \"" + getCMakeGenerator() + "\" -D CMAKE_BUILD_TYPE=" + buildMode.getName();
    cmakeCmd += " " + projectFolder.getAbsolutePath();
    commandList.add(cmakeCmd);
    return commandList;
}
```

**Problem**: The CMake command is constructed here, but there's no way to add the `-DCMAKE_SYSTEM_NAME=Windows` flag without modifying this code.

**Why Plugins Are Essential**:
- **Runtime Construction**: CMake commands are built at runtime, not from templates
- **Dynamic Configuration**: The plugin can read configuration and adjust commands accordingly
- **Single Point of Control**: All CMake invocations go through this method
- **Proper Timing**: Happens during `compileAll`, when CMake is actually executed

**Solution**: Modified the method to accept `Project` parameter and check for cross-compilation:
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

**Impact**: Without this plugin change, CMake would never receive the `-DCMAKE_SYSTEM_NAME=Windows` flag, and cross-compilation detection would fail.

---

### 4.2 The Property Propagation Challenge

**The Issue**: Gradle properties can come from multiple sources, but we need to read from `MDE4CPP_Generator.properties`, which is not a standard Gradle properties file.

**Gradle Property Sources**:
1. Environment variables: `ORG_GRADLE_PROJECT_CROSS_COMPILE_WINDOWS=true`
2. Gradle properties files: `gradle.properties`
3. Command-line: `-PCROSS_COMPILE_WINDOWS=true`

**Our Requirement**: Read from `MDE4CPP_Generator.properties` (generator configuration file, not Gradle properties).

**Why Plugins Are Essential**:
- **Direct File Access**: Java code can read any file, not just Gradle properties
- **Flexible Reading**: Can implement custom property reading logic
- **Fallback Support**: Can check Gradle properties first, then fall back to file

**Solution**: `GradlePropertyAnalyser.isCrossCompileWindowsRequested()` method:

```java
static boolean isCrossCompileWindowsRequested(Project project)
{
    // First check Gradle property (from ORG_GRADLE_PROJECT_CROSS_COMPILE_WINDOWS)
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

**Benefits**:
- Supports both Gradle properties and file-based configuration
- Provides fallback mechanism
- Centralized property reading logic

---

### 4.3 The Template Generation Timing

**The Issue**: Templates run during `generateAll` (before compilation), but they need to generate Windows-specific `CMakeLists.txt` code. However, the cross-compilation flag is only known at compilation time.

**Timeline**:
1. `generateAll` runs → Templates generate `CMakeLists.txt`
2. `compileAll` runs → Plugin executes CMake with `-DCMAKE_SYSTEM_NAME=Windows`
3. CMake processes `CMakeLists.txt` → Checks `CMAKE_SYSTEM_NAME` variable

**Why This Works**:
- Templates generate **conditional** CMake code that checks `CMAKE_SYSTEM_NAME`
- The variable is set by the plugin via `-DCMAKE_SYSTEM_NAME=Windows` flag
- CMake evaluates the condition at configuration time (during `compileAll`)

**Template Code** (example from `generateBuildFile.mtl`):
```cmake
IF(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND WIN32))
    # Windows (native or cross-compiled)
    [generateCMakeFindLibraryCommands('', 'lib')/]
ELSEIF(APPLE)
    [generateCMakeFindLibraryCommands('.dylib', 'bin')/]
ELSEIF(UNIX)
    # Linux, BSD, Solaris, Minix
    [generateCMakeFindLibraryCommands('.so', 'bin')/]
ENDIF()
```

**Why Plugins Are Essential**:
- **Flag Injection**: Plugin adds `-DCMAKE_SYSTEM_NAME=Windows` to CMake command
- **Variable Setting**: This sets the variable that templates check
- **Timing**: Plugin runs at the right time (during compilation) to set the variable

**Alternative (Why It Doesn't Work)**: If we tried to pass the flag to templates during generation:
- Templates would need to know the target platform at generation time
- Would require template engine modifications
- Would require regeneration when switching modes

**Our Solution**: Templates generate conditional code, plugin sets the condition variable, CMake evaluates the condition. This decouples generation from compilation.

---

### 4.4 Why Not Just Environment Variables?

**The Question**: Why not just set `CMAKE_SYSTEM_NAME` as an environment variable in `setenv`?

**Attempted Approach**:
```bash
# In setenv
export CMAKE_SYSTEM_NAME=Windows
```

**Why It Doesn't Work**:
1. **CMake Doesn't Read It**: CMake does not automatically read `CMAKE_SYSTEM_NAME` from environment variables
2. **Must Be Command-Line Flag**: CMake only recognizes `CMAKE_SYSTEM_NAME` when passed as `-DCMAKE_SYSTEM_NAME=Windows`
3. **Plugin Constructs Command**: The CMake command is built in Java code, so the flag must be added there

**Evidence**: CMake documentation states that `CMAKE_SYSTEM_NAME` must be set via `-D` flag or in a toolchain file, not via environment variables.

**Why Plugins Are Essential**:
- **Command Construction**: Only the plugin can add the `-D` flag to the CMake command
- **Proper Format**: Plugin ensures the flag is in the correct format
- **Guaranteed Execution**: Flag is always added when cross-compiling

**Solution**: Plugin adds `-DCMAKE_SYSTEM_NAME=Windows` to the CMake command line, ensuring CMake correctly detects cross-compilation.

---

## Design Decisions Breakdown

### Decision 1: Store Configuration in MDE4CPP_Generator.properties

**Rationale**:
- **Consistency**: The file already exists for generator configuration
- **Discoverability**: Developers expect generator settings in this file
- **Centralization**: All generator-related configuration in one place
- **Simplicity**: No need to create a new configuration file

**File Location**: `MDE4CPP_Generator.properties`

**Implementation**:
```properties
# Cross-compilation to Windows (only effective when building on Linux)
# Set to 'true' to generate Windows binaries (.dll, .exe) on Linux
# Set to 'false' or leave unset for normal Linux build (.so, ELF binaries)
CROSS_COMPILE_WINDOWS=true
```

**Alternative Considered**: Gradle properties file (`gradle.properties`)

**Why Rejected**:
- Less discoverable (generator config belongs with generators)
- Would require developers to look in multiple places
- Inconsistent with existing project structure

**Impact**: This decision ensures the configuration is easy to find and modify, and fits naturally into the existing project structure.

---

### Decision 2: Read in setenv for Environment Setup

**Rationale**:
- **Early Setup**: `setenv` runs before any build steps, ensuring environment is ready
- **Natural Location**: `setenv` already sets up build environment variables
- **Compiler Selection**: `CC` and `CXX` must be set before CMake runs
- **Standard Practice**: Environment variables are the standard way to select compilers

**File Location**: `setenv` (lines ~33-50)

**Implementation**:
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

**Alternative Considered**: Set compiler in build scripts only

**Why Rejected**:
- Too late: CMake may have already detected the wrong compiler
- Inconsistent: Different build scripts would need to set it
- Error-prone: Easy to forget in some scripts

**Impact**: This ensures the cross-compiler is selected before any build tool runs, preventing incorrect compiler detection.

---

### Decision 3: Read in Java Plugin for CMake Flags

**Rationale**:
- **Command Construction**: Plugin builds CMake commands, so it's the only place to add flags
- **Proper Timing**: Happens during compilation, when CMake is executed
- **Single Point**: All CMake invocations go through the plugin
- **Direct Control**: Can ensure the flag is always added when needed

**File Location**: `gradlePlugins/MDE4CPPCompilePlugin/src/tui/sse/mde4cpp/CommandBuilder.java`

**Implementation**:
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

**Alternative Considered**: Pass via Gradle properties (`ORG_GRADLE_PROJECT_CROSS_COMPILE_WINDOWS`)

**Why Rejected**:
- Would require `setenv` to set environment variable
- Less discoverable (hidden in environment)
- Single source of truth is better (read from file directly)

**Impact**: This ensures CMake receives the critical `-DCMAKE_SYSTEM_NAME=Windows` flag, enabling proper cross-compilation detection.

---

### Decision 4: Update Templates to Check CMAKE_SYSTEM_NAME

**Rationale**:
- **CMake Variable**: `CMAKE_SYSTEM_NAME` is set by the plugin, available at CMake configuration time
- **Conditional Logic**: Templates can generate platform-specific code based on this variable
- **Decoupling**: Generation and compilation are decoupled (templates don't need to know target at generation time)
- **Standard Practice**: Using CMake variables for platform detection is standard

**File Locations**:
- `generator/ecore4CPP/ecore4CPP.generator/src/ecore4CPP/generator/main/generateBuildFile.mtl`
- `generator/UML4CPP/UML4CPP.generator/src/UML4CPP/generator/main/configuration/generateCMakeFiles.mtl`
- `generator/fUML4CPP/fUML4CPP.generator/src/fUML4CPP/generator/main/build_files/generateExecutionCMakeFile.mtl`

**Implementation**:
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

**Alternative Considered**: Generate different templates based on property at generation time

**Why Rejected**:
- Would require template engine modifications
- Would require regeneration when switching modes
- More complex than conditional CMake code

**Impact**: This allows templates to generate correct platform-specific code without needing to know the target platform at generation time.

---

### Decision 5: Add WINDOWS_EXPORT_ALL_SYMBOLS

**Rationale**:
- **Windows Requirement**: Windows DLLs require explicit symbol export for external linkage
- **Virtual Functions**: Virtual functions from base classes must be exported
- **CMake Property**: CMake provides automatic symbol export via this property
- **Minimal Changes**: No need to modify source code with `__declspec(dllexport)`

**File Locations**: All CMake generator templates

**Implementation**:
```cmake
# Export all symbols for Windows DLLs (needed for cross-compilation)
# This ensures virtual functions from base classes are visible when linking
IF(CMAKE_SYSTEM_NAME STREQUAL "Windows" OR (NOT CMAKE_SYSTEM_NAME AND WIN32))
    SET_TARGET_PROPERTIES(${PROJECT_NAME} PROPERTIES WINDOWS_EXPORT_ALL_SYMBOLS TRUE)
ENDIF()
```

**Alternative Considered**: Manual `__declspec(dllexport)` annotations in source code

**Why Rejected**:
- **Too Invasive**: Would require changes to all source files
- **Maintenance Burden**: Every new class would need annotations
- **Error-Prone**: Easy to forget annotations, causing linker errors
- **Platform-Specific**: Would pollute code with Windows-specific macros

**Impact**: This ensures all symbols are exported from Windows DLLs automatically, preventing linker errors for virtual functions.

---

### Decision 6: Build ANTLR4 as Static Library

**Rationale**:
- **DLL Issues**: ANTLR4 has DLL import/export problems with MinGW cross-compiler
- **Static Linking**: Static libraries avoid symbol visibility issues
- **Simpler**: No need to manage DLL dependencies
- **Proven Solution**: Static linking is a common workaround for cross-compilation issues

**File Location**: `src/common/parser/build.gradle`

**Implementation**:
```gradle
if (crossCompileWindows) {
    cmakeArgs.add(0, "-DCMAKE_SYSTEM_NAME=Windows")
    cmakeArgs.addAll([
        "-DANTLR_BUILD_SHARED=OFF",
        "-DANTLR_BUILD_STATIC=ON",
        "-DANTLR_BUILD_TESTS=OFF"
    ])
    environment.putAll(System.getenv())
}
```

**Alternative Considered**: Fix ANTLR4 source code to properly handle DLL import/export

**Why Rejected**:
- **Third-Party Library**: Would require patching external dependency
- **Maintenance Burden**: Patches must be maintained across ANTLR4 updates
- **Complexity**: DLL import/export fixes are non-trivial
- **Risk**: Modifying third-party code increases risk of bugs

**Impact**: This avoids DLL issues entirely by using static linking, which is simpler and more reliable for cross-compilation.

---

## Why This Approach Works

### 6.1 Single Source of Truth

**Principle**: One configuration file (`MDE4CPP_Generator.properties`) controls the entire build target.

**Implementation**:
- Configuration stored in: `MDE4CPP_Generator.properties`
- Read by: `setenv`, Java plugin, dependency build scripts
- Result: No synchronization issues, no conflicting settings

**Benefits**:
- **Consistency**: All components read the same value
- **Simplicity**: One place to change the setting
- **Reliability**: No risk of configuration drift

**Example Flow**:
```
MDE4CPP_Generator.properties (CROSS_COMPILE_WINDOWS=true)
    ↓
setenv (sets CC, CXX)
    ↓
Java Plugin (adds -DCMAKE_SYSTEM_NAME=Windows)
    ↓
CMake (detects Windows, sets CMAKE_SYSTEM_NAME)
    ↓
Templates (check CMAKE_SYSTEM_NAME, generate Windows code)
```

---

### 6.2 Leverages Existing Infrastructure

**Principle**: Use existing mechanisms rather than creating new ones.

**Existing Mechanisms Used**:
1. **Property Files**: `MDE4CPP_Generator.properties` already exists
2. **Environment Variables**: `setenv` already sets up environment
3. **CMake Variables**: Templates already check platform variables
4. **Plugin Architecture**: Java plugins already construct CMake commands

**Benefits**:
- **Minimal Changes**: Only small modifications needed
- **Familiar**: Developers already understand these mechanisms
- **Maintainable**: Uses well-established patterns

**Code Changes Summary**:
- 3 Java files modified in plugin (minimal changes)
- Templates updated with Windows detection (extended existing platform checks)
- Dependency build scripts updated (necessary for cross-compilation)

---

### 6.3 Minimal Code Changes

**Principle**: Make the smallest changes necessary to achieve the goal.

**Changes Made**:

1. **GradlePropertyAnalyser.java**: Added one method (~40 lines)
2. **CommandBuilder.java**: Modified one method signature, added 3 lines
3. **MDE4CPPCompile.java**: Updated one method call (1 line)
4. **Templates**: Extended existing platform checks (few lines each)
5. **Build Scripts**: Added cross-compilation logic (necessary for dependencies)

**Total Impact**:
- **Java Code**: ~50 lines added/modified
- **Templates**: ~10 lines per template (4 templates)
- **Build Scripts**: ~30 lines per script (2 scripts)
- **Configuration**: 3 lines added

**Comparison to Alternatives**:
- Alternative 2 (Template Engine): Would require hundreds of lines
- Alternative 3 (Post-Processing): Would require complex scripts
- Alternative 4 (Separate Scripts): Would duplicate entire build logic

---

### 6.4 Works at All Layers

**Principle**: The solution addresses every layer of the build system.

**Layer Coverage**:

1. **Configuration Layer**: `MDE4CPP_Generator.properties` stores the setting
2. **Environment Layer**: `setenv` sets compiler environment variables
3. **Plugin Layer**: Java plugin adds CMake flags
4. **Template Layer**: Templates generate conditional CMake code
5. **CMake Layer**: CMake detects cross-compilation and configures build
6. **Compilation Layer**: Make compiles with cross-compiler

**Why This Matters**:
- **Complete Solution**: No gaps in the implementation
- **Reliable**: Each layer handles its responsibility
- **Maintainable**: Clear separation of concerns

**Flow Diagram**:
```
Configuration (MDE4CPP_Generator.properties)
    ↓
Environment (setenv: CC, CXX)
    ↓
Plugin (CommandBuilder: -DCMAKE_SYSTEM_NAME=Windows)
    ↓
CMake (CMAKE_SYSTEM_NAME=Windows)
    ↓
Templates (IF(CMAKE_SYSTEM_NAME STREQUAL "Windows"))
    ↓
Build (Windows binaries)
```

---

## Trade-offs and Limitations

### Trade-off 1: Multiple Read Points

**The Trade-off**: Configuration is read in multiple places (`setenv`, Java plugin, build scripts), rather than a single read point.

**Why It Exists**: Different components need the configuration at different times and in different formats:
- `setenv` needs it early (before Gradle starts) for environment setup
- Java plugin needs it during compilation for CMake flags
- Build scripts need it for dependency compilation

**Mitigation**:
- **Single Source of Truth**: All read from the same file
- **Clear Documentation**: Documented where and why each read happens
- **Consistent Reading**: All use the same property name

**Impact**: Low risk, as long as all components read from the same source.

---

### Trade-off 2: Requires Clean Builds

**The Trade-off**: Switching between `CROSS_COMPILE_WINDOWS=true` and `false` requires cleaning CMake cache files, or builds may fail.

**Why It Exists**: CMake caches configuration in `CMakeCache.txt` and `.cmake` directories. When switching build targets, the cache retains old settings (compiler paths, system detection, etc.).

**Mitigation**:
- **Automatic Cleanup**: `buildAll.sh` automatically cleans cache files before each build
- **Documentation**: Clear instructions on when to clean
- **Script Enhancement**: Cleanup function is built into the build script

**Impact**: Low impact, as cleanup is automated. Users just need to run `buildAll.sh` instead of individual commands.

---

### Trade-off 3: Static ANTLR4 Library

**The Trade-off**: ANTLR4 must be built as a static library when cross-compiling, even though it could be shared on native Windows.

**Why It Exists**: ANTLR4 has DLL import/export issues with MinGW cross-compiler. Static linking avoids these issues entirely.

**Mitigation**:
- **Only Affects Cross-Compilation**: Native Windows builds can still use shared libraries
- **No Functional Impact**: Static vs. shared doesn't affect functionality
- **Simpler**: Static linking is simpler for cross-compilation

**Impact**: Minimal. Static linking works fine, and only affects cross-compilation builds.

---

## Lessons Learned

### 1. CMake Cross-Compilation Requires Explicit Flag

**Lesson**: CMake's automatic cross-compilation detection is unreliable. The `-DCMAKE_SYSTEM_NAME=Windows` flag must be explicitly passed.

**Why**: CMake uses `CMAKE_SYSTEM_NAME` to determine the target platform. Without this flag, CMake may incorrectly detect the host platform (Linux) as the target.

**Application**: Always pass `-DCMAKE_SYSTEM_NAME=<target>` when cross-compiling, even if `CC` and `CXX` are set.

---

### 2. Windows DLL Symbol Export is Critical

**Lesson**: Windows DLLs require explicit symbol export for external linkage. Virtual functions from base classes must be exported.

**Why**: Windows DLLs use a different linking model than Linux shared libraries. Without explicit exports, symbols are not visible to dependent libraries.

**Application**: Use `WINDOWS_EXPORT_ALL_SYMBOLS TRUE` CMake property for Windows DLLs, or manually export symbols with `__declspec(dllexport)`.

---

### 3. Static Libraries Are Simpler for Cross-Compilation

**Lesson**: Static libraries avoid DLL import/export issues and are simpler to manage in cross-compilation scenarios.

**Why**: Static linking doesn't require symbol visibility management, and avoids platform-specific DLL issues.

**Application**: Consider static libraries for third-party dependencies when cross-compiling, especially if they have DLL issues.

---

### 4. Single Source of Truth Prevents Configuration Drift

**Lesson**: Having one configuration file that all components read prevents synchronization issues and configuration drift.

**Why**: Multiple configuration sources can get out of sync, causing hard-to-debug build failures.

**Application**: Always use a single source of truth for build configuration, even if it means reading it in multiple places.

---

### 5. Plugin Layer is the Right Place for Build-Time Decisions

**Lesson**: Build-time decisions (like adding CMake flags) should be made in the plugin layer, not in templates or scripts.

**Why**: Plugins execute at the right time (during compilation), have access to configuration, and can dynamically adjust build commands.

**Application**: Use plugins for dynamic build configuration, templates for static code generation.

---

## Future Improvements

### 1. CMake Toolchain Files

**Improvement**: Use CMake toolchain files for cleaner cross-compilation configuration.

**Benefits**:
- Centralized cross-compilation settings
- Standard CMake approach
- Easier to maintain

**Implementation**: Create `cmake/toolchain-mingw.cmake` with cross-compilation settings, pass via `-DCMAKE_TOOLCHAIN_FILE`.

---

### 2. MinGW Installation Validation

**Improvement**: Add validation to ensure MinGW cross-compiler is installed before attempting cross-compilation.

**Benefits**:
- Early error detection
- Clear error messages
- Better user experience

**Implementation**: Check for `x86_64-w64-mingw32-gcc` in `PATH` when `CROSS_COMPILE_WINDOWS=true`.

---

### 3. Build Mode Detection

**Improvement**: Detect mixed build modes (some projects built for Linux, some for Windows) and warn or prevent.

**Benefits**:
- Prevents accidental mixed builds
- Clear error messages
- Better build reliability

**Implementation**: Check `CMakeCache.txt` files for `CMAKE_SYSTEM_NAME` and compare with current setting.

---

### 4. Template Property Passing

**Improvement**: Pass `CROSS_COMPILE_WINDOWS` directly to templates during generation, allowing templates to generate platform-specific code at generation time.

**Benefits**:
- Templates can generate correct code from the start
- No need for conditional CMake code
- Cleaner generated files

**Implementation**: Extend Acceleo template engine to accept properties, or use template parameters.

---

### 5. Automated Testing

**Improvement**: Add automated tests that verify cross-compilation works correctly.

**Benefits**:
- Catches regressions early
- Validates implementation
- Builds confidence

**Implementation**: CI/CD pipeline that builds for both Linux and Windows, verifies binary types.

---

## Conclusion

The chosen approach—using Gradle properties with plugin changes—provides the best balance of simplicity, effectiveness, and maintainability. By leveraging existing infrastructure and making minimal code changes, we achieved a robust cross-compilation solution that works at all layers of the build system.

The key insight was recognizing that the plugin layer is the right place for build-time decisions, allowing us to inject CMake flags dynamically while keeping templates and configuration simple. This approach ensures the solution is maintainable, extensible, and aligned with software engineering best practices.

