/// foo
module poyo.test;

align(3 + 4) @(3, 4.5, "67") @nogc int funcName(int x, int y)
{
    return funcName(x + 1);
}
