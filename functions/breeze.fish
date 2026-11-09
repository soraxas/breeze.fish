set -l __breeze_light_supported_numeric_subcommands \
    diff stash checkout add mv rm restore reset log
set -l __breeze_light_supported_numeric_subcommands (path sort -- $__breeze_light_supported_numeric_subcommands)

set -l __breeze_light_subcommands \
    "status:Git status with numeric number inserted" \
    "_show_files:Display the internal file list in breeze" \
    "_complete:Print out completions string"

# main function
function breeze \
    --inherit-variable __breeze_light_supported_numeric_subcommands \
    --inherit-variable __breeze_light_subcommands

    argparse --ignore-unknown s/show-status d-dry -- $argv

    set -l cmd $argv[1]
    set -e argv[1]

    function __breeze_light_color_echo
        set_color green
        echo -e $argv 1>&2
        set_color normal
    end

    if test "$cmd" = status
        __breeze_light_show_status

    else if test "$cmd" = add

        # check for message flag
        set -l msg_idx (contains --index -- '-m' $argv)
        if test -n "$msg_idx"
            if test $msg_idx -lt (count $argv)
                # there are messages after the -m message. (sanity check)
                set commit_msg $argv[(math "$msg_idx + 1")..-1]
                set argv -- $argv[1..(math "$msg_idx - 1")]
            end
        end

        # add if it is non-empty
        set -l target_files (__breeze_light_parse_user_input $argv)
        if test -z "$target_files"
            __breeze_light_color_echo "No files to add."
            return 1
        end

        set -l cmd git add $target_files
        __breeze_light_color_echo "> Running: $cmd"
        not set -q _flag_dry
        and eval "$cmd"

        test $status -eq 0
        or return $status

        # perform commit with the message being all args after the flag
        if set -q commit_msg
            __breeze_light_color_echo "> Running: git commit -sm \"$commit_msg\""
            not set -q _flag_dry
            and git commit -sm "$commit_msg"
        end

        # perform show status if -s is specified
        if set -q _flag_show_status
            __breeze_light_color_echo "> Running: git status"
            not set -q _flag_dry
            and __breeze_light_show_status
        end

    else if string match -q "$cmd" $__breeze_light_supported_numeric_subcommands
        # it's important for this to be a fallback (after the previous specialised cmds)
        set -l cmd git "$cmd" (__breeze_light_parse_user_input $argv)
        __breeze_light_color_echo "> Running: $cmd"
        not set -q _flag_dry
        and eval "$cmd"

    else if test "$cmd" = _complete
        printf "%s\tPassthrough (replaces numeric)\n" $__breeze_light_supported_numeric_subcommands
        printf "%s\t%s\n" (string split ':' $__breeze_light_subcommands)
    else if test "$cmd" = _show_files
        set -l i 1
        set -l fnames (__breeze_light_get_filelist)
        or return
        for fname in $fnames
            printf '[%i] %s\n' $i "$fname"
            set i (math "$i + 1")
        end
    else
        printf "Usage: breeze <COMMAND>\n"
        printf "       breeze add [-s|--show-status] [--dry] [-m <COMMIT_MSG>]\n"
        printf "\n"
        printf "COMMAND:\n"
        printf "\t%-8s\t%s\n" (eval (status current-function) _complete | string replace -r '\t' '\n')
        printf "\n"
        printf "OPTIONS:\n"
        printf "  -s --show-status  %s\n" "Display status afterwards, for easy reference."
        printf "  --dry             %s\n" "Echo what will be performed, but don't do anything."
        printf "  -m                %s\n" "Immediately commit, and everything after this flag will the message."
        printf "\n"
        printf "NUMERIC: [numeric|comma separated|range|filename]\n"
        printf "\n"
        printf "EXAMPLE:\n"
        printf "    breeze add 1 2 4\n"
        printf "    breeze add 4,5 7-11 13-14\n"
        printf "    breeze add 3 foobar          (Add 3rd on list, and the file 'foobar')\n"
        # printf "    breeze add -3                (Implies [1-3])\n"
        # printf "    breeze add 3-                (Implies [3] till end of list)\n"
        printf "    breeze add 4 -m add README   (Add [4]; after succeeded, commit with msg 'add README')\n"
        printf "    breeze add 2 -p              (Add [2] with git's patch flag '-p') \n"
        printf "    breeze rm 5 --cached         (remove [5] with cached option)\n"
        printf "    breeze mv 1 NEW_NAME         (rename [1] to new_file)\n"
        return 1
    end

