#!/bin/bash
assert() {
  expected="$1"
  input="$2"

  ./zig-out/bin/vanadium "$input" 2> tmp.s || exit
  gcc -static -o tmp tmp.s
  ./tmp
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "$input => $actual"
  else
    echo "$input => $expected expected, but got $actual"
    exit 1
  fi
}

zig build

echo "assert"
assert 0 0
assert 20 20
assert 25 '5+20'
assert 50 '5+20+25'
assert 15 '20-5'
assert 41 ' 12 + 34 - 5 '
assert 47 '5+6*7'
assert 15 '5*(9-6)'
assert 4 '(3+5)/2'

echo OK