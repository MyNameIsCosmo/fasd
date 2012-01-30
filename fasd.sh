#!/usr/bin/env sh
# This tool gives you quick access to your frequent/recent files
#
# INSTALL:
#   Source this file somewhere in your shell rc (.bashrc or .zshrc).
#
# SYNOPSIS:
#   fasd [options] [query ...]
#     options:
#       -s        show list of files with their ranks
#       -l        list paths only
#       -i        interactive mode
#       -e <cmd>  set command to execute on the result file
#       -a        match files and directories
#       -d        match directories only
#       -f        match files only
#       -r        match by rank only
#       -h        show a brief help message
#
# EXAMPLES:
#   f foo # list recent files mathcing foo
#   f foo bar # list recent files mathcing foo and bar
#   f -e vim foo # run vim on the most frecent file matching foo
#
# TIPS:
#   alias z="f -d -e cd"
#   alias v="f -e vim"
#   alias m="f -e mplayer"
#   alias o="f -e xdg-open"

fasd() {

  case "$1" in
  --init)
    [ -s "$HOME/.fasdrc" ] && . "$HOME/.fasdrc"
    # set default options
    [ -z "$_F_DATA" ] && _F_DATA="$HOME/.f"
    [ -z "$_F_BLACKLIST" ] && _F_BLACKLIST="--help"
    [ -z "$_F_SHIFT" ] && _F_SHIFT="sudo busybox"
    [ -z "$_F_IGNORE" ] && _F_IGNORE="fasd cd ls echo"
    [ -z "$_F_SINK" ] && _F_SINK=/dev/null
    [ -z "$_F_TRACK_PWD" ] && _F_TRACK_PWD=1
    [ -z "$_F_MAX" ] && _F_MAX=2000

    { if [ -z "$_F_AWK" ]; then
        # awk preferences
        for awk in gawk original-awk nawk mawk awk; do
          $awk "" && _F_AWK=$awk && break
        done
      fi
    } >> "$_F_SINK" 2>&1
    ;;

  --init-alias)
    cat <<EOS
    alias a='fasd -a'
    alias s='fasd -si'
    alias d='fasd -d'
    alias f='fasd -f'
    alias sd='fasd -sid'
    alias sf='fasd -sif'
EOS
  ;;

  --init-interactive)
    { # set default aliases
      eval "$(fasd --init-alias)"
      if compctl; then # zsh
        eval "$(fasd --init-zsh)"
      elif complete; then # bash
        eval "$(fasd --init-bash)"
      else # posix shell
        eval "$(fasd --init-posix)"
      fi
    } >> "$_F_SINK" 2>&1
    ;;

  --init-zsh)
    cat <<EOS
    # zsh command mode completion
    _f_zsh_cmd_complete() {
      local compl
      read -c compl
      compstate[insert]=menu # no expand
      eval 'reply=(\${(f)"\$(fasd --complete "\$compl")"})'
    }
    # enbale command mode completion
    compctl -U -K _f_zsh_cmd_complete -V f -x 'C[-1,-*e],s[-]n[1,e]' -c -- fasd
    # zsh word mode completion
    _f_zsh_word_complete() {
      [ "\$2" ] && local _f_cur="\$2"
      [ -z "\$_f_cur" ] && eval 'local _f_cur="\${words[CURRENT]}"'
      eval 'local fnd="\${_f_cur//,/ }"'
      local typ=\${1:-e}
      fasd --query \$typ \$fnd | sort -nr | sed 's/^[0-9.]*[ ]*//' | while read line; do
        compadd -U -V f "\$line"
      done
      compstate[insert]=menu # no expand
    }
    _f_zsh_word_complete_f() { _f_zsh_word_complete f ; }
    _f_zsh_word_complete_d() { _f_zsh_word_complete d ; }
    _f_zsh_word_complete_trigger() {
      eval 'local _f_cur="\${words[CURRENT]}"'
      # fasd --word-complete-trigger \$_f_cur 1>&2
      eval \$(fasd --word-complete-trigger _f_zsh_word_complete \$_f_cur)
    }
    # enable word mode completion
    zstyle ':completion:*' completer _complete _ignored \
      _f_zsh_word_complete_trigger
    # define zle widgets
    zle -C f-complete 'menu-select' _f_zsh_word_complete
    zle -C f-complete-f 'menu-select' _f_zsh_word_complete_f
    zle -C f-complete-d 'menu-select' _f_zsh_word_complete_d
    # add zsh hook
    _f_preexec() { { eval "fasd --add \$(fasd --sanitize \$3)"; } >> "\$_F_SINK" 2>&1; }
    autoload -U add-zsh-hook
    add-zsh-hook preexec _f_preexec
