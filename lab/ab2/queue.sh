#!/bin/bash
# Everything after the first Lab 8 pass, in order, one container at a time (a 2-core host can only take one).
# Lab 8 and 8b share one credit budget (BUDGET in ab.sh / ab2.sh). Logs: ab2/results/logs/queue.log
set -u
LAB="$(cd "$(dirname "$0")/.." && pwd)"
export MODEL EFFORT=medium
lab8_panel="grok-4.7 gpt-6-luna gpt-5.3-codex gemini-3.8-flash mai-code-1.1-flash kimi-k3 claude-haiku-5.5"
cd "$LAB/ab"
PANEL="$lab8_panel" ./ab.sh panel;        echo "LAB8_PANEL_EXIT=$?"
PANEL="$lab8_panel" ./ab.sh panel_check;  echo "LAB8_PANEL_CHECK_EXIT=$?"
cd "$LAB/ab2"
./ab2.sh baseline;                        echo "8B_BASELINE_EXIT=$?"
./ab2.sh recipe;                          echo "8B_RECIPE_EXIT=$?"
MODEL=claude-sonnet-5.5 ./ab2.sh agent;   echo "8B_AGENT_EXIT=$?"
./ab2.sh panel;                           echo "8B_PANEL_EXIT=$?"
./ab2.sh crosscheck;                      echo "8B_CROSSCHECK_EXIT=$?"
echo QUEUE_DONE
