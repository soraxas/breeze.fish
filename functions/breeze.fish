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

function __breeze_light_get_filelist -d "retrieve list of files from this repo"
    # get file status from git
    # in git status --porcelain, the first two character is for
    # file status, and the third is a space. This is consistent,
    # so we can simply use substring rather than complex regex
    # set -l file_names (git status --porcelain | string sub --start 4)
    # Going to use git status short instead, as it supports relative path
    set -l file_names (git status --short | string sub --start 4)
    or return $status
    # if a file is renamed, it will be shown as XXXXX -> YYYYYY
    # add the two to file list as well.
    set -l i 1
    set -l num_files (count $file_names)
    while test $i -le $num_files
        # try to split
        set -l try_split (string split -- ' -> ' $file_names[$i])
        if test (count $try_split) -eq 2
            # append both to end of list
            set -e file_names[$i] # remove this non-file
            set -a file_names $try_split[1]
            set -a file_names $try_split[2]
        end
        set i (math "$i + 1")
    end
    printf '%s\n' $file_names
end

function __breeze_light_show_status -d "add numeric to git status"
    # if true, place [n] in front of the filename
    # else, place in front of the entire status.

    set -l file_names (__breeze_light_get_filelist)
    set -l num_files (count $file_names)

    # prepare a list of file names without surrounding double quotes
    set -l file_names_wo_quote
    for file in $file_names
        # remove surrounding double quotes if exists
        set -l file_wo_quote (string replace -r -- '^["](.*)["]$' '$1' $file)
        and set -l file $file_wo_quote
        set -a file_names_wo_quote $file
    end

    for line in (git -c color.status=always status)
        # A line that contains information about a gitfile will either be:
        #                 foo            <- for untracked
        #   modified:     bar
        #    deleted:     hello (new commits)
        #
        # i.e., three main variant
        # echo ---------------
        if string match -q -r '\e\[[0-9;]+m' $line

            # This line has some sort of escaped color code in it.
            # This must be a line that indicates a file within it

            # loop through the list of file and find exact match

            ################################################
            # (1) Method: looping to find highest matched file (old method)
            # # keep track of the highest matched fname
            # set -l max_match_length 0
            set -l idx -1
            # for i in (seq 1 (count $file_names_wo_quote))
            #     set -l file $file_names_wo_quote[$i]
            #     # find a file that has the maximum matched characters
            #     if string match -q "*$file*" "$line"
            #         set -l _tmp_length (string length -- $file)
            #         if test $_tmp_length -gt $max_match_length
            #             set max_match_length $_tmp_length
            #             set idx $i
            #         end
            #     end
            # end
            ################################################
            # (2) Method: using hashmap-like approach (to speed up)
            # This no longer use glob-search, but with exact match
            # we will do this by first splitting the line into line parts
            # and process it by progressively re-joining the parts
            # (that's because the prefix always are at the start of the line)
            # e.g. modified is at the start, whereas untracked files has no prefix

            # the follow line remove all ANSI escape color code
            # https://stackoverflow.com/questions/14693701/how-can-i-remove-the-ansi-escape-sequences-from-a-string-in-python
            set -l clean_line (string replace -ra -- '\x1B(?:[@-Z\\-_]|\[[0-?]*[ -/]*[@-~])' '' (string trim -- $line))
            # trim potential prefix (e.g. modified:)
            # or potential suffix (e.g. (new commits) for submodules)
            set clean_line (string replace -ra -- '(^\s*modified:\s)|(\s\(new commits\)\s*$)' '' $clean_line)

            set -l line_parts -- (string split -- ' ' $clean_line)
            set -l line_parts_n (count $line_parts)
            set -l i 1
            while test $i -le $line_parts_n
                set -l -- sub_line "$line_parts[$i..$line_parts_n]"
                if set __idx (contains -i -- "$sub_line" $file_names_wo_quote) # `set` won't modify $status, so this succeeds if `contains` succeeds
                    # find a matching file, most likely
                    set idx $__idx
                    break
                end
                set i (math $i + 1)
            end

            if test $idx -le 0
                # couldn't find a matching file?
                # print the original line
                echo $line
                continue
            end

            ################################################

            if test "$__fish_breeze_show_num_before_fname" = true
                # This is to place number right before the filename
                string replace -f "$file" "[$idx] $file" $line

            else
                # This is to place number right after the first ANSI escape color code

                # this finds the index of the starting color code, in the format of:
                # i j   ->  where i is the starting idx of the token and j is the length
                if set -l start_color_code (string match --index -r '\e\[[0-9;]+m' $line | string split ' ')

                    # line prefix (i.e. whitespace + colorcode)
                    set -l prefix (string sub --length (math "$start_color_code[1] + $start_color_code[2] - 1") $line)
                    # line main (i.e. file status + the suffix bits)
                    set -l suffix (string sub --start (math "$start_color_code[1] + $start_color_code[2]") $line)

                    printf $prefix"%s " (__breeze_light_helper_get_bracket_num $idx $num_files)
                    printf $suffix"\n"
                end
            end

        else
            # this line is not a file status line
            echo $line
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
