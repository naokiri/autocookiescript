#!/bin/sh

set -o nounset
set -o errexit

#set -x
#set -T


#
# Requirements (AFAIK)
# x11-apps for xwd
# x11-utils for xwininfo
# xdotool for xdotool
# imagemagick for convert
#

VERBOSE=0
REALLY_RUN=0
DEBUG_RUN=0

#RGB raw ppm style
#Use grabc command to find the color in your env
CHOCOCHIP_COLOR="90 52 42" 

vout() {
    if [ $VERBOSE -eq 1 ]; then
        >&2 echo $1
    fi
}

show_help() {
    cat << EOF
Plays cookie clicker for you.

Options:
-h, -? : Show help and exit
-s : Really run. By default, it shows help and doesn't run to make sure you really want to run this script.
-v : Verbose output
-d : Debug run. temp files won't be cleaned up.

Usage:
Open your browser. 
Open the cookie clicker visible on the left side of the screen.
Open a terminal visible on the right side of the screen.
Run $0 -s and follow the instruction and leave the PC.
Move the mouse cursor and wait a while to stop.
EOF
}


# $1: Browser window id
# returns: browser window relative point in "x y" format when success
# "FAIL" in failure
search_choco() {
    browser_x_ida=$1
    vout "$browser_x_ida"    
    if [ $DEBUG_RUN -eq 0 ];then
        outfile=$(mktemp "xwd.XXXXXX.xwd")
        tmpppmfile=$(mktemp "ppm.XXXXXX.ppm")
        tmpppmbits=$(mktemp "ppm.bits.XXXXXX")
    else
        outfile=tmp.xwd
        tmpppmfile=tmp.ppm
        tmpppmbits=tmp.ppm.bits
    fi
    xdotool windowactivate --sync "$browser_x_ida"
    xwd -id "$browser_x_ida" > $outfile
    convert $outfile -compress none $tmpppmfile       
    browser_size=$(cat $tmpppmfile | sed -n 3p)
    browser_width=$(echo "$browser_size" | cut -d' ' -f1)
    browser_height=$(echo "$browser_size" | sed -n 3p | cut -d' ' -f2)        
    cat $tmpppmfile | 
        tail -n +5 | # Remove ppm header
        tr -d '\n' | 
        sed 's/ /\n/g' | # 1 line per 1 color
        sed 4~3i--- | tr '\n' ' ' | sed 's/--- /\n/g' > $tmpppmbits # 1 line per 1 dot
    choco_search=$(grep -n "$CHOCOCHIP_COLOR" $tmpppmbits | head -n 1)
    if [ $DEBUG_RUN -eq 0 ]; then
        rm -f $outfile $tmpppmfile $tmpppmbits        
    fi
    if [ -z "$choco_search" ]; then
        >&2 echo "No chocochip found"
        return 1
    fi
    choco_point=$(echo "$choco_search" | cut -d':' -f1)
    choco_x=$(expr $choco_point % $browser_width)
    choco_y=$(expr $choco_point / $browser_width)
    echo "$choco_x $choco_y"
    return 0
}

main() {
    if [ "$REALLY_RUN" -ne 1 ];then
        show_help
        return
    fi

    echo "Click the browser opening the Cookie clicker on active window."
    vout "Running xwininfo to get the browser window id"
    browser_x_id=$(xwininfo | grep '^xwininfo: Window id:' | awk '{print $4}')
    vout "browser window id: $browser_x_id"
   
    choco_point=$(search_choco "$browser_x_id")
    if [ "FAIL" = "$choco_point" ]; then
        echo "No chocochip found"
        return 1
    fi
    choco_x=$(echo $choco_point | cut -d' ' -f1)
    choco_y=$(echo $choco_point | cut -d' ' -f2) 
    vout "found choco at $choco_x,$choco_y"

    xdotool mousemove --window "$browser_x_id" $choco_x $choco_y
    eval $(xdotool getmouselocation --shell)
    orig_x=$X
    orig_y=$Y
    orig_screen=$SCREEN
    orig_window=$WINDOW

    continue=1
    while [ $continue -gt 0 ] ; do        
        xdotool mousemove --window "$browser_x_id" $choco_x $choco_y \
                click --repeat 10 1
        eval $(xdotool getmouselocation --shell)
        if [ $orig_x -ne $X -o \
                     $orig_y -ne $Y -o \
                     $orig_screen -ne $SCREEN -o \
                     $orig_window -ne $WINDOW ]; then
            vout "Mouse move detected. Stop loop."
            continue=0
        fi             
    done
}

if [ $# -eq 0 ];then
    show_help
    exit 0
fi

while getopts "dhsv" opts
do
    case $opts in
        d)
            DEBUG_RUN=1
            ;;
        s)
            REALLY_RUN=1
            echo "Run!"
            ;;
        h)
            show_help
            exit 0
            ;;
        v)
            VERBOSE=1
            ;;
        \?)
            show_help
            exit 0
            ;;            
    esac
done
shift $((OPTIND - 1))

main
