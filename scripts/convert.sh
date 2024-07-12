#!/bin/bash

# Ubuntu way
#apt install xvfb
#apt install blender python3-pip
#apt install python3-lxml python3-shapely python3-matplotlib (for CityGML converter)
#OR
# Debian way
#wget https://download.blender.org/release/Blender2.92/blender-2.92.0-linux64.tar.xz
#tar -xvf blender-2.92.0-linux64.tar.xz
#change .env BLENDER_PATH or make symlink to it `ln -s PATH_TO_YOUR_UNCOMPRESSED_BLENDER/blender-2.92.0-linux64/blender /usr/local/bin/blender`
#pip install numpy or apt install python3-numpy
#pip install triangle
#usage: ./convert.sh -c COMPRESS -cl COMPRESSION_LEVEL -i 'INPUT' -o 'OUTPUT' -b BINARY -f FORCE_OVERRIDE

set -e

source $(dirname $0)/.env

#BLENDER_PATH='/var/lib/snapd/snap/blender/current/'

#Defaults:
COMPRESSION=false
COMPRESSION_LEVEL=3
GLTF="gltf"
FORCE="false"
isOutput=false
IS_ARCHIVE=false

check_blender () {
	if ! command -v blender &> /dev/null; then
		echo "Blender doesn't exist, install it by 'apt install blender python3-pip' then 'pip install numpy' or change BLENDER_PATH with your Blender instance"
		return 1
	else
		echo "Blender exists and be used for next steps..."
		return 0
	fi
}

check_xvfb_run () {
	if ! command -v xvfb-run &> /dev/null; then
		echo "xvfb-run doesn't exist, install it by 'apt install xvfb'"
		return 1
	else
		echo "xvfb-run exists and be used for next steps..."
		return 0
	fi
}

check_scripts () {
	if [ ! -d ${SPATH}/scripts ]; then
		echo "Can't find dependencies directory. Did you change your SPATH value in scripts/.env?"
		return 1
	else
		return 0
	fi
}

check_blender
check_xvfb_run
check_scripts

show_usage () {
	echo "Usage: ./convert.sh -c true/false -cl [0-6] -i 'INPUT' -o 'OUTPUT' -b true/false -f true/false"
	echo "-c=compress -cl=compression level -i=input path -o=output path -b=binary -f=force override existing file"
}

while getopts ":c:l:o:i:b:f:" flag; do
    case "${flag}" in
        c) COMPRESSION=${OPTARG};;
        l) COMPRESSION_LEVEL=${OPTARG};;
        i) INPUT="${OPTARG}";;
        o) OUTPUT="${OPTARG}";;
        f) FORCE="${OPTARG}";;
        a) IS_ARCHIVE="${OPTARG}";;
        b) if [[ "${OPTARG}" = "true" ]]; then GLTF="glb"; else GLTF="gltf"; fi;;
    esac
done

render_preview () {
	SNAME=$NAME
	if [[ ! -d "$INPATH/views" ]]; then
		mkdir "$INPATH/views/"
	fi

	echo "Rendering thumbnails..."

	if [[ "$EXT" != "glb" ]]; then
		SNAME="gltf/${NAME}"
	fi;

	xvfb-run --auto-servernum --server-args="-screen 0 512x512x16" sudo ${BLENDER_PATH}blender -b -P ${SPATH}/scripts/render.py -- "$INPATH/$SNAME.glb" "glb" $1 "$INPATH/views/" $IS_ARCHIVE -E BLENDER_EEVEE -f 1  > /dev/null 2>&1
}

handle_file () {
	INPATH=$1
	FILENAME=$2
	NAME=$3
	EXT=$4
	OUTPUT=$5
	OUTPUTPATH=$6

	if [[ "$isOutput" = false ]]; then
		${BLENDER_PATH}blender -b -P ${SPATH}/scripts/2gltf2/2gltf2.py -- "$INPATH/$FILENAME" "$GLTF" "$COMPRESSION" "$COMPRESSION_LEVEL" > /dev/null 2>&1
	else
		${BLENDER_PATH}blender -b -P ${SPATH}/scripts/2gltf2/2gltf2.py -- "$INPATH/$FILENAME" "$GLTF" "$COMPRESSION" "$COMPRESSION_LEVEL" "$OUTPUT$OUTPUTPATH" > /dev/null 2>&1
	fi
	
	if [[ -f "$INPATH/gltf/$NAME.glb" ]]; then
		render_preview $EXT
	else
		render_preview "$INPATH/$NAME.$EXT"
	fi;
}

handle_unsupported_file () {
	INPATH=$1
	FILENAME=$2
	NAME=$3
	EXT=$4
	OUTPUT=$5
	OUTPUTPATH=$6

	touch "${INPATH}/gltf/${NAME}.glb.off"
}

handle_ifc_file () {
	INPATH=$1
	FILENAME=$2
	NAME=$3
	EXT=$4
	OUTPUT=$5
	OUTPUTPATH=$6

	if [[ ! -d "$INPATH"/gltf/ ]]; then
		mkdir "$INPATH"/gltf/
	fi

	${SPATH}/scripts/IfcConvert "$INPATH/$FILENAME" "$INPATH/gltf/$NAME.glb" > /dev/null 2>&1
	render_preview $EXT
}

