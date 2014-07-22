# ADBGUI

The ADBGUI Framework allows you to easily create a custom Web-Gui for your database. 

For office people you can say its a lightweight, extensible opensource  M$ Access in the browser.


## Official Documentation
* http://www.adbgui.org/    
* http://www.adbgui.org/lib/exe/detail.php?id=start&media=howto:screenshot.jpg

## Supported Databases
* MySQL
* PostgreSQL
* csv files


## Installation on Debian GNU/Linux:

```bash
# The name of your database frontend empowerd with ADBGUI
export PROJECTNAME=myproject

apt-get update
apt-get --force-yes -y install git libjson-perl

# clone to local folder (here /opt )
cd /opt/
git clone https://github.com/pRiVi/ADBGUI.git
mv ADBGUI $PROJECTNAME
cd $PROJECTNAME

# If you want to use the qooxdoo feature   : paramter "qx"
# If you do not want apache to be installed: paramter "noap"
bash install/install.debian.sh qx

# Here you install all your modules, or a skeleton for a new project
perl install/skeleton.pl $PROJECTNAME 
bash install/reconfig.debian.sh
perl dbm.pl
```
