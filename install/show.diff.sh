git diff; for i in `ls`; do [ -d $i ] && echo $i && cd $i 2>/dev/null && git diff && cd ..; done

