import std;

static foreach(i; 0 .. 5)
{
    mixin(format!"int x%d;"(i));
}

enum Color
{
    Red = 1,
    Blue,
    Green,
    deprecated White,
}

static foreach(color; EnumMembers!Color)
{
    pragma(msg, color);
}

Color fromString(string s)
{
    final switch (s)
    {
        static foreach (c2; EnumMembers!Color)
        {
            case c2.to!string:
                return c2;
        }
    }
}

int f(Color c)
{
    if (const Color a = c)
    {
        writeln("const here");
    }
    if (const a = c)
    {
        writeln("const here");
    }
    if (auto a = cast(const)c)
    {
        writeln("const here");
    }
    switch (c)
    {
        case Color.Red:
            writeln("This is Red");
            goto case Color.Blue;
        default:
            writeln("other");
            return 1;
    }
}
