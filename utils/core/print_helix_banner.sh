#!/bin/bash

print_helix_banner() {
    # Default values for arguments if not provided
    local version="${1:-v0.0.0-dev}" # Default version if $1 is empty
    local subtitle="${2:-Deployment Orchestrator}" # Default subtitle if $2 is empty
    local git_sha
    local timestamp

    # Resolve Git SHA (short)
    if git rev-parse --git-dir > /dev/null 2>&1; then
        git_sha=$(git rev-parse --short HEAD)
    else
        git_sha="N/A"
    fi

    # Current timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S %Z")

    # ASCII Art Banner - Bold Magenta
    echo -e "\e[1;35m" # Bold Magenta
    cat <<'EOF'
      ██   ██╗██████╗██╗    ██╗██╗  ██╗       
      ██╔══██║██╔═══╝██║    ██║╚██╗██╔╝       
      ███████║████╗  ██║    ██║ ╚███╔╝       
      ██╔══██║██╔═╝  ██║    ██║ ██╔██╗     
      ██║  ██║██████╗██████╗██║██╔╝ ██╗     
      ╚═╝  ╚═╝╚═════╝╚═════╝╚═╝╚═╝  ╚═╝ ©   
─────────────────────────────────────────────
EOF
    # Interpolated metadata banner - Bold Cyan for main info, Green for subtitle
    echo -e "\e[1;36m" # Bold Cyan
    echo "🎛️  H E L I X \e[1;33m${version}\e[1;36m  🐳" # Bold Yellow for version
    echo " \e[1;32m• ${subtitle} •\e[1;36m" # Bold Green for subtitle
    echo "─────────────────────────────────────────────"
    echo "🕒  ${timestamp} • 🧬 Git:${git_sha}"
    echo -e "\e[0m" # Reset colors
}
