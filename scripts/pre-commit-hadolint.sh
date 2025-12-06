#!/bin/bash
# Pre-commit hook for Hadolint Dockerfile linting
# Uses local hadolint installation

set -e

if ! command -v hadolint >/dev/null 2>&1; then
    echo "Skipping: hadolint not installed (brew install hadolint)"
    exit 0
fi

# Ignored rules for development environment:
# DL3002 - Last USER should not be root (we need root for system operations)
# DL3005 - Do not use apt-get upgrade (needed for development environment)
# DL3008 - Pin versions in apt-get install (development env wants latest)
# DL3013 - Pin versions in pip (development env wants latest)
# DL3016 - Pin versions in npm install (development env wants latest)
# DL3062 - Pin versions in go install (development env wants latest)
# DL4001 - Either use Wget or Curl but not both (both are needed)
# SC1091 - Not following: File not included in mock (external files)
# SC2016 - Expressions don't expand in single quotes (intentional for delayed expansion)
# SC2034 - Variable appears unused (used by external scripts/processes)
# SC2086 - Double quote to prevent globbing (often intentional for word splitting)

IGNORES="--ignore DL3002 --ignore DL3005 --ignore DL3008 --ignore DL3013"
IGNORES="${IGNORES} --ignore DL3016 --ignore DL3062 --ignore DL4001 --ignore SC1091"
IGNORES="${IGNORES} --ignore SC2016 --ignore SC2034 --ignore SC2086"

echo "Running Hadolint on Dockerfile(s)..."

exit_code=0
for dockerfile in "$@"; do
    echo "Linting: ${dockerfile}"
    # shellcheck disable=SC2086
    if ! hadolint ${IGNORES} "${dockerfile}"; then
        exit_code=1
    fi
done

exit $exit_code
