function gitnuke() {
  local current_branch=$(git rev-parse --abbrev-ref HEAD)

  if ! gum confirm "Delete all branches except $current_branch, main, dev, and development?"; then
    echo "Cancelled."
    return 1
  fi

  git branch | grep -v 'development\|dev\|main\|'"$current_branch" | xargs git branch -D
}
