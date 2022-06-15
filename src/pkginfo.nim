# A tiny utility package to extract Nimble information from any project
#
# (c) 2022 Released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/pkginfo

import semver
import std/[macros, tables, json, jsonutils]

from std/os import parentDir, getHomeDir, dirExists, normalizedPath, fileExists
from std/strutils import Whitespace, Digits, strip, split, join,
                        startsWith, endsWith, parseInt

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

proc getInfo(depPkgName: string) {.compileTime.}
proc getInfo(depPkgName: string, obj: JsonNode) {.compileTime.}

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

template getNimbleLink(nimbleProjectPath: untyped): untyped =
    var nimbleLinkFile = find(File, nimbleProjectPath, "*.nimble-link")
    if nimbleLinkFile.len == 0:
        raise newException(PackageDefect, "Could not find a nimble file at\n" & nimbleProjectPath)
    staticRead(nimbleLinkFile).split("\n")[0]

template getNimbleFile(nimbleProjectPath: untyped): untyped = 
    ## Retrieve nimble file contents using `staticRead`
    var nimbleFile = find(File, nimbleProjectPath, "*.nimble")
    if nimbleFile.len != 0:
        nimbleFile = nimbleFile.split("\n")[0]
        if not nimbleFile.endsWith(".nimble"):
            # try look for `nimble-link` packages
            nimbleFile = getNimbleLink(nimbleFile)
    elif nimbleFile.len == 0:
        # try look for `nimble-link` packages
        nimbleFile = getNimbleLink(nimbleProjectPath)
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

template initNimble(version, author, desc, license, srcDir: string) =
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
                    Nimble.nimVersion = pkgVersion
            else: deps.add pkgName
        else: continue # ignore anything else

template extractStatic(key: string, val: JsonNode) =
    ## Extract Nimble information from static `pkginfo.json` file
    if key == "version":
        version = val.getStr
    elif key == "author":
        author = val.getStr
    elif key == "description":
        desc = val.getStr
    elif key == "license":
        license = val.getStr
    elif key == "srcDir":
        srcDir = val.getStr
    elif key == "pkgType":
        if val.getInt == 0: pkgType = Main
        else:               pkgType = Dependency
    elif key == "nimVersion":
        nimVersion = val.getStr
    elif key == "deps":
        for pkgName, pkgInfo in pairs(val):
            getInfo(pkgName, pkgInfo)

proc getInfo(depPkgName: string) {.compileTime.} =
    ## Get package information from `.nimble` file
    var deps: seq[string]
    var version, author, desc, license, srcDir: string
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

proc getInfo(depPkgName: string, obj: JsonNode) {.compileTime.} =
    ## Get package information from current `pkginfo.json`
    Nimble.deps[depPkgName] = Pkg(pkgType: Dependency)
    for key, val in pairs(obj):
        if key == "version":
            Nimble.deps[depPkgName].version = val.getStr
        elif key == "author":
            Nimble.deps[depPkgName].author = val.getStr
        elif key == "description":
            Nimble.deps[depPkgName].description = val.getStr
        elif key == "license":
            Nimble.deps[depPkgName].license = val.getStr
        elif key == "srcDir":
            Nimble.deps[depPkgName].srcDir = val.getStr
        elif key == "pkgType":
            Nimble.deps[depPkgName].pkgType = Dependency

macro getPkgInfo(nimblePath: static string) =
    ## Retrieve main package information
    var hasStaticPkgInfo: bool
    var projectPath = nimblePath.normalizedPath()
    let pkginfoPath = projectPath & "/pkginfo.json"
    Nimble = Pkg(pkgType: Main)
    var nimVersion, version, author, desc, license, srcDir: string
    var pkgType: PkgType

    if fileExists(pkginfoPath):
        let nimbleFilePath = getNimbleFile(projectPath)
        var nimbleLastModified, pkgInfoLastModified: string
        when defined macosx:
            nimbleLastModified = staticExec("stat -f %m " & nimbleFilePath)
            pkgInfoLastModified = staticExec("stat -f %m " & pkginfoPath)
        elif defined windows:
            ## TODO
        else:
            nimbleLastModified = staticExec("stat -c %y " & nimbleFilePath)
            pkgInfoLastModified = staticExec("stat -c %y " & pkginfoPath)

        if parseInt(pkgInfoLastModified) > parseInt(nimbleLastModified):
            hasStaticPkgInfo = true

    if hasStaticPkgInfo:
        let pkgInfoObj = parseJson(staticRead(pkginfoPath))
        for key, val in pairs(pkgInfoObj):
            extractStatic(key, val)
        initNimble(version, author, desc, license, srcDir)
    else:    
        var deps: seq[string]
        extractDeps(projectPath, true)
        for depPkgName in deps:
            if depPkgName in ["nim", "pkginfo"]: continue # TODO a better way to skip the `pkginfo` itself
            depPkgName.getInfo()
        initNimble(version, author, desc, license, srcDir)
        writeFile(pkginfoPath, $toJson(Nimble)) # store pkg info in pkginfo.json

template hasDep*(pkgName: string): untyped =
    ## Determine if current project requires a package by name
    Nimble.deps.hasKey(pkgName)

template getDep*(pkgName: string): untyped =
    ## Retrieve a dependency from current deps
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

macro pkg*(pkgName: static string = ""): untyped =
    result = newStmtList()
    if pkgName.len == 0:
        result.add quote do:
            Nimble
    else:
        result.add quote do:
            let pkg = getDep(`pkgName`)
            if pkg != nil:
                pkg
            else: nil

getPkgInfo(getProjectPath() & "/..") # init pkginfo