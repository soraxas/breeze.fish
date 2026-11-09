#!/usr/bin/env -S fish --no-config
# Tests for breeze: compares the working-tree version against an older
# version (the "reference", default f45681b = last two-git-call version)
# on the same throwaway repos, and checks the new version agrees with itself.
#
#   fish --no-config tests/test_breeze.fish [REF]
#
# Run with --no-config so your own config does not interfere / slow it down.
# Each git call can be slow on some machines; for a faster run put a plain
# git first on PATH, e.g.  PATH=/opt/homebrew/bin:$PATH fish --no-config tests/test_breeze.fish
#
# Checks per scenario:
#   same-text     status output is identical once the [N] markers are removed
#   same-files    both list the same files (old's rename source and quoting aside)
#   same-target   on every line both versions number, they point at the same file
#   self          new: each numbered line shows its file; numbers 1..N, top to bottom
#   fname-mode    new with __fish_breeze_show_num_before_fname=true puts "[N] file"
#   add           new: `breeze --dry add` resolves numbers to the displayed files

set -l root (path resolve (status dirname)/..)
set -l ref $argv[1]
set -q ref[1]; or set ref f45681b

set -g tmp (mktemp -d)
set -g new_src $root/functions/breeze.fish
set -g old_src $tmp/breeze.old.fish
git -C $root show $ref:functions/breeze.fish >$old_src
or begin
    echo "cannot read functions/breeze.fish at $ref" >&2
    exit 2
end

# Isolate from the user's/system git config and locale so output is stable.
set -gx GIT_CONFIG_NOSYSTEM 1
set -gx GIT_CONFIG_GLOBAL $tmp/gitconfig
set -gx LC_ALL C
printf '%s\n' '[user]' '  name = t' '  email = t@t' \
    '[init]' '  defaultBranch = main' \
    '[commit]' '  gpgsign = false' \
    '[protocol "file"]' '  allow = always' >$GIT_CONFIG_GLOBAL

set -g n_pass 0
set -g n_fail 0
set -g n_note 0
function ok
    set n_pass (math $n_pass + 1)
    echo "  ok    $argv"
end
function fail
    set n_fail (math $n_fail + 1)
    echo "  FAIL  $argv[1]"
    for l in $argv[2..-1]
        echo "          $l"
    end
end
function note
    set n_note (math $n_note + 1)
    echo "  note  $argv"
end

# run breeze from SRC inside DIR: bz SRC DIR args...
function bz
    command fish --no-config -c '
        source $argv[1]; or exit 98
        cd $argv[2]; or exit 99
        breeze $argv[3..-1]' $argv
end

# (helpers take arguments, never stdin: `string` in a function given zero
# arguments would read stdin instead)
function strip_ansi
    set -q argv[1]; or return 0
    string replace -ra -- '\x1B\[[0-?]*[ -/]*[@-~]' '' $argv
end
# remove the "[N] " marker (with its alignment padding)
function strip_num
    set -q argv[1]; or return 0
    string replace -r -- ' *\[\d+\] ' '' $argv
end
# number on a line, or 0
function line_num
    string match -rq -- '\[(?<n>\d+)\] ' $argv[1]; and echo $n; or echo 0
end
# old list entries can be "quoted" (git --short quotes odd names)
function unquote
    for f in $argv
        string replace -r -- '^"(.*)"$' '$1' $f
    end
end
# _show_files prints "[i] name"
function show_files
    set -l raw (bz $argv _show_files)
    set -q raw[1]; or return 0
    string replace -r -- '^\[\d+\] ' '' $raw
end
# 1..N (nothing for 0; `seq 0` prints "1 0")
function range -a n
    set -l i 1
    while test $i -le $n
        echo $i
        set i (math $i + 1)
    end
end

