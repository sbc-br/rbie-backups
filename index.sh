#!/bin/sh

fileName=$(cat log-file-name.txt)
log=$(cat $fileName | tr "\n" "|" | sed 's/||/|/g')

echo "Content-Type: text/html"
echo

content=$(cat page.html)

echo $content | sed "s/#LOG#/$log/"
