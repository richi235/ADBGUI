#!/bin/bash
### The official ADBGUI localisation switcher (TM)^^ ###
### Just execute to switch to german localisation

    # overwrite the current lang file with the german ones
    cp ./locale-files/Text_de.pm Text.pm
    # overwrite the current DBDesign_Labels file with the german one
    cp ./locale-files/DBDesign_Labels_de.pm DBDesign_Labels.pm
