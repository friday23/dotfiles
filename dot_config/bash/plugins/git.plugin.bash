# Guard clause: ensure git is installed before loading git utilities
if ! command -v git &>/dev/null; then
  return
fi

# Git Aliases
alias gst='git status'
alias gco='git checkout'
alias gcb='git checkout -b'
alias gcm='git commit -m'

# Git Function: Quick branch cleaner
git-clean-branches() {
  echo "Pruning merged local branches..."
  git branch --merged | grep -v "\*" | grep -v "main" | grep -v "master" | xargs -n 1 git branch -d
}
