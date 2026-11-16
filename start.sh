#!/usr/bin/env bash
# Start the visa slot monitor.
#
# The Chrome automation tools only exist inside an INTERACTIVE Claude Code
# session -- `claude -p` headless runs cannot see them (verified: the tool
# comes back "not available"). So this script opens a real session and hands
# it the setup prompt. Leave the window open; closing it stops the monitor.
set -euo pipefail
cd "$(dirname "$0")"

[ -f config.json ] || { echo "No config.json. cp config.example.json config.json and fill it in." >&2; exit 1; }
./render.sh > run-prompt.txt

exec claude "监控启动。请做两件事：
1. 用 CronCreate 按 config.json 里的 interval_cron 建一个定时任务，任务内容是：\"武汉面签日期监控。先用 cat 读取 $(pwd)/run-prompt.txt，然后严格按照里面的步骤执行，不要改动、不要扩大范围。没有命中就安静结束，只输出一两行。\"
2. 然后立刻手动跑一轮，确认能读到日历，把结果告诉我。

注意：Chrome 必须开着并且已经登录签证网站。如果读不到，告诉我需要我做什么，不要自己去过人机验证。"
