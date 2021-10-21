#!/bin/bash

rm -rf hack/

mkdir -p "hack/packages"
mkdir -p "hack/logs"
mkdir -p "hack/docs"

process() {
  echo "# Processing $1 version $2"

  echo ' - download + extract'
  mkdir -p "hack/packages/$1-$2/";
  curl -sL "https://storage.googleapis.com/pub-packages/packages/$1-$2.tar.gz" | tar -xz -C "hack/packages/$1-$2/"

  echo ' - generating documentation'
  time -p dart run pub_dartdoc --input "hack/packages/$1-$2" --output "hack/docs/$1-$2" --no-validate-links 2>&1 | tee > "hack/logs/$1-$2.txt"
}

process retry        3.1.0
process googleapis   5.0.0
process googleapis   6.0.0
process google_fonts 2.1.0
process win32        2.2.10

for f in `ls hack/docs/`; do
  echo "## $f";
  echo 'number of files:';
  find "hack/docs/$f" -type f | wc -l;
  echo "raw JSON size:";
  cat "hack/docs/$f/doc-index.json" | wc -c;
  echo 'gzipped JSON size:';
  cat "hack/docs/$f/doc-index.json" | gzip -c -9 | wc -c ;
  echo '';
done
