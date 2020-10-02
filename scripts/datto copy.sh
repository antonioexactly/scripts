set -x

Uri=${1}
HANAVER=${2}
HANAUSR=${3}
HANAPWD=${4}
HANASID=${5}
HANANUMBER=${6}
vmSize=${7}
SUBEMAIL=${8}
SUBID=${9}
SUBURL=${10}

#if needed, register the machine
if [ "$SUBEMAIL" != "" ]; then
  if [ "$SUBURL" != "" ]; then 
   SUSEConnect -e $SUBEMAIL -r $SUBID --url $SUBURL
  else 
   SUSEConnect -e $SUBEMAIL -r $SUBID
  fi
fi

#decode hana version parameter
HANAVER=${HANAVER^^}


#get the VM size via the instance api
VMSIZE=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/compute/vmSize?api-version=2017-08-01&format=text"`


#install hana prereqs
zypper install -y glibc-2.22-51.6
zypper install -y systemd-228-142.1
zypper install -y unrar
zypper install -y sapconf
zypper install -y saptune
mkdir /etc/systemd/login.conf.d
mkdir /hana
mkdir /hana/data
mkdir /hana/log
mkdir /hana/shared
mkdir /hana/backup
mkdir /usr/sap

#VG & LV naming comvention
sharedvgname="sap""$HANASID""vg"
sharedlvname="lvsap""$HANASID""01"
usrlvname="lvsap""$HANASID""02"
backupvgname="sap""$HANASID""bvg"
backuplvname="lvsap""$HANASID""b01"
datavgname="sap""$HANASID""dvg"
logvgname="sap""$HANASID""lvg"
datalvname="lvsap""$HANASID""d01"
loglvname="lvsap""$HANASID""l01"
hdatapart="/dev/""$datavgname""/""$datalvname"
hsharedpart="/dev/""$sharedvgname""/""$sharedlvname"
hlogpart="/dev/""$logvgname""/""$loglvname"
husrpart="/dev/""$sharedvgname""/""$usrlvname"
hbackuppart="/dev/""$backupvgname""/""$backuplvname"

zypper in -t pattern -y sap-hana
saptune solution apply HANA
saptune daemon start

# step2
echo $Uri >> /tmp/url.txt

cp -f /etc/waagent.conf /etc/waagent.conf.orig
sedcmd="s/ResourceDisk.EnableSwap=n/ResourceDisk.EnableSwap=y/g"
sedcmd2="s/ResourceDisk.SwapSizeMB=0/ResourceDisk.SwapSizeMB=2048/g"
cat /etc/waagent.conf | sed $sedcmd | sed $sedcmd2 > /etc/waagent.conf.new
cp -f /etc/waagent.conf.new /etc/waagent.conf

#don't restart waagent, as this will kill the custom script.
#service waagent restart

