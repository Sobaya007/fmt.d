import std;
import fmt.formatter;
import fmt.editorconfig;

void main(string[] args) {

    auto formatter = new Formatter;

    bool inplace;
    string configDir = ".";
    EditorConfig editorconfig;

    auto helpInformation = getopt(
            args,
            "brace_style", format!"(%s)"([EnumMembers!(Formatter.BraceStyle)].map!(to!string).join("|")), &formatter.option.braceStyle,
            "end_of_line", format!"(%s)"([EnumMembers!(Formatter.EOL)].map!(to!string).join("|")), &formatter.option.eol,
            "indent_style|t", format!"(%s)"([EnumMembers!(Formatter.IndentStyle)].map!(to!string).join("|")), &formatter.option.indentStyle,
            "indent_size", &formatter.option.indentSize,
            "inplace|i", "Edit files in place", &inplace,
            "--config_dir, -c", "Path to directory to load .editorconfig file from", &configDir,
    );

    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.",
                helpInformation.options);
        return;
    }

    auto configPath = configDir.buildPath(".editorconfig");
    if (configPath.exists)
        editorconfig = loadConfig(readText(configPath));

    if (inplace) {
        import std.file : fwrite = write;
        auto fileName = args.back;
        auto option = editorconfig.find(fileName);
        if (option.isNull is false)
            formatter.option = option.get();
        fwrite(fileName, formatter.formatSourceCode(readText(fileName)));
    } else {
        auto option = editorconfig.find("tmp.d");
        if (option.isNull is false)
            formatter.option = option.get();
        formatter.formatSourceCode(stdin.byLine.join("\n").to!string).write;
    }
}
