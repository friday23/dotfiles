# ==============================================================================
# Plugin: General Utilities & Helpers
# ==============================================================================

# 1. Useful Navigation & System Aliases
alias cls='clear'
alias df='df -h'                         # Human-readable disk usage
alias free='free -m'                     # Megabyte memory usage
alias myip='curl -s ifconfig.me && echo' # Quick public IP check

# 2. Universal Archive Extractor Function
# Handles almost any compression format using local variables and switch-cases
extract() {
  if [ -z "$1" ]; then
    echo "Usage: extract <archive_file>"
    return 1
  fi

  if [ -f "$1" ]; then
    local target="$1"
    case "$target" in
    *.tar.bz2) tar xvjf "$target" ;;
    *.tar.gz) tar xvzf "$target" ;;
    *.bz2) bunzip2 "$target" ;;
    *.rar) unrar x "$target" ;;
    *.gz) gunzip "$target" ;;
    *.tar) tar xvf "$target" ;;
    *.tbz2) tar xvjf "$target" ;;
    *.tgz) tar xvzf "$target" ;;
    *.zip) unzip "$target" ;;
    *.7z) 7z x "$target" ;;
    *) echo "Error: '$target' format not recognized by extract()." ;;
    esac
  else
    echo "Error: '$1' is not a valid file."
    return 1
  fi
}
