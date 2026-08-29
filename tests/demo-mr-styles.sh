#!/usr/bin/env bash
O=$'\033[0m'; U='https://gitlab.com/newell-paul1/suspensions/-/merge_requests/23'
L=$'\033]8;;'"$U"$'\a'; E=$'\033]8;;\a'
row(){ printf '  %-28s %s\n' "$1" "$2"; }
printf '\n'
row "1 underline only"        "$L"$'\033[4m\033[38;5;46m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "2 underline + blue"      "$L"$'\033[4m\033[38;5;39m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "3 curly blue underline"  "$L"$'\033[4:3m\033[58;5;39m\033[38;5;46m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "4 nerd gitlab glyph"     "$L"$'\033[38;5;208m\033[0m \033[4m\033[38;5;39m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "5 nerd merge glyph"      "$L"$'\033[38;5;39m \033[4m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "6 powerline pill"        "$L"$'\033[38;5;236m\033[48;5;236m\033[38;5;39m !23 \033[38;5;46m✓ \033[0m\033[38;5;236m'"$O$E"
row "7 solid green pill"      "$L"$'\033[38;5;22m\033[48;5;22m\033[1m\033[38;5;46m !23 ✓ \033[0m\033[38;5;22m'"$O$E"
row "8 truecolor gitlab"      "$L"$'\033[38;2;252;109;38m\033[4m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "9 dim label + bold ref"  "$L"$'\033[2mmr\033[0m \033[1;4m\033[38;5;39m!23'"$O"$' \033[38;5;46m✓'"$O$E"
row "10 arrow affordance"     "$L"$'\033[38;5;46m!23 ✓\033[0m \033[38;5;39m↗'"$O$E"
printf '\n'
