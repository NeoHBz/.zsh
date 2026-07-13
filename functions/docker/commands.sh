alias ndc='[ -f docker-compose.yaml ] && nano docker-compose.yaml || nano compose.yaml'
alias dc="docker compose"
alias dcu="docker compose up"
alias dcd="docker compose down"
alias dcl="docker compose logs"
alias dcr="docker compose restart"
dps() {
  {
    printf '\033[1;36mCONTAINER ID\033[0m\t\033[1;32mNAME\033[0m\t\033[1;33mSTATUS\033[0m\t\033[1;35mPORTS\033[0m\n'
    docker ps --format '{{printf "\033[36m%s\033[0m" .ID}}\t{{printf "\033[32m%s\033[0m" .Names}}\t{{printf "\033[33m%s\033[0m" .Status}}\t{{printf "\033[35m%s\033[0m" .Ports}}'
  } | column -t -s $'\t'
}
