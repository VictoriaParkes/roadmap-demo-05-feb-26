# ARG: Makes Python version configurable at build time
# slim: Smaller base image (saves ~800MB vs full Python image)
ARG PYTHON_VERSION=3.9
FROM python:${PYTHON_VERSION}-slim

# Sets /app as the working directory inside the container
# All subsequent commands run from this directory
# Creates the directory if it doesn't exist
WORKDIR /app

# Dependency Installation (Two-Step Process)
# Step 1: Copy only requirements.txt first
# Step 2: Install dependencies
# Why separate? Docker layer caching - if your code changes
#but dependencies don't, Docker reuses the cached pip install
# layer (faster rebuilds)
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt

# Create a new user instead of running as root user
RUN useradd -m appuser

# Application Code
# Copies all remaining files from build context to /app
# Done after dependencies so code changes don't invalidate
# the pip cache layer
# COPY . .
# change the ownership of all files and dirs in /app to the appuser account
# RUN chown -R appuser:appuser /app

# Ownership set during copy operation
COPY --chown=appuser:appuser . .
# to give appuser write permissions
RUN mkdir -p instance && chown -R appuser:appuser instance

# Switch to app user
USER appuser

# Documents that the app listens on port 5000
# This is documentation only, doesn't actually publish the port
# Still need -p 5000:5000 when running the container
EXPOSE 5000

# Health check to monitor Flask application
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
  CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:5000', timeout=2)" || exit 1

# Execute
# Runs when container starts
# Can be overridden at runtime
CMD ["python", "app.py"]

# Why This Structure Works Well
# Layer caching: Dependencies cached separately from code
# Simple: No security complexity, good for development
# Fast rebuilds: Only reinstalls dependencies when requirements.txt changes
# This is the standard pattern for most Python web applications.