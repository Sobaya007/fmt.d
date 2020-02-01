/// foo
module poyo.test;

import std;

align(3 + 4) @(3, 4.5, "67") @nogc int funcName(int x, int y)
{
    if (y < 0)
    {
        assert(false, "Invalid argument");
    }
    return funcName(x + 1);
}

alias f = (int x) => writeln(x);
