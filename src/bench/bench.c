{ return 0; }
{ return 42; }
{ return 5+20-4; }
{ return  12 + 34 - 5 ; }
{ return 5+6*7; }
{ return 5*(9-6); }
{ return (3+5)/2; }
// { return -10+20; } - disabled because of unknown libc segfault
// { return - -10; }
// { return - - +10; }
{ return 0==1; }
{ return 42==42; }
{ return 0!=1; }
{ return 42!=42; }
{ return 0<1; }
{ return 1<1; }
{ return 2<1; }
{ return 0<=1; }
{ return 1<=1; }
{ return 2<=1; }
{ return 1>0; }
{ return 1>1; }
{ return 1>2; }
{ return 1>=0; }
{ return 1>=1; }
{ return 1>=2; }
{ a=3; return a; }
{ a=3; z=5; return a+z; }
{ a=3; return a; }
{ a=3; z=5; return a+z; }
{ a=b=3; return a+b; }
{ foo=3; return foo; }
{ foo123=3; bar=5; return foo123+bar; }
{ return 1; 2; 3; }
{ 1; return 2; 3; }
{ 1; 2; return 3; }
{ {1; {2;} return 3;} }
{ ;;; return 5; }
{ if (0) return 2; return 3; }
{ if (1-1) return 2; return 3; }
{ if (1) return 2; return 3; }
{ if (2-1) return 2; return 3; }
{ if (0) { 1; 2; return 3; } else { return 4; } }
{ if (1) { 1; 2; return 3; } else { return 4; } }
 { i=0; j=0; for (i=0; i<=10; i=i+1) j=i+j; return j; }
{ for (;;) {return 3;} return 5; }
 { i=0; while(i<10) { i=i+1; } return i; }