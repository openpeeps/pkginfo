# A tiny utility package to extract Nimble information from any project
#
# (c) 2022 Released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/pkginfo

import std/[macros, tables]

from std/os import parentDir, getHomeDir, dirExists
from std/strutils import strip, split, startsWith, Whitespace

type
    FinderType = enum
        File = "f"
        Dir = "d"

    PkgInfo = ref object
        version: string
        author: string
        description: string
        license: string
        srcDir: string
        binDir: string
        deps: Table[string, PkgInfo]

    PkgInfoDefect* = object of CatchableError

var Nimble {.compileTime.}: PkgInfo

template getPkgPath(pkgDirName = ""): untyped =
    if pkgDirName.len == 0:
        getHomeDir() & ".nimble/pkgs"
    else:
        getHomeDir() & ".nimble/pkgs/" & pkgDirName

template ensureNimblePkgsExists(): untyped =
    if not dirExists(getPkgPath()):
        raise newException(PkgInfoDefect, "Could not find `pkgs` directory")

template find(ftype: FinderType, path: string, pattern = ""): untyped =
    staticExec("find " & path & " -type " & $ftype & " -maxdepth 1 -name " & pattern & " -print")

template getNimbleFile(nimbleProjectPath: untyped): untyped = 
    var nimbleFile = find(File, nimbleProjectPath, "*.nimble")
    if nimbleFile.len == 0:
        raise newException(PkgInfoDefect, "Could not find a nimble file")
    nimbleFile = nimbleFile.strip()
    nimbleFile

template getVal(line: string, field = "", chSep = '"'): untyped = 
    var startVal: bool
    var val: string
    for ch in line:
        if ch == chSep:
            if startVal == true:
                startVal = false
            else:
                startVal = true
                continue
        if startVal:
            add val, ch
        elif ch in Whitespace:
            continue
    val

template getDep(line: string, chSep = '"'): untyped =
    var startVal: bool
    var pkgname: string
    for ch in line:
        if ch == chSep:
            if startVal == true:
                startVal = false
            else:
                startVal = true
                continue
        if startVal:
            if ch in {'>', '=', '<'}: # TODO extract version
                startVal = false
                continue
            add pkgname, ch
        elif ch in Whitespace:
            continue
    (pkgName: pkgname.strip(), pkgVersion: "")

template initNimble(version, author, desc, license, srcDir: string, deps: seq[string]) =
    Nimble = PkgInfo()
    Nimble.version = version
    Nimble.author = author
    Nimble.description = desc
    Nimble.license = license
    Nimble.srcDir = srcDir
    # Nimble.deps = deps

template addNimbleDep(name: string, pkgInfo: var PkgInfo) =
    Nimble.deps[name] = pkgInfo

template extractDeps() =
    for line in staticRead(getNimbleFile(nimblePath)).split("\n"):
        if line.startsWith "version":
            version = line.getVal "version"
        elif line.startsWith "author":
            author = line.getVal "author"
        elif line.startsWith "description":
            desc = line.getVal "description"
        elif line.startsWith "license":
            license = line.getVal "license"
        elif line.startsWith "srcDir":
            srcDir = line.getVal "srcDir"
        elif line.startsWith "requires":
            let (pkgName, pkgVersion) = line.getDep()
            if pkgName != "nim":
                deps.add pkgName
        else: continue # ignore anything else

macro pkginfo(nimblePath: static string) =
    var deps: seq[string]
    var version, author, desc, license, srcDir: string
    extractDeps()
    initNimble(version, author, desc, license, srcDir, deps)

    for depPkgName in deps:
        let depNimblePath = find(Dir, getPkgPath(), depPkgName & "*")
        echo depNimblePath

template hasDep*(pkgName: string): untyped =
    Nimble.deps.hasKey(pkgName)

macro requires*(pkgName: string): untyped = 
    result = newStmtList()
    result.add quote do:
        hasDep(`pkgName`)

pkginfo(getProjectPath() & "/..")