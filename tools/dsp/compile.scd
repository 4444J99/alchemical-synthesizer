(
var root = "BRAHMA_REPO_ROOT".getenv;
var failures = List.new;
var files = List.new, visit;
visit = { |directory|
    directory.files.do { |file| if(file.extension == "scd") { files.add(file.fullPath) } };
    directory.folders.do { |folder| visit.value(folder) };
};
visit.value(PathName(root +/+ "brahma/sc"));
files = files.asArray.sort;
files.do { |path|
    if(thisProcess.interpreter.compileFile(path).isNil) {
        failures.add(path);
        ("COMPILE_FAIL " ++ path).postln;
    };
};
("COMPILE_TOTAL " ++ files.size ++ " FAILURES " ++ failures.size).postln;
if(failures.isEmpty and: { files.notEmpty }) {
    "DSP_PASS compilation".postln;
    0.exit;
} { 1.exit };
)
