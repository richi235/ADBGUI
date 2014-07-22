apt-get --force-yes -y install libwww-perl libgd-graph3d-perl libunix-syslog-perl libpoe-perl mysql-server libpoe-component-client-http-perl libdate-calc-perl libjson-perl libclone-perl libemail-mime-createhtml-perl libemail-send-perl

cd install 2>/dev/null

export apachefiles="gui.pl DBDesign.pm gui.cfg url.css"
export apachelinks="$apachefiles ADBGUI bilder"
export defaultfiles="dbm.pl dbm.cfg DBDesign.pm"

# Apache und gui.pl
for i in "$defaultfiles"; do
   cp $i ..;
done;

chmod +x dbm.pl;

touch ../gui.cfg;

if [[ $1 == "noap" || $2 == "noap" ]]; then
   /bin/true;
else
   cp $apachefiles ..;
   chmod +x ../gui.pl;
fi

echo "\$DB->{name} = '$PROJECTNAME';" >>../DBDesign.pm

# Qooxoo
if [[ $1 == "qx" || $2 == "qx" ]]; then
   apt-get --force-yes -y install unzip python;
   rm -R qooxdoo-*-sdk ../qooxdoo-*-sdk 2>/dev/null;
   unzip qooxdoo-*-sdk.zip;
   mv qooxdoo-*-sdk ..;
fi

cd ..

# MySQL
perl ADBGUI/createMysql.pl createdb|mysql -p

# QX
if [[ $1 == "qx" || $2 == "qx" ]]; then
   rm -R myproject 2>/dev/null;
   qooxdoo-*-sdk/tool/bin/create-application.py -n myproject;
   bash ADBGUI/Qooxdoo/install.sh;
   perl install/setupQXConfig.pl;
   cd myproject;
   for i in build source; do
      ./generate.py $i;
      cd $i;
      rm bilder 2>/dev/null;
      ln -s ../../bilder .;
      rm qooxdoo-*-sdk 2>/dev/null;
      ln -s ../../qooxdoo-*-sdk .;
      ln -s source .;
      cd ..;
   done;
   cd ..;
fi;

if [[ $1 == "noap" || $2 == "noap" ]]; then
   /bin/true;
else
   apt-get --force-yes -y install apache2
   for i in $apachelinks; do
      rm /usr/lib/cgi-bin/$i 2>/dev/null;
      ln -s `pwd`/$i /usr/lib/cgi-bin/$i;
   done;
fi;

if [[ -h /var/www/bilder ]]; then
   rm /var/www/bilder;
fi
ln -s `pwd`/bilder/ /var/www/bilder

