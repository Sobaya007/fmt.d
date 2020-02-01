import std;

void main()
{
    for (int i = 0; i < 10; i++)
    {
        if (i % 3 == 0 || i % 5 == 0)
        {
            if (i % 3 == 0)
                write("Fizz");
            if (i % 5 == 0)
                write("Buzz");
            writeln;
        }
        else
            writeln(i);
    }
}
