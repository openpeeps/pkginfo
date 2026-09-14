# A tiny utility package to extract Nimble information from any project
#
# (c) 2022 George Lemon | MIT License
#          Made by Humans from OpenPeep
#          https://github.com/openpeeps/pkginfo

import semver
import std/[os, macros, tables, json, strutils, times, osproc]
export semver

type
  Pkg* = ref object
    name*: string
    version*: string
    author*: string
    desc*: string
    license*: string
    srcDir*: string
    binDir*: string
    nimblePath*: string
    nim*: string
    dependencies*: Table[string, Pkg]

  PackageDefect* = object of CatchableError

var PackageCT* {.compileTime.}: Pkg
var Package*: Pkg

#
# Shared JSON helpers (func = usable at compile-time and runtime)
#
func pkgToJsonNode(pkg: Pkg): JsonNode =
  result = newJObject()
  if pkg == nil:
    return result
  result["name"] = %pkg.name
  result["version"] = %pkg.version
  result["author"] = %pkg.author
  result["desc"] = %pkg.desc
  result["license"] = %pkg.license
  result["srcDir"] = %pkg.srcDir
  result["binDir"] = %pkg.binDir
  result["nimblePath"] = %pkg.nimblePath
  result["nim"] = %pkg.nim
  var deps = newJObject()
  for k, v in pkg.dependencies:
    deps[k] = pkgToJsonNode(v)
  result["dependencies"] = deps

func jsonNodeToPkg(node: JsonNode): Pkg =
  result = Pkg(
    name: node{"name"}.getStr(""),
    version: node{"version"}.getStr(""),
    author: node{"author"}.getStr(""),
    desc: node{"desc"}.getStr(""),
    license: node{"license"}.getStr(""),
    srcDir: node{"srcDir"}.getStr(""),
    binDir: node{"binDir"}.getStr(""),
    nimblePath: node{"nimblePath"}.getStr(""),
    nim: node{"nim"}.getStr(""),
    dependencies: initTable[string, Pkg]()
  )
  if node.hasKey("dependencies"):
    let deps = node["dependencies"]
    if deps.kind == JObject:
      for k, v in deps:
        result.dependencies[k] = jsonNodeToPkg(v)

func extractNimVersion(requiresNode: JsonNode): string =
  ## Pull the nim version out of a `nimble dump --json` requires array.
  ## Handles `ver.ver` objects, plain `ver` strings, and falls back
  ## to parsing the human readable `str` field (e.g. ">= 1.6.4").
  if requiresNode.kind != JArray:
    return ""
  for dep in requiresNode:
    if dep{"name"}.getStr("") != "nim":
      continue
    if dep.hasKey("ver"):
      let v = dep["ver"]
      if v.kind == JObject and v.hasKey("ver"):
        let s = v["ver"].getStr("")
        if s.len != 0:
          return s
      elif v.kind == JString:
        let s = v.getStr("")
        if s.len != 0:
          return s
    if dep.hasKey("str"):
      let s = dep["str"].getStr("")
      var i = 0
      while i < s.len and not s[i].isDigit():
        inc i
      var ver = ""
      while i < s.len and (s[i].isDigit() or s[i] == '.'):
        ver.add(s[i])
        inc i
      if ver.len != 0:
        return ver
  return ""

#
# Compile-time helpers
#
proc findNimbleFileCT(dir: string): string {.compileTime.} =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      return path
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble-link"):
      try:
        let target = readFile(path).splitLines()[0].strip()
        if target.len != 0:
          if target.endsWith(".nimble") and fileExists(target):
            return target
          elif dirExists(target):
            for k2, p2 in walkDir(target):
              if k2 == pcFile and p2.endsWith(".nimble"):
                return p2
          elif fileExists(target):
            return target
      except:
        discard
  return ""

proc findProjectRootCT(startDir: string): string {.compileTime.} =
  var dir = startDir.normalizedPath()
  while true:
    if findNimbleFileCT(dir).len != 0:
      return dir
    let parent = parentDir(dir)
    if parent == dir or parent.len == 0:
      break
    dir = parent
  return ""

