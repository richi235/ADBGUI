### ADBGUI reconfigure script ###

# check if sudo is installed
if hash sudo 2>/dev/null; then
    # sudo is installed proceed as normal
    sudocommand="sudo"
else     # check if we are root
    if (( $EUID == 0 )); then
        sudocommand= '' 2>/dev/null # we are, so we will simply install everything as root
    else
        echo "sudo is not installed and you are not root"
        echo "please install sudo or execute as root"
        exit
     fi   
fi

export IFS=$(echo -en "\n\b")

if [[ $1 == "dropdb" || $2 == "dropdb" ]]; then
   echo "WARNING: You are deleting and reinitialising all your database content if you enter your db password now!!!";
   # MySQL
   perl ADBGUI/createMysql.pl dropdb $1 | mysql  --user=root --password;
else
   echo DB is not reinitalised. use "dropdb" to do this.
fi

# Bilder aller Projekte joinen
rm -r bilder 2>/dev/null
mkdir bilder

# copy dbm.pl from install to production in case it got updated
cp install/dbm.pl ../

unset IFS
for i in `echo */bilder`; do
   export IFS=$(echo -en "\n\b")
   for j in `ls $i`; do
      ln -s ../$i/$j bilder/$j;
   done;
done



unset IFS    #  iterate over all the submodule-folders
for i in `ls | grep -v install | grep -vi qooxdoo | grep -v myproject | grep -v bilder`; do
   export IFS=$(echo -en "\n\b")
   if [ -f $i/install/install.debian.sh ]; then
      cd $i;
      # execute the installscripts of all submodules/slice-packs
      bash install/install.debian.sh;
      cd ..;
   fi;
   if [[ $1 == "noap" || $2 == "noap" ]]; then
      /bin/true;
   else
      if [ -d /usr/lib/cgi-bin/$i ]; then
         echo -e "\nNeeding sudo to clean up stuff from Apache:"
         $sudocommand rm /usr/lib/cgi-bin/$i;
         $sudocommand ln -s `pwd`/$i /usr/lib/cgi-bin/$i;
      fi;
   fi;
done

if [ -f ADBGUI/Text.pm ]; then
   /bin/true;
else
   echo "No language selected, installing english.";
   cd ADBGUI;
   cp locale-files/Text_en.pm Text.pm ;
   cd ..;
fi;

if [ -f ADBGUI/DBDesign_Labels.pm ]; then
   /bin/true;
else
   cd ADBGUI;
   cp locale-files/DBDesign_Labels_en.pm DBDesign_Labels.pm ;
   cd ..;
fi;
