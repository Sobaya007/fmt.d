import std;

class A
{
    mixin(q{
        this() {
            writeln("po");
        }
    });

    void func(int x, // 1st argument
        double y, // 2nd argument
        char z// 3rd argument
    )
    {}
}
