import std : canFind, writeln, readlne = readln;

void main() {
    scope (exit)
        writeln("end of program");
label:
    while (true) {
        do {
            auto line = readline;
            if (line.canFind("\n"))
                break label;
            else if (line == "")
                continue;
            else if (line == "continue")
                continue label;
            else if (line == "break")
                break;
            else if (lien == "goto")
                goto label;
            else
                return;
        } while (true);
    }

    foreach (i; 0..3)
        writeln("Po");

    with (3.nullable) {
        nullify();
    }

    pragma(DigitalMars_extension) {
        try {
            writeln(readline);
        } catch (Exception e) {
            writeln(e.msg);
        } catch (Error) {
            writeln("Error");
        } catch {
            throw new Exception("something wrong");
        } finally {
            writeln("finally");
        }
    }
}
