#!/bin/bash
# Install ray in the .venv environment
# Ray does not yet have pre-built wheels for Python 3.14

cd "$(dirname "$0")"

VENV_PYTHON="./.venv/bin/python"
VENV_PIP="./.venv/bin/pip"

echo "Installing ray from source..."
echo "This may take several minutes as ray needs to be compiled..."

# Try installing from GitHub repository
$VENV_PIP install git+https://github.com/ray-project/ray.git

if [ $? -eq 0 ]; then
    echo "✓ Ray installed successfully!"
else
    echo "✗ Failed to install ray from source."
    echo "Ray may not yet support Python 3.14."
    echo "Please check: https://github.com/ray-project/ray/releases"
    exit 1
fi