if [ "$VMSIZE" == "Standard_M32ts" ] || [ "$VMSIZE" == "Standard_M32ls" ] || [ "$VMSIZE" == "Standard_M64ls" ] || [ $VMSIZE == "Standard_DS14_v2" ] ; then
echo "logicalvols start" >> /tmp/parameter.txt
  # this assumes that 5 disks are attached at lun 0 through 4
  echo "Creating partitions and physical volumes"
  pvcreate -ff -y /dev/disk/azure/scsi1/lun0   
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun1
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun2
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun3

  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate $sharedvgname $sharedvglun
  lvcreate -l 50%FREE -n $sharedlvname $sharedvgname 
 
  #usr volume creation  
  lvcreate -l 100%FREE -n $usrlvname $sharedvgname

  #backup volume creation
  backupvglun="/dev/disk/azure/scsi1/lun1"  
  vgcreate $backupvgname $backupvglun
  lvcreate -l 100%FREE -n $backuplvname $backupvgname 

  #data volume creation
  datavglun="/dev/disk/azure/scsi1/lun2"
  logvglun="/dev/disk/azure/scsi1/lun3"
  vgcreate $datavgname $datavglun 
  vgcreate $logvgname $logvglun
  lvcreate -l 100%FREE -n $datalvname $datavgname
  lvcreate -l 100%FREE -n $loglvname $logvgname


  mkfs -t xfs /dev/$datavgname/$datalvname
  mkfs -t xfs /dev/$logvgname/$loglvname
  mkfs -t xfs /dev/$sharedvgname/$sharedlvname
  mkfs -t xfs /dev/$backupvgname/$backuplvname 
  mkfs -t xfs /dev/$sharedvgname/$usrlvname
    
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M64s" ]; then
  #this is the medium size
  # this assumes that 6 disks are attached at lun 0 through 5
  echo "Creating partitions and physical volumes"
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun6
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun7
  pvcreate -ff -y /dev/disk/azure/scsi1/lun8
  pvcreate -ff -y /dev/disk/azure/scsi1/lun9

  echo "logicalvols start" >> /tmp/parameter.txt
  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
  #usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

  #backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

  #data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  datavg4lun="/dev/disk/azure/scsi1/lun7"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun $datavg4lun
  PHYSVOLUMES=4
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

  #log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun8"
  logvg2lun="/dev/disk/azure/scsi1/lun9"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg
  mount -t xfs /dev/logvg/loglv /hana/log 
echo "/dev/mapper/logvg-loglv /hana/log xfs defaults 0 0" >> /etc/fstab

  mkfs.xfs /dev/datavg/datalv
  mkfs.xfs /dev/logvg/loglv
  mkfs -t xfs /dev/sharedvg/sharedlv 
  mkfs -t xfs /dev/backupvg/backuplv 
  mkfs -t xfs /dev/usrsapvg/usrsaplv
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M64ms" ] || [ $VMSIZE == "Standard_M128s" ]; then

  # this assumes that 6 disks are attached at lun 0 through 9
  echo "Creating partitions and physical volumes"
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun6
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun7
  pvcreate  -ff -y /dev/disk/azure/scsi1/lun8

  echo "logicalvols start" >> /tmp/parameter.txt
  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
  #usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

  #backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

  #data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun 
  PHYSVOLUMES=3
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

  #log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun7"
  logvg2lun="/dev/disk/azure/scsi1/lun8"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg
  mount -t xfs /dev/logvg/loglv /hana/log   
echo "/dev/mapper/logvg-loglv /hana/log xfs defaults 0 0" >> /etc/fstab

  mkfs.xfs /dev/datavg/datalv
  mkfs.xfs /dev/logvg/loglv
  mkfs -t xfs /dev/sharedvg/sharedlv 
  mkfs -t xfs /dev/backupvg/backuplv 
  mkfs -t xfs /dev/usrsapvg/usrsaplv
echo "logicalvols end" >> /tmp/parameter.txt
fi

