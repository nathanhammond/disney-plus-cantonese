apiVersion="5.1"
kidsModeEnabled="false"
impliedMaturityRating="1850"
appLanguage="en"
contentClass="contentType"

# REGIONS="AD AG AR AT AU BB BE BL BO BR BS BZ CA CH CL CO CR DA DE DK DM DO EC ES FI FR GB GD GF GG GL GP GT GY HK HN HT IE IM IS IT JA JE JM KN KO LC LI LU MC MF MQ MU MX NC NI NL NO NZ PA PE PL PT PY RE SE SG SR SV TT TW US UY VC VE WF YT"
# CURL_REGIONS="AD,AG,AR,AT,AU,BB,BE,BL,BO,BR,BS,BZ,CA,CH,CL,CO,CR,DA,DE,DK,DM,DO,EC,ES,FI,FR,GB,GD,GF,GG,GL,GP,GT,GY,HK,HN,HT,IE,IM,IS,IT,JA,JE,JM,KN,KO,LC,LI,LU,MC,MF,MQ,MU,MX,NC,NI,NL,NO,NZ,PA,PE,PL,PT,PY,RE,SE,SG,SR,SV,TT,TW,US,UY,VC,VE,WF,YT"

REGIONS="AU CA DK FR GB HK JP NZ SE SG TW US"
CURL_REGIONS="AU,CA,DK,FR,GB,HK,JP,NZ,SE,SG,TW,US"
SLUGS="movies series"
CURL_SLUGS="movies,series"

for REGION in $REGIONS
do
  rm -rf $REGION
  mkdir -p $REGION
done

/usr/local/opt/curl/bin/curl --parallel --connect-timeout 5 --max-time 10 --retry 5 "https://disney.content.edge.bamgrid.com/svc/content/Collection/StandardCollection/version/$apiVersion/region/{$CURL_REGIONS}/audience/$kidsModeEnabled/maturity/$impliedMaturityRating/language/$appLanguage/contentClass/$contentClass/slug/{$CURL_SLUGS}" -o "#1/#2-Collection.json"

jq -r '{ key: input_filename[0:2], value: [.data .Collection .containers[] .set .refId] }' */movies-Collection.json | jq -s '. | from_entries' > region_curatedsets-movies.json
jq -r '{ key: input_filename[0:2], value: [.data .Collection .containers[] .set .refId] }' */series-Collection.json | jq -s '. | from_entries' > region_curatedsets-series.json

for REGION in $REGIONS
do
  CURATED_SETS=`jq -r ".$REGION | join(\",\")" region_curatedsets-movies.json`
  /usr/local/opt/curl/bin/curl --parallel --connect-timeout 5 --max-time 10 --retry 5 "https://disney.content.edge.bamgrid.com/svc/content/CuratedSet/version/$apiVersion/region/$REGION/audience/$kidsModeEnabled/maturity/$impliedMaturityRating/language/$appLanguage/setId/{$CURATED_SETS}/pageSize/30/page/1" -o "$REGION/#1-CuratedSet-p1.json"
done

for SET_FILENAME in `ls */*CuratedSet-p1.json`
do
  PAGES=`cat $SET_FILENAME | jq '.data .CuratedSet .meta .hits / 30 | ceil'`
  if [["$PAGES" == '1']]; then
    continue
  fi
  REGION=${SET_FILENAME:0:2}
  CURATED_SET_ID=${SET_FILENAME:3:36}
  /usr/local/opt/curl/bin/curl --parallel --connect-timeout 5 --max-time 10 --retry 5 "https://disney.content.edge.bamgrid.com/svc/content/CuratedSet/version/5.1/region/$REGION/audience/false/maturity/1850/language/en/setId/$CURATED_SET_ID/pageSize/30/page/[2-$PAGES]" -o "$REGION/$CURATED_SET_ID-CuratedSet-p#1.json"
done

for REGION in $REGIONS
do
  MOVIES=`jq -r --slurp '[[.[] .data .CuratedSet .items[] .family .encodedFamilyId] | unique | .[] | strings] | join(",")' $REGION/*CuratedSet*.json`
  /usr/local/opt/curl/bin/curl --parallel --connect-timeout 5 --max-time 10 --retry 5 "https://disney.content.edge.bamgrid.com/svc/content/DmcVideoBundle/version/$apiVersion/region/$REGION/audience/$kidsModeEnabled/maturity/$impliedMaturityRating/language/$appLanguage/encodedFamilyId/{$MOVIES}" -o "$REGION/movie-#1.json"

  jq -r --slurp '.[] .data .DmcVideoBundle .video .text .title .full .program .default .content' $REGION/movie-*.json > "$REGION/titles.txt" # TITLES
  jq -r --slurp '.[] | ["https://www.disneyplus.com/movies", getpath(path(.data .DmcVideoBundle .video .text .title .slug .program .default .content)), getpath(path(.data .DmcVideoBundle .video .family .encodedFamilyId))] | join("/")' $REGION/movie-*.json > "$REGION/urls.txt" # URLS
  jq -r --slurp '.[] .data .DmcVideoBundle .video .mediaMetadata .audioTracks | map(select(.language == "yue") // false) | any' $REGION/movie-*.json > "$REGION/audio.txt" # CANTONESE AUDIO

  echo -e 'Title\tURL\tCantonese Audio' > $REGION.tsv
  paste -d '\t' "$REGION/titles.txt" "$REGION/urls.txt" "$REGION/audio.txt" | sort -f >> $REGION.tsv
  sed -i '' 's/\"/""/g' $REGION.tsv
  sed -E -i '' 's/^([^	]+)	/"\1"	/' $REGION.tsv
  sed -i '' 's/^\"Title\"	/Title	/' $REGION.tsv
done
