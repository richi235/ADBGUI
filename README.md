# ADBGui

ADBGui allows you to create a gui for a database. 

For office people you can say its a lightweight, extinsible opensource  M$ Access in the browser.


## Official Documentation
* http://www.adbgui.org/    
* http://www.adbgui.org/lib/exe/detail.php?id=start&media=howto:screenshot.jpg

## Supported Databases
* MySQL
* PostgreSQL
* csv files


## Installation on Debian GNU/Linux:

```bash
export PROJECTNAME=myproject

apt-get update
apt-get --force-yes -y install git libjson-perl

cd /opt/
git clone https://github.com/pRiVi/ADBGUI.git
mv adbgui $PROJECTNAME
cd $PROJECTNAME

# If you want to use the qooxdoo feature   : paramter "qx"
# If you do not want apache to be installed: paramter "noap"
bash install/install.debian.sh qx
perl install/skeleton.pl $PROJECTNAME # Here you install all your modules, or a skeleton for a new project
bash install/reconfig.debian.sh
perl dbm.pl
```