EOS
    ;;

  --init-bash)
    cat <<EOS
    # bash command mode completion
    _f_bash_cmd_complete() {
      # complete command after "-e"
      eval 'local cur=\${COMP_WORDS[COMP_CWORD]}
      [[ \${COMP_WORDS[COMP_CWORD-1]} == -*e ]] && \
        COMPREPLY=( \$(compgen -A command \$cur) ) && return'
      # get completion results using expanded aliases
      local RESULT=\$( fasd --complete "\$(alias -p \${COMP_WORDS} | \
        sed -n "\\\$s/^.*'\(.*\)'/\1/p") \${COMP_LINE#* }" )
      local IFS=\$'\n'
      eval 'COMPREPLY=( \$RESULT )'
    }
    _f_bash_hook_cmd_complete() {
      for cmd in \$*; do
        complete -F _f_bash_cmd_complete \$cmd
      done
    }
    # enable bash command mode completion
    _f_bash_hook_cmd_complete a s d f sd sf
    # bash word mode completion
    _f_bash_word_complete() {
      [ "\$_f_cur" ] || eval 'local _f_cur="\${COMP_WORDS[COMP_CWORD]}"'
      local typ=\${1:-e}
      eval 'local fnd="\${_f_cur//,/ }"'
      local RESULT=\$(fasd --query \$typ \$fnd | sed 's/^[0-9.]*[ ]*//')
      local IFS=\$'\n'
      eval 'COMPREPLY=( \$RESULT )'
    }
    _f_bash_word_complete_trigger() {
      [ "\$_f_cur" ] || eval 'local _f_cur="\${COMP_WORDS[COMP_CWORD]}"'
      eval "\$(fasd --word-complete-trigger _f_bash_word_complete \$_f_cur)"
    }
    _f_bash_word_complete_wrap() {
      eval 'local _f_cur="\${COMP_WORDS[COMP_CWORD]}"'
      _f_bash_word_complete_trigger
      eval 'local z=\${COMP_WORDS[0]}'
      # try original comp func
      [ "\$COMPREPLY" ] || eval "\$( echo "\$_F_BASH_COMPLETE_P" | \
        sed -n "/ \$z\$/"'s/.*-F \(.*\) .*/\1/p' )"
      # fall back on original complete options
      local cmd="\$(echo "\$_F_BASH_COMPLETE_P" | \
        sed -n "/ \$z\$/"'s/complete/compgen/') \$_f_cur"
      [ "\$COMPREPLY" ] || eval 'COMPREPLY=( \$(eval \$cmd) )'
    }
    _f_bash_hook_word_complete_wrap_all() {
      export _F_BASH_COMPLETE_P="\$(complete -p)"
      for cmd in \$(complete -p | awk '{print \$NF}' | tr '\n' ' '); do
        complete -o default -o bashdefault -F _f_bash_word_complete_wrap \$cmd
      done
    }
    # enable word mode completion as default completion
    complete -o default -o bashdefault -D -F _f_bash_word_complete_trigger
    # add bash hook
    echo \$PROMPT_COMMAND | grep -v -q "fasd --add" && \
      PROMPT_COMMAND='eval "fasd --add \$(fasd --sanitize \$(history 1 | \
      sed -e "s/^[ ]*[0-9]*[ ]*//"))" >> "\$_F_SINK" 2>&1;'"\$PROMPT_COMMAND"
EOS
    ;;

  --init-posix)
    cat <<EOS
    _f_ps1_func() {
      eval "fasd --add \$(fasd --sanitize \$(fc -nl -0 | sed -n '\$s/\s*\(.*\)/\1/p'))"
    }
    _f_ps1_install() {
      echo "\$PS1" | grep -v -q "_f_ps1_func" && \
      export PS1="\\\$(_f_ps1_func >> "\$_F_SINK" 2>&1)\$PS1"
    }
    echo "\$PS1" | grep -q '\\\\' && _f_ps1_install
    [ "\$KSH_VERSION" ] && _f_ps1_install # ksh has the compatibility
