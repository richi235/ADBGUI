#!/bin/bash
cd /opt/birkeneck/
perl ADBGUI/getDebugData.pl |bzip2 >/root/DBBackups/`date +%Y%m%d`.ADBGUI.sql.bz2

