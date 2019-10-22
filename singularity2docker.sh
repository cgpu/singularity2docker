#! /bin/bash
#
# singularity2docker.sh will convert a singularity image back into a docker
# image.
#
# USAGE: singularity2docker.sh ubuntu.sif
#
# Copyright (C) 2018-2020 Vanessa Sochat.
#
# This program is free software: you can redistribute it and/or modify it
# under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or (at your
# option) any later version.
#
# This program is distributed in the hope that it will be useful, but WITHOUT
# ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
# FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Affero General Public
# License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <https://www.gnu.org/licenses/>.

set -o errexit
set -o nounset

usage="USAGE: singularity2docker -n container:new container.simg"

# --- Option processing --------------------------------------------
if [ $# == 0 ] ; then
    echo $usage
    echo "OPTIONS:

          -n|--name: docker container name (container:new)
          -v|--verbose: show output from sandbox build

          "
    exit 1;
fi

container="container:new"

while true; do
    case ${1:-} in
        -h|--help|help)
            echo ${usage};
            exit 1;
        ;;
        --name|-n|n)
            shift
            container="${1:-}";
            shift
        ;;
        -*)
            echo "Beep boop, unknown option: ${1:-}"
            exit 1
        ;;
        *)
            break;
        ;;
    esac
done

image=$1

echo ""
echo "Input Image: ${image}"



################################################################################
### Sanity Checks ##############################################################
################################################################################

echo
echo "1. Checking for software dependencies, Singularity and Docker..."

# The image must exist

if [ ! -e "${image}" ]; then
    echo "Cannot find ${image}, did you give the correct path?"
    exit 1
fi


# Singularity must be installed

if hash singularity 2>/dev/null; then
   echo "Found Singularity $(singularity --version)"
else
   echo "Singularity must be installed to use singularity2docker.sh"
   exit 1
fi

# Docker must be installed

if hash docker 2>/dev/null; then
   echo "Found Docker $(docker --version)"
else
   echo "Docker must be installed to use singularity2docker.sh"
   exit 1
fi


################################################################################
### Image Format ###############################################################
################################################################################

# Get the image format
# This is here in case we want to remove Singularity dependency and just work
# with mksquashfs/unsquashfs. Most users that want to convert from Singularity
# will likely have it installed.
# We shouldn't need this as long as older formats are supported to build from
# If we can just use unsquashfs after this we probably don't need Singularity 
# dependency

#libexec=$(dirname $(singularity selftest 2>&1 | grep 'lib' | awk '{print $4}' | sed -e 's@\(.*/singularity\).*@\1@'))
#image_type="$(echo $libexec | awk '{print $1}')/singularity/bin/image-type"
#image_format=$(SINGULARITY_MESSAGELEVEL=0 ${image_type} ${image})
#echo "Found image format ${image_format}"


################################################################################
### Image Sandbox Export #######################################################
################################################################################

echo
echo "2.  Preparing sandbox for export..."
sandbox=$(mktemp -d -t singularity2docker.XXXXXX)
singularity build --sandbox ${sandbox} ${image}

################################################################################
### Environment/Metadata #######################################################
################################################################################

echo
echo "3.  Exporting metadata..."

# Create temporary Dockerfile

echo 'FROM scratch
ADD . /' > ${sandbox}/Dockerfile

# Environment

echo "ENV LD_LIBRARY_PATH /.singularity.d/libs" >> $sandbox/Dockerfile
echo "ENV PATH /usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" >> $sandbox/Dockerfile


# Labels

# Note: Singularity has not been consistent with output of metadata
# If you have issues here, you might need to tweak the jq parsing below
entries=$(singularity inspect -l --json ${image} | jq '.attributes .labels')
keys=$(echo $entries | jq 'keys[]')

for key in ${keys}; do

 echo "$opt" | tr -d '"'

    value=$(singularity inspect -l --json ${image} | jq -r ${term})
    echo "Adding LABEL ${key} ${value}"
    echo "LABEL ${key} \"${value}\"" >> $sandbox/Dockerfile
done

# Command will be to source the environment and run the runscript!

echo "Adding command..."
echo '#!/bin/sh
. /environment
exec /.singularity.d/runscript' > ${sandbox}/run_singularity2docker.sh
echo "CMD [\"/bin/bash\", \"run_singularity2docker.sh\"]" >> $sandbox/Dockerfile

################################################################################
### Build ######################################################################
################################################################################

echo
echo "4.  Build away, Merrill!"

docker build -t ${container} ${sandbox} > /dev/null 2>&1
echo "Created container ${container}"
echo "docker inspect ${container}"
rm -rf ${sandbox}
