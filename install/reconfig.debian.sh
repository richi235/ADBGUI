### ADBGUI reconfigure script ###

export IFS=$(echo -en "\n\b")

if [[ $1 == "dropdb" || $2 == "dropdb" ]]; then
   echo WARNING: You are deleting and reinitialising all your database content if you enter your db password now!!!;
   # MySQL
   perl ADBGUI/createMysql.pl dropdb $1 | mysql  --user=root --password;
else
   echo DB is not reinitalised. use "dropdb" to do this.
fi

# Bilder aller Projekte joinen
rm -R bilder 2>/dev/null
mkdir bilder

unset IFS

for i in `echo */bilder`; do
   export IFS=$(echo -en "\n\b")
   for j in `ls $i`; do
      ln -s ../$i/$j bilder/$j;
   done;
done

unset IFS

for i in `ls|grep -v install|grep -vi qooxdoo|grep -v myproject|grep -v bilder`; do
   export IFS=$(echo -en "\n\b")
   if [ -f $i/install.debian.sh ]; then
      cd $i;
      bash install.debian.sh;
      cd ..;
   fi;
   if [[ $1 == "noap" || $2 == "noap" ]]; then
      /bin/true;
   else
      if [ -d /usr/lib/cgi-bin/$i ]; then
         echo -e "\nNeeding sudo to clean up stuff from Apache:"
         sudo rm /usr/lib/cgi-bin/$i;
         sudo ln -s `pwd`/$i /usr/lib/cgi-bin/$i;
      fi;
   fi;
done
if [ -f ADBGUI/Text.pm ]; then
   /bin/true;
else
   echo "No language selected, installing english.";
   cd ADBGUI;
   cp Text_english.pm Text.pm;
   cd ..;
fi;

