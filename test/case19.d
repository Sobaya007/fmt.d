void func1() pure nothrow @safe @nogc
{
    void *pc;
    asm pure nothrow @trusted @nogc
    {
        call L1          ;
      L1:                ;
        pop  EBX         ;
        mov pc[EBP],EBX ;
    }

    asm
    {
        db 5,6,0x83;
        ds 0x1234;  
        di 0x1234;  
        dl 0x1234;  
        df 1.234;   
        dd 1.234;   
        de 1.234;   
        db "abc";   
        ds "abc";   
    }
}