# check_scenario [--old-differs] NAME DIR
#   --old-differs: the reference is known to print this repo wrongly, so a
#   same-text mismatch is a note, not a failure
function check_scenario
    argparse old-differs -- $argv; or return
    set -l name $argv[1]
    set -l dir $argv[2]
    echo
    echo "== $name"
    set -l old_out (strip_ansi (bz $old_src $dir status))
    set -l new_out (strip_ansi (bz $new_src $dir status))
    set -l old_files (unquote (show_files $old_src $dir))
    set -l new_files (show_files $new_src $dir)

    # same-text
    set -l a (strip_num $old_out)
    set -l b (strip_num $new_out)
    if test "$a" = "$b"; and test (count $a) -eq (count $b)
        ok same-text
    else
        set -l msg
        for i in (range (math max (count $a), (count $b)))
            test "$a[$i]" = "$b[$i]"; or set -a msg "line $i: old='$a[$i]' new='$b[$i]'"
        end
        if set -q _flag_old_differs
            note "same-text differs as expected: $msg"
        else
            fail same-text $msg
        end
    end

    # same-files (old also lists a rename's source path; new does not)
    set -l rename_src (string match -rg -- '^\s*renamed:\s+(.*) -> ' $b)
    set -l missing
    for f in $old_files
        contains -- $f $new_files $rename_src; or set -a missing "only in old: $f"
    end
    for f in $new_files
        contains -- $f $old_files; or set -a missing "only in new: $f"
    end
    if set -q missing[1]
        fail same-files $missing
    else
        ok "same-files ("(count $new_files)")"
    end

    # same-target
    set -l bad
    set -l old_unnumbered
    for i in (range (count $new_out))
        set -l m (line_num $old_out[$i])
        set -l n (line_num $new_out[$i])
        test $n -gt 0; or continue
        if test $m -eq 0
            set -a old_unnumbered "$b[$i]"
            continue
        end
        # old numbered a rename by "a -> b" pieces; compare on the new path
        set -l old_target (string split -m1 -- ' -> ' $old_files[$m])[-1]
        test "$old_target" = "$new_files[$n]"
        or set -a bad "'$b[$i]': old [$m]=$old_files[$m]  new [$n]=$new_files[$n]"
    end
    if set -q bad[1]
        fail same-target $bad
    else
        ok same-target
    end
    for l in $old_unnumbered
        note "old left unnumbered: $l"
    end

    # self
    set -l bad
    set -l seen
    for i in (range (count $new_out))
        set -l n (line_num $new_out[$i])
        test $n -gt 0; or continue
        string match -q -- "*$new_files[$n]*" $b[$i]
        or set -a bad "line '$b[$i]' has [$n] but file $n is '$new_files[$n]'"
        if not contains -- $n $seen
            test $n -eq (math (count $seen) + 1)
            or set -a bad "[$n] appears before [(math (count $seen) + 1)]"
            set -a seen $n
        end
    end
    test (count $seen) -eq (count $new_files)
    or set -a bad "numbered "(count $seen)" of "(count $new_files)" files"
    if set -q bad[1]
        fail self $bad
    else
        ok self
    end

    # fname-mode
    set -l fm (strip_ansi (command fish --no-config -c '
        set -g __fish_breeze_show_num_before_fname true
        source $argv[1]; cd $argv[2]; breeze status' $new_src $dir))
    set -l bad
    for i in (range (count $new_out))
        set -l n (line_num $new_out[$i])
        test $n -gt 0; or continue
        string match -q -- "*[$n] $new_files[$n]*" $fm[$i]
        or set -a bad "expected '[$n] $new_files[$n]' in '$fm[$i]'"
    end
    if set -q bad[1]
        fail fname-mode $bad
    else
        ok fname-mode
    end

    # add
    set -l nf (count $new_files)
    if test $nf -eq 0
        set -l got (strip_ansi (bz $new_src $dir --dry add 1 2>&1))
        if string match -q -- '*git add*' $got
            fail "add 1 with no files" "got: $got"
        else
            ok "add 1 with no files is refused"
        end
    else
        set -l expect
        for f in $new_files
            string match -q -- '* *' $f; and set f "'$f'"
            set -a expect $f
        end
        set -l range 1
        test $nf -ge 2; and set range 1-$nf
        set -l got (strip_ansi (bz $new_src $dir --dry add $range 2>&1))
        set got (string replace -- '> Running: ' '' $got | string match -rv -- '^$')
        if test "$got" = "git add $expect"
            ok "add $range"
        else
            fail "add $range" "expected: git add $expect" "got:      $got"
        end
    end
end

function repo -a dir
    mkdir -p $dir
    and git -C $dir init -q
end
function commit_all -a dir
    git -C $dir add -A
    and git -C $dir commit -qm init
end

# ---------------------------------------------------------------- scenarios

set -l d $tmp/basic
repo $d
printf 'x\n' >$d/mod.txt
printf 'x\n' >$d/del.txt
mkdir $d/src
printf 'x\n' >$d/src/deep.txt
commit_all $d
printf 'y\n' >>$d/mod.txt
rm $d/del.txt
printf 'y\n' >>$d/src/deep.txt
printf 'n\n' >$d/staged-new.txt
git -C $d add staged-new.txt
printf 'u\n' >$d/untracked.txt
printf 'u\n' >"$d/with space.txt"
mkdir $d/newdir
printf 'u\n' >$d/newdir/a.txt
check_scenario "basic: modified/deleted/staged/untracked/space/dir" $d

set -l d $tmp/staged-and-rename
repo $d
printf 'x\n' >$d/both.txt
printf 'x\n' >$d/old-name.txt
commit_all $d
printf 'y\n' >>$d/both.txt
git -C $d add both.txt
printf 'z\n' >>$d/both.txt
git -C $d mv old-name.txt new-name.txt
check_scenario "staged+unstaged same file, staged rename" $d

set -l d $tmp/similar-names
repo $d
printf 'x\n' >$d/foo.bak
printf 'x\n' >$d/afoo
mkdir -p $d/dir
printf 'x\n' >$d/dir/foo
commit_all $d
for f in foo.bak afoo dir/foo
    printf 'y\n' >>$d/$f
end
printf 'u\n' >$d/foo
check_scenario "similar names (foo, afoo, foo.bak, dir/foo)" $d

set -l d $tmp/conflict
repo $d
printf 'base\n' >$d/c.txt
commit_all $d
git -C $d checkout -qb other
printf 'other\n' >$d/c.txt
git -C $d commit -qam other
git -C $d checkout -q main
printf 'main\n' >$d/c.txt
git -C $d commit -qam main
git -C $d merge -q other >/dev/null 2>&1
check_scenario "merge conflict" $d

set -l d $tmp/submodule
repo $d/inner
printf 'x\n' >$d/inner/i.txt
commit_all $d/inner
repo $d/outer
printf 'x\n' >$d/outer/o.txt
commit_all $d/outer
git -C $d/outer submodule -q add $d/inner sub 2>/dev/null
git -C $d/outer commit -qm sub
printf 'y\n' >>$d/outer/sub/i.txt
git -C $d/outer/sub commit -qam bump
printf 'y\n' >>$d/outer/o.txt
check_scenario "submodule with new commits" $d/outer

set -l d $tmp/subdir-cwd
repo $d
printf 'x\n' >$d/top.txt
mkdir $d/sub
printf 'x\n' >$d/sub/here.txt
commit_all $d
printf 'y\n' >>$d/top.txt
printf 'y\n' >>$d/sub/here.txt
check_scenario "run from a subdirectory (relative ../ paths)" $d/sub

set -l d $tmp/percent
repo $d
printf 'u\n' >"$d/pct%s.txt"
printf 'u\n' >"$d/100%.txt"
# old printed each line with `printf $line`, so % sequences were eaten
check_scenario --old-differs "percent signs in filenames (old version mangled them)" $d

set -l d $tmp/clean
repo $d
printf 'x\n' >$d/a.txt
commit_all $d
check_scenario "clean repo" $d

echo
echo "== outside a repo"
mkdir $tmp/norepo
bz $old_src $tmp/norepo status >/dev/null 2>&1
set -l old_rc $status
bz $new_src $tmp/norepo status >/dev/null 2>&1
set -l new_rc $status
if test $new_rc -ne 0
    ok "new fails (rc=$new_rc; old rc=$old_rc)"
else
    fail "new should fail outside a repo"
end

echo
echo "passed $n_pass, failed $n_fail, notes $n_note   (reference: $ref)"
rm -rf $tmp
test $n_fail -eq 0
