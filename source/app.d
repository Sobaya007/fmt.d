import std;
import fmt.formatter;

void main(string[] args) {

    auto formatter = new Formatter;

    bool inplace;

    auto helpInformation = getopt(
            args,
            "brace_style", format!"(%s)"([EnumMembers!(Formatter.BraceStyle)].map!(to!string).join("|")), &formatter.option.braceStyle,
            "end_of_line", format!"(%s)"([EnumMembers!(Formatter.EOL)].map!(to!string).join("|")), &formatter.option.eol,
            "indent_style|t", format!"(%s)"([EnumMembers!(Formatter.IndentStyle)].map!(to!string).join("|")), &formatter.option.indentStyle,
            "indent_size", &formatter.option.indentSize,
            "inplace|i", "Edit files in place", &inplace,
    );

    if (helpInformation.helpWanted)
    {
        defaultGetoptPrinter("Some information about the program.",
                helpInformation.options);
        return;
    }

    if (inplace) {
        import std.file : fwrite = write;
        auto fileName = args.back;
        fwrite(fileName, formatter.formatSourceCode(readText(fileName)));
    } else {
        formatter.formatSourceCode(stdin.byLine.join("\n").to!string).write;
    }
}