if [ $VMSIZE == "Standard_M128ms" ] || [ $VMSIZE == "Standard_M208ms_v2" ]; then

  # this assumes that 6 disks are attached at lun 0 through 5
  echo "Creating partitions and physical volumes"
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun6
  pvcreate -ff -y  /dev/disk/azure/scsi1/lun7
  pvcreate  -ff -y /dev/disk/azure/scsi1/lun8
  pvcreate  -ff -y /dev/disk/azure/scsi1/lun9
  pvcreate  -ff -y /dev/disk/azure/scsi1/lun10

  echo "logicalvols start" >> /tmp/parameter.txt
  #shared volume creation
  sharedvglun="/dev/disk/azure/scsi1/lun0"
  vgcreate sharedvg $sharedvglun
  lvcreate -l 100%FREE -n sharedlv sharedvg 
 
  #usr volume creation
  usrsapvglun="/dev/disk/azure/scsi1/lun1"
  vgcreate usrsapvg $usrsapvglun
  lvcreate -l 100%FREE -n usrsaplv usrsapvg

  #backup volume creation
  backupvg1lun="/dev/disk/azure/scsi1/lun2"
  backupvg2lun="/dev/disk/azure/scsi1/lun3"
  vgcreate backupvg $backupvg1lun $backupvg2lun
  lvcreate -l 100%FREE -n backuplv backupvg 

  #data volume creation
  datavg1lun="/dev/disk/azure/scsi1/lun4"
  datavg2lun="/dev/disk/azure/scsi1/lun5"
  datavg3lun="/dev/disk/azure/scsi1/lun6"
  datavg4lun="/dev/disk/azure/scsi1/lun7"
  datavg5lun="/dev/disk/azure/scsi1/lun8"
  vgcreate datavg $datavg1lun $datavg2lun $datavg3lun $datavg4lun $datavg5lun
  PHYSVOLUMES=4
  STRIPESIZE=64
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n datalv datavg

  #log volume creation
  logvg1lun="/dev/disk/azure/scsi1/lun9"
  logvg2lun="/dev/disk/azure/scsi1/lun10"
  vgcreate logvg $logvg1lun $logvg2lun
  PHYSVOLUMES=2
  STRIPESIZE=32
  lvcreate -i$PHYSVOLUMES -I$STRIPESIZE -l 100%FREE -n loglv logvg
  mount -t xfs /dev/logvg/loglv /hana/log 
  echo "/dev/mapper/logvg-loglv /hana/log xfs defaults 0 0" >> /etc/fstab

  mkfs.xfs /dev/datavg/datalv
  mkfs.xfs /dev/logvg/loglv
  mkfs -t xfs /dev/sharedvg/sharedlv 
  mkfs -t xfs /dev/backupvg/backuplv 
  mkfs -t xfs /dev/usrsapvg/usrsaplv
fi


#!/bin/bash
echo "mounthanashared start" >> /tmp/parameter.txt
mount -t xfs $hsharedpart /hana/shared
mount -t xfs $hbackuppart /hana/backup 
mount -t xfs $husrpart /usr/sap
mount -t xfs $hdatapart /hana/data
mount -t xfs $hlogpart /hana/log
echo "mounthanashared end" >> /tmp/parameter.txt

echo "write to fstab start" >> /tmp/parameter.txt
echo "$hdatapart"" /hana/data xfs defaults 0 0" >> /etc/fstab
echo "$hsharedpart"" /hana/shared xfs defaults 0 0" >> /etc/fstab
echo "$hbackuppart"" /hana/backup xfs defaults 0 0" >> /etc/fstab
echo "$husrpart"" /usr/sap xfs defaults 0 0" >> /etc/fstab
echo "$hlogpart"" /hana/log xfs defaults 0 0" >> /etc/fstab
echo "write to fstab end" >> /tmp/parameter.txt

if [ ! -d "/hana/data/sapbits" ]
 then
 mkdir "/hana/data/sapbits"
fi

#####################
SAPBITSDIR="/hana/data/sapbits"


#Rewrite for better automation
if [ "${HANAVER}" = "SAP HANA PLATFORM EDITION 2.0 SPS04" ] 
then
  cd $SAPBITSDIR
  /usr/bin/wget $Uri/SapHana/SP04/HANA.ZIP
  mkdir "HANAMedia"
  cd "HANAMedia"
  unzip ../HANA.ZIP
  cd $SAPBITSDIR
 #add additional requirement
  zypper install -y libatomic1
