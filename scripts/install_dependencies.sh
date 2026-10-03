#!/usr/bin/env bash
# ==============================================================================
# SuperHearing Dependency & Tool Installation Script
# Automates the setup of Xcode, command-line utilities, Python libraries,
# and Swift Package Manager (SPM) dependencies for CI/CD and local development.
# ==============================================================================

set -euo pipefail

# Color formatting
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m' # No Color

log_info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
log_success() { echo -e "${GREEN}[SUCCESS]${NC} $*"; }
log_warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
INSTALL_MODEL_TOOLS=false
INSTALL_BREW_EXTRAS=false

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --with-model-tools|--include-model-tools)
      INSTALL_MODEL_TOOLS=true
      shift
      ;;
    --with-brew-extras)
      INSTALL_BREW_EXTRAS=true
      shift
      ;;
    --all)
      INSTALL_MODEL_TOOLS=true
      INSTALL_BREW_EXTRAS=true
      shift
      ;;
    -h|--help)
      cat <<EOF
Usage: $(basename "$0") [OPTIONS]

Automates installation of all required dependencies, tools, and packages
for SuperHearing iOS builds on GitHub Actions and local development machines.

Options:
  --with-model-tools   Install Python packages for CoreML/Demucs model export (PyTorch, coremltools)
  --with-brew-extras   Install optional macOS developer CLI utilities (xcbeautify, jq, tree)
  --all                Install both core build tools and model export tooling
  -h, --help           Show this help message
EOF
      exit 0
      ;;
    *)
      log_warn "Unknown option: $1"
      shift
      ;;
  esac
done

echo -e "${BOLD}======================================================${NC}"
echo -e "${BOLD} SuperHearing Build Environment Setup${NC}"
echo -e "${BOLD}======================================================${NC}"
log_info "Working directory: ${PROJECT_DIR}"
log_info "OS: $(uname -s) ($(uname -m))"

# ------------------------------------------------------------------------------
# 1. Xcode & macOS Developer Tools Setup
# ------------------------------------------------------------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  log_info "Configuring macOS Developer Environment..."

  # In GitHub Actions or multi-Xcode macOS machines, select the latest stable Xcode
  if [[ -d "/Applications/Xcode_16.0.app" ]]; then
    SELECTED_XCODE="/Applications/Xcode_16.0.app"
  elif [[ -d "/Applications/Xcode_15.4.app" ]]; then
    SELECTED_XCODE="/Applications/Xcode_15.4.app"
  elif [[ -d "/Applications/Xcode_15.3.app" ]]; then
    SELECTED_XCODE="/Applications/Xcode_15.3.app"
  elif [[ -d "/Applications/Xcode.app" ]]; then
    SELECTED_XCODE="/Applications/Xcode.app"
  else
    SELECTED_XCODE=""
  fi

  if [[ -n "$SELECTED_XCODE" ]]; then
    log_info "Selecting Xcode version at ${SELECTED_XCODE}..."
    sudo xcode-select -s "${SELECTED_XCODE}" 2>/dev/null || xcode-select -s "${SELECTED_XCODE}" 2>/dev/null || true
  fi

  # Verify active Xcode
  if command -v xcodebuild >/dev/null 2>&1; then
    XCODE_VER=$(xcodebuild -version | tr '\n' ' ')
    log_success "Active ${XCODE_VER}"
  else
    log_error "xcodebuild not found! Please install Xcode or Command Line Tools."
    exit 1
  fi

  # Auto-accept Xcode license in CI if needed
  if [[ "${CI:-false}" == "true" ]] || [[ "${GITHUB_ACTIONS:-false}" == "true" ]]; then
    sudo xcodebuild -license accept 2>/dev/null || true
  fi
else
  log_warn "Running on non-macOS platform ($(uname -s)). Xcode build steps will be skipped."
fi

# ------------------------------------------------------------------------------
# 2. Package Manager & CLI Tools Setup (Homebrew / System Tools)
# ------------------------------------------------------------------------------
log_info "Checking essential archiving and build utilities..."