proc isCacheStaleCT(nimbleFile, cacheFile: string): bool {.compileTime.} =
  when defined(macosx) or defined(macos):
    let aStr = staticExec("stat -f %m \"" & nimbleFile & "\"").strip()
    let bStr = staticExec("stat -f %m \"" & cacheFile & "\"").strip()
    try:
      let a = parseInt(aStr)
      let b = parseInt(bStr)
      result = a > b
    except:
      result = true
  elif defined(windows):
    # Windows: conservatively keep cache; TODO powershell stat
    result = false
  else:
    let aStr = staticExec("stat --format %Y \"" & nimbleFile & "\"").strip()
    let bStr = staticExec("stat --format %Y \"" & cacheFile & "\"").strip()
    try:
      let a = parseInt(aStr)
      let b = parseInt(bStr)
      result = a > b
    except:
      result = true

proc nimbleDumpCT(projectRoot: string): string {.compileTime.} =
  ## `nimble dump <abs path> --json` is not supported by current nimble
  ## (it doubles the path). Run inside the project root instead.
  staticExec("cd \"" & projectRoot & "\" && nimble dump --json")

proc generatePkgInfoCT(projectRoot: string): Pkg {.compileTime.} =
  let dumpStr = nimbleDumpCT(projectRoot)
  if dumpStr.strip().len == 0 or dumpStr.contains("Error:"):
    raise newException(PackageDefect, "nimble dump failed for " & projectRoot & ": " & dumpStr)
  let node = parseJson(dumpStr)
  result = Pkg(
    name: node{"name"}.getStr(""),
    version: node{"version"}.getStr(""),
    author: node{"author"}.getStr(""),
    desc: node{"desc"}.getStr(""),
    license: node{"license"}.getStr(""),
    srcDir: node{"srcDir"}.getStr(""),
    binDir: node{"binDir"}.getStr(""),
    nimblePath: node{"nimblePath"}.getStr(""),
    nim: "",
    dependencies: initTable[string, Pkg]()
  )
  if node.hasKey("requires"):
    result.nim = extractNimVersion(node["requires"])
  if node.hasKey("requires"):
    for dep in node["requires"]:
      let depName = dep{"name"}.getStr("")
      if depName.len == 0 or depName in ["nim", "pkginfo"]:
        continue
      if result.dependencies.hasKey(depName):
        continue
      let depDumpStr = staticExec("nimble dump \"" & depName & "\" --json")
      if depDumpStr.strip().len == 0 or depDumpStr.contains("Error:"):
        continue
      try:
        let depNode = parseJson(depDumpStr)
        var depPkg = Pkg(
          name: depNode{"name"}.getStr(""),
          version: depNode{"version"}.getStr(""),
          author: depNode{"author"}.getStr(""),
          desc: depNode{"desc"}.getStr(""),
          license: depNode{"license"}.getStr(""),
          srcDir: depNode{"srcDir"}.getStr(""),
          binDir: depNode{"binDir"}.getStr(""),
          nimblePath: depNode{"nimblePath"}.getStr(""),
          nim: "",
          dependencies: initTable[string, Pkg]()
        )
        result.dependencies[depName] = depPkg
      except:
        discard

proc ensurePkgInfoCT() {.compileTime.} =
  try:
    let start = getProjectPath()
    var root = findProjectRootCT(start)
    if root.len == 0:
      root = findProjectRootCT(start / "../")
    if root.len == 0:
      # last resort: use current source path parent
      root = findProjectRootCT(currentSourcePath().parentDir())
    if root.len == 0:
      return
    let nimbleFile = findNimbleFileCT(root)
    if nimbleFile.len == 0:
      return
    let cacheFile = root / ".pkginfo.json"
    var useCache = false
    if fileExists(cacheFile):
      try:
        if not isCacheStaleCT(nimbleFile, cacheFile):
          useCache = true
      except:
        discard
    if useCache:
      try:
        let content = readFile(cacheFile)
        let node = parseJson(content)
        PackageCT = jsonNodeToPkg(node)
        if PackageCT != nil:
          return
      except:
        discard
    # generate
    PackageCT = generatePkgInfoCT(root)
    try:
      writeFile(cacheFile, $pkgToJsonNode(PackageCT))
    except:
      discard
  except:
    # never fail compilation due to pkginfo
    discard

