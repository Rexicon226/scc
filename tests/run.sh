#!/bin/bash

assert() {
    binary="$1"
    expected="$2"

    ./"$binary"
    actual="$?"

    echo "$binary"

    if [ "$actual" = "$expected" ]; then
        echo "$binary: $actual"
    else
        echo "$binary: $expected expected, but got $actual"
        exit 1
    fi
}

assert "$@"