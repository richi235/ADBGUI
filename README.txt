This software allows to have an gui for a database and the internal links of the tables. For office people you can say its an opensource access in the browser.

More details you can find here:

http://www.adbgui.org/
http://www.adbgui.org/lib/exe/detail.php?id=start&media=howto:screenshot.jpg

Autoinstall on debian:

export PROJECTNAME=myproject
apt-get update
apt-get --force-yes -y install git libjson-perl
cd /opt/
git clone git@github.com:pRiVi/ADBGUI.git
mv adbgui $PROJECTNAME
cd $PROJECTNAME
# If you want to use the qooxdoo feature   : paramter "qx"
# If you do not want apache to be installed: paramter "noap"
bash install/install.debian.sh qx
perl install/skeleton.pl $PROJECTNAME # <- Here you install all your modules, or a skelettion of a new project
bash install/reconfig.debian.sh
perl dbm.pl
