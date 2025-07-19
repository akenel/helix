#!/usr/bin/env bash

# Braille spinner for background jobs
spin() {
  local pid=$1
  local delay=0.1
  local spinstr="⠋⠙⠹⠸⠼⠴⠦⠧⠇⠏"
  local i=0

  tput civis # hide cursor
  while kill -0 $pid 2>/dev/null; do
    printf "\r🌀 Deploying %s " "${spinstr:i++%${#spinstr}:1}"
    sleep $delay
  done
  tput cnorm # restore cursor
  echo -ne "\r✅ Done                            \n"
}
