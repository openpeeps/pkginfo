# A tiny utility package to extract Nimble information from any project
#
# (c) 2022 Released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/pkginfo

import semver
import std/[macros, tables]

from std/os import parentDir, getHomeDir, dirExists
from std/strutils import Whitespace, Digits, strip, split, join, startsWith, parseInt

export semver

type
    FinderType = enum
        File = "f"
        Dir = "d"
    
    PkgType = enum
        Main, Dependency

    Pkg = ref object
        version: string
        author, description, license: string
        srcDir, binDir: string
        case pkgType: PkgType:
        of Main:
            nimVersion: string
            deps: Table[string, Pkg]
        else: discard

    PackageDefect* = object of CatchableError

var Nimble {.compileTime.}: Pkg

proc getInfo(depPkgName: string, isMain = false) {.compileTime.}

template getPkgPath(pkgDirName = ""): untyped =
    if pkgDirName.len == 0:
        getHomeDir() & ".nimble/pkgs"
    else:
        getHomeDir() & ".nimble/pkgs/" & pkgDirName

template ensureNimblePkgsExists(): untyped =
    if not dirExists(getPkgPath()):
        raise newException(PackageDefect, "Could not find `pkgs` directory")

template find(ftype: FinderType, path: string, pattern = ""): untyped =
    ## Find either files or directories in ~/.nimble/pkgs
    ## TODO Windows support using walkDirRec
    staticExec("find " & path & " -type " & $ftype & " -maxdepth 1 -name " & pattern & " -print")

template getNimbleFile(nimbleProjectPath: untyped): untyped = 
    ## Retrieve nimble file contents using `staticRead`
    var nimbleFile = find(File, nimbleProjectPath, "*.nimble")
    if nimbleFile.len == 0:
        # try look for `nimble-link` packages
        let nimbleLinkFile = find(File, nimbleProjectPath, "*.nimble-link")
        if nimbleLinkFile.len == 0:
            raise newException(PackageDefect, "Could not find a nimble file at\n" & nimbleProjectPath)
        nimbleFile = staticRead(nimbleLinkFile).split("\n")[0]
    nimbleFile = nimbleFile.strip()
    nimbleFile

template getVal(line: string, field = "", chSep = '"'): untyped =
    ## Retrieve values from `.nimble` variables
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

template extractDep(line: string, chSep = '"'): untyped =
    ## Extract package names from dependencies
    var startVal: bool
    var pkgName: string
    var pkgVers: seq[char]
    for ch in line:
        if ch == chSep:
            if startVal == true:
                startVal = false
            else:
                startVal = true
                continue
        if startVal:
            if ch in {'>', '=', '<', '.'}: 
                # https://github.com/nim-lang/nimble#creating-packages
                continue
            elif ch in Digits:
                pkgVers.add(ch)
            else: add pkgName, ch
        elif ch in Whitespace:
            continue
    var pkgVersion = pkgVers.join(".")
    (pkgName: pkgName.strip(), pkgVersion: pkgVersion)

template initNimble(version, author, desc, license, srcDir: string, deps: seq[string]) =
    # https://github.com/nim-lang/nimble#package
    Nimble.version = version
    Nimble.author = author
    Nimble.description = desc
    Nimble.license = license
    Nimble.srcDir = srcDir

template extractDeps(nimblePath: string, isMain = false) =
    let nimbleFilePath = getNimbleFile(nimblePath)
    for line in staticRead(nimbleFilePath).split("\n"):
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
            let (pkgName, pkgVersion) = line.extractDep()
            if pkgName == "nim":
                if isMain:
                    nimVersion = pkgVersion
            else: deps.add pkgName
        else: continue # ignore anything else

proc getInfo(depPkgName: string, isMain = false) {.compileTime.} =
    var deps: seq[string]
    var nimVersion, version, author, desc, license, srcDir: string
    let depPackagePath = find(Dir, getPkgPath(), depPkgName & "*")
    extractDeps(depPackagePath)
    Nimble.deps[depPkgName] = Pkg(
        pkgType: Dependency,
        version: version,
        author: author,
        description: desc,
        license: license,
        srcDir: srcDir
    )
    for depPkgName in deps:
        if depPkgName in ["nim", "pkginfo"]: continue
        depPkgName.getInfo()

macro getPkgInfo(nimblePath: static string) =
    ## Retrieve main package information
    var deps: seq[string]
    var nimVersion, version, author, desc, license, srcDir: string
    Nimble = Pkg()
    extractDeps(nimblePath, true)
    Nimble.nimVersion = nimVersion
    for depPkgName in deps:
        if depPkgName in ["nim", "pkginfo"]: continue # TODO a better way to skip the `pkginfo` itself
        depPkgName.getInfo(isMain = true)
    initNimble(version, author, desc, license, srcDir, deps)

template hasDep*(pkgName: string): untyped =
    Nimble.deps.hasKey(pkgName)

template getDep*(pkgName: string): untyped =
    if Nimble.deps.hasKey(pkgName):
        Nimble.deps[pkgName]
    else: nil

macro requires*(pkgName: string): untyped = 
    ## Determine if current library has a dependency with given name.
    ## This macro works for all direct and indirect dependencies.
    result = newStmtList()
    result.add quote do:
        hasDep(`pkgName`)

proc version*(vers: string): Version {.compileTime.} =
    ## Create a `Version` object instance from string
    var versTuple: tuple[major, minor, patch: int, build, metadata: string]
    let v = vers.split(".")
    versTuple.major = parseInt v[0]
    versTuple.minor = parseInt v[1]
    versTuple.patch = parseInt v[2]
    if v.len == 4:  versTuple.build = v[3]
    if v.len == 5:  versTuple.metadata = v[4]
    result = newVersion(versTuple.major, versTuple.minor, versTuple.patch, versTuple.build, versTuple.metadata)

proc getVersion*(pkgInfo: Pkg): Version {.compileTime.} =
    ## Get a package `version` from `.nimble`
    if pkgInfo != nil:
        result = parseVersion(pkgInfo.version)

proc getAuthor*(pkgInfo: Pkg): string {.compileTime.} =
    ## Get a package `author` name from `.nimble`
    if pkgInfo != nil:
        result = pkgInfo.author

proc getDescription*(pkgInfo: Pkg): string {.compileTime.} =
    ## Get a package `description` from `.nimble`
    if pkgInfo != nil:
        result = pkgInfo.description

proc getLicense*(pkgInfo: Pkg): string {.compileTime.} =
    ## Get a package license from `.nimble`
    if pkgInfo != nil:
        result = pkgInfo.license

proc nimVersion*(): Version {.compileTime.} =
    ## Get a package Nim version from `.nimble`
    result = parseVersion(Nimble.nimVersion)

macro pkg*(pkgName): untyped =
    result = newStmtList()
    result.add quote do:
        let pkg = getDep(`pkgName`)
        if pkg != nil:
            pkg
        else: nil

getPkgInfo(getProjectPath() & "/..") # init pkginfo