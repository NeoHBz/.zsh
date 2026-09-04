run() {
  local package_manager="bun"
  local file_arg="$1"
  local choice=""
  local -a run_args=("$@")

  # Handle direct file execution if a file argument is provided
  if [ -n "$file_arg" ] && [ -f "$file_arg" ]; then
    local file_ext="${file_arg##*.}"
    
    # Run based on file extension
    case "$file_ext" in
      ts)
        eval "ts-node $file_arg"
        return 0
        ;;
      php)
        eval "php -S localhost:9999 $file_arg"
        return 0
        ;;
      json)
        # Set appropriate choice based on json file type
        if [[ "$file_arg" == *"package.json" ]]; then
          choice="p"
        elif [[ "$file_arg" == *"composer.json" ]]; then
          choice="c"
        else
          echo "Unsupported JSON file: $file_arg"
          return 1
        fi
        ;;
      js|cjs|mjs)
        # Check for ecosystem config file
        if [[ "$file_arg" == *"ecosystem.config."* ]]; then
          choice="e"
        else
          # Handle as a regular JavaScript file
          eval "node $file_arg"
          return 0
        fi
        ;;
      *)
        echo "Unsupported file type: $file_ext"
        return 1
        ;;
    esac
  fi

  # If file_arg was given but isn't an existing file, check package.json scripts
  # for a keyword match (e.g. `run usb` matches a script named "usb-dev")
  if [ -n "$file_arg" ] && [ -z "$choice" ] && [ -f "package.json" ]; then
    local jq_out
    jq_out=$(jq -r --arg kw "$file_arg" \
      '.scripts // {} | keys[] | select((. | ascii_downcase) | contains($kw | ascii_downcase))' \
      package.json 2>/dev/null)

    if [ -n "$jq_out" ]; then
      local -a script_matches
      script_matches=("${(@f)jq_out}")
      local chosen_script=""

      if [ "${#script_matches[@]}" -eq 1 ]; then
        chosen_script="${script_matches[1]}"
      elif command -v gum &>/dev/null; then
        chosen_script=$(gum choose "${script_matches[@]}")
      else
        echo "Multiple matching scripts found for '$file_arg':"
        local i=1 s
        for s in "${script_matches[@]}"; do
          echo "  $i) $s"
          i=$((i + 1))
        done
        printf "Select a script number: "
        local sel
        read -r sel
        chosen_script="${script_matches[$sel]}"
      fi

      if [ -n "$chosen_script" ]; then
        eval "$package_manager run $chosen_script"
        return 0
      fi
    fi
  fi

  # Determine which configuration to use if not already set
  if [ -z "$choice" ]; then
    # Check for ecosystem config files
    local ecosystem_file=""
    [ -f "ecosystem.config.js" ] && ecosystem_file="ecosystem.config.js"
    [ -f "ecosystem.config.cjs" ] && ecosystem_file="ecosystem.config.cjs"
    [ -f "ecosystem.config.mjs" ] && ecosystem_file="ecosystem.config.mjs"
    local docker_compose_file=""
    [ -f "docker-compose.yml" ] && docker_compose_file="docker-compose.yml"
    [ -f "docker-compose.yaml" ] && docker_compose_file="docker-compose.yaml"
    
    if [ -n "$ecosystem_file" ]; then
      if [ -f "package.json" ] || [ -f "composer.json" ] || [ -f ".turbo" ] || [ -f "turbo.json" ] || [ -n "$docker_compose_file" ]; then
        # Build options list for user selection
  local -a menu_options
  menu_options=()
        [ -f "package.json" ] && menu_options+=("package.json (p)")
        [ -f "composer.json" ] && menu_options+=("composer.json (c)")
        ([ -f ".turbo" ] || [ -f "turbo.json" ]) && menu_options+=(".turbo/turbo.json (t)")
        [ -n "$docker_compose_file" ] && menu_options+=("$docker_compose_file (d)")
        menu_options+=("$ecosystem_file (e)")

        if command -v gum &>/dev/null; then
          choice=$(gum choose "${menu_options[@]}")
        else
          echo "gum not installed; defaulting to ${menu_options[1]}"
          choice="${menu_options[1]}"
        fi
    # Extract the letter inside parentheses, e.g. "package.json (p)" -> "p"
    local _letter="${choice##*\(}"
    _letter="${_letter%\)}"
        if [ -n "$_letter" ] && [ "$_letter" != "$choice" ]; then
          choice="$_letter"
        else
          choice=${choice:0:1}
        fi
      else
        echo "$ecosystem_file is present. Do you want to run it? (y/n, default: y): "
        if command -v gum &>/dev/null; then
          choice=$(gum confirm && echo "e" || echo "n")
        else
          printf "[Y/n] "
          local ans
          read -r ans
          if [ -z "$ans" ] || [[ "$ans" =~ ^[Yy]$ ]]; then
            choice="e"
          else
            choice="n"
          fi
        fi
      fi
    elif [ -f "composer.json" ]; then
      choice="c"
    elif [ -f "package.json" ]; then
      if [ -f ".turbo" ] || [ -f "turbo.json" ]; then
        choice="t"
      else
        choice="p"
      fi
    elif [ -f ".turbo" ] || [ -f "turbo.json" ]; then
      choice="t"
    elif [ -n "$docker_compose_file" ]; then
      choice="d"
    else
      echo "No supported configuration files found in the current directory."
      return 1
    fi
  fi

  # Execute based on the determined choice
  case "$choice" in
    p)
      # Run package.json scripts
      if [ -f "package.json" ]; then
        for script in "dev" "start"; do
          if [ "$(jq -r ".scripts.$script != null" package.json)" = "true" ]; then
            eval "$package_manager $script"
            return 0
          fi
        done
      fi
      return 1
      ;;
    e) 
      # Run ecosystem config
      local ecosystem_file=""
      [ -f "ecosystem.config.js" ] && ecosystem_file="ecosystem.config.js"
      [ -f "ecosystem.config.cjs" ] && ecosystem_file="ecosystem.config.cjs"
      [ -f "ecosystem.config.mjs" ] && ecosystem_file="ecosystem.config.mjs"
      [ -n "$file_arg" ] && ecosystem_file="$file_arg"
      eval "pm2 start $ecosystem_file" 
      ;;
    t)
      # Run turbo scripts (dev/start/build) if available in turbo.json
      if [ -f ".turbo" ] || [ -f "turbo.json" ]; then
        if [ -f "turbo.json" ]; then
          for script in "dev" "start" "build"; do
            if jq -e "(.pipeline // .tasks // {}) | has(\"$script\")" turbo.json >/dev/null 2>&1; then
              eval "turbo run $script"
              return 0
            fi
          done
        fi

        # Fallback to turbo build if no scripts were found in turbo.json
        eval "turbo run build"
        return 0
      fi
      return 1
      ;;
    c)
      # Run PHP Composer projects
      if [ -f "composer.json" ]; then
        # Try scripts in priority order
        for script in "serve" "start" "dev"; do
          if [ "$(jq -r ".scripts.$script != null" composer.json)" = "true" ]; then
            eval "composer $script"
            return 0
          fi
        done
        
        # Fallbacks if no scripts found
        if [ -f "artisan" ]; then
          eval "php artisan serve"
        else
          eval "php -S localhost:9999"
        fi
        return 0
      fi
      return 1
      ;;
    d)
      # Run docker compose
      if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        docker compose "${run_args[@]}"
        return $?
      fi
      return 1
      ;;
    n)
      echo "Skipping running ecosystem.config.js"
      ;;
    *)
      echo "Invalid choice. Please select a valid option."
      return 1
      ;;
  esac
}
