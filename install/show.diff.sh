#!/bin/bash
export GIT_PAGER=cat
git diff; for i in `ls|sort`; do [[ "$i" != "Documentation" ]] && [[ "$i" != "ADBGUI" ]]  && [[ "$i" != "install" ]] && [ -d $i ] && [[ `ls $i/*.pm 2>/dev/null` != "" ]] && echo \[$i\] && echo && cd $i 2>/dev/null && git diff -w && cd ..; done

