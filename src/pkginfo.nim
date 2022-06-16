# A tiny utility package to extract Nimble information from any project
#
# (c) 2022 Released under MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeep/pkginfo

import semver
import std/[macros, tables, json, jsonutils]

from std/os import parentDir, getHomeDir, dirExists, normalizedPath,
                   fileExists, walkDir, splitPath, PathComponent
from std/strutils import Whitespace, Digits, strip, split, join,
                        startsWith, endsWith, parseInt, contains

export semver

type
    FinderType = enum
        File = "f"
        Dir = "d"
    
    PkgType = enum
        Main, Dep

    Pkg = ref object
        name: string
        version: string
        author: string
        desc: string
        license: string
        srcDir, binDir: string
        case pkgType: PkgType:
        of Main:
            nim: string
            dependencies: Table[string, Pkg]
        else: discard

    PackageDefect* = object of CatchableError

var Package {.compileTime.}: Pkg

template getPkgPath(pkgDirName = ""): untyped =
    ## TODO first, find where is Nimble installed using `which nimble`
    if pkgDirName.len == 0:
        getHomeDir() & ".nimble/pkgs"
    else:
        getHomeDir() & ".nimble/pkgs/" & pkgDirName

template ensureNimblePkgsExists(): untyped =
    if not dirExists(getPkgPath()):
        raise newException(PackageDefect, "Could not find `pkgs` directory")

template find(ftype: FinderType, dirpath: string, pattern = ""): untyped =
    ## Find either files or directories in ~/.nimble/pkgs
    var dirOrFilePath: string
    case ftype:
    of Dir:
        for dir in walkDir(dirpath):
            if dir.kind == PathComponent.pcDir:
                let pkgdir = splitPath(dir.path)
                if startsWith(pkgdir.tail, pattern):
                    if endsWith(pkgdir.tail, "-#head"):
                        dirOrFilePath = dir.path
                        break
                    else:
                        if dirOrFilePath.len == 0:
                            dirOrFilePath = dir.path
                            break
                        else: continue
            else: continue
    of File:
        for file in walkDir(dirpath):
            if file.kind == PathComponent.pcFile:
                let pkgfile = splitPath(file.path)
                if endsWith(pkgfile.tail, pattern):
                    dirOrFilePath = file.path
                    break
                else: continue
            else: continue
    dirOrFilePath
    # staticExec("find " & dirpath & " -type " & $ftype & " -maxdepth 1 -name " & pattern & " -print")

template getNimbleLink(nimbleProjectPath: untyped): untyped =
    var nimbleLinkFile = find(File, nimbleProjectPath, ".nimble-link")
    if nimbleLinkFile.len == 0:
        raise newException(PackageDefect, "Could not find a nimble file at\n" & nimbleProjectPath)
    staticRead(nimbleLinkFile).split("\n")[0]

template getNimbleFile(nimbleProjectPath: untyped): untyped = 
    ## Retrieve nimble file contents using `staticRead`
    var nimbleFile = find(File, nimbleProjectPath, ".nimble")
    if nimbleFile.len != 0:
        nimbleFile = nimbleFile.split("\n")[0]
        if not nimbleFile.endsWith(".nimble"):
            # try look for `nimble-link` packages
            nimbleFile = getNimbleLink(nimbleFile)
    elif nimbleFile.len == 0:
        # try look for `nimble-link` packages
        nimbleFile = getNimbleLink(nimbleProjectPath)
    nimbleFile

# proc isInstalled(): bool {.compileTime.} =

