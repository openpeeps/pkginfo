<p align="center">
    📦 A tiny utility package to extract Nimble metadata from any <code>.nimble</code> package<br>
</p>

<p align="center">
  <code>nimble install pkginfo</code> / <code>clue install pkginfo</code>
</p>

<p align="center">
  <a href="https://tim-engine.github.io/tim/">API reference</a><br>
  <img src="https://github.com/tim-engine/tim/workflows/test/badge.svg" alt="Github Actions">  <img src="https://github.com/tim-engine/tim/workflows/docs/badge.svg" alt="Github Actions">
</p>

## 😍 Key Features
- Read Nimble metadata at compile time and runtime
- Query current package and direct dependencies
- Conditional compilation with `requires()`
- Semver helpers via re-exported `semver`
- Fast `.pkginfo.json` cache
- Safe by default, never breaks your build

## Quick Start
```nim
import pkginfo

echo pkg().getName        # "pkginfo"
echo pkg().getVersion     # Version object, e.g. 0.2.0
echo pkg().getLicense     # "MIT"
echo $nimVersion()        # Nim constraint from .nimble, e.g. 1.6.4
```

## Examples

### 1. Read your own package info (compile time and runtime)
```nim
import pkginfo

static:
  # Runs at compile time via PackageCT
  echo pkg().getName
  echo pkg().getAuthor
  echo pkg().getDescription
  assert pkg().getLicense == "MIT"
  assert pkg().getVersion >= version("0.1.0")

# Same calls at runtime via Package
echo pkg().getName
echo pkg().getDescription
```

### 2. Conditionally compile on an optional dependency
```nim
import pkginfo

when requires("semver"):
  static:
    assert pkg("semver") != nil
    assert pkg("semver").getVersion > v("1.1.1")
    assert pkg("semver").getLicense == "BSD-3-Clause"
  echo "semver support enabled: ", $pkg("semver").getVersion
else:
  echo "building without semver"

when not requires("toktok"):
  static:
    assert pkg("toktok") == nil
```

### 3. Inspect dependencies at runtime
```nim
import pkginfo

if hasDep("semver"):
  let dep = pkg("semver")   # alias for getDep("semver")
  echo dep.getName          # "semver"
  echo dep.getVersion       # e.g. 1.2.3
  echo dep.getLicense
  echo dep.nimblePath
  echo dep.srcDir

echo hasDep("toktok")       # false
assert getDep("toktok") == nil
```

### 4. Version checks with semver
```nim
import pkginfo
# semver is re-exported, no extra import needed

static:
  assert nimVersion() >= v"1.6.4"
  assert pkg().getVersion >= version("0.1.0")

if pkg("semver").getVersion > v("1.1.1"):
  echo "new enough semver"
```

Available version helpers:
- `version("0.2.0")`: parse a literal into a `Version` (works at CT and RT)
- `getVersion(pkg)`: parse `pkg.version` string into a `Version`
- `nimVersion()`: parse the `nim` constraint from your `.nimble` file

### 5. Force a fresh read and bypass the cache
```nim
import pkginfo

# Regenerates .pkginfo.json from `nimble dump --json`
refresh()
echo pkg().getVersion

# One shot read without touching Package / PackageCT
let fresh = dumpProject()
echo fresh.getName, " ", $fresh.getVersion
```

### 6. What gets cached in `.pkginfo.json`
After the first build you will find this next to your `.nimble` file:
```json
{
  "name": "pkginfo",
  "version": "0.2.0",
  "author": "George Lemon",
  "desc": "A tiny utility package to extract Nimble information from any project",
  "license": "MIT",
  "srcDir": "src",
  "binDir": "",
  "nimblePath": "/path/to/pkginfo/pkginfo.nimble",
  "nim": "1.6.4",
  "dependencies": {
    "semver": {
      "name": "semver",
      "version": "1.2.3",
      "license": "BSD-3-Clause",
      "nimblePath": "/path/to/semver.nimble",
      "dependencies": {}
    }
  }
}
```
Delete it or run `refresh()` after editing `.nimble` requires. The file is rewritten automatically when the `.nimble` file is newer than the cache.

## API Reference
| Proc / Template | Scope | Description |
| --- | --- | --- |
| `pkg(name = ""): Pkg` | CT + RT | Current project when called without args, or a direct dependency via `pkg("semver")`. Returns `nil` if missing. |
| `getDep(name): Pkg` | CT + RT | Same as `pkg(name)`. Explicit dependency lookup. |
| `hasDep(name): bool` | CT + RT | True if `name` is a direct dependency. |
| `requires(name): bool` | CT + RT | Alias for `hasDep`. Designed for `when requires("x"):` guards. |
| `getName(p): string` | CT + RT | `p.name`, or `""` when `p` is `nil`. |
| `getAuthor(p): string` | CT + RT | `p.author`, or `""` when `p` is `nil`. |
| `getDescription(p): string` | CT + RT | `p.desc`, or `""` when `p` is `nil`. |
| `getLicense(p): string` | CT + RT | `p.license`, or `""` when `p` is `nil`. |
| `getVersion(p): Version` | CT + RT | Parses `p.version` with semver. |
| `version(s): Version` | CT + RT | Parses a version literal such as `version("0.2.0")`. |
| `nimVersion(): Version` | CT + RT | Parses the `nim` constraint (e.g. `1.6.4` from `requires "nim >= 1.6.4"`). |
| `dumpProject(): Pkg` | CT + RT | Fresh `nimble dump` read, bypasses `Package` / `PackageCT`. |
| `refresh()` | RT | Regenerates `Package` and rewrites `.pkginfo.json`. |
| `Package: Pkg` | RT | Runtime package info, initialized at program start. |
| `PackageCT: Pkg` | CT | Compile time package info, initialized in a `static:` block. |
| `Pkg` fields | both | `name`, `version`, `author`, `desc`, `license`, `srcDir`, `binDir`, `nimblePath`, `nim: string`, `dependencies: Table[string, Pkg]`. |
| `PackageDefect` | both | Raised only by direct `dumpProject()` calls when `nimble dump` fails. Init paths swallow it. |

Direct `Pkg` field access (`pkg().name`, `pkg().version`, `dep.nimblePath`) works anywhere. The `get*` wrappers add nil safety.

## How It Works
1. On `import pkginfo`, a `static:` block locates the project root (`getProjectPath()`, then parent dirs, then `currentSourcePath()`), resolves `.nimble` or `.nimble-link`, then runs `nimble dump --json` inside that root at compile time.
2. Each direct requirement except `nim` and `pkginfo` itself gets its own `nimble dump <dep> --json` lookup (one level deep, failures skipped silently).
3. The result is stored in `PackageCT` and written to `.pkginfo.json`.
4. At program startup the same flow runs with `execCmdEx` into `Package`. If the cache is fresh it is loaded instead of shelling out.
5. Public templates pick the CT or RT implementation with `when nimvm`.

## Developing
```
clue test
clue dump
```

## ❤ Contributions & Support
- 🐛 Found a bug? [Create a new Issue](https://github.com/openpeeps/pkginfo/issues)
- 👋 Wanna help? [Fork it!](https://github.com/openpeeps/pkginfo/fork)


## 🎩 License
MIT license. [Made by Humans from OpenPeeps](https://github.com/openpeeps).<br>
Copyright &copy; 2026 OpenPeeps & Contributors &mdash; All rights reserved.
