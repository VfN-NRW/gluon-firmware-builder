#!/usr/bin/env bash

set -e

DIR="$(pwd)"

if [ -z "$1" ]; then
	printf 'ERROR: no gluon-release was specified.\n' >&2
	exit 1
fi

if [ -z "$2" ]; then
	printf 'you have to select stable, nightly, alpha, beta or rc\n' >&2
	exit 1
fi

if [ "$2" == "stable" ]; then
	updatepath='$2'
elif [ "$2" == "nightly" ] || [ "$2" == "alpha" ] || [ "$2" == "beta" ] || [ "$2" == "rc" ]; then
	updatepath='unstable/$2'
else
	echo "Second command-line parameter has to be stable, nightly, alpha, beta or rc"
	exit 1
fi

. ./gluon

sel_gluon_release="$1"
selected_found=0

for GluonRelease in $GLUON_RELEASES; do
	if ! [ "$GluonRelease" == "$sel_gluon_release" ]; then
		continue
	else
		selected_found=1
		break
	fi
done

if [ "$selected_found" -ne "1" ]; then
	printf 'ERROR: "$sel_gluon_release" could not be found in ./gluon file.\n' >&2
	exit 1
fi

./get-gluon $GluonRelease

if [ ! -d "$GluonRelease" ]; then
	printf 'ERROR: Gluon-Folder could not be located.\n' >&2
	exit 1
fi

./copy-patches $GluonRelease
./apply-patchsets $GluonRelease

cd $DIR

echo "generating default site..."
./gen-site $sel_gluon_release vfnnrw/leverkusen 2>&1 >/dev/null

echo "fetching profiles..."
profiles="$(ls -1 site-modules/vfnnrw | grep -vE 'all|LICENSE|README.md|version')"

profiles="remscheid" #only build profile x

branches="ar71xx-generic" # ipq806x ar71xx-nand mpc85xx-generic x86-generic " #x86-kvm_guest

cd ./$GluonRelease

version="$(echo $(cat ./site/site.mk | grep "^DEFAULT_GLUON_RELEASE" | cut -d = -f 2 |  awk '{gsub(/^ +| +$/,"")} {print $0 }'))"

echo "running make update..."
( make update ) 2>&1 >/dev/null

echo "building version $version..."

for profile in $profiles; do
	echo "  creating images for $profile"
	echo "    cleaning images-folder..."
	( rm -fR ./output/images/* || true ) 2>&1 >/dev/null
	echo "      setting site..."
	( cd ..; ./gen-site $sel_gluon_release vfnnrw/$profile ) 2>&1 >/dev/null
		for branch in $branches; do
		echo "        building architecture $branch"
		echo "          building..."

		( make -j35 GLUON_BRANCH=stable GLUON_LANGS="en de" GLUON_TARGET=$branch; exit $? ) 2>&1 >/dev/null
		if [ "$?" -ne 0 ]; then #FIXME: does not work :(
			echo "      ERROR: BUILD FAILED, REBUILDING WITH DEBUGGING ENABLED, Logging to it error.log"
			( make V=s GLUON_BRANCH=stable GLUON_LANGS="en de" GLUON_TARGET=$branch; exit $? ) 2>&1 >error.log
			if [ "$?" -ne 0 ]; then
				echo "      DEBUG BUILD FINISHED STILL UNSUCCESSFUL!"
				exit 1
			else
				echo "      DEBUG BUILD FINISHED SUCCESSFULLY, continuing normal build..."
			fi
		fi
	done

	echo "  generating manifest..."

	( make manifest GLUON_BRANCH=stable; exit $? ) 2>&1 >/dev/null

	echo "  uploading images..."

	( ssh odin.vfn-nrw.de -p4337 "mkdir -p /srv/http/gluon/$profile/$updatepath/$version/$2/" ) 2>&1 >/dev/null && ( scp -rP4337 output/images/* odin.vfn-nrw.de:/srv/http/gluon/$profile/$updatepath/$version/$2/ 2>&1 >/dev/null )
	echo "    images for $profile has been uploaded."
done

cd $DIR
