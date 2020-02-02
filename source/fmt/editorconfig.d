module fmt.editorconfig;

import std;
import fmt.formatter;

class Option {
    string pattern;
    Formatter.Option option;
    this(string pattern, Formatter.Option option) {
        this.pattern = pattern;
        this.option = option;
    }
}

struct EditorConfig {
    bool root;
    Option[] options;

    Formatter.Option opIndex(string pattern) {
        return options.find!(op => op.pattern == pattern).front.option;
    }

    Nullable!(Formatter.Option) find(string fileName) {
        foreach_reverse(op; options) {
            if (sectionMatch(fileName, op.pattern))
                return op.option.nullable;
        }
        return typeof(return).init;
    }
}

EditorConfig loadConfig(string fileContent) {
    EditorConfig result;
    Option option;
    foreach (line; fileContent.split("\n")) {
        if (line.isBlank) continue;
        if (line.isComment) continue;
        if (line.isSectionHeader) {
            auto sectionHeader = line.getSectionHeader();
            option =  new Option(sectionHeader, Formatter.Option.init);
            result.options ~= option;
            continue;
        }
        if (line.isKeyValuePair) {
            auto key = line.getKey();
            auto value = line.getValue();
            enforce(key == "root" || option, "Section header is not specified.");
            switch (key) {
                case "brace_style":
                    option.option.braceStyle = value.to!(Formatter.BraceStyle);
                    continue;
                case "indent_style":
                    option.option.indentStyle = value.to!(Formatter.IndentStyle);
                    continue;
                case "indent_size":
                    option.option.indentSize = value.to!size_t;
                    continue;
                case "end_of_line":
                    option.option.eol = value.to!(Formatter.EOL);
                    continue;
                case "root":
                    result.root = value.to!bool;
                    continue;
                default:
                    continue;
            }
        }
        enforce(false, "Invalid line: " ~ line);
    }
    return result;
}

bool sectionMatch(string fileName, string sectionHeader) {
    auto pattern = sectionHeader
        .replaceAll(ctRegex!`\{\d+\.\.\d+\}`, "(\\d+)")
        .replace("?", ".")
        .replace(".", "\\.")
        .replace("**", ".__star__")
        .replace("*", "[^/]*")
        .replace("__star__", "*")
        .replaceAll(ctRegex!`\{.*?\}`, "(.*)");

    auto r = fileName.matchAll(regex(pattern));
    if (!r) return false;
    auto matchResult = r.front.map!(to!string).array;
    if (matchResult.empty) return false;
    if (matchResult.length == 1) return true;
    string[] originalPatterns = sectionHeader.matchAll(ctRegex!`\{(.*?)\}`).front.map!(to!string).array;

    foreach (originalPattern, filePart; zip(originalPatterns[1..$], matchResult[1..$])) {
        if (originalPattern.canFind("..")) {
            try {
                auto range = originalPattern.split("..").to!(int[]);
                if (range.length != 2) return false;
                if (!(range[0] <= filePart.to!int && filePart.to!int <= range[1])) return false;
            } catch(ConvException) {
                return false;
            }
        } else {
            if (!originalPattern.split(",").canFind(filePart)) return false;
        }
    }
    return true;
}

private {
    bool isBlank(string line) {
        return line.chomp == "";
    }

    bool isComment(string line) {
        return cast(bool)line.match(ctRegex!`^#`);
    }

    bool isSectionHeader(string line) {
        return cast(bool)line.match(ctRegex!` *\[.*\] *`);
    }

    bool isKeyValuePair(string line) {
        return cast(bool)line.match(ctRegex!`.*=.*`);
    }

    string getSectionHeader(string line) {
        return line.matchFirst(ctRegex!` *\[(.*)\] *`)[1];
    }

    string getKey(string line) {
        return line.split("=")[0].strip;
    }

    string getValue(string line) {
        return line.split("=")[1].strip;
    }
}

unittest {
    auto configs = loadConfig(readText("test/.editorconfig"));
    assert(configs.root is true);

    assert(configs["*"].eol == Formatter.EOL.lf);

    assert(configs["*.py"].indentStyle == Formatter.IndentStyle.space);
    assert(configs["*.py"].indentSize == 4);

    assert(configs["Makefile"].indentStyle == Formatter.IndentStyle.tab);

    assert(configs["lib/**.js"].indentStyle == Formatter.IndentStyle.space);
    assert(configs["lib/**.js"].indentSize == 2);

    assert(configs["{package.json,.travis.yml}"].indentStyle == Formatter.IndentStyle.space);
    assert(configs["{package.json,.travis.yml}"].indentSize == 2);
}

unittest {
    assert( sectionMatch("poyo3.d", "*"));

    assert( sectionMatch("poyo3.d", "*.d"));
    assert(!sectionMatch("poyo3.d", "*.py"));

    assert( sectionMatch("poyo3.d", "*.{js,d}"));
    assert(!sectionMatch("poyo3.d", "*.{js,py}"));

    assert( sectionMatch("poyo3.d", "*{0..5}.{js,d}"));
    assert(!sectionMatch("poyo3.d", "*{0..2}.{js,d}"));

    assert( sectionMatch("foo/poyo3.d", "foo/poyo3.d"));
    assert(!sectionMatch("foo/poyo3.d", "foo/poyo2.d"));

    assert( sectionMatch("foo/poyo3.d", "{foo/poyo3.d,bar/poyo.d}"));
    assert(!sectionMatch("foo/poyo3.d", "{foo/poyo2.d,bar/poyo3.d}"));
}
