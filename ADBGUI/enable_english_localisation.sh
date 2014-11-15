#!/bin/bash
### The official ADBGUI localisation switcher (TM)^^ ###
### just execute to switch to english localisation

    # overwrite the current lang file with the english ones
    rm Text.pm
    ln locale-files/Text_en.pm Text.pm
    # overwrite the current DBDesign_Labels file with the english one
    rm DBDesign_Labels.pm
    ln locale-files/DBDesign_Labels_en.pm DBDesign_Labels.pm
