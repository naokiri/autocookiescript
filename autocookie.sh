#!/bin/sh

#
# TODO: List up POSIX unfriendly code in requirements
#

set -o nounset
set -o errexit

#set -x
#set -T


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

# $1: window id
# returns: filename of screenshot
get_screenshot() {
    browser_x_id=$1
    outfile=$(mktemp "tmp/xwd.XXXXXX.xwd")
    xdotool windowactivate --sync "$browser_x_id"
    xwd -id "$browser_x_id" > $outfile
    echo "$outfile"
    return 0
}

# $1: Browser window screenshot file
# returns: browser window relative point in "x y" format when success
# "FAIL" in failure
search_choco() {
    infile=$1
    tmpppmfile=$(mktemp "tmp/ppm.XXXXXX.ppm")
    tmpppmbits=$(mktemp "tmp/ppm.bits.XXXXXX")
    convert $infile -compress none $tmpppmfile       
    browser_size=$(cat $tmpppmfile | sed -n 3p)
    browser_width=$(echo "$browser_size" | cut -d' ' -f1)
    browser_height=$(echo "$browser_size" | sed -n 3p | cut -d' ' -f2)
    cat $tmpppmfile | 
        tail -n +5 | # Remove ppm header
        tr -d '\n' | 
        sed 's/ /\n/g' | # 1 line per 1 color
        sed 4~3i--- | tr '\n' ' ' | sed 's/--- /\n/g' > $tmpppmbits # 1 line per 1 dot
    choco_search=$(grep -n "$CHOCOCHIP_COLOR" $tmpppmbits | head -n 1)
    if [ $DEBUG_RUN -eq 0 ];then
        rm -f $tmpppmfile $tmpppmbits
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

# $1 inital screenshot file
# $2 browser window id
# returns "x y width(=height)" of the detected boundary
# Right square diff means buttons or the big cookie or the golden cookie.
# This function ignores too small or too big square, so it's the golden cookie.
detect_square_boundary_diff() {
    initial_screen=$1
    current_screen=$(get_screenshot $2)    
    vout "$initial_screen $current_screen"
    diff_out=$(mktemp "tmp/diff.XXXXXX.ppm")
    components=$(mktemp "tmp/components.XXXXXX.out")

    if [ $VERBOSE -eq 0 ]; then
        verbose=""
    else
        verbose="-verbose"
    fi
    set +o errexit
    compare $verbose $initial_screen $current_screen -highlight-color red -lowlight-color white $diff_out
    set -o errexit
    if [ $DEBUG_RUN -eq 0 ]; then
        debug_out=":null"
    else
        debug_out=$(mktemp "tmp/diff_component.XXXXXX")
    fi
    convert $diff_out -define connected-components:verbose=true -define connected-components:area-threshold=4900 -connected-components 8 $debug_out | tail -n +2 > $components
    vout "saved $components"
    while IFS= read -r line
    do
        vout "diff component: $line"
        bbox=$(echo "$line" | sed 's/^[ ]*//' | cut -d' ' -f2)        
        boxwidth=$(echo "$bbox" | tr 'x+' ' ' | cut -d' ' -f1)
        boxheight=$(echo "$bbox" | tr 'x+' ' ' | cut -d' ' -f2)
        set +o errexit
        # Detect not too big and square diff 
        is_good_square=$(expr $boxwidth \< 200 \& $boxwidth \> \( $boxheight \- 2 \) \& $boxwidth \< \( $boxheight \+ 2 \))
        set -o errexit
        if [ $is_good_square -eq 1 ]; then
            # Must be golden cookie            
            boxx=$(echo "$bbox" | tr 'x+' ' ' | cut -d' ' -f3)
            boxy=$(echo "$bbox" | tr 'x+' ' ' | cut -d' ' -f4)
            echo "$boxx $boxy $boxwidth"
        fi
    done < $components
    
    if [ $DEBUG_RUN -eq 0 ]; then        
        rm -f $current_screen $diff_out $components
    fi
}

main() {
    if [ "$REALLY_RUN" -ne 1 ];then
        echo "Strange call."
        show_help
        return
    fi

    echo "Click the browser opening the Cookie clicker on active window."
    vout "Running xwininfo to get the browser window id"
    browser_x_id=$(xwininfo | grep '^xwininfo: Window id:' | awk '{print $4}')
    vout "browser window id: $browser_x_id"

    initial_screenshot=$(get_screenshot "$browser_x_id")
    choco_point=$(search_choco "$initial_screenshot")
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
        golden_box=$(detect_square_boundary_diff $initial_screenshot "$browser_x_id")
        if [ "$golden_box" != "" ];then
            vout "golden_box $golden_box"
            golden_edge_x=$(echo $golden_box | cut -d' ' -f1)
            golden_edge_y=$(echo $golden_box | cut -d' ' -f2)
            golden_r=$(expr $(echo $golden_box | cut -d' ' -f3) / 2)
            golden_x=$(expr $golden_edge_x + $golden_r)
            golden_y=$(expr $golden_edge_y + $golden_r)
            vout "golden click $golden_x $golden_y"
            xdotool mousemove --window "$browser_x_id" $golden_x $golden_y click 1
        fi

        # TODO: seq 5 or so is upper bound in initial cookie, but can make golden check less when you buy "Lucky day", "Serendipity"
        for i in $(seq 5); do
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

            if [ $continue -eq 0 ]; then
                break
            fi
        done
    done

    if [ $DEBUG_RUN -eq 0 ]; then
        rm -f $initial_screenshot
    fi
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
            vout "Run!"
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
