#!/bin/bash
# body lon lat start stop out   (sea level, to match panchang convention)
curl -s -G "https://ssd.jpl.nasa.gov/api/horizons.api" \
  --data-urlencode "format=text" \
  --data-urlencode "COMMAND='$1'" \
  --data-urlencode "OBJ_DATA='NO'" \
  --data-urlencode "EPHEM_TYPE='OBSERVER'" \
  --data-urlencode "CENTER='coord@399'" \
  --data-urlencode "COORD_TYPE='GEODETIC'" \
  --data-urlencode "SITE_COORD='$2,$3,0'" \
  --data-urlencode "START_TIME='$4'" \
  --data-urlencode "STOP_TIME='$5'" \
  --data-urlencode "STEP_SIZE='1 m'" \
  --data-urlencode "QUANTITIES='4'" \
  --data-urlencode "R_T_S_ONLY='TVH'" \
  --data-urlencode "CAL_FORMAT='CAL'" >> "$6"
