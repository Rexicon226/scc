#!/bin/bash

assert() {
  expected="$1"
  input="$2"

  $scc_path --cli "$input" > ./tests/output.s || exit

  zig cc \
  -Wno-unused-command-line-argument \
  -target x86_64-linux\
  -static \
  -z noexecstack \
  -o ./tests/output ./tests/output.s \

  ./tests/output
  actual="$?"

  if [ "$actual" = "$expected" ]; then
    echo "$input => $actual"
  else
    echo "$input => $expected expected, but got $actual"

    # Might want to keep the assembly for debugging
    rm ./tests/output

    echo "Assembly:"

    cat ./tests/output.s
      
    exit 1
  fi

  rm ./tests/output.s
  rm ./tests/output
}

# Check that there was an argument
if [ $# -ne 2 ]; then
  echo "Usage: $0 <scc>"
  exit 1
fi

scc_path=$1
tests_file=$2

# Check that the scc executable exists
if [ ! -f "$scc_path" ]; then
  echo "scc executable not found at $scc_path"
  exit 1
fi

# Check that the input file exists
if [ ! -f "$tests_file" ]; then
  echo "Tests file not found at $tests_file"
  exit 1
fi

# Check that the input file is not empty
if [ ! -s "$tests_file" ]; then
  echo "Tests file is empty"
  exit 1
fi

# Parse the tests file, ignoring lines that start with #
# Lines are in the format: "0 - { return 0; }"
while IFS= read -r line
do
  # Ignore lines starting with #
  if [[ ${line:0:1} == '#' ]]; then
    continue
  fi

  # Ignore empty lines
  if [[ -z "$line" ]]; then
    continue
  fi

  # Extract the expected result and input
  expected=$(echo "$line" | cut -d' ' -f1)
  input=$(echo "$line" | cut -d' ' -f3-)

  assert "$expected" "$input"
done < "$tests_file"