#
# Runtime helpers
#
proc findNimbleFileRT(dir: string): string =
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble"):
      return path
  for kind, path in walkDir(dir):
    if kind == pcFile and path.endsWith(".nimble-link"):
      try:
        let target = readFile(path).splitLines()[0].strip()
        if target.len != 0:
          if target.endsWith(".nimble") and fileExists(target):
            return target
          elif dirExists(target):
            for k2, p2 in walkDir(target):
              if k2 == pcFile and p2.endsWith(".nimble"):
                return p2
          elif fileExists(target):
            return target
      except:
        discard
  return ""

proc findProjectRootRT(startDir: string): string =
  var dir = startDir.normalizedPath()
  while true:
    if findNimbleFileRT(dir).len != 0:
      return dir
    let parent = parentDir(dir)
    if parent == dir or parent.len == 0:
      break
    dir = parent
  return ""

proc isCacheStaleRT(nimbleFile, cacheFile: string): bool =
  try:
    let a = getLastModificationTime(nimbleFile).toUnix()
    let b = getLastModificationTime(cacheFile).toUnix()
    result = a > b
  except:
    result = true

proc nimbleDumpRT(projectRoot: string): tuple[output: string, exitCode: int] =
  ## See nimbleDumpCT: cd into the root instead of passing it as an arg.
  execCmdEx("cd \"" & projectRoot & "\" && nimble dump --json")

proc generatePkgInfoRT(projectRoot: string): Pkg =
  let (outp, code) = nimbleDumpRT(projectRoot)
  if code != 0 or outp.strip().len == 0 or outp.contains("Error:"):
    raise newException(PackageDefect, "nimble dump failed for " & projectRoot & ": " & outp)
  let node = parseJson(outp)
  result = Pkg(
    name: node{"name"}.getStr(""),
    version: node{"version"}.getStr(""),
    author: node{"author"}.getStr(""),
    desc: node{"desc"}.getStr(""),
    license: node{"license"}.getStr(""),
    srcDir: node{"srcDir"}.getStr(""),
    binDir: node{"binDir"}.getStr(""),
    nimblePath: node{"nimblePath"}.getStr(""),
    nim: "",
    dependencies: initTable[string, Pkg]()
  )
  if node.hasKey("requires"):
    result.nim = extractNimVersion(node["requires"])
  if node.hasKey("requires"):
    for dep in node["requires"]:
      let depName = dep{"name"}.getStr("")
      if depName.len == 0 or depName in ["nim", "pkginfo"]:
        continue
      if result.dependencies.hasKey(depName):
        continue
      let (depOut, depCode) = execCmdEx("nimble dump \"" & depName & "\" --json")
      if depCode != 0 or depOut.strip().len == 0 or depOut.contains("Error:"):
        continue
      try:
        let depNode = parseJson(depOut)
        var depPkg = Pkg(
          name: depNode{"name"}.getStr(""),
          version: depNode{"version"}.getStr(""),
          author: depNode{"author"}.getStr(""),
          desc: depNode{"desc"}.getStr(""),
          license: depNode{"license"}.getStr(""),
          srcDir: depNode{"srcDir"}.getStr(""),
          binDir: depNode{"binDir"}.getStr(""),
          nimblePath: depNode{"nimblePath"}.getStr(""),
          nim: "",
          dependencies: initTable[string, Pkg]()
        )
        result.dependencies[depName] = depPkg
      except:
        discard

