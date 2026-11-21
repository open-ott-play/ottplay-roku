' Regression tests for the Stat() size adapter used by the download tasks.
sub fileInfoTests()
    eq(statSize(invalid), invalid, "Missing Stat() result has no size")
    eq(statSize({}), invalid, "Stat() result without a size key has no size")
    eq(statSize({size: invalid}), invalid, "Invalid size is rejected")
    eq(statSize({size: 0}), 0, "Empty file size is valid")
    eq(statSize({size: 5}), 5, "Small file size is returned")
    eq(statSize({size: 8388609}), 8388609, "Oversized file size is returned to the caller")
    eq(statSize({size: "5"}), invalid, "Textual size is rejected")
    eq(statSize({size: -1}), invalid, "Negative size is rejected")
    eq(statSize({size: 5.5}), invalid, "Fractional size is rejected")
end sub
