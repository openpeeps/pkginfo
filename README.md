<p align="center">
    <img src="https://raw.githubusercontent.com/georgelemon/nimble-website/main/.github/nimble.png" width="70px"><br>
    A tiny utility package to extract Nimble information from any <code>.nimble</code> project<br>
</p>

## 😍 Key Features
- [x] Meta-programming powered by Nim's Macros 
- [x] Compile-time & Runtime
- [x] Open Source under `MIT` License

## Installing
```
nimble install pkginfo
```

## Examples

Use `requires` macro to determine the current package dependencies and change the way application works.

```nim
import pkginfo

when requires "toktok":
    # here you can import additional libraries or modules
    # execute blocks of code or whatever you need
```

Extract the `version` of a package from `.nimble` project for backwards compatibility support
```nim
import pkginfo

when requires "toktok":
    when pkg("toktok").getVersion > version("0.1.1"):
        # backwards compatibility support
    else:
        # code for newer versions
```

## Roadmap
- [x] Extract deps info
- [x] Semver support via [Semver lib](https://github.com/euantorano/semver.nim)
- [ ] Extend support for [Nimble variables](https://github.com/nim-lang/nimble#package)
- [x] Handle indirect deps
- [ ] Cache dependency metadata in a `nimble-deps.json`
- [ ] Add unit tests
- [ ] Test with bigger projects

### ❤ Contributions
Contribute with code, ideas, bugfixing or you can even [donate via PayPal address](https://www.paypal.com/donate/?hosted_button_id=RJK3ZTDWPL55C) 🥰

### 👑 Discover Nim language
<strong>What's Nim?</strong> Nim is a statically typed compiled systems programming language. It combines successful concepts from mature languages like Python, Ada and Modula. [Find out more about Nim language](https://nim-lang.org/)

<strong>Why Nim?</strong> Performance, fast compilation and C-like freedom. We want to keep code clean, readable, concise, and close to our intention. Also a very good language to learn in 2022.

### 🎩 License
Pkginfo is an Open Source Software released under `MIT` license. [Made by Humans from OpenPeep](https://github.com/openpeep).<br>
Copyright &copy; 2022 OpenPeep & Contributors &mdash; All rights reserved.

<a href="https://hetzner.cloud/?ref=Hm0mYGM9NxZ4"><img src="https://openpeep.ro/banners/openpeep-footer.png" width="100%"></a>
