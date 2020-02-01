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

    // formatter.formatSourceCode(readText("test.d")).writeln;
    // foreach (e; dirEntries("test", SpanMode.depth)) {
    //     if (e.to!string.match(ctRegex!`case(\d+)\.d`)) {
    //         auto a = formatter.formatSourceCode(readText(e).chomp);
    //         auto b = readText(e.stripExtension ~ "_ans.d").chomp;
    //         assert(a == b, format!"%s:\n-----\n%s\n----\n%s\n----"(e,a,b));
    //     }
    // }
    // formatter.option.braceStyle = Formatter.BraceStyle.Otbs;
    // foreach (e; dirEntries("../sbylib", SpanMode.depth)) {
    //     if (e.extension == ".d") {
    //         if (e.array.canFind("resource")) continue;
    //         try {
    //             writeln(formatter.formatSourceCode(readText(e)));
    //         } catch (Throwable t) {
    //             writefln("%s:\n-----\n%s", e, readText(e));
    //             throw t;
    //         }
    //     }
    // }
}
