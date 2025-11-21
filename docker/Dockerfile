# Multi-stage Dockerfile for MDE4CPP
# Based on verified setup commands from Debian 13

# ============================================================================
# Stage 1: Base Dependencies
# ============================================================================
FROM eclipse-temurin:21-jdk-jammy AS base

# Install minimal dependencies needed to run install_dependencies.sh
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    sudo \
    git \
    && rm -rf /var/lib/apt/lists/*

# Set JAVA_HOME for JDK 21 (already in base image)
ENV JAVA_HOME=/opt/java/openjdk

# ============================================================================
# Stage 2: Install Dependencies
# ============================================================================
FROM base AS dependencies

# Create user and project directory structure
RUN useradd -u 1000 -m -d /home/mde4cpp mde4cpp \
    && mkdir -p /home/mde4cpp \
    && chown -R mde4cpp:mde4cpp /home/mde4cpp

# Switch to root to run install_dependencies.sh (it needs root for system packages)
USER root

WORKDIR /home/mde4cpp

# Clone MDE4CPP Cross-Compilation repository
RUN git clone -b main https://github.com/KrishnamohanKapri/MDE4CPP_CICD.git /tmp/mde4cpp-repo && \
    bash -c 'shopt -s dotglob && mv /tmp/mde4cpp-repo/* /home/mde4cpp/' && \
    rmdir /tmp/mde4cpp-repo

# Make install script executable
RUN cd /home/mde4cpp && chmod +x ./install_dependencies.sh

# Run install_dependencies.sh as root (it will detect root and install system packages)
# The script will install Eclipse in user space (/home/mde4cpp/eclipse)
RUN cd /home/mde4cpp && ./install_dependencies.sh

# Verify Eclipse and plugins are installed correctly
RUN echo "Verifying Eclipse installation..." && \
    if [ ! -f /home/mde4cpp/eclipse/eclipse ]; then \
        echo "ERROR: Eclipse not found!"; \
        exit 1; \
    fi && \
    if [ ! -d /home/mde4cpp/eclipse/plugins ]; then \
        echo "ERROR: Eclipse plugins directory not found!"; \
        exit 1; \
    fi && \
    REQUIRED_PLUGINS="org.eclipse.acceleo.common org.eclipse.emf.ecore org.eclipse.uml2.uml org.eclipse.ocl" && \
    MISSING=0 && \
    for plugin in $REQUIRED_PLUGINS; do \
        if ! ls /home/mde4cpp/eclipse/plugins/${plugin}_*.jar 1>/dev/null 2>&1; then \
            echo "ERROR: Required plugin $plugin not found!"; \
            MISSING=1; \
        fi; \
    done && \
    if [ $MISSING -eq 1 ]; then \
        echo "ERROR: Some required Eclipse plugins are missing!"; \
        exit 1; \
    fi && \
    echo "✓ Eclipse and plugins verified"

# Set up environment variables (verified values)
ENV MDE4CPP_HOME=/home/mde4cpp \
    MDE4CPP_ECLIPSE_HOME=/home/mde4cpp/eclipse \
    JAVA_HOME=/opt/java/openjdk \
    PATH="/home/mde4cpp/application/bin:/home/mde4cpp/application/tools:${PATH}"

# Create setenv script with cross-compilation support using heredoc
RUN cat > /home/mde4cpp/setenv << 'EOF'
#!/bin/bash

# ########################################
# # Environment configuration of MDE4CPP #
# ########################################
# path to MDE4CPP home folder
export MDE4CPP_HOME=/home/mde4cpp

# path to eclipse home folder including Acceleo plugins
# required for creating the generators
export MDE4CPP_ECLIPSE_HOME=/home/mde4cpp/eclipse

# ##################################################
# # configure Gradle tasks and compiling processes #
# ##################################################
# enable parallel execution of Gradle tasks permanently with value 'true', otherwise 'false'
export GRADLE_OPTS=-Dorg.gradle.parallel=true

# configure count of worker for each compile task 
# (if two compiling tasks are performed in parallel, 2 x WORKER processes are executed)
export ORG_GRADLE_PROJECT_WORKER=3

# release version will be compiled with value unequal '0' or if ORG_GRADLE_PROJECT_RELEASE and ORG_GRADLE_PROJECT_DEBUG are undefined
export ORG_GRADLE_PROJECT_RELEASE=1

# debug version will be compiled with value unequal '0' or if ORG_GRADLE_PROJECT_RELEASE and ORG_GRADLE_PROJECT_DEBUG are undefined
export ORG_GRADLE_PROJECT_DEBUG=0

# debug messages of fUML library will be enabled with value '1', this property has no effect on release compiling
export ORG_GRADLE_PROJECT_DEBUG_MESSAGE_FUML=0

# Cross-compilation to Windows configuration
# Read CROSS_COMPILE_WINDOWS from MDE4CPP_Generator.properties
# Always read from file to ensure it matches the current configuration
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
    # Note: We use regular 'make' even for cross-compilation (x86_64-w64-mingw32-make may not be installed)
    # The important part is that CC and CXX point to the cross-compilers
    export MAKE=make
fi

# update the PATH variable locally to be able to call the executable and scripts from all subfolders
export PATH="$MDE4CPP_HOME/application/bin:$MDE4CPP_HOME/application/tools:$PATH"

# #############################
# # configure LD_LIBRARY_PATH #
# #############################
export LD_LIBRARY_PATH=$LD_LIBRARY_PATH:$MDE4CPP_HOME/application/bin

# #############################################################################
# # Configure JAVA CLASSPATH                                                  #
# #############################################################################
export CLASSPATH=$MDE4CPP_ECLIPSE_HOME/plugins

# ##############################################################################
# # configure compiler information for include path setting inside cpp eclipse #
# ##############################################################################
export CPP_IDE_EXECUTABLE=$MDE4CPP_ECLIPSE_HOME

# The generators create eclipse cpp projects files including include path.
# Estimated path to compiler includes: ${COMPILER_HOME}/lib/gcc/${COMPILER_DELIVERY_NAME}/${COMPILER_VERSION}/include
# Configuration is only necessary for eclipse use.

# cd ./gradlePlugins
# ../application/tools/gradlew publishMDE4CPPPluginsToMavenLocal

# cd $MDE4CPP_HOME
EOF

# Strip any CRLF line endings from setenv (Windows compatibility)
RUN sed -i 's/\r$//' /home/mde4cpp/setenv && chmod +x /home/mde4cpp/setenv

# Strip CRLF from properties file if it exists (Windows compatibility)
RUN if [ -f /home/mde4cpp/MDE4CPP_Generator.properties ]; then \
        sed -i 's/\r$//' /home/mde4cpp/MDE4CPP_Generator.properties; \
    fi

# Make gradlew executable
RUN cd /home/mde4cpp && chmod +x ./application/tools/gradlew

# Build Gradle plugins first (verified - required before building metamodels)
RUN cd /home/mde4cpp && . ./setenv && cd /home/mde4cpp/gradlePlugins && ../application/tools/gradlew publishMDE4CPPPluginsToMavenLocal --no-daemon

# Create all generators (verified - must be done before buildAll)
RUN cd /home/mde4cpp && . ./setenv && ./application/tools/gradlew createAllGenerators --no-daemon

# Verify generators were created
RUN if [ ! -f /home/mde4cpp/application/generator/ecore4CPP.jar ] || \
       [ ! -f /home/mde4cpp/application/generator/UML4CPP.jar ] || \
       [ ! -f /home/mde4cpp/application/generator/fUML4CPP.jar ]; then \
        echo "ERROR: Generator JARs not created!"; \
        exit 1; \
    fi && \
    echo "✓ Generators created successfully"

# Generate all models (matching buildAll.sh)
RUN cd /home/mde4cpp && . ./setenv && ./application/tools/gradlew generateAll --no-daemon

# Fix line endings for ALL Gradle files in the project (comprehensive approach)
# This ensures any Gradle file, whether generated or not, has LF line endings
RUN find /home/mde4cpp -type f -name "*.gradle" \
    -exec sed -i 's/\r$//' {} \; 2>/dev/null || true

# Force Gradle to re-evaluate project structure
RUN cd /home/mde4cpp && . ./setenv && ./application/tools/gradlew projects --no-daemon > /dev/null 2>&1 || true

# Compile all generated code (matching buildAll.sh)
RUN cd /home/mde4cpp && . ./setenv && ./application/tools/gradlew compileAll --no-daemon

# Build OCL components (matching buildAll.sh)
RUN cd /home/mde4cpp && . ./setenv && ./application/tools/gradlew src:buildOCLAll --no-daemon

# Default command to start bash shell with environment sourced
# CMD ["/bin/bash", "-i"]