else 
    if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS05" ]
    then
        cd $SAPBITSDIR
        /usr/bin/wget $Uri/SapHana/SP05/HANA.ZIP
        mkdir "HANAMedia"
        cd "HANAMedia"
        unzip ../HANA.ZIP
        cd $SAPBITSDIR
        #add additional requirement
        zypper install -y libatomic1
    else
        if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS02" ]
        then
              cd $SAPBITSDIR
              /usr/bin/wget --quiet $Uri/SapHana/SP02/HANA_part1.exe
              /usr/bin/wget --quiet $Uri/SapHana/SP02/HANA_part2.rar
              /usr/bin/wget --quiet $Uri/SapHana/SP02/HANA_part3.rar
              /usr/bin/wget --quiet $Uri/SapHana/SP02/HANA_part4.rar
              cd $SAPBITSDIR

              echo "hana unrar start" >> /tmp/parameter.txt
              #!/bin/bash
              cd $SAPBITSDIR
              mkdir "HANAMedia"
              cd "HANAMedia"
              unrar  -o- x HANA_part1.exe
              echo "hana unrar end" >> /tmp/parameter.txt
        else      
            if [ "$HANAVER" = "SAP HANA PLATFORM EDITION 2.0 SPS03" ]
            then
                  cd $SAPBITSDIR
                  /usr/bin/wget --quiet $Uri/SapHana/SP03/HANA_part1.exe
                  /usr/bin/wget --quiet $Uri/SapHana/SP03/HANA_part2.rar
                  /usr/bin/wget --quiet $Uri/SapHana/SP03/HANA_part3.rar
                  /usr/bin/wget --quiet $Uri/SapHana/SP03/HANA_part4.rar
                  cd $SAPBITSDIR

                  echo "hana unrar start" >> /tmp/parameter.txt
                  #!/bin/bash
                  cd $SAPBITSDIR
                  mkdir "HANAMedia"
                  cd "HANAMedia"
                  unrar  -o- x HANA_part1.exe
                  echo "hana unrar end" >> /tmp/parameter.txt
            fi
        fi
    fi
fi

#!/bin/bash
cd /hana/data/sapbits
echo "hana download start" >> /tmp/parameter.txt
/usr/bin/wget --quiet $Uri/SapHana/md5sums
/usr/bin/wget --quiet "https://raw.githubusercontent.com/antonioexactly/arm-hana-deploy/master/hdbinst.cfg"
echo "hana download end" >> /tmp/parameter.txt

date >> /tmp/testdate
cd /hana/data/sapbits

echo "hana prepare start" >> /tmp/parameter.txt
cd /hana/data/sapbits

#!/bin/bash
cd /hana/data/sapbits
myhost=`hostname`
sedcmd="s/REPLACE-WITH-HOSTNAME/$myhost/g"
sedcmd2="s/\/hana\/shared\/sapbits\/51052325/\/hana\/data\/sapbits\/HANAMedia/g"
sedcmd3="s/root_user=root/root_user=$HANAUSR/g"
sedcmd4="s/AweS0me@PW/$HANAPWD/g"
sedcmd5="s/sid=H10/sid=$HANASID/g"
sedcmd6="s/number=00/number=$HANANUMBER/g"
cat hdbinst.cfg | sed $sedcmd | sed $sedcmd2 | sed $sedcmd3 | sed $sedcmd4 | sed $sedcmd5 | sed $sedcmd6 > hdbinst-local.cfg
echo "hana preapre end" >> /tmp/parameter.txt

#put host entry in hosts file using instance metadata api
VMIPADDR=`curl -H Metadata:true "http://169.254.169.254/metadata/instance/network/interface/0/ipv4/ipAddress/0/privateIpAddress?api-version=2017-08-01&format=text"`
VMNAME=`hostname`
cat >>/etc/hosts <<EOF
$VMIPADDR $VMNAME
EOF

#!/bin/bash
echo "install hana start" >> /tmp/parameter.txt
cd /hana/data/sapbits/HANAMedia/DATA_UNITS/HDB_LCM_LINUX_X86_64
/hana/data/sapbits/HANAMedia/DATA_UNITS/HDB_LCM_LINUX_X86_64/hdblcm -b --configfile /hana/data/sapbits/hdbinst-local.cfg
echo "install hana end" >> /tmp/parameter.txt