template parsePkg(dep: JsonNode, hasStaticPkgInfo: bool) =
    let pkgName = dep["name"].getStr
    var nimblePkg: JsonNode
    if not hasStaticPkgInfo:
        if Package.dependencies.hasKey(pkgName): continue
        elif pkgName in ["nim", "pkginfo"]: continue
        let pkgNimbleContents = staticExec("nimble dump " & pkgName & " --json" )
        nimblePkg = parseJson(pkgNimbleContents)
    else: nimblePkg = dep
    Package.dependencies[pkgName] = Pkg(pkgType: Dep)
    Package.dependencies[pkgName].name = nimblePkg["name"].getStr
    Package.dependencies[pkgName].version = nimblePkg["version"].getStr
    Package.dependencies[pkgName].author = nimblePkg["author"].getStr
    Package.dependencies[pkgName].desc = nimblePkg["desc"].getStr
    Package.dependencies[pkgName].license = nimblePkg["license"].getStr
    if not hasStaticPkgInfo:
        if nimblePkg["requires"].len != 0:
            get(nimblePkg["requires"], hasStaticPkgInfo)

proc get(deps: JsonNode, hasStaticPkgInfo = false) {.compileTime.} =
    if deps.kind == JArray:
        for dep in items(deps):
            parsePkg(dep, hasStaticPkgInfo)
    else:
        for k, dep in pairs(deps):
            parsePkg(dep, hasStaticPkgInfo)

macro getPackageInformation(path: static string) =
    var hasStaticPkgInfo: bool
    var mainNimble: JsonNode
    var projectPath = path.normalizedPath()
    let pkginfoPath = projectPath & "/pkginfo.json"

    if fileExists(pkginfoPath):
        let nimbleFilePath = getNimbleFile(projectPath)
        var nimbleLastModified, pkgInfoLastModified: string
        when defined macosx:
            nimbleLastModified = staticExec("stat -f %m " & nimbleFilePath)
            pkgInfoLastModified = staticExec("stat -f %m " & pkginfoPath)
            if parseInt(pkgInfoLastModified) > parseInt(nimbleLastModified):
                hasStaticPkgInfo = true
        elif defined windows:
            ## TODO
        else:
            nimbleLastModified = staticExec("stat --format %Y " & nimbleFilePath)
            pkgInfoLastModified = staticExec("stat --format %Y " & pkginfoPath)
            if parseInt(pkgInfoLastModified) > parseInt(nimbleLastModified):
                hasStaticPkgInfo = true
    var mainNimbleContents: string
    if hasStaticPkgInfo:
        mainNimbleContents = staticRead(pkginfoPath)
    else:
        mainNimbleContents = staticExec("nimble dump " & projectPath & " --json" )
    Package = Pkg(pkgType: Main)
    mainNimble = parseJson(mainNimbleContents)
    for k, v in pairs(mainNimble):
        if k == "name":
            Package.name = v.getStr
        elif k == "version":
            Package.version = v.getStr
        elif k == "desc":
            Package.desc = v.getStr
        elif k == "license":
            Package.license = v.getStr
        elif k in ["requires", "dependencies"]:
            if not hasStaticPkgInfo:
                Package.nim = v[0]["ver"]["ver"].getStr
            get(v, hasStaticPkgInfo)

    if hasStaticPkgInfo:
        Package.nim = mainNimble["nim"].getStr

    if not hasStaticPkgInfo:
        writeFile(pkginfoPath, $toJson(Package)) # store pkg info in pkginfo.json

template hasDep*(pkgName: string): untyped =
    ## Determine if current project requires a package by name
    Package.dependencies.hasKey(pkgName)

template getDep*(pkgName: string): untyped =
    ## Retrieve a dependency from current deps
    if Package.dependencies.hasKey(pkgName):
        Package.dependencies[pkgName]
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
        result = pkgInfo.desc

proc getLicense*(pkgInfo: Pkg): string {.compileTime.} =
    ## Get a package license from `.nimble`
    if pkgInfo != nil:
        result = pkgInfo.license

proc nimVersion*(): Version {.compileTime.} =
    ## Get Nim version from main working project
    result = parseVersion(Package.nim)

macro pkg*(pkgName: static string = ""): untyped =
    result = newStmtList()
    if pkgName.len == 0:
        result.add quote do:
            Package
    else:
        result.add quote do:
            let pkg = getDep(`pkgName`)
            if pkg != nil:
                pkg
            else: nil

getPackageInformation(getProjectPath() & "/..") # init pkginfo
