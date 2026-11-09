# breeze.fish

Numbered `git status` for [fish](https://fishshell.com): refer to files by
number instead of typing paths.

```console
$ breeze status
On branch main
Changes to be committed:
	[1] new file:   staged-new.txt

Changes not staged for commit:
	[2] deleted:    del.txt
	[3] modified:   mod.txt
	[4] modified:   src/deep.txt

Untracked files:
	[5] newdir/
	[6] with space.txt

$ breeze add 1 3-4 6
> Running: git add staged-new.txt mod.txt src/deep.txt 'with space.txt'
```

## Install

```sh
fisher install soraxas/breeze.fish
```

## Usage

```
breeze status                     git status, with numbers
breeze add [-s|--show-status] [--dry] [-m <COMMIT_MSG>] <NUMERIC>...
breeze <diff|stash|checkout|mv|rm|restore|reset|log> <NUMERIC>...
breeze _show_files                print the numbered file list
```

`NUMERIC` can be a number (`3`), a comma list (`4,5`), a range (`7-11`), an
open range (`3-`, from 3 to the end) or a plain filename/option, which is
passed through unchanged:

```sh
breeze add 3 foobar          # add [3] and the file 'foobar'
breeze add 4 -m add README   # add [4], then commit with message 'add README'
breeze add 2 -p              # add [2] with git's -p
breeze rm 5 --cached         # git rm --cached [5]
breeze mv 1 NEW_NAME         # rename [1] to NEW_NAME
breeze --dry add 1-3         # only print the git command
```

Set `__fish_breeze_show_num_before_fname` to `true` to put the number right
before the filename (`modified:   [3] mod.txt`) instead of before the status.

### How numbering works

breeze runs `git status` **once** and builds both the display and the file
list from that one output, so the number you see is always the file you get.

- Files are numbered top to bottom, in display order.
- A file shown in more than one section (e.g. staged and also modified again)
  keeps its first number.
- A rename is numbered by its new path (`renamed: a -> b` refers to `b`).
- Submodules are numbered by their path (`sub (new commits)` refers to `sub`).
- Paths are relative to your current directory, like `git status` shows them.

breeze reads git's English output (it runs git with `LC_ALL=C`) and forces the
long format, so a `status.short` setting doesn't break it.

## Tests

```sh
fish --no-config tests/test_breeze.fish [REF]
```

The script builds throwaway repos (renames, staged + modified files, merge
conflicts, submodules, spaces and `%` in names, similar names, running from a
subdirectory, a clean repo, outside a repo) with your git config and locale
switched off, and checks that:

- the numbers point at the file on the same line, and run 1..N top to bottom;
- `breeze --dry add` turns the numbers into the files shown;
- the output matches the version at `REF` (default `f45681b`, the last version
  that ran git twice) once the `[N]` markers are removed, and both versions
  point the same lines at the same files.

If `git` is slow on your machine, put a faster one first on `PATH` for the run.
