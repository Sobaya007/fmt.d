import std;

shared static this() const
{
    writeln("shared static constructor");
}

shared static ~this() const
{
    writeln("shared static destructor");
}

static this() const
{
    writeln("static constructor");
}

static ~this() const
{
    writeln("static destructor");
}

enum attr;

debug = Po;
version = V2;

class B;
class A(Int) : B
if (is(Int : int))
{
    Int x = void;

    alias x this;

    alias T = typeof(this);
    alias X = typeof(typeof(this).x);

    invariant (x > 0);

    invariant
    {
        assert(x > 0);
    }

    @disable this(this);
    @disable this(string);

    this(Int2)(Int2 x) @nogc
    if (is(Int2 : int))
    {
        this.x = x;
    }

    ~this() nothrow
    {
        writeln("destructing...");
    }

    auto clone(this This)(@attr bool flag = false) const
    {
        return new This;
    }
}

alias cintp = const(int)*;
alias str = mixin("string");

extern(C++) auto func(Args...)(ref Args args)
if (is(Args[0] == void delegate()))
{
    alias T = Args[1 .. $];
    static assert(is(T[0] == int function() nothrow));
    args[2] = () const @nogc
    {
        args[3] = 4;
    };
    return T.init;
}

deprecated extern(C):
auto func2(const int[3] x...) @nogc pure
{
    import std : format, split;
    return format!"%d, %d"(x[0], x[1]).split(", ");
}

extern(C++, foo) int global;

extern(Objective-C) int global2;

enum : int
{
    A = 3,
    B = 5,
}

version (unittest)
{
    enum Init(T) = T.init;
}

import std : isBasicType;
interface I;
interface I2(T) : I
if (isBasicType!T)
{
    T get();
}

template Po(T, alias S)
if (is(T : int[]))
{
    enum Po = T.stringof ~ S(T);
}

unittest
{
    assert(global > 3);
}
