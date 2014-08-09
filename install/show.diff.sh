#!/bin/bash
git diff; for i in `ls|sort`; do [ -d $i ] && echo $i && cd $i 2>/dev/null && git diff && cd ..; done