proc ensurePkgInfoRT() =
  var start = ""
  try:
    start = getCurrentDir()
  except:
    start = getAppDir()
  var root = findProjectRootRT(start)
  if root.len == 0:
    try:
      root = findProjectRootRT(getAppDir())
    except:
      discard
  if root.len == 0:
    return
  let nimbleFile = findNimbleFileRT(root)
  if nimbleFile.len == 0:
    return
  let cacheFile = root / ".pkginfo.json"
  var useCache = false
  if fileExists(cacheFile):
    if not isCacheStaleRT(nimbleFile, cacheFile):
      useCache = true
  if useCache:
    try:
      let content = readFile(cacheFile)
      let node = parseJson(content)
      Package = jsonNodeToPkg(node)
      return
    except:
      discard
  # generate
  try:
    Package = generatePkgInfoRT(root)
    writeFile(cacheFile, $pkgToJsonNode(Package))
  except:
    # fallback to cache if generation failed
    if fileExists(cacheFile):
      try:
        let content = readFile(cacheFile)
        Package = jsonNodeToPkg(parseJson(content))
      except:
        discard

#
# Init — compile-time and runtime
#
static:
  ensurePkgInfoCT()

# Runtime init (executed when program starts)
try:
  ensurePkgInfoRT()
except:
  discard

#
# Internal CT/RT dispatch helpers for public API
#
proc hasDepCT(name: string): bool {.compileTime.} =
  PackageCT != nil and PackageCT.dependencies.hasKey(name)

proc hasDepRT(name: string): bool =
  Package != nil and Package.dependencies.hasKey(name)

template hasDep*(name: string): bool =
  ## Determine if current project requires a package by name
  when nimvm:
    hasDepCT(name)
  else:
    hasDepRT(name)

proc getDepCT(name: string): Pkg {.compileTime.} =
  if PackageCT != nil and PackageCT.dependencies.hasKey(name):
    PackageCT.dependencies[name]
  else:
    nil

proc getDepRT(name: string): Pkg =
  if Package != nil and Package.dependencies.hasKey(name):
    Package.dependencies[name]
  else:
    nil

template getDep*(name: string): Pkg =
  when nimvm:
    getDepCT(name)
  else:
    getDepRT(name)

template requires*(pkgName: string): bool =
  ## Determine if current library has a dependency with given name.
  ## Works for direct dependencies.
  hasDep(pkgName)

#
# Version helpers
#
func versionImpl(vers: string): Version =
  var versTuple: tuple[major, minor, patch: int, build, metadata: string]
  let v = vers.split(".")
  if v.len > 0 and v[0].len != 0:
    versTuple.major = parseInt(v[0])
  if v.len > 1:
    versTuple.minor = parseInt(v[1])
  if v.len > 2:
    versTuple.patch = parseInt(v[2])
  if v.len == 4:
    versTuple.build = v[3]
  if v.len == 5:
    versTuple.metadata = v[4]
  result = newVersion(versTuple.major, versTuple.minor, versTuple.patch, versTuple.build, versTuple.metadata)

proc versionCT(vers: string): Version {.compileTime.} = versionImpl(vers)
proc versionRT(vers: string): Version = versionImpl(vers)

template version*(vers: string): Version =
  when nimvm:
    versionCT(vers)
  else:
    versionRT(vers)

proc getVersionCT(pkgInfo: Pkg): Version {.compileTime.} =
  try:
    if pkgInfo != nil and pkgInfo.version.len != 0:
      result = parseVersion(pkgInfo.version)
    else:
      result = parseVersion("0.0.0")
  except:
    result = parseVersion("0.0.0")

proc getVersionRT(pkgInfo: Pkg): Version =
  try:
    if pkgInfo != nil and pkgInfo.version.len != 0:
      result = parseVersion(pkgInfo.version)
    else:
      result = parseVersion("0.0.0")
  except:
    result = parseVersion("0.0.0")

template getVersion*(pkgInfo: Pkg): Version =
  when nimvm:
    getVersionCT(pkgInfo)
  else:
    getVersionRT(pkgInfo)

proc getNameCT(pkgInfo: Pkg): string {.compileTime.} =
  if pkgInfo != nil: pkgInfo.name else: ""

proc getNameRT(pkgInfo: Pkg): string =
  if pkgInfo != nil: pkgInfo.name else: ""

template getName*(pkgInfo: Pkg): string =
  when nimvm: getNameCT(pkgInfo) else: getNameRT(pkgInfo)