end

function __breeze_light_helper_get_bracket_num
    # This helps to align the bracket numbers
    # by prefixing spaces
    set -l num_length (string length $argv[1])
    set -l max_num_length (string length $argv[2])
    set -l spaces_needed (string repeat ' ' -n (math "$max_num_length - $num_length"))
    echo "$spaces_needed"'['$argv[1]']'
end

function __breeze_light_collect -d "run git status ONCE; fill the display lines and the numbered file list"
    # Both `breeze status` (display) and `breeze add N` (numbering) are derived
    # from this single `git status` call, so the numbers always agree and we
    # never pay for two git processes (each exec can be expensive).
    #
    # Sets globals:
    #   __breeze_light_lines     raw (coloured) git status lines
    #   __breeze_light_line_idx  per line: file number, or 0 if not a file line
    #   __breeze_light_files     file paths, numbered in display order
    set -g __breeze_light_lines
    set -g __breeze_light_line_idx
    set -g __breeze_light_files

    # --long: ignore a user's `status.short = true`
    # LC_ALL=C: fixed English labels/headers, so the parsing below is stable
    set -l raw (LC_ALL=C command git -c color.status=always status --long)
    or return $status

    set -l section
    for line in $raw
        set -l clean (string replace -ra -- '\x1B\[[0-?]*[ -/]*[@-~]' '' $line)
        set -l idx 0

        if string match -q -- \t'*' $clean
            # a file line (always tab-indented in the long format)
            set -l path (string sub --start 2 -- $clean)
            if test "$section" != untracked
                #   modified:   foo          renamed:    a -> b
                #   both modified:   foo     modified:   sub (new commits)
                set path (string replace -r -- '^(new file|modified|deleted|renamed|copied|typechange|unknown|unmerged|both deleted|added by us|deleted by them|added by them|deleted by us|both added|both modified):\s+' '' $path)
                set path (string replace -r -- ' \((?:new commits|modified content|untracked content)(?:, (?:new commits|modified content|untracked content))*\)$' '' $path)
                # rename/copy: number the new path
                set path (string split -m1 -- ' -> ' $path)[-1]
            end
            # a path listed in several sections keeps its first number
            if not set idx (contains -i -- $path $__breeze_light_files)
                set -a __breeze_light_files $path
                set idx (count $__breeze_light_files)
            end
        else if string match -q -- 'Untracked files:' $clean; or string match -q -- 'Ignored files:' $clean
            set section untracked
        else if string match -qr -- '^\S.*:$' $clean
            # Changes to be committed: / Changes not staged for commit: / Unmerged paths:
            set section tracked
        end

        set -a __breeze_light_line_idx $idx
        set -a __breeze_light_lines $line
    end
end


function __breeze_light_get_filelist -d "retrieve list of files from this repo"
    __breeze_light_collect
    or return $status
    # (printf with no arguments would still print one empty line)
    set -q __breeze_light_files[1]
    and printf '%s\n' $__breeze_light_files
    return 0
end


function __breeze_light_show_status -d "add numeric to git status"
    __breeze_light_collect
    or return $status

    set -l num_files (count $__breeze_light_files)
    set -l n 0
    for line in $__breeze_light_lines
        set n (math $n + 1)
        set -l idx $__breeze_light_line_idx[$n]

        if test "$idx" -le 0
            # this line is not a file status line
            printf '%s\n' $line
            continue
        end

        if test "$__fish_breeze_show_num_before_fname" = true
            # place number right before the filename
            set -l file $__breeze_light_files[$idx]
            string replace -- "$file" "[$idx] $file" $line
            continue
        end

        # place number right after the first ANSI colour code
        # (string match --index gives "start length" of the token)
        if set -l start_color_code (string match --index -r '\e\[[0-9;]+m' $line | string split ' ')
            # line prefix (i.e. whitespace + colorcode)
            set -l prefix (string sub --length (math "$start_color_code[1] + $start_color_code[2] - 1") -- $line)
            # line main (i.e. file status + the suffix bits)
            set -l suffix (string sub --start (math "$start_color_code[1] + $start_color_code[2]") -- $line)
            printf '%s%s %s\n' $prefix (__breeze_light_helper_get_bracket_num $idx $num_files) $suffix
        else
            printf '%s %s\n' (__breeze_light_helper_get_bracket_num $idx $num_files) $line
        end
    end
