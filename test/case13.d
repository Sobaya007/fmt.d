import std;

pragma(inline)
string get(T)() {
    return T.stringof;
}

void main() {
    int[] x = new int[3];
    writeln(x[0]);
    delete x;

    auto y = Nullable!int(3);

    auto z = new int(3);

    auto s = format!"%s = %s"(y, z);

    writeln(get!int);

    alias f = function ref (int x) => x;
    alias g = delegate int(int x) pure nothrow {
        return x;
    };
    alias h = x => x;
    alias w = {
        writeln("w");
    };

    mixin(import("po.d"));

    static if (is(T == S[], S)) {
        pragma(msg, S.stringof);
    } else static if (is(int[] U)) {
        pragma(msg, const(U[]).stringof.length);
    } else {
        pragma(msg, int.stringof);
        writeln(int(3));
    }
    pragma(msg, typeof(y));
    writeln(typeid(z));

    alias vec4 = __vector(float[4]);

    auto c = new (1,2) class (x,y) A {
        int[] x;
        this(int[] x, Nullable!int y) {
            this.x = x;
            writeln(x, y);
        }
    };

    struct S {
        align struct M {
            int[int] mem;
            int[] mem2;
        }
        M m;
        int mem;
    }

    auto ss = {
        m: {
            mem: [
                3 : 5,
                4 : 4,
            ],
            [9, 10]
        },
        mem: 0
    };
}