MISSING_TOOLS=()
for tool in zip unzip git; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    MISSING_TOOLS+=("$tool")
  fi
done

if [[ ${#MISSING_TOOLS[@]} -gt 0 ]]; then
  log_warn "Missing tools: ${MISSING_TOOLS[*]}"
  if command -v brew >/dev/null 2>&1; then
    log_info "Installing missing tools via Homebrew..."
    brew install "${MISSING_TOOLS[@]}"
  elif sudo -n true 2>/dev/null || [[ "${CI:-false}" == "true" ]]; then
    if command -v apt-get >/dev/null 2>&1; then
      sudo apt-get update && sudo apt-get install -y "${MISSING_TOOLS[@]}"
    elif command -v pacman >/dev/null 2>&1; then
      sudo pacman -Sy --noconfirm "${MISSING_TOOLS[@]}"
    fi
  else
    log_warn "Cannot install missing tools automatically without non-interactive sudo. Please install: ${MISSING_TOOLS[*]}"
  fi
else
  log_success "All standard archiving and version-control utilities are present (zip, unzip, git)."
fi

# Optional Homebrew developer tools
if [[ "$INSTALL_BREW_EXTRAS" == "true" ]] && command -v brew >/dev/null 2>&1; then
  log_info "Installing optional developer tools via Homebrew..."
  brew install xcbeautify jq tree || true
fi

# ------------------------------------------------------------------------------
# 3. Python & CoreML / Demucs Export Tooling (Optional or on-demand)
# ------------------------------------------------------------------------------
if [[ "$INSTALL_MODEL_TOOLS" == "true" ]]; then
  log_info "Setting up Python tools for CoreML conversion & Demucs INT8 export..."
  if command -v python3 >/dev/null 2>&1; then
    python3 -m pip install --upgrade pip setuptools wheel
    log_info "Installing PyTorch, CoreMLTools, and Demucs..."
    python3 -m pip install "torch" "torchaudio" "demucs" "coremltools>=7.0" "numpy" "soundfile"
    log_success "Model preparation dependencies successfully installed."
  else
    log_error "python3 is not installed. Unable to install model dependencies."
    exit 1
  fi
fi

# ------------------------------------------------------------------------------
# 4. Resolve Swift Package Manager (SPM) Dependencies
# ------------------------------------------------------------------------------
if [[ "$(uname -s)" == "Darwin" ]] && command -v xcodebuild >/dev/null 2>&1; then
  if [[ -d "${PROJECT_DIR}/SuperHearing.xcodeproj" ]]; then
    log_info "Resolving Swift Package Dependencies (swift-async-algorithms, swift-collections)..."
    cd "${PROJECT_DIR}"
    xcodebuild -project SuperHearing.xcodeproj \
               -scheme SuperHearing \
               -resolvePackageDependencies \
               -clonedSourcePackagesDirPath "${PROJECT_DIR}/.build/SourcePackages" || {
      # Fallback to default resolution
      xcodebuild -project SuperHearing.xcodeproj -scheme SuperHearing -resolvePackageDependencies
    }
    log_success "Swift Package Dependencies resolved successfully."
  fi
fi

# ------------------------------------------------------------------------------
# 5. Build Environment Verification Summary
# ------------------------------------------------------------------------------
echo -e "\n${BOLD}--- Environment Verification Summary ---${NC}"
if command -v xcodebuild >/dev/null 2>&1; then
  echo -e "✓ Xcode:      $(xcodebuild -version | head -n 1)"
fi
if command -v swift >/dev/null 2>&1; then
  echo -e "✓ Swift:      $(swift --version | head -n 1)"
fi
if command -v zip >/dev/null 2>&1; then
  echo -e "✓ Zip:        $(zip -v 2>&1 | head -n 2 | tail -n 1)"
fi
if command -v python3 >/dev/null 2>&1; then
  echo -e "✓ Python:     $(python3 --version)"
fi
if command -v codesign >/dev/null 2>&1; then
  echo -e "✓ Codesign:   $(which codesign)"
fi
echo -e "${BOLD}----------------------------------------${NC}"
log_success "Build dependencies and environment are ready!"
