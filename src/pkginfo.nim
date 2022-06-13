import std/[macros, tables]
from std/strutils import strip, split, startsWith, Whitespace

type
    Dependency = object
        version: string
        name: string

    PkgInfo = object
        version: string
        author: string
        description: string
        license: string
        srcDir: string
        binDir: string
        deps: Table[string, Dependency]

    PkgInfoDefect* = object of CatchableError

var Nimble {.compileTime.}: PkgInfo

macro pkginfo() =
    # echo staticRead(getProjectPath() & "/")
    var nimbleFile = staticExec("find " & getProjectPath() & "/.. -type f -name *.nimble -print")
    if nimbleFile.len == 0:
        raise newException(PkgInfoDefect, "Could not find a nimble file")
    nimbleFile = nimbleFile.strip()

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

    var deps = initTable[string, Dependency]()
    var version, author, desc, license, srcDir: string
    for line in staticRead(nimbleFile).split("\n"):
        if line.startsWith "version":
            version = line.getVal "version"
        elif line.startsWith "author":
            author = line.getVal "author"
        elif line.startsWith "author":
            desc = line.getVal "description"
        elif line.startsWith "license":
            license = line.getVal "license"
        elif line.startsWith "srcDir":
            srcDir = line.getVal "srcDir"
        elif line.startsWith "requires":
            let pkgName = line.getVal()
            deps[pkgName] = Dependency(name: pkgName)

    Nimble.version = version
    Nimble.author = author
    Nimble.description = desc
    Nimble.license = license
    Nimble.srcDir = srcDir
    Nimble.deps = deps

macro get*(pkg: var PkgInfo, field: string) =
    result = newDotExpr(pkg, ident field.strVal)

template hasDep*(pkgName: string): untyped =
    Nimble.deps.hasKey(pkgName)

macro requires*(pkgName: string): untyped = 
    result = newStmtList()
    result.add quote do:
        hasDep(`pkgName`)

pkginfo()