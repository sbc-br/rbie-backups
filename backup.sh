#!/bin/bash

start(){

    local SCRIPT=$(readlink -f "$0")
    local SCRIPTPATH=$(dirname "$SCRIPT")
    local backupsLogFile=$SCRIPTPATH/executions.log

    local startTime=$(date +"%s")

    date -d "@$startTime" +"%d-%m-%Y %H:%M:%S - Backup started" >> $backupsLogFile

    executeBackup
    #sleep $(shuf -i 5-10 -n 1)

    local endTime=$(date +"%s")
    local elapsedTime=$((endTime - startTime))

    echo $(date +"%d-%m-%Y %H:%M:%S - ") $(date -u -d "@$elapsedTime" +"Backup completed in %Hh %Mmin %Ssec") >> $backupsLogFile
    echo "" >> $backupsLogFile
}

executeBackup(){

    local dataDir=$SCRIPTPATH/data
    local configDir=$SCRIPTPATH/config
    local remoteDir=/home/ceieb059

    #local lastIndex=""
    local lastIndex=$(echo $(find $dataDir -maxdepth 1 ! -name data -printf "%f\n" | sort | tail -n 1) | sed 's/^0*//')
    local lastBackupDir="$dataDir/$(printf '%06d' $lastIndex)"
    local lastFilesDir=$lastBackupDir/files
    local lastDatabasesDir=$lastBackupDir/databases
    local lastChecksumsFile=$lastDatabasesDir/checksums.dat


    local currentIndex=$(($lastIndex + 1))
    local currentBackupDir="$dataDir/$(printf '%06d' $currentIndex)"
    local currentFilesDir=$currentBackupDir/files
    local currentDatabasesDir=$currentBackupDir/databases
    local currentChecksumsFile=$currentDatabasesDir/checksums.dat

    local tempDatabasesDir=$currentBackupDir/db_temp

    backupDatabases
    backupFiles
}

backupFiles(){

    echo "Starting backup of files"

    saveFilesPermissions
    copyFiles
}

copyFiles(){

    echo "Copying files from server to $currentFilesDir"

    if firstBackup; then
        rsync --delete --info=progress2 --no-inc-recursive -azhe ssh rbie:$remoteDir/ $currentFilesDir 2>/dev/null 
    else
        rsync --delete --info=progress2 --no-inc-recursive --link-dest=$lastFilesDir/  -azhe ssh rbie:$remoteDir/ $currentFilesDir 2>/dev/null 
    fi

    echo "Files copied successfully from server"
}

saveFilesPermissions(){

    local permissionsFile=$currentBackupDir/permissions.acl

    echo "Saving files permissions to: $permissionsFile"

    local lineCount=$(($(ssh rbie find $remoteDir 2>/dev/null | wc -l) * 7))

    ssh rbie getfacl --recursive $remoteDir 2>/dev/null  | pv --eta --rate --bytes --buffer-size 10m --name "Saving permissions" --size 778295 -l > $permissionsFile

    echo "Files permissions saved successfully"
}

backupDatabases(){

    mkdir -p $tempDatabasesDir
    mkdir -p $currentDatabasesDir

    local dbConfigFile

    for dbConfigFile in $configDir/*.cnf; do

        local dbName=$(db "SELECT database()")
        local dbSize=$(db "SELECT ROUND(SUM(data_length) * 0.80) AS db_size FROM information_schema.TABLES WHERE table_schema = '$dbName'")
        local dbSqlFile="$tempDatabasesDir/$dbName.sql"
        local dbZipFile="$tempDatabasesDir/$dbName.zip"

        echo "Found database '$dbName'"
        echo "Estimated size: $(toHumanSize $dbSize)"

        backupSingleDatabase

        echo ""
    done

    rm -Rf $tempDatabasesDir
}

backupSingleDatabase(){

    dumpDatabase
    syncDatabase
}

syncDatabase(){

    echo "Synchronizing database..."

    if firstBackup; then
        mv $dbZipFile "$currentDatabasesDir/$dbName.zip"
    else
        if [ $databasesAreEqual -eq 1 ]; then
            echo "Database '$dbName' has not changed since last backup"
            echo "Hardlinking database..."

            ln "$lastDatabasesDir/$dbName.zip" "$currentDatabasesDir/$dbName.zip"
        else
            echo "Database '$dbName' has changed since last backup"
            echo "Copying database..."

            mv $dbZipFile "$currentDatabasesDir/$dbName.zip"
        fi
    fi

    echo "Database synchronized successfully to file $currentDatabasesDir/$dbName.zip"
}

dumpDatabase(){

    echo "Dumping database..."

    mysqldump --defaults-extra-file=$dbConfigFile $dbName | pv --eta --rate --bytes --buffer-size 10m --name "Dump progress" --size $dbSize > $dbSqlFile

    # Super fast strip last line of file to remove comments with timestamp
    dd if=/dev/null of=$dbSqlFile bs=1 seek=$(echo $(stat --format=%s $dbSqlFile ) - $( tail -n1 $dbSqlFile | wc -c) | bc ) &> /dev/null

    md5=$(md5sum $dbSqlFile)
    md5=${md5/"$tempDatabasesDir/"/}
    md5="$md5 # Inside $dbName.zip"
    md5=${md5/  / }

    lastMd5=$(cat $lastChecksumsFile | grep $dbName.zip)

    echo $md5 >> $currentChecksumsFile

    echo "Database dumped successfuly to file: $dbSqlFile"

    if [ "$md5" == "$lastMd5" ]; then
        databasesAreEqual=1
    else
        databasesAreEqual=0
        compressDatabase
    fi
}

compressDatabase(){

    echo "Compressing database dump..."

    zip -9 -j --quiet - $dbSqlFile | (pv --eta --rate --bytes --buffer-size 10m --name "Compression progress" --size $(stat --printf="%s" $dbSqlFile) > $dbZipFile)

    echo "Database dump compressed successfully to file: $dbZipFile"
}

db(){
    echo $(mysql --defaults-extra-file=$dbConfigFile --skip-column-names <<< $1)
}

toHumanSize(){
    echo $(echo $1 | awk '
    function human(x) {
        if (x<1000) {return x} else {x/=1024}
        s="kMGTEPZY";
        while (x>=1000 && length(s)>1)
            {x/=1024; s=substr(s,2)}
        return int(x+0.5) substr(s,1,1)
    }
    {sub(/^[0-9]+/, human($1)); print}')
}

firstBackup(){
    [ ! -d "$lastBackupDir" ]
}

start
