#!/bin/bash
export GIT_PAGER=cat
export list=`ls|sort`;
if [[ "$1" != "" ]]; then
   export list=`ls|grep $1|sort`;
   if [[ "$1" == "ADBGUI" ]]; then
      echo;
      echo "[ADBGUI]";
      echo;
      git diff;
      git status;
      exit 0;
   fi;
else
   echo;
   echo "[ADBGUI]";
   echo;
   git diff;
   git status;
fi;

for i in $list; do [[ "$i" != "Documentation" ]] && [[ "$i" != "ADBGUI" ]] && [[ "$i" != "install" ]] && [ -d $i ] && [[ `ls $i/*.pm 2>/dev/null` != "" ]] && echo && echo \[$i\] && echo && cd $i 2>/dev/null && git diff -w && git status && cd ..; done