end

function __breeze_light_parse_user_input -d "parse user's numeric input to breeze"
    # allow using comma to separate numbers, so we will first iterate all args and
    # split if it contains comma
    set -l argv (string split -- ',' $argv)
    # set -l file_names (git status --porcelain | string sub --start 4)
    set -l file_names (__breeze_light_get_filelist)

    set -l num_files (count $file_names)

    function __breeze_light_sanity_chk_start_num
        if not test $argv[1] -gt 0
            echo "[ERROR]: starting num '$argv[1]' must be > 0. Skipping." 1>&2
            return 1
        end
        return 0
    end

    function __breeze_light_sanity_chk_end_num
        set -l num_files $argv[2]
        if not test $argv[1] -le $num_files
            echo "[ERROR]: ending num '$argv[1]' must be <= range '$num_files'. Skipping." 1>&2
            return 1
        end
        return 0
    end

    function __breeze_light_sanity_chk_start_end_num
        # ensure n is smaller than m
        if not test $argv[1] -lt $argv[2]
            echo "[ERROR]: starting num '$argv[1]' must be < ending num '$argv[2]'. Skipping." 1>&2
            return 1
        end
        return 0
    end

    function __breeze_light_echo_file_with_quote
        # if there are surrounding double quotes (newer git version adds
        # quotes for git status --short), remove them, as fish echo do
        # not need to be nazi quotes.
        if string match -qr -- '^"[^"]*"$' "$argv[1]"
            set argv[1] (string sub --start 2 --length (math (string length -- $argv[1])"-2") -- $argv[1])
        end
        # if there are space(s) within the arg, add surrounding quotes
        if string match -qr -- '^[^\'"].*[ ].*[^\'"]$' "$argv[1]"
            set argv[1] "'$argv[1]'"
        end

        echo $argv[1]
    end

    function __breeze_light_echo_range_files
        set -l start_n $argv[1]
        set -l end_n $argv[2]
        set -e argv[1]
        set -e argv[1]
        set -l i $start_n
        while test $i -le $end_n
            __breeze_light_echo_file_with_quote $argv[$i]
            set i (math $i + 1)
        end
    end
    # set -l num_files $argv[1]

    set -l target_files

    for arg in $argv

        # for normal case of one single numeric
        if string match -q -r -- '^[0-9]+$' $arg
            __breeze_light_sanity_chk_start_num $arg
            or continue
            __breeze_light_sanity_chk_end_num $arg $num_files
            or continue

            __breeze_light_echo_file_with_quote $file_names[$arg]

            # for case n-m
        else if string match -q -r -- '^[0-9]+-[0-9]+$' $arg
            set -l idxes (string split '-' $arg)
            __breeze_light_sanity_chk_start_end_num $idxes[1] $idxes[2]
            or continue
            __breeze_light_sanity_chk_start_num $idxes[1]
            or continue
            __breeze_light_sanity_chk_end_num $idxes[2] $num_files
            or continue

            __breeze_light_echo_range_files $idxes[1] $idxes[2] $file_names

            ########################################
            # we want to make breeze works with arbitary pass-through options
            # so we will not support implies start. And maybe not implied end?
            ########################################

            # for case n- (implied end)
        else if string match -q -r -- '^[0-9]+-$' $arg
            # ensure n is > 0
            set arg (string sub --length (math (string length -- $arg)"-1") -- $arg)

            __breeze_light_sanity_chk_start_num $arg
            or continue
            __breeze_light_sanity_chk_end_num $arg $num_files
            or continue

            __breeze_light_echo_range_files $arg $num_files $file_names

            #     # for case -m (implied start)
            # else if string match -q -r -- '^-[0-9]+$' $arg
            #     # ensure m is < num_files
            #     set arg (string sub --start 2 -- $arg)

            #     __breeze_light_sanity_chk_start_num $arg
            #     or continue
            #     __breeze_light_sanity_chk_end_num $arg $num_files
            #     or continue

            #     __breeze_light_echo_range_files 1 $arg $file_names

            #     # probably is file name
        else
            __breeze_light_echo_file_with_quote $arg
        end

    end
end
