import unittest, std/os
import ../src/pkginfo

test "when not requires <pkg>":
  when not requires "toktok":
    static: assert pkg("toktok") == nil

test "when requires <pkg>":
  when requires "semver":
    static:
      assert pkg("semver") != nil

test "when requires <pkg> -- check `version`":
  when requires "semver":
    static:
      assert pkg("semver").getVersion > v("1.1.1")

test "when requires <pkg> -- check `license`":
  when requires "semver":
    static:
      assert pkg("semver").getLicense == "BSD-3-Clause"

test "check `nimVersion`":
  static:
    echo nimVersion()
    assert nimVersion() >= v"1.6.4"

test "check `pkg` `version`":
  static:
    assert pkg().getVersion >= version("0.1.0")

test "check `pkg` `license`":
  static:
    assert pkg().getLicense == "MIT"

test "runtime pkg access":
  assert pkg().getName == "pkginfo"
  assert pkg().getLicense == "MIT"
  assert hasDep("semver")
  assert pkg("semver").getVersion > v("1.1.1")
  assert pkg("semver").getLicense == "BSD-3-Clause"
  assert not hasDep("toktok")
  assert pkg("toktok") == nil

test "pkgToJson cache exists":
  assert fileExists(".pkginfo.json") or fileExists("../.pkginfo.json")