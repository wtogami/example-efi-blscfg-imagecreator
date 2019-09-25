#!/bin/bash
KSFILE=$1
KSNAME=${KSFILE%.ks}

if [ ! -f ${KSFILE} ]; then
  echo
  echo "SYNOPSIS"
  echo "   $0 <KICKSTARTFILE>"
  echo
  echo "EXAMPLES"
  echo "   $0 hbp-fedora31.ks"
  echo "   $0 hbp-el8.ks"
  echo
  exit 1
fi

set -x
appliance-creator -c ${KSFILE} \
	          -d -v --logfile /tmp/${KSNAME}.log \
		  --cache /root/cache --no-compress \
		  -o /tmp/appoutput --format raw --name ${KSNAME}
