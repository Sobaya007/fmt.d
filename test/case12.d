enum A = ((0 & 1) | 2) ^ 3;
enum B = (true && false) || false;
enum C = 2 ^^ 0.5;

static if (is(int[] : const int[])) {
    pragma(msg, "here");
} else static if (3 in [1,2,3]) {
    pragma(msg, "there");
} else {
    pragma(msg, "foo");
}
