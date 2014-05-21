rm myproject/source/class/myproject/Application.js
for i in `ls ADBGUI/Qooxdoo/`; do ln -s ../../../../ADBGUI/Qooxdoo/$i myproject/source/class/myproject/$i; done
