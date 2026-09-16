#!/bin/bash
# body, outfile
curl -s -G "https://ssd.jpl.nasa.gov/api/horizons.api" \
  --data-urlencode "format=text" \
  --data-urlencode "COMMAND='$1'" \
  --data-urlencode "OBJ_DATA='NO'" \
  --data-urlencode "MAKE_EPHEM='YES'" \
  --data-urlencode "EPHEM_TYPE='OBSERVER'" \
  --data-urlencode "CENTER='500@399'" \
  --data-urlencode "START_TIME='1900-01-01 00:00'" \
  --data-urlencode "STOP_TIME='2100-01-01 00:00'" \
  --data-urlencode "STEP_SIZE='40 d'" \
  --data-urlencode "QUANTITIES='31'" \
  --data-urlencode "APPARENT='AIRLESS'" \
  --data-urlencode "CAL_FORMAT='CAL'" > "$2"
