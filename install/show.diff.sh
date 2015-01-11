#!/bin/bash
export GIT_PAGER=cat
export list=`ls|sort`;
export cmd='(git diff --color -w); (git status)'
if [[ "$CMD" != "" ]]; then
   export cmd="$CMD"
fi;
if [[ "$1" != "" ]]; then
   export list=`ls|grep $1|sort`;
   if [[ "$1" == "ADBGUI" ]]; then
      echo;
      echo "[ADBGUI]";
      echo;
      bash -c "$cmd";
      exit 0;
   fi;
else
   echo;
   echo "[ADBGUI]";
   echo;
   bash -c "$cmd";
fi;

for i in $list; do [[ "$i" != "Documentation" ]] && [[ "$i" != "ADBGUI" ]] && [[ "$i" != "install" ]] && [ -d $i ] && [[ `ls $i/*.pm 2>/dev/null` != "" ]] && echo && echo \[$i\] && echo && cd $i 2>/dev/null && bash -c "$cmd" && cd ..; done

