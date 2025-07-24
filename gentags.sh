#!/bin/bash
rm -f files.txt
find $PWD -type f -name '*.c' \
	-or -name '*.cpp' \
	-or -name '*.cxx' \
	-or -name '*.h' \
	-or -name '*.hxx' \
	-or -name '*.hpp' \
	| grep -v build \
	| grep -v cmake \
	> files.txt

cscope -b -i files.txt
ctags -L files.txt
