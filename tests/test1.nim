import unittest, pkginfo

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
            assert pkg("semver").getVersion >= v "1.1.1"

test "when requires <pkg> -- check `license`":
    when requires "semver":
        static:
            assert pkg("semver").getLicense == "BSD3"

test "check `nimVersion`":
    static:
        assert nimVersion() == v "1.6.4"

test "check `pkg` `version`":
    static:
        assert pkg().getVersion >= v "0.1.0"

test "check `pkg` `license`":
    static:
        assert pkg().getLicense == "MIT"