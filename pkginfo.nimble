# Package

version       = "0.1.4"
author        = "George Lemon"
description   = "A tiny utility package to extract Nimble information from any project"
license       = "MIT"
srcDir        = "src"


# Dependencies

requires "nim >= 1.6.4"
requires "semver#head"

task tests, "Run tests":
    exec "testament p 'tests/*.nim'"
