#!/bin/bash

main(){
    parseArguments "$@"
    executeBackup

    log "Backup completed in: "
    log $duration
}

executeBackup(){

    local SCRIPT=$(readlink -f "$0")
    local SCRIPTPATH=$(dirname "$SCRIPT")

    local backupDir=$SCRIPTPATH/data/$outputDir
    local dbDir=$backupDir/databases
    local filesDir=$backupDir/files
    local configDir=$SCRIPTPATH/config

    rm -Rf $backupDir
    mkdir -p $dbDir
    mkdir -p $filesDir

    backupDatabases

}

backupDatabases(){

    local dbConfigFile

    for dbConfigFile in $configDir/*.cnf
    do

        local dbName=$(db "SELECT database()")
        local dbSize=$(db "SELECT ROUND(SUM(data_length) * 0.80) AS db_size FROM information_schema.TABLES WHERE table_schema = '$dbName'")
        local dbSqlFile="$dbDir/$dbName.sql"
        local dbZipFile="$dbDir/$dbName.zip"

        log "Found database '$dbName'"
        log "Estimated size: $(toHumanSize $dbSize)"

        backupSingleDatabase

        log ""

    done
}

backupSingleDatabase(){
    dumpDatabase
    compressDatabase
}

dumpDatabase(){

    log "Dumping database..."

    if [ $verbose -gt 0 ]; then
        mysqldump --defaults-extra-file=$dbConfigFile $dbName | pv --eta --rate --bytes --buffer-size 10m --name "Dump progress" --size $dbSize > $dbSqlFile
    else
        mysqldump --defaults-extra-file=$dbConfigFile $dbName > $dbSqlFile
    fi

    log "Database dumped successfuly to file: $dbSqlFile"
}

compressDatabase(){

    log "Compressing database dump..."

    if [ $verbose -gt 0 ]; then
        zip -9 -j --quiet - $dbSqlFile | (pv --eta --rate --bytes --buffer-size 10m --name "Compression progress" --size $(stat --printf="%s" $dbSqlFile) > $dbZipFile)
    else
        zip -9 -j --quiet - $dbSqlFile > $dbZipFile
    fi

    log "Database dump compressed successfully to file: $dbZipFile"
    log "Removing uncompressed database dump: $dbSqlFile"

    rm $dbSqlFile

    log "Database dump removed succsessfully"
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

log(){
    if [ $verbose -eq 1 ]; then
        if [ $# -gt 0 ]; then
            echo $@
        else
            echo ""
        fi
    fi
}

parseArguments(){

    verbose=0

    while [ "$#" -gt 0 ]; do
        case "$1" in
                -v|--verbose) verbose=1 ;;
            -o|--out|--output)
                outputDir="$2"; shift ;;
            --) shift; break;;
            #*)  usage ;;
        esac
        shift
    done

    if [ "$outputDir" = "" ]; then
        echo "You need to inform the output directory"
        exit -1
    fi
}

main "$@"
