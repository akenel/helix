#!/bin/bash
set -euo pipefail
trap 'echo "❌ Error in $0 on line $LINENO — aborting."' ERR
# Colors for maximum visual impact
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[1;35m'
WHITE='\033[1;37m'
BG_RED='\033[41m'
BG_GREEN='\033[42m'
BG_BLUE='\033[44m'
NC='\033[0m'
REEL_MODE=false
[[ "${1:-}" == "--reel" ]] && REEL_MODE=true

# 🎭 HELIX BEFORE-VS-AFTER DEMO
RECORD_MODE=false
[[ "${1:-}" == "--record" ]] && RECORD_MODE=true

check_and_install_dependencies() {
  local missing_deps=()
  local dependencies=(asciinema agg)

  # Check for each dependency
  for dep in "${dependencies[@]}"; do
    if ! command -v "$dep" &> /dev/null; then
      missing_deps+=("$dep")
    fi
  done

  # If no dependencies are missing, we're good to go.
  if [[ ${#missing_deps[@]} -eq 0 ]]; then
    return 0
  fi

  # Inform the user about the missing dependencies
  echo -e "\n${YELLOW}⚠️  The following packages are required for the recording feature:${NC}"
  for dep in "${missing_deps[@]}"; do
    echo -e "${YELLOW} - $dep${NC}"
  done

  # Ask the user if they want to install them
  echo -e "\n${CYAN}Would you like to install them now? (requires sudo password) [Y/n]${NC}"
  read -r response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    echo -e "\n${GREEN}Installing dependencies...${NC}"

    # --- ADDED: Temporarily configure APT to be more robust ---
    # Create a temporary APT configuration file to increase the timeout and retries
    local apt_conf="/etc/apt/apt.conf.d/99helix-demo-timeout"
    echo "Acquire::http::Timeout \"120\";" | sudo tee "$apt_conf" > /dev/null
    echo "Acquire::http::Retries \"5\";" | sudo tee -a "$apt_conf" > /dev/null
    
    # Run apt-get update and install
    sudo apt-get update
    sudo apt-get install "${missing_deps[@]}" || true
    
    # --- ADDED: Clean up the temporary APT configuration file ---
    sudo rm -f "$apt_conf"

    # Check if the installation was successful
    for dep in "${missing_deps[@]}"; do
      if ! command -v "$dep" &> /dev/null; then
        echo -e "\n${RED}❌ Failed to install $dep. Please install manually to use recording feature.${NC}"
        return 1
      fi
    done

    echo -e "\n${GREEN}Dependencies installed successfully!${NC}"
    return 0
  else
    echo -e "\n${YELLOW}Recording will be skipped. Continuing without asciinema and agg.${NC}"
    return 1
  fi
}

# --- Main script logic (before any demo output) ---
if $RECORD_MODE; then
  if check_and_install_dependencies; then
    # Redirect output for recording
    exec > >(tee helix-demo.log)
    exec 2>&1
    echo -e "\n${CYAN}🚀 Recording demo to helix-demo.cast...${NC}"
  else
    # Fallback if installation failed or was declined
    RECORD_MODE=false
    echo -e "\n${YELLOW}Recording mode disabled.${NC}"
  fi
fi

# functions
show_system_specs() {
  echo -e "\n${WHITE}🔍 SYSTEM ENVIRONMENT:${NC}"
  echo -e "${CYAN}• OS:$(uname -srmo)"
  echo -e "• CPU: $(lscpu | grep 'Model name' | awk -F ':' '{print $2}' | xargs)"
  echo -e "• Cores: $(nproc)"
  echo -e "• RAM: $(free -h --si | awk '/Mem:/ {print $2}')"
  echo -e "• Docker: $(docker --version | cut -d',' -f1)"
  echo -e "• Shell: $SHELL${NC}"
}
open_in_browser() {
  local file="$1"
  if [[ -f "$file" ]]; then
    if command -v wslview &>/dev/null; then
      wslview "$file" &>/dev/null & # Redirect output and run in background
    elif command -v xdg-open &>/dev/null; then
      xdg-open "$file" &>/dev/null & # Redirect output and run in background
    else
      echo -e "${YELLOW}⚠️ Cannot auto-open. Please manually open: $file${NC}"
    fi
  fi
}

simulate_enterprise_burn() {
  echo -e "\n${RED}💸 Simulating Enterprise Cloud Spend...${NC}"
  local total=0
  for i in {1..10}; do
    local increment=$((RANDOM % 90 + 10))
    total=$((total + increment))
    echo -ne "💣 Burning Budget: \$ $total\r"
    sleep 0.5
  done
  echo -e "\n${GREEN}💰 Local Setup Cost: \$8 — Coffee not included ☕️${NC}"
}
show_random_tweets() {
  # Get the directory where the script is located
  local script_dir
  script_dir="$( cd "$( dirname "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )"

  # Construct the full path to the tweets file
  local file="${script_dir}/helix.tweets"

  echo -e "\n${MAGENTA}💬 REAL DEVELOPER QUOTES:${NC}"
  if [[ -f "$file" ]]; then
    shuf -n 3 "$file" | while read -r tweet; do
      echo -e "${CYAN}💡 $tweet${NC}"
      sleep 1
    done
  else
    echo -e "${RED}⚠️ Missing helix.tweets file at: ${file}${NC}"
  fi
}
# This function creates an HTML report from the demo log
generate_html_report() {
  REPORT_FILE="helix-demo.html" # Using the helix-demo.html filename
  
  cat <<EOF > "$REPORT_FILE"
<html>
<head>
  <title>Helix Demo Report</title>
  <style>body { font-family: monospace; background: #000; color: #0f0; padding: 2em; }</style>
</head>
<body>
<pre>
$(cat helix-demo.log)
</pre>
</body>
</html>
EOF

  echo -e "\n${WHITE}📄 HTML report generated: ${REPORT_FILE}${NC}"
}
pause_or_wait() {
  if $REEL_MODE; then
    sleep "${1:-3}"
  else
    echo -e "${CYAN}↩️  Press ENTER to continue...${NC}"
    read -r
  fi
}

# Dramatic pause function
dramatic_pause() {
    local seconds=${1:-2}
    for ((i=seconds; i>0; i--)); do
        echo -n "."
        sleep 1
    done
    echo
}

# Typing effect for maximum drama
type_text() {
    local text="$1"
    local delay=${2:-0.05}
    for ((i=0; i<${#text}; i++)); do
        echo -n "${text:$i:1}"
        sleep $delay
    done
    echo
}

# Show enterprise pain vs Helix bliss
show_comparison() {
    local category="$1"
    local enterprise_pain="$2"
    local helix_bliss="$3"
    local enterprise_time="$4"
    local helix_time="$5"
    
    echo -e "\n${WHITE}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "${YELLOW}📊 $category${NC}"
    echo -e "${WHITE}═══════════════════════════════════════════════════════════════${NC}"
    
    echo -e "${BG_RED}${WHITE} 😭 ENTERPRISE HORROR STORY ${NC}"
    echo -e "${RED}⏱️  Time: $enterprise_time${NC}"
    echo -e "${RED}💸 Pain Level: MAXIMUM${NC}"
    echo -e "${RED}🔥 $enterprise_pain${NC}"
    
    echo
    echo -e "${BG_GREEN}${WHITE} 🚀 HELIX MAGIC ✨ ${NC}"
    echo -e "${GREEN}⏱️  Time: $helix_time${NC}"
    echo -e "${GREEN}💰 Cost: NEGLIGIBLE${NC}"
    echo -e "${GREEN}🎯 $helix_bliss${NC}"
    
    dramatic_pause 2
}

# The nuclear bomb function - shows the impossible
show_nuclear_comparison() {
    echo -e "\n${MAGENTA}💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥${NC}"
    echo -e "${WHITE}🚨 NUCLEAR COMPARISON - THIS WILL BLOW YOUR MIND 🚨${NC}"
    echo -e "${MAGENTA}💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥${NC}"
    
    echo -e "\n${CYAN}What enterprise teams think is impossible...${NC}"
    dramatic_pause 3
    echo -e "${GREEN}Helix does over breakfast! ☕️${NC}"
    dramatic_pause 2
}

clear
echo -e "${MAGENTA}"
cat << 'EOF'
██╗  ██╗███████╗██╗     ██╗██╗  ██╗      ██████╗ ███████╗███╗   ███╗ ██████╗ 
██║  ██║██╔════╝██║     ██║╚██╗██╔╝      ██╔══██╗██╔════╝████╗ ████║██╔═══██╗
███████║█████╗  ██║     ██║ ╚███╔╝       ██║  ██║█████╗  ██╔████╔██║██║   ██║
██╔══██║██╔══╝  ██║     ██║ ██╔██╗       ██║  ██║██╔══╝  ██║╚██╔╝██║██║   ██║
██║  ██║███████╗███████╗██║██╔╝ ██╗      ██████╔╝███████╗██║ ╚═╝ ██║╚██████╔╝
╚═╝  ╚═╝╚══════╝╚══════╝╚═╝╚═╝  ╚═╝      ╚═════╝ ╚══════╝╚═╝     ╚═╝ ╚═════╝ 
      "BEFORE vs AFTER: How One Script Destroyed Enterprise Consulting"
EOF
echo -e "${NC}"

echo -e "\n${WHITE}Welcome to the most shocking DevOps comparison ever created...${NC}"
type_text "Prepare to witness the impossible..." 0.1

echo -e "\n${YELLOW}⚠️  WARNING: This demo has caused the following side effects:${NC}"
echo -e "${RED}  • Enterprise architects questioning their careers${NC}"
echo -e "${RED}  • DevOps consultants hiding their LinkedIn profiles${NC}"
echo -e "${RED}  • German engineering teams learning English curse words${NC}"
echo -e "${RED}  • AWS sales reps crying into their commission reports${NC}"

echo -e "\n${CYAN}Press ENTER to proceed at your own risk...${NC}"
read -r

# ═══════════════════════════════════════════════════════════════
# ROUND 1: KUBERNETES SETUP
# ═══════════════════════════════════════════════════════════════

show_comparison \
    "🎯 KUBERNETES CLUSTER SETUP" \
    "6-month project, 47 meetings, 23 stakeholders, 8 environments, $ 200k budget minimum, 
     3 consulting firms, 147 Jira tickets, 89 Slack channels, 
     12 architecture reviews, and a nervous breakdown" \
    "One command: './setup-helix.sh' 
     ☕️ Time to make coffee and boom - production-ready cluster!" \
    "6 MONTHS + THERAPY" \
    "20 MINUTES"

# ═══════════════════════════════════════════════════════════════
# ROUND 2: IDENTITY MANAGEMENT
# ═══════════════════════════════════════════════════════════════

show_comparison \
    "🔐 IDENTITY & AUTH SETUP" \
    "Active Directory integration nightmare, LDAP configuration hell,
     SAML certificates from 3 different vendors, 
     OAuth flows that nobody understands,
     Enterprise SSO that breaks every Tuesday" \
    "Keycloak with submarine-empire realm automatically configured!
     Admin, dev, guest users ready to rock!
     RBAC that actually makes sense!" \
    "3-6 MONTHS + ANTIDEPRESSANTS" \
    "5 MINUTES"

# ═══════════════════════════════════════════════════════════════
# ROUND 3: SECRET MANAGEMENT
# ═══════════════════════════════════════════════════════════════

show_comparison \
    "🗝️ SECRETS MANAGEMENT" \
    "HashiCorp Vault Enterprise license negotiations,
     HSM integration with 47 compliance checkboxes,
     Key rotation policies that require PhD in cryptography,
     Backup strategies approved by 12 committees" \
    "Vault auto-unsealed with our submarine crew secrets!
     TLS certificates managed automatically!
     No compliance nightmares!" \
    "4-8 MONTHS + SECURITY AUDIT" \
    "INCLUDED FOR FREE"

# ═══════════════════════════════════════════════════════════════
# ROUND 4: MONITORING & OBSERVABILITY
# ═══════════════════════════════════════════════════════════════

show_comparison \
    "📊 MONITORING SETUP" \
    "Datadog/New Relic/Splunk enterprise contracts,
     Custom dashboards that take 2 weeks to create,
     Alert fatigue from 847 meaningless notifications,
     APM agents that slow everything down" \
    "Popeye enterprise validation built-in!
     Beautiful HTML reports that make you look smart!
     Health checks that actually tell you useful stuff!" \
    "2-4 MONTHS + ALERT THERAPY" \
    "WORKS OUT OF THE BOX"

# ═══════════════════════════════════════════════════════════════
# ROUND 5: DEVELOPMENT WORKFLOW
# ═══════════════════════════════════════════════════════════════

show_comparison \
    "🛠️ DEVELOPER EXPERIENCE" \
    "GitLab Enterprise with 47 approval workflows,
     Jenkins pipelines that break if you look at them wrong,
     Docker registry that costs more than your car,
     Deployment processes requiring 12 approvals" \
    "Local development that mirrors production exactly!
     No network latency, no cloud bills, no permissions hell!
     Deploy faster than enterprise teams can schedule meetings!" \
    "FOREVER + SOUL CRUSHING" \
    "INSTANT GRATIFICATION"

# ═══════════════════════════════════════════════════════════════
# THE NUCLEAR BOMB SECTION
# ═══════════════════════════════════════════════════════════════

show_nuclear_comparison

echo -e "\n${WHITE}🔥 THE NUMBERS THAT BROKE THE INTERNET 🔥${NC}"
echo -e "${WHITE}════════════════════════════════════════════${NC}"

echo -e "\n${YELLOW}💸 Let's talk money... Enterprise vs Reality 💸${NC}"
echo -e "\n${CYAN}Press ENTER to see the financial devastation (or wait 8 seconds)...${NC}"
read -t 8 -r || true

echo -e "\n📊 COST COMPARISON (Monthly):"
echo -e "┌─────────────────────────────────────────────────────────────┐"
echo -e "│  ${BG_RED}${WHITE} ENTERPRISE CLOUD HORROR ${NC}                                  │"
echo -e "├─────────────────────────────────────────────────────────────┤"
echo -e "│  AWS EKS Control Plane:          $ 73/month                 │"
echo -e "│  Worker Nodes (3x m5.large):     $ 310/month                │"
echo -e "│  Load Balancer:                  $ 18/month                 │"
echo -e "│  EBS Storage (100GB):            $ 10/month                 │"
echo -e "│  Data Transfer:                  $ 50/month                 │"
echo -e "│  CloudWatch Logs:                $ 25/month                 │"
echo -e "│  Backup Storage:                 $ 15/month                 │"
echo -e "│  ──────────────────────────────────────────                 │"
echo -e "│  ${RED}TOTAL: $ 501/month = $ 6,012/year${NC}                          │"
echo -e "└─────────────────────────────────────────────────────────────┘"

echo -e "\n${RED}☝️  Look at those numbers... $ 501 PER MONTH! 💸${NC}"
echo -e "\n${CYAN}Now brace yourself for the Helix magic... (Press ENTER or wait 6 seconds)${NC}"
read -t 6 -r || true

echo -e "┌─────────────────────────────────────────────────────────────┐"
echo -e "│  ${BG_GREEN}${WHITE} HELIX LAPTOP MAGIC ✨ ${NC}                                    │"
echo -e "├─────────────────────────────────────────────────────────────┤"
echo -e "│  Laptop Cost (one-time):            $ 1,200                 │"
echo -e "│  Docker Desktop (already have):     $ 0/month               │"
echo -e "│  Kubernetes (built-in):             $ 0/month               │"
echo -e "│  Popeye Validation (free):          $ 0/month               │"
echo -e "│  Monitoring (built-in):             $ 0/month               │"
echo -e "│  Secrets Management (built-in):     $ 0/month               │"
echo -e "│  Identity Management (built-in):    $ 0/month               │"
echo -e "│  Developer Experience (free):       $ 0/month               │"
echo -e "│  Local Storage (SSD):               $ 0/month               │"
echo -e "│  Backup (built-in):                 $ 0/month               │"
echo -e "│  Network (local):                   $ 0/month               │"
echo -e "│  Monitoring (built-in):             $ 0/month               │"
echo -e "│  Logging (built-in):                $ 0/month               │"
echo -e "│  CI/CD (built-in):                  $ 0/month               │"
echo -e "│  Developer Tools (free):            $ 0/month               │"
echo -e "│  Training (free online resources):  $ 0/month               │"
echo -e "│  Electricity (24/7):                $ 8/month               │"
echo -e "│  Internet (already have):           $ 0/month               │"
echo -e "│  Cloud Storage (none needed):       $ 0/month               │"
echo -e "│  Licensing (open source):           $ 0/month               │"
echo -e "│  ────────────────────────────────────────────               │"
echo -e "│  ${GREEN}TOTAL: $ 8/month = $ 96/year${NC}                               │"
echo -e "└─────────────────────────────────────────────────────────────┘"

echo -e "\n${GREEN}🤯 EIGHT DOLLARS! Your coffee budget beats enterprise cloud! ☕️${NC}"
echo -e "\n${CYAN}Ready for the financial bomb? (Press ENTER or wait 5 seconds)${NC}"
read -t 5 -r || true

echo -e "\n${MAGENTA}💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥${NC}"
echo -e "${MAGENTA} 💰 ANNUAL SAVINGS: $ 5,916 💰${NC}"
echo -e "${MAGENTA} 🏆 ROI: 6,150% 🏆${NC}"
echo -e "${MAGENTA}💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥💥${NC}"

echo -e "\n${WHITE}Let that sink in... $ 5,916 saved EVERY YEAR! 🤑${NC}"
dramatic_pause 5

echo -e "\n${WHITE}⚡ PERFORMANCE COMPARISON:${NC}"
echo -e "${WHITE}════════════════════════════${NC}"

echo -e "\n${CYAN}Now let's talk SPEED... (Press ENTER or wait 5 seconds)${NC}"
read -t 5 -r || true

cat << EOF

🚀 POD STARTUP TIMES:
    Enterprise Cloud: 15-45 seconds (network overhead)
    Helix Laptop:     2-8 seconds  (native speed)

EOF

echo -e "${GREEN}⚡ 5-10x FASTER startup! No network delays! ⚡${NC}"
echo -e "\n${CYAN}But wait, there's more... (Press ENTER or wait 4 seconds)${NC}"
read -t 4 -r || true

cat << EOF
    
🌐 NETWORK LATENCY:
    Enterprise Cloud: 50-200ms (internet hops)
    Helix Laptop:      0.1ms      (localhost magic)

EOF

echo -e "${GREEN}🌟 500-2000x FASTER networking! Physics wins! 🌟${NC}"
echo -e "\n${CYAN}The performance destruction continues... (Press ENTER or wait 4 seconds)${NC}"
read -t 4 -r || true

cat << EOF
    
📦 IMAGE PULLS:
    Enterprise Cloud: 30-120 seconds (registry downloads)
    Helix Laptop:      1-5 seconds   (local cache)
    
🔧 DEPLOYMENT TIME:
    Enterprise Cloud: 5-15 minutes (pipeline + approvals)
    Helix Laptop:      30 seconds   (direct deployment)

EOF

echo -e "\n${MAGENTA}💥 REALITY CHECK: Your laptop DESTROYS enterprise cloud performance! 💥${NC}"
dramatic_pause 4

echo -e "\n${WHITE}🎓 LEARNING CURVE DESTRUCTION:${NC}"
echo -e "${WHITE}═══════════════════════════════════${NC}"

echo -e "\n${CYAN}Now for the educational nightmare vs enlightenment... (Press ENTER or wait 6 seconds)${NC}"
read -t 6 -r || true

cat << EOF

📚 ENTERPRISE KUBERNETES LEARNING PATH:
    ❌ 6 months AWS training ($ 5,000)
    ❌ 3 months Terraform certification ($ 2,000)    
    ❌ 4 months Helm chart mastery (sanity loss)
    ❌ 2 months RBAC understanding (therapy required)
    ❌ 12 months debugging cloud networking (hair loss)
    ────────────────────────────────────────────────
    💸 Total: $ 7,000 + emotional damage

EOF

echo -e "${RED}💸 $ 7,000 and 27 months of your LIFE! Plus therapy costs! 💸${NC}"
echo -e "\n${CYAN}Now witness the Helix enlightenment... (Press ENTER or wait 5 seconds)${NC}"
read -t 5 -r || true

cat << EOF

🎯 HELIX LEARNING PATH:
    ✅ 1 day: Clone repo, run script
    ✅ 1 week: Understand everything    
    ✅ 1 month: Teaching others
    ✅ 3 months: Enterprise consulting offers
    ────────────────────────────────────────────────
    💰 Total: Free + career advancement

EOF

echo -e "\n${GREEN}🚀 FREE education that makes you MORE valuable than enterprise experts! 🚀${NC}"
dramatic_pause 4

echo -e "\n${MAGENTA}🎭 REAL DEVELOPER TESTIMONIALS (NOT FAKE!):${NC}"
echo -e "${MAGENTA}════════════════════════════════════════════${NC}"

echo -e "\n${CYAN}💬 \"I spent 8 months setting up our enterprise Kubernetes.${NC}"
echo -e "${CYAN}   Helix did it in 20 minutes. I'm updating my resume.\" ${NC}"
echo -e "${YELLOW}   - Senior DevOps Engineer, Fortune 500 Company${NC}"

echo -e "\n${CYAN}💬 \"Our German engineering team called it 'impossible'.${NC}"
echo -e "${CYAN}   I did it on a Tuesday. They're learning new words.\" ${NC}"
echo -e "${YELLOW}   - Intern, Automotive Company${NC}"

echo -e "\n${CYAN}💬 \"AWS wanted $ 876/month for our setup.${NC}"
echo -e "${CYAN}   Helix does it for the cost of a Netflix subscription.\" ${NC}"
echo -e "${YELLOW}   - Startup CTO${NC}"

echo -e "\n${CYAN}💬 \"I showed this to our enterprise architect.${NC}"
echo -e "${CYAN}   He stared at his screen for 47 minutes without blinking.\" ${NC}"
echo -e "${YELLOW}   - Platform Engineer${NC}"

dramatic_pause 3

echo -e "\n${WHITE}🌍 GLOBAL IMPACT REPORT:${NC}"
echo -e "${WHITE}═══════════════════════════${NC}"

cat << EOF

📈 SINCE HELIX LAUNCH:
    🔥 647 enterprise consulting contracts cancelled
    💼 23 DevOps consultants changed careers    
    🏢 89 companies fired their "cloud experts"
    📚 156 Kubernetes courses became obsolete
    💸 $ 2.3M saved by developers worldwide
    🎓 1,247 junior devs now outperform seniors
    
🚨 ENTERPRISE RESPONSE:
    ❌ "This is impossible" (proved wrong)
    ❌ "It's not production ready" (it is)
    ❌ "No enterprise features" (has everything)
    ❌ "Won't scale" (scales better than cloud)
    ❌ "No support" (community is amazing)
    
✅ REALITY CHECK:
    ✅ Works better than $ 100k solutions
    ✅ Faster than enterprise teams
    ✅ Costs 99.8% less
    ✅ Actually understandable
    ✅ No vendor lock-in

EOF

dramatic_pause 3

echo -e "\n${MAGENTA}💥 THE VIRAL SOCIAL MEDIA EXPLOSION:${NC}"
echo -e "${MAGENTA}═══════════════════════════════════════${NC}"

echo -e "\n${WHITE}🐦 TWITTER CHAOS:${NC}"
echo -e "${CYAN}#HelixVsEnterprise trending worldwide${NC}"
echo -e "${CYAN}#PopeyeValidation breaking the internet${NC}"
echo -e "${CYAN}#WSLUbuntuWins causing AWS stock to dip${NC}"

echo -e "\n${WHITE}📱 VIRAL POSTS READY TO COPY:${NC}"

cat << 'EOF'

🔥 TWEET TEMPLATES (COPY & PASTE):

1. "Just replaced our $876/month AWS EKS with a $8/month laptop setup. 
    Performance is BETTER. Setup took 20 minutes. 
    Enterprise architects hate this one trick! #HelixVsEnterprise"

2. "German engineering team: 'Kubernetes setup takes 6 months'
    WSL Ubuntu kid: 'Hold my coffee ☕️'
    *deploys production cluster during breakfast*
    #PopeyeValidation #DevOpsRevolution"

3. "Enterprise consultant: '$200k for Kubernetes project'
    Helix script: 'chmod +x setup-helix.sh && ./setup-helix.sh'
    Consultant: *updates LinkedIn to 'seeking new opportunities'*"

4. "Plot twist: The most reliable Kubernetes cluster runs in your bedroom,
    not AWS us-east-1. Latency: 0.1ms. Downtime: What's that?
    #HelixPlatform #CloudIsntAlwaysTheAnswer"

5. "Enterprise: 47 meetings to discuss Kubernetes strategy
    Helix: One script to deploy production cluster
    Time saved: 6 months + sanity
    #EnterpriseVsReality"

EOF

dramatic_pause 2

echo -e "\n${RED}🚨 ENTERPRISE DAMAGE CONTROL ATTEMPTS:${NC}"
echo -e "${RED}═══════════════════════════════════════════${NC}"

cat << 'EOF'

❌ "But what about compliance?"
✅ Helix: Built-in RBAC, TLS everywhere, audit logs

❌ "What about enterprise support?"
✅ Helix: Community support faster than enterprise tickets

❌ "But our security team won't approve!"
✅ Helix: More secure than default cloud setups

❌ "It won't integrate with our existing tools!"
✅ Helix: Standard Kubernetes APIs, works with everything

❌ "The CEO will never approve this!"
✅ CEO: "Why are we spending $ 50k/month on cloud bills?"

EOF

dramatic_pause 3

echo -e "\n${GREEN}🎯 THE HELIX ADVANTAGE SUMMARY:${NC}"
echo -e "${GREEN}════════════════════════════════════${NC}"

cat << 'EOF'

🏆 WHAT HELIX PROVES:
    ✅ Local development can beat cloud enterprise
    ✅ Simple scripts can replace 6-month projects
    ✅ Open source can outperform expensive licenses
    ✅ One person can outperform enterprise teams
    ✅ Understanding beats complexity
    ✅ Physics beats marketing (localhost is faster)

🚀 WHAT YOU GET:
    ✅ Production-ready Kubernetes in 20 minutes
    ✅ Identity management that actually works
    ✅ Secrets management without PhD requirements
    ✅ Monitoring that tells you useful things
    ✅ Deployment pipeline that doesn't break
    ✅ Developer experience that sparks joy

💰 WHAT YOU SAVE:
    ✅ $5,916/year in cloud costs
    ✅ 6 months of project time
    ✅ $7,000 in training costs
    ✅ Infinite hours of debugging cloud networking
    ✅ Your sanity and hair
    ✅ Your faith in simple solutions

EOF
simulate_enterprise_burn
pause_or_wait 4
show_random_tweets
pause_or_wait 3
show_system_specs
pause_or_wait 4
echo -e "\n${WHITE}🎉 DEMO COMPLETE! 🎉${NC}"
echo -e "\n${MAGENTA}🎉 CONGRATULATIONS! 🎉${NC}"
echo -e "${WHITE}You've just witnessed the demo that broke the DevOps world!${NC}"

echo -e "\n${CYAN}🌟 WHAT HAPPENS NEXT:${NC}"
echo -e "${GREEN}1. Share this demo with every developer you know${NC}"
echo -e "${GREEN}2. Watch enterprise consultants panic${NC}"
echo -e "${GREEN}3. Enjoy your 99.8% cost savings${NC}"
echo -e "${GREEN}4. Build amazing things with the time you saved${NC}"
echo -e "${GREEN}5. Become the hero your company needs${NC}"

echo -e "\n${YELLOW}⚠️  FINAL WARNING:${NC}"
echo -e "${RED}This demo has been known to cause:${NC}"
echo -e "${RED}• Spontaneous deployment of production systems${NC}"
echo -e "${RED}• Uncontrollable urge to cancel cloud subscriptions${NC}"
echo -e "${RED}• Sudden clarity about enterprise complexity${NC}"
echo -e "${RED}• Permanent immunity to vendor lock-in${NC}"

echo -e "\n${WHITE}🚀 Ready to join the revolution?${NC}"
echo -e "\n${GREEN}./setup-helix.sh${NC}"
echo -e "${GREEN}./validate-helix.sh${NC}"
echo -e "${GREEN}# Change the world${NC}"

echo -e "\n${MAGENTA}💪 Popeye says: 'I yam what I yam, and Helix beats enterprise!'${NC}"

dramatic_pause 3


# --- START FINAL REPORT GENERATION ---
# All demo content is now logged to helix-demo.log.
# Now we can safely call the function to create the HTML report.
# Note: I have removed the redundant `cat <<EOF ...` block here.
# The generate_html_report function is now doing the work.
generate_html_report

open_in_browser "./helix-demo.html"
echo -e "\n${WHITE}💻 Helix Report generated: helix-demo.html${NC}"
echo -e "${WHITE}📖 Read it, share it, and watch the enterprise crumble!${NC}"
echo -e "\n${WHITE}Thank you for witnessing the impossible!${NC}"
echo -e "${WHITE}Stay tuned for more Helix magic!${NC}"

# Check for existing recording
if [[ -f helix-demo.cast ]]; then
  echo -e "${YELLOW}⚠️ helix-demo.cast already exists. Overwrite it? (y/N)${NC}"
  read -r confirm
  [[ "$confirm" =~ ^[Yy]$ ]] || exit 0
fi

# Record terminal session
asciinema rec --overwrite -t "Helix: Before vs After" helix-demo.cast
echo -e "\n${WHITE}🎥 Recording saved as helix-demo.cast${NC}"

# Convert to webm or mp4 using agg (if available)
if command -v agg >/dev/null 2>&1; then
  agg --theme solarized-dark helix-demo.cast -o helix-demo.webm
  echo -e "\n${WHITE}🎬 Video created: helix-demo.webm${NC}"
elif command -v docker >/dev/null 2>&1; then
  docker run --rm -v "$PWD:/data" asciinema/asciicast2gif \
    -t solarized-dark helix-demo.cast helix-demo.gif && \
  ffmpeg -y -i helix-demo.gif -movflags faststart helix-demo.mp4
  echo -e "\n${WHITE}🎬 MP4 created: helix-demo.mp4${NC}"
else
  echo -e "${YELLOW}⚠️ No converter available (agg/docker). Cast file only.${NC}"
fi

# Final message
echo -e "\n${CYAN}↩️ Press any key to return to the Helix Menu...${NC}"
read -n 1 -s -r
exit 0
