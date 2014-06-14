cd install 2>/dev/null

cd ..

if [[ $1 == "dropdb" || $2 == "dropdb" ]]; then
   echo WARNING: You are deleting and reinitialising all your database content if you enter your db password now!!!;
   # MySQL
   perl ADBGUI/createMysql.pl dropdb $1|mysql -p;
else
   echo DB is not reinitalised. use "dropdb" to do this.
fi

# Bilder aller Projekte joinen
rm -R bilder 2>/dev/null
mkdir bilder

for i in `echo */bilder`; do
   export IFS=$(echo -en "\n\b")
   for j in `ls $i`; do
      ln -s ../$i/$j bilder/$j;
   done;
done

for i in `find . -name install.debian.sh -type f|grep -v ./install/install.debian.sh`; do
   if [[ $i != "install/install.debian.sh" ]]; then bash $i; fi;
done;

if [[ $1 == "noap" || $2 == "noap" ]]; then
   /bin/true;
else
   for i in `ls|grep -v install|grep -vi qooxdoo|grep -v myproject|grep -v bilder`; do
      if [ -d /usr/lib/cgi-bin/$i ]; then rm /usr/lib/cgi-bin/$i; ln -s `pwd`/$i /usr/lib/cgi-bin/$i; fi;
   done;
fi

