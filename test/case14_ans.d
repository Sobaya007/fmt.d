import std;

void main()
{
    writeln(__vector(float[2]).init);
    writeln(["a" : "apple"]);
    writeln([]);
    writeln(()
    {
        writeln("!writeln"[1 .. $]);
    });
    writeln(__traits(allMembers, int));
    writeln(mixin("writeln"));
    writeln(1 < 2 ? 3 : 4);
    writeln(typeid(1L * 3.14));
    writeln(new MyInt.Inner());
    writeln(cast(char)65);
    writeln(cast(const char)65);
    writeln(cast()cast(const)cast(const shared)65);
}

double[] solve(double a, double b, double c)
in (a > 0)
in
{
    writeln([a, b, c]);
}
out (xs; xs.all!(x => a * x ^^ 2 + b * x + c == 0))
out (xs; xs !is null)
out (; a > 0)
out (xs)
{
    writeln(xs);
}
out
{
    writeln("finished");
}
do
{
    auto d = b ^^ 2 - 4 * a * c;

    pragma(msg, typeof(return));

    if (d == 0)
        return [-b / (2 * a)];
    else
        return [(-b - d ^^ 0.5) / (2 * a), (-b + d ^^ 0.5) / (2 * a)];
}

struct MyInt
{
    int x;
    mixin Proxy!x P;

    class Inner
    {
        int i;
    }
}
