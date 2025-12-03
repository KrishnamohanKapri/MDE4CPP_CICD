# Optimized for runtime builds via docker-compose
# Dependencies are installed at runtime via install_dependencies.sh in the build-full service

# ============================================================================
# Base Image with JDK
# ============================================================================
FROM eclipse-temurin:21-jdk-jammy

# Install minimal dependencies needed for install_dependencies.sh to run
# install_dependencies.sh will install the rest of the system packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    bash \
    sudo \
    && rm -rf /var/lib/apt/lists/* \
    && apt-get clean

# Set JAVA_HOME for JDK 21 (needed for Gradle and build tools)
ENV JAVA_HOME=/opt/java/openjdk

# Create user and project directory structure
RUN useradd -u 1000 -m -d /home/mde4cpp mde4cpp \
    && mkdir -p /home/mde4cpp \
    && chown -R mde4cpp:mde4cpp /home/mde4cpp

# Set working directory
WORKDIR /home/mde4cpp

# Note: All MDE4CPP files, Eclipse, and dependencies are installed at runtime
# via bind mount and install_dependencies.sh in the build-full service
# Environment variables (MDE4CPP_HOME, MDE4CPP_ECLIPSE_HOME) are set via setenv