EOS
    ;;

  --readlink)
    shift; local p np
    case "$1" in
      /*) p="$1";;
      *) p="$PWD/$1";;
    esac
    np="$(echo "$p" | sed 's@[^/]*/*\.\.\(/\|$\)@@g;s@\./@@g;s@/\+@/@g;s@[./]*$@@')"
    [ -e "${np:=/}" ] || return 1
    echo "$np"
    ;;

  # if "$_f_cur" is a query, then eval all the arguments
  --word-complete-trigger)
    shift
    [ "$2" ] && local _f_cur="$2" || return
    case "$_f_cur" in
      ,*)
        echo "$1" e "$_f_cur";;
      f,*)
        echo "$1" f "${_f_cur#?}";;
      d,*)
        echo "$1" d "${_f_cur#?}";;
      *,,)
        echo "$1" e "$_f_cur";;
      *,,f)
        echo "$1" f "${_f_cur%?}";;
      *,,d)
        echo "$1" d "${_f_cur%?}";;
    esac
    ;;

  --sanitize)
    shift
    echo "$@" | sed 's/\(^\| \).\?[<>|]\+/ /g;s/&$//'
    ;;

  --add) # add entries
    shift

    # stop if we don't own ~/.f (we're another user but our ENV is still set)
    [ -f "$_F_DATA" -a ! -O "$_F_DATA" ] && return

    # make zsh do word splitting here
    [ "$ZSH_VERSION" ] && emulate sh && setopt localoptions

    # blacklists
    local each
    for each in $_F_BLACKLIST; do
      case " $* " in *\ $each\ *) return;; esac
    done

    # shifts
    while true; do
      case " $_F_SHIFT " in
        *\ $1\ *) shift;;
        *) break
      esac
    done

    # ignores
    case " $_F_IGNORE " in
      *\ $1\ *) return
    esac

    shift # shift out the command itself

    local paths
    while [ "$1" ]; do
      # add the adsolute path to "paths", and a separator "|"
      paths="$paths|$(fasd --readlink "$1" 2>> "$_F_SINK")"
      shift
    done

    # add current pwd if the option is set
    [ "$_F_TRACK_PWD" = "1" -a "$PWD" != "$HOME" ] && paths="$paths|$PWD"

    [ -z "${paths##|}" ] && return # stop if we have nothing to add

    # maintain the file
    local tempfile
    tempfile="$(mktemp $_F_DATA.XXXXXX)" || return
    $_F_AWK -v list="$paths" -v now="$(date +%s)" -v max="$_F_MAX" -F"|" '
      BEGIN {
        split(list, files, "|")
        for(i in files) {
          path = files[i]
          if ( path == "" ) continue
          paths[path] = path # array for checking
          rank[path] = 1
          time[path] = now
        }
      }
      $2 >= 1 {
        if( $1 in paths ) {
          rank[$1] = $2 + 1
          time[$1] = now
        } else {
          rank[$1] = $2
          time[$1] = $3
        }
        count += $2
      }
      END {
        if( count > max )
          for( i in rank ) print i "|" 0.9*rank[i] "|" time[i] # aging
        else
          for( i in rank ) print i "|" rank[i] "|" time[i]
      }' "$_F_DATA" 2>> "$_F_SINK" >| "$tempfile"
    if [ $? -ne 0 -a -f "$_F_DATA" ]; then
      env rm -f "$tempfile"
    else
      env mv -f "$tempfile" "$_F_DATA"
    fi
    ;;

  --query)
    shift
    [ "$1" ] && local typ="$1"
    [ "$2" ] && local fnd="$2"
    [ "$3" ] && local mode="$3"
    # query the database, this need some local variables to be set
    while read line; do
      [ -${typ:-e} "${line%%\|*}" ] && echo "$line"
    done < "$_F_DATA" | \
    $_F_AWK -v t="$(date +%s)" -v mode="$mode" -v q="$fnd" -F"|" '
      function frecent(rank, time) {
        dx = t-time
        if( dx < 3600 ) return rank*4
        if( dx < 86400 ) return rank*2
        if( dx < 604800 ) return rank/2
        return rank/4
      }
      function likelihood(pattern, path) {
        m = gsub( "/+", "/", path )
        r = 1
        for( i in pattern ) {
          tmp = path
          gsub( ".*" pattern[i], "", tmp)
          n = gsub( "/+", "/", tmp )
          if( n == m )
            return 0
          else if( n == 0 )
            r *= 20 # F
          else
            r *= 1 - ( n / m )
        }
        return r
      }
      function getRank() {
        if( mode == "rank" )
          f = $2
        else
          f = frecent($2, $3)
        wcase[$1] = f * likelihood( pattern, $1 )
        nocase[$1] = f * likelihood( pattern2, tolower($1) )
      }
      BEGIN {
        split(q, pattern, " ")
        for( i in pattern ) pattern2[i] = tolower(pattern[i]) # nocase
      }
      {
        getRank()
        cx = cx || wcase[$1]
        ncx = ncx || nocase[$1]
      }
      END {
        if( cx ) {
          for( i in wcase )
            if( wcase[i] ) printf "%-10s %s\n", wcase[i], i
        } else if( ncx ) {
          for( i in nocase )
            if( nocase[i] ) printf "%-10s %s\n", nocase[i], i
        }
      }' - 2>> "$_F_SINK"
    ;;

  *) # parsing logic and processing
    [ -f "$_F_DATA" ] || return # no db yet
    local fnd last
    while [ "$1" ]; do case "$1" in
      --complete) [ "$2" = "--" ] && shift; set -- $(echo $2); local list=1 r=r;;
      --) while [ "$2" ]; do shift; fnd="$fnd$1 "; last="$1"; done;;
      -*) local o="${1#-}"; while [ "$o" ]; do case $o in
          s*) local show=1;;
          l*) local list=1;;
          i*) local interactive=1 show=1;;
          r*) local mode=rank;;
          t*) local mode=recent;;
          e*) o="${o#?}"; if [ "$o" ]; then # there are characters after "-e"
                local exec=$o # anything after "-e"
              else # use the next argument
                local exec=${2:?"Argument needed after -e"}
                shift
              fi; break;;
          a*) local typ=e;;
          d*) local typ=d;;
          f*) local typ=f;;
          h*) echo "fasd [options] [query ...]
  options:
    -s        show list of files with their ranks
    -l        list paths only
    -i        interactive mode
    -e <cmd>  set command to execute on the result file
    -a        match files and directories
    -d        match directories only
    -f        match files only
    -r        match by rank only
    -h        show a brief help message" >&2; return;;
        esac; o="${o#?}"; done;;
      *) fnd="$fnd $1"; last="$1";;
    esac; shift; done

    # if we hit enter on a completion just execute
    case "$last" in
     # completions will always start with /
     /*) [ -z "$show$list" -a -${typ:-e} "$last" -a "$exec" ] \
       && $exec "$last" && return;;
    esac

    local result
    result="$(fasd --query 2>> "$_F_SINK")" # query the database
    [ $? -gt 0 ] && return
    if [ "$interactive" ]; then
      result="$(echo "$result" | sort -nr)"
      echo "$result" | sed = | sed 'N;s/\n/\t/' | sort -nr
      local i; printf "> "; read i; [ 0 -lt "$i" ] || exit 1
      ${exec:=echo} "$(echo "$result" | sed -n "${i:=1}"'s/^[0-9.]*[ ]*//p')"
    elif [ "$list" ]; then
      echo "$result" | sort -n${r} | sed 's/^[0-9.]*[ ]*//'
    elif [ "$show" ]; then
      echo "$result" | sort -n${r}
    elif [ "$fnd" -a "$exec" ]; then # exec
      $exec "$(echo "$result" | sort -n | sed -n '$s/^[0-9.]*[ ]*//p')"
    elif [ "$fnd" -a ! -t 1 ]; then # echo if output is not terminal
      echo "$result" | sort -n | sed -n '$s/^[0-9.]*[ ]*//p'
    else # no args, show
      echo "$result" | sort -n${r}
    fi

  esac
}

fasd --init

case "$-" in
  *i*) fasd --init-interactive;; # assume being sourced
  *) # assume being executed as an executable
    if [ -x "$_F_SHELL" -a -z "$_F_SET" ]; then
      _F_SET=1 $_F_SHELL "$0" "$@"
      exit $?
    else
      fasd "$@"
    fi
esac

