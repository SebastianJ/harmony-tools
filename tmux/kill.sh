#!/bin/bash

sessions=($(tmux ls))

if (( ${#sessions[@]} )); then
  for session in "${sessions[@]}"; do
    if [[ $session =~ ^harmony ]]; then
      echo "Found session ${session} - will proceed to terminate it..."
      tmux send -t "${session}" C-c
      tmux send -t "${session}" "exit"
      tmux send -t "${session}" Enter
    fi
  done
fi
