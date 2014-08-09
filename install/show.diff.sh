#!/bin/bash
export GIT_PAGER=cat
git diff; for i in `ls|sort`; do [[ -d $i && "ls $i/*.pm" != "" ]] && echo \[$i\] && echo && cd $i 2>/dev/null && git diff -w && cd ..; done

