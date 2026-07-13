function gcd() {
    if git show-ref --verify --quiet refs/heads/dev; then
        git checkout dev
    elif git show-ref --verify --quiet refs/heads/development; then
        git checkout development
    else
        echo "dev branch not found"
    fi
}