handle_blend_file () {
	INPATH=$1
	FILENAME=$2
	NAME=$3
	EXT=$4

	if [[ ! -d "$INPATH"/gltf/ ]]; then
		mkdir "$INPATH"/gltf/
	fi

	${BLENDER_PATH}blender -b -P ${SPATH}/scripts/convert-blender-to-gltf.py "$INPATH/$FILENAME" "$INPATH/gltf/$NAME.glb" > /dev/null 2>&1
	render_preview $EXT
}

handle_gml_file () {
	INPATH=$1
	FILENAME=$2
	NAME=$3
	EXT=$4
	OUTPUT=$5
	OUTPUTPATH=$6
	
	GLB_PATH="${INPATH}/${NAME}_GLB"
	
	#if [[ ! -d $GLB_PATH ]]; then
		mkdir -p $GLB_PATH
		cp -rf $INPATH/$FILENAME $GLB_PATH/
		#python3 ${SPATH}/scripts/CityGML2OBJv2/CityGML2OBJs.py -i "$GLB_PATH" -o "$GLB_PATH" #> /dev/null 2>&1
		if [[ ! -d "$INPATH"/gltf/ ]]; then
			mkdir "$INPATH"/gltf/
		fi
		${BLENDER_PATH}blender -b -P ${SPATH}/scripts/2gltf2/2gltf2.py -- "$GLB_PATH/${NAME}.obj" "$GLTF" "$COMPRESSION" "$COMPRESSION_LEVEL" "$INPATH/gltf/$NAME.glb" > /dev/null 2>&1
		render_preview $EXT
		#rm -rf $GLB_PATH
	#fi


}

if [[ ! -z "$INPUT" && -f $INPUT ]]; then
	FILENAME=${INPUT##*/}
	NAME="${FILENAME%.*}"
	EXT=${FILENAME//*.}
	INPATH=${INPUT%/*}

	if [[ $FILENAME = $INPATH ]]; then
		INPATH="."
	fi
	if [[ -z "$OUTPUT" ]]; then
		OUTPUT=`echo $INPATH/\gltf`
	else
		echo $OUTPUT
		OUTFILENAME=${OUTPUT%/*}     # trim everything past the last /
		OUTFILENAME=${OUTFILENAME##*/}
		OUTFILENAME=${OUTFILENAME/"_ZIP"/""}
		OUTFILENAME=${OUTFILENAME/"_RAR"/""}
		OUTFILENAME=${OUTFILENAME/"_TAR"/""}
		OUTFILENAME=${OUTFILENAME/"_XZ"/""}
		OUTFILENAME=${OUTFILENAME/"_GZ"/""}
		OUTPUTPATH=`echo $OUTFILENAME.$GLTF`
		OUTPUT=`echo ${OUTPUT}gltf/`
		isOutput=true
	fi
	if [[ "$EXT" != "$filename" ]]; then
		EXT="${EXT,,}"
		if [[ ! -d "$OUTPUT" ]]; then
			mkdir "$OUTPUT"
		fi
		if [[ ! -f $OUTPUT/$NAME.$GLTF || $FORCE ]]; then
			start=`date +%s`
			case $EXT in
				abc|dae|fbx|obj|ply|stl|wrl|x3d)
					echo "Converting $EXT file..."
					handle_file "$INPATH" "$FILENAME" "$NAME" $EXT "$OUTPUT" "$OUTPUTPATH"
					end=`date +%s`
					echo "File $FILENAME compressed successfully. Runtime: $((end-start))s."
					exit 0;
				;;
			  ifc)
					echo "Converting $EXT file..."
					handle_ifc_file "$INPATH" "$FILENAME" "$NAME" $EXT "$OUTPUT" "$OUTPUTPATH"
					end=`date +%s`
					echo "File $FILENAME compressed successfully. Runtime: $((end-start))s."
					exit 0;
				;;
			  blend)
					echo "Converting $EXT file..."
					handle_blend_file "$INPATH" "$FILENAME" "$NAME" $EXT
					end=`date +%s`
					echo "File $FILENAME compressed successfully. Runtime: $((end-start))s."
					exit 0;
				;;
			  gml)
					echo "Converting $EXT file..."
					handle_gml_file "$INPATH" "$FILENAME" "$NAME" $EXT "$OUTPUT" "$OUTPUTPATH"
					end=`date +%s`
					echo "File $FILENAME compressed successfully. Runtime: $((end-start))s."
					exit 0;
				;;
			  glb)
					render_preview $EXT
					end=`date +%s`
					echo "Given file was already compressed."
					exit 0;
				;;

			  *)
					handle_unsupported_file "$INPATH" "$FILENAME" "$NAME" $EXT "$OUTPUT" "$OUTPUTPATH"
					#echo "Flie extension $EXT is not supported for conversion yet."
					exit 0;
				;;
			esac
		else
			echo "Compressed file $OUTPUT/$NAME.$GLTF already exists."
			exit 1;
		fi
	else
		echo "No extension found on $FILENAME";
		exit 2;
	fi
elif [[ -z "$INPUT" ]]; then
	echo "No input file provided"
	show_usage
else
	echo "Given file '$INPUT' not found"
	show_usage
fi
