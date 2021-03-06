#!/bin/sh
#
# Copyright 2014 Johannes Schauer <j.schauer@email.de>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.

set -e

ARCH="amd64"
SUITE="unstable"
MIRROR="http://http.debian.net/debian"
DIRECTORY="`pwd`/debian-$SUITE-$ARCH"
DISTNAME="$SUITE-$ARCH"

APT_FILE_OPTS="--architecture $ARCH"
APT_FILE_OPTS=$APT_FILE_OPTS" --cache $HOME/.chdist/$DISTNAME/var/cache/apt/apt-file"
APT_FILE_OPTS=$APT_FILE_OPTS" --sources-list $HOME/.chdist/$DISTNAME/etc/apt/sources.list"

# delete possibly existing dist
rm -rf ~/.chdist/$DISTNAME;

# the "[arch=amd64]" is a workaround until #774685 is fixed
chdist --arch=$ARCH create $DISTNAME "[arch=amd64]" $MIRROR $SUITE main
chdist --arch=$ARCH apt-get $DISTNAME update

apt-file $APT_FILE_OPTS update

mkdir -p $DIRECTORY

printf "" > $DIRECTORY/interested-file
printf "" > $DIRECTORY/interested-explicit
printf "" > $DIRECTORY/activated-file
printf "" > $DIRECTORY/activated-explicit

# find all binary packages with /triggers$
curl --globoff "http://binarycontrol.debian.net/?q=&path=${SUITE}%2F[^%2F]%2B%2Ftriggers%24&format=pkglist" \
	| xargs chdist apt-get $DISTNAME --print-uris download \
	| sed -ne "s/^'\([^']\+\)'\s\+\([^_]\+\)_.*/\2 \1/p" \
	| sort \
	| while read pkg url; do
	echo "working on $pkg..." >&2
	tmpdir=`mktemp -d`
	curl --retry 2 --location --silent "$url" \
		| dpkg-deb --ctrl-tarfile /dev/stdin \
		| tar -C "$tmpdir" --exclude=./md5sums -x
	if [ ! -f "$tmpdir/triggers" ]; then
		rm -r "$tmpdir"
		continue
	fi
	# find all triggers that are either interest or interest-await
	# and which are file triggers (start with a slash)
	egrep "^\s*interest(-await)?\s+/" "$tmpdir/triggers" | while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/interested-file
	egrep "^\s*interest(-await)?\s+[^/]" "$tmpdir/triggers" | while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/interested-explicit
	egrep "^\s*activate(-await)?\s+/" "$tmpdir/triggers" | while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/activated-file
	egrep "^\s*activate(-await)?\s+[^/]" "$tmpdir/triggers" | while read line; do
		echo "$pkg $line"
	done >> $DIRECTORY/activated-explicit
	rm -r "$tmpdir"
done

printf "" > $DIRECTORY/result-file

# go through those that are interested in a path and check them against the
# files provided by its dependency closure
cat $DIRECTORY/interested-file | while read pkg ttype ipath; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any
	# of the files they ship match one of the interested paths
	dose-ceve -c $pkg -T cudf -t deb \
		$HOME/.chdist/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| apt-file $APT_FILE_OPTS show -F --from-file - \
		| sed -ne "s ^\([^:]\+\):\s\+\(${ipath}\) \1\t\2 p" \
		| while read dep cpath; do
			[ "$pkg" != "$dep" ] || continue
			echo "$pkg $ipath $dep $cpath"
		done >> $DIRECTORY/result-file
done

# go through those that are interested in a path and check them against the
# packages in the dependency closure which activate such a path
cat $DIRECTORY/interested-file | while read pkg ttype ipath; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any
	# of them activate a matching path
	dose-ceve -c $pkg -T cudf -t deb \
		$HOME/.chdist/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| while read dep; do
			[ "$pkg" != "$dep" ] || continue
			# using the space as sed delimeter because ipath has slashes
			# a space should work because neither package names nor paths have them
			sed -ne "s ^$dep\s\+activate\(-await\)\?\s\+\($ipath.*\) \2 p" $DIRECTORY/activated-file | while read cpath; do
				echo "$pkg $ipath $dep $cpath"
			done
		done >> $DIRECTORY/result-file
done

printf "" > $DIRECTORY/result-explicit

# go through those that are interested in an explicit trigger and check them
# against the packages in their dependency closure which activate it
cat $DIRECTORY/interested-explicit | while read pkg ttype iname; do
	echo "working on $pkg..." >&2
	echo "getting dependency closure..." >&2
	# go through all packages in the dependency closure and check if any of
	# them activate the trigger in which this package is interested
	dose-ceve -c $pkg -T cudf -t deb \
		$HOME/.chdist/$DISTNAME/var/lib/apt/lists/*_dists_${SUITE}_main_binary-${ARCH}_Packages \
		| awk '/^package:/ { print $2 }' \
		| while read dep; do
			[ "$pkg" != "$dep" ] || continue
			if egrep "^$dep\s+activate(-await)?\s+$iname\s*$" $DIRECTORY/activated-explicit > /dev/null; then
				echo "$pkg $iname $dep"
			fi
		done >> $DIRECTORY/result-explicit
done

echo "+----------------------------------------------------------+"
echo "|                     result summary                       |"
echo "+----------------------------------------------------------+"
echo ""
echo "number of found file based trigger cycles:"
wc -l < $DIRECTORY/result-file
if [ `wc -l < $DIRECTORY/result-file` -ne 0 ]; then
	echo "Warning: found file based trigger cycles"
	echo "number of packages creating file based trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-file | sort | uniq | wc -l
	echo "unique packages creating file based trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-file | sort | uniq
fi
echo "number of found explicit trigger cycles:"
wc -l < $DIRECTORY/result-explicit
if [ `wc -l < $DIRECTORY/result-explicit` -ne 0 ]; then
	echo "Warning: found explicit trigger cycles"
	echo "number of packages creating explicit trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-explicit | sort | uniq | wc -l
	echo "unique packages creating explicit trigger cycles:"
	awk '{ print $1 }' $DIRECTORY/result-explicit | sort | uniq
fi
if [ `wc -l < $DIRECTORY/result-file` -ne 0 ]; then
	echo ""
	echo ""
	echo "+----------------------------------------------------------+"
	echo "|               file based trigger cycles                  |"
	echo "+----------------------------------------------------------+"
	echo ""
	echo "# Associates binary packages with other binary packages they can form a file"
	echo "# trigger cycle with. The first column is the binary package containing the file"
	echo "# trigger, the second column is the file trigger, the third column is a binary"
	echo "# package providing a path that triggers the binary package in the first column,"
	echo "# the fourth column is the triggering path of provided by the binary package in"
	echo "# the third column."
	echo ""
	cat $DIRECTORY/result-file
fi
if [ `wc -l < $DIRECTORY/result-explicit` -ne 0 ]; then
	echo ""
	echo ""
	echo "+----------------------------------------------------------+"
	echo "|               explicit trigger cycles                    |"
	echo "+----------------------------------------------------------+"
	echo ""
	echo "# Associates binary packages with other binary packages they can form an explicit"
	echo "# trigger cycle with. The first column is the binary package interested in the"
	echo "# explicit trigger, the second column is the name of the explicit trigger, the"
	echo "# third column is the binary package activating the trigger."
	echo ""
	cat $DIRECTORY/result-explicit
fi
