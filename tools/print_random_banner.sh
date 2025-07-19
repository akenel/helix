#!/usr/bin/env bash
# 🧭 cluster_info.sh — Displays current Kubernetes cluster context information.
# This script is intended to be sourced by other scripts.
# tools\print_random_banner.sh
print_random_banner() {
  case $((RANDOM % 10)) in
    0) echo -e "╭──────────────────────╮\n│   HELIX INITIATED ™  │\n╰──────────────────────╯" ;;
    1) echo -e "╭────────────────────────────╮\n│  🔐 IDENTITY STACK READY   │\n╰────────────────────────────╯" ;;
    2) echo -e "╭────────────────────────╮\n│   🧞‍♂️  WISH GRANTED — OK   │\n╰────────────────────────╯" ;;
    3) echo -e "╭────────────────────────╮\n│  ✅ CLUSTER: READY NOW  │\n╰────────────────────────╯" ;;
    4) echo -e "╭────────────────────────╮\n│ 🕵️  Case Solved — Helix™ │\n╰────────────────────────╯" ;;
    5) echo -e "╭────────────────────────────╮\n│ 🎨 THEME + 📜 REALM: APPLIED │\n╰────────────────────────────╯" ;;
    6) echo -e "╭────────────────────────╮\n│ 🤖 SYSTEMS: OPERATIONAL │\n╰────────────────────────╯" ;;
    7) echo -e "╔════════════════════════╗\n║    HELIX PLATFORM 🧬    ║\n╚════════════════════════╝" ;;
    8) chuck | fold -w 24 -s | sed 's/^/│ /;s/$/ │/' | awk 'BEGIN{print "╭────────────────────────╮"} {print} END{print "╰────────────────────────╯"}' ;;
    9) echo -e "╭────────────────────────╮\n│ 🛠️ TOOLS INSTALLED — OK │\n╰────────────────────────╯" ;;
  esac
}