proc getAuthorCT(pkgInfo: Pkg): string {.compileTime.} =
  if pkgInfo != nil: pkgInfo.author else: ""

proc getAuthorRT(pkgInfo: Pkg): string =
  if pkgInfo != nil: pkgInfo.author else: ""

template getAuthor*(pkgInfo: Pkg): string =
  when nimvm: getAuthorCT(pkgInfo) else: getAuthorRT(pkgInfo)

proc getDescriptionCT(pkgInfo: Pkg): string {.compileTime.} =
  if pkgInfo != nil: pkgInfo.desc else: ""

proc getDescriptionRT(pkgInfo: Pkg): string =
  if pkgInfo != nil: pkgInfo.desc else: ""

template getDescription*(pkgInfo: Pkg): string =
  when nimvm: getDescriptionCT(pkgInfo) else: getDescriptionRT(pkgInfo)

proc getLicenseCT(pkgInfo: Pkg): string {.compileTime.} =
  if pkgInfo != nil: pkgInfo.license else: ""

proc getLicenseRT(pkgInfo: Pkg): string =
  if pkgInfo != nil: pkgInfo.license else: ""

template getLicense*(pkgInfo: Pkg): string =
  when nimvm: getLicenseCT(pkgInfo) else: getLicenseRT(pkgInfo)

proc nimVersionCT(): Version {.compileTime.} =
  try:
    if PackageCT != nil and PackageCT.nim.len != 0:
      parseVersion(PackageCT.nim)
    else:
      parseVersion("0.0.0")
  except:
    parseVersion("0.0.0")

proc nimVersionRT(): Version =
  try:
    if Package != nil and Package.nim.len != 0:
      parseVersion(Package.nim)
    else:
      parseVersion("0.0.0")
  except:
    parseVersion("0.0.0")

template nimVersion*(): Version =
  when nimvm: nimVersionCT() else: nimVersionRT()

proc pkgCTImpl(name: string = ""): Pkg {.compileTime.} =
  if name.len == 0:
    PackageCT
  else:
    getDepCT(name)

proc pkgRTImpl(name: string = ""): Pkg =
  if name.len == 0:
    Package
  else:
    getDepRT(name)

template pkg*(pkgName: string = ""): Pkg =
  when nimvm:
    pkgCTImpl(pkgName)
  else:
    pkgRTImpl(pkgName)

proc dumpProjectCT(): Pkg {.compileTime.} =
  let start = getProjectPath()
  var root = findProjectRootCT(start)
  if root.len == 0:
    root = findProjectRootCT(start / "../")
  if root.len != 0:
    result = generatePkgInfoCT(root)
  else:
    result = Pkg(name: "", version: "", author: "", desc: "", license: "", srcDir: "", binDir: "", nimblePath: "", nim: "", dependencies: initTable[string, Pkg]())

proc dumpProjectRT(): Pkg =
  var start = ""
  try: start = getCurrentDir()
  except: start = getAppDir()
  var root = findProjectRootRT(start)
  if root.len == 0:
    try: root = findProjectRootRT(getAppDir())
    except: discard
  if root.len != 0:
    result = generatePkgInfoRT(root)
  else:
    result = Pkg(name: "", version: "", author: "", desc: "", license: "", srcDir: "", binDir: "", nimblePath: "", nim: "", dependencies: initTable[string, Pkg]())

template dumpProject*(): Pkg =
  when nimvm:
    dumpProjectCT()
  else:
    dumpProjectRT()

proc refresh*() =
  ## Force regeneration of .pkginfo.json
  var start = ""
  try: start = getCurrentDir()
  except: start = getAppDir()
  var root = findProjectRootRT(start)
  if root.len == 0:
    try: root = findProjectRootRT(getAppDir())
    except: discard
  if root.len == 0: return
  try:
    Package = generatePkgInfoRT(root)
    writeFile(root / ".pkginfo.json", $pkgToJsonNode(Package))
    # also update CT var for consistency when called at CT? no-op at runtime
  except:
    discard
