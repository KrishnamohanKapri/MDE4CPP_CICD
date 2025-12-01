# Multi-stage Dockerfile for MDE4CPP
# Optimized for runtime builds via docker-compose

# ============================================================================
# Stage 1: Base Dependencies
# ============================================================================
FROM eclipse-temurin:21-jdk-jammy AS base

# Install minimal dependencies needed to run install_dependencies.sh
# Combine commands to reduce layers
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    sudo \
    git \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

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

# Clone MDE4CPP repository (needed for install_dependencies.sh)
# Remove git after cloning to reduce image size
RUN git clone -b main https://github.com/KrishnamohanKapri/MDE4CPP_CICD.git /tmp/mde4cpp-repo && \
    bash -c 'shopt -s dotglob && mv /tmp/mde4cpp-repo/* /home/mde4cpp/' && \
    rmdir /tmp/mde4cpp-repo && \
    chmod +x ./install_dependencies.sh && \
    ./install_dependencies.sh && \
    # Remove git after cloning (not needed at runtime with bind mount)
    apt-get purge -y git && \
    apt-get autoremove -y && \
    rm -rf /var/lib/apt/lists/* && \
    apt-get clean

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

# Set up environment variables
ENV MDE4CPP_HOME=/home/mde4cpp \
    MDE4CPP_ECLIPSE_HOME=/home/mde4cpp/eclipse \
    JAVA_HOME=/opt/java/openjdk \
    PATH="/home/mde4cpp/application/bin:/home/mde4cpp/application/tools:${PATH}"

# Strip CRLF from properties file if it exists (Windows compatibility)
RUN if [ -f /home/mde4cpp/MDE4CPP_Generator.properties ]; then \
        sed -i 's/\r$//' /home/mde4cpp/MDE4CPP_Generator.properties; \
    fi

# Make gradlew executable (fallback, bind mount will override)
RUN chmod +x /home/mde4cpp/application/tools/gradlew 2>/dev/null || true
