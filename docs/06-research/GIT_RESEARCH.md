# Remote Git Operations Research

## 1. Remote Execution Strategy: `git -C` vs Shell Chaining

When executing Git commands over an SSH transport session (`SshTransportHandle.run` or `exec`), commands can be targeted to a remote working directory in two primary ways:

1. **Shell Chaining**: `cd '/path/to/project' && git status`
2. **Directory Flag**: `git -C '/path/to/project' status`

### Comparison

| Factor | `cd <dir> && git ...` | `git -C <dir> ...` |
|---|---|---|
| **Subshell / Chaining** | Requires shell composition (`&&`, subshell execution) | Single process invocation without shell operators |
| **Error Handling** | Ambiguous exit code on `cd` failure vs `git` failure | Pure Git exit codes (`0`, `128`, `1`) |
| **Path Escaping** | Must escape path for `cd` AND handle shell parser | Standard POSIX single-quote escaping on argument |
| **Worktree / Subdir** | Depends on shell current working directory state | Internally resolved by Git kernel |
| **Availability** | All POSIX shells | Supported in Git 1.8.5+ (standard on all modern Linux distros) |

**Decision**: Use `git -C <workingDirectory> ...` for all Git operations. It provides clean separation, avoids shell chaining, and standardizes argument passing.

---

## 2. Machine-Readable Git Output Formats

Human-oriented Git commands (e.g. `git status`, `git branch -v`) vary based on user locale, terminal width, and Git configuration. To guarantee stable, deterministic parsing, we strictly use machine-readable formats.

### 2.1. Status: `git status --porcelain=v2 --branch`

`--porcelain=v2` (Git 2.11+) provides a well-defined format with explicit record types and line prefixes:

#### Branch Header Records (`#`)
- `# branch.oid <commit_hash> | (initial)`: Current HEAD commit hash.
- `# branch.head <branch_name> | (detached)`: Current branch name or `(detached)` for detached HEAD.
- `# branch.upstream <upstream_name>`: Upstream tracking branch (e.g. `origin/main`).
- `# branch.ab +<ahead> -<behind>`: Commits ahead/behind upstream.

#### Changed Entries (`1` - Ordinary change)
Format: `1 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <path>`
- `XY`: 2-character staging state (`X` = index / staged, `Y` = working tree / unstaged).
  - `.`: Unmodified
  - `M`: Modified
  - `A`: Added
  - `D`: Deleted
  - `T`: Type changed
- `sub`: Submodule state (e.g. `N...`).
- `mH`, `mI`, `mW`: Octal file modes in HEAD, Index, Worktree.
- `hH`, `hI`: SHA-1/SHA-256 object hashes.
- `path`: Target file path (relative to repo root).

#### Renamed/Copied Entries (`2`)
Format: `2 <XY> <sub> <mH> <mI> <mW> <hH> <hI> <X><score> <path>\t<origPath>`
- Captures renamed or copied files with origin and target path separated by tab (`\t`).

#### Unmerged Conflict Entries (`u`)
Format: `u <XY> <sub> <m1> <m2> <m3> <mW> <h1> <h2> <h3> <path>`
- Indicates merge conflict states (`DD`, `AU`, `UD`, `UA`, `DU`, `AA`, `UU`).

#### Untracked Entries (`?`)
Format: `? <path>`

#### Ignored Entries (`!`)
Format: `! <path>`

---

### 2.2. Commit Log: `git log --format` with ASCII Unit Separators

Using format delimiters like commas or spaces leads to parsing bugs when commit messages, authors, or subjects contain those characters.

We use the ASCII Unit Separator (`\x1f` / `31`) as an unambiguous delimiter between record fields:
```bash
git -C <workingDirectory> log -n 50 --format="%H%x1f%h%x1f%an%x1f%ae%x1f%at%x1f%s%x1f%P"
```
Fields:
1. `%H`: Full 40-character commit hash
2. `%h`: Abbreviated commit hash
3. `%an`: Author name
4. `%ae`: Author email
5. `%at`: Author timestamp (UNIX epoch seconds)
6. `%s`: Subject line (first line of commit message)
7. `%P`: Parent hashes (space separated)

---

### 2.3. Diff Generation

Diffs are retrieved as unified diff text (`-u` default) with size boundaries:
- **Unstaged Changes**: `git -C <dir> diff -- <path>` (or repo-wide: `git -C <dir> diff`)
- **Staged Changes**: `git -C <dir> diff --cached -- <path>` (or repo-wide: `git -C <dir> diff --cached`)

To prevent mobile memory exhaustion on massive diffs (e.g. lockfiles or generated assets), diffs are capped at a safe threshold (e.g., 64KB / 500 lines) with a clear `"Diff truncated"` indicator.

---

## 3. Path Option Injection Protection (`--`)

In Git CLI syntax, an argument beginning with `-` (e.g., `-rf`, `--help`, `-v`) is parsed as a flag/option rather than a file path unless disambiguated by `--`:

```bash
# VULNERABLE:
git add -f
# SAFE:
git add -- -f
```

**Rule**: All file path arguments in `git add`, `git restore`, `git diff`, and `git checkout` MUST be preceded by `--`.

---

## 4. Mutation Scope & Safety Policies

### Supported Safe Mutations
1. **Stage File**: `git -C <dir> add -- <path>`
2. **Unstage File**: `git -C <dir> restore --staged -- <path>`
3. **Commit**: `git -C <dir> commit -m <escaped_message>`
   - Requires explicit non-empty user commit message.
   - Operates strictly on existing staged changes.
   - Never uses `-a` (auto-stage).
   - Never uses `--amend` by default.

### Explicitly Blocked Commands
- `git push`, `git push --force` (`PUSH_DEFERRED`)
- `git reset --hard` (Blocked)
- `git clean -f`, `git clean -fd` (Blocked)
- `git checkout -- .`, `git restore .` (Blocked)
- `git config --global` (Blocked)

---

## 5. Sensitive File Patterns

Consistent with M4 SFTP policies, diff inspection must detect sensitive files before displaying plaintext diff contents:
- `.env`, `.env.*`
- `*.pem`, `*.key`, `*.p12`, `*.pfx`, `id_rsa`, `id_ed25519`
- `credentials*`, `secrets*`
- `*token*`, `*password*`
