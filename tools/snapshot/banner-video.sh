#!/bin/sh
# Assembles the README banner's loop from its two recordings, light and dark,
# into an MP4 and a GIF. Record them first:
#
#   MOTION=1 SCHEME=light sh run.sh scenes/Banner.hx
#   MOTION=1 sh run.sh scenes/Banner.hx
#
# Each recording opens with LEAD frames while textures upload, then is one half
# of a 12 s loop at 30 fps, half a second longer than the half so the two can be
# cross-faded where they meet: after the lead-in, frames 0 to 179 are the half,
# 180 to 194 overlap the next half's first 15. Writes
# .ashui/snapshots/banner.mp4 (H.264, the recordings' full size) and
# .ashui/snapshots/banner.gif (GIF_WIDTH wide, 15 fps). Needs ffmpeg and
# ImageMagick.
set -e
cd "$(dirname "$0")/../.."
shots=.ashui/snapshots
light=$shots/motion/banner-loop-light
dark=$shots/motion/banner-loop
gif_width=${GIF_WIDTH:-960}
lead=12
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

n=0
# A recording's frame `i` of its half, past the lead-in.
frame() {
	printf "%s/frame-%03d.png" "$1" $(($2 + lead))
}
put() {
	cp "$(frame "$1" "$2")" "$(printf "$work/%04d.png" $n)"
	n=$((n + 1))
}
# `from`'s frames 180 to 194 giving way to `to`'s 0 to 14: a soft-edged circle spreading
# from the island at the top centre, eased, until it covers the frame.
fade() {
	size=$(magick identify -format "%w %h" "$(frame "$1" 0)")
	w=${size% *}
	h=${size#* }
	reach=$(awk "BEGIN { print sqrt(($w / 2) ^ 2 + $h ^ 2) * 1.08 }")
	for k in $(seq 0 14); do
		r=$(awk "BEGIN { u = ($k + 1) / 16; e = u * u * (3 - 2 * u); print e * $reach }")
		# The mask drawn at an eighth of the size and blurred there, then enlarged: the same soft edge, far quicker.
		magick -size "$((w / 8))x$((h / 8))" xc:black -fill white -draw "circle $((w / 16)),0 $((w / 16)),$(awk "BEGIN { print $r / 8 }")" \
			-blur 0x$((w / 320)) -resize "${w}x${h}!" "$work/mask.png"
		# The next half, its alpha the mask, laid over this one.
		magick "$(frame "$1" $((180 + k)))" \( "$(frame "$2" $k)" "$work/mask.png" -alpha off -compose copy_opacity -composite \) \
			-compose over -composite "$(printf "$work/%04d.png" $n)"
		n=$((n + 1))
	done
	rm -f "$work/mask.png"
}
# Light from its frame 15, so the loop's seam is the dark-to-light cross-fade at the end.
for i in $(seq 15 179); do put "$light" $i; done
fade "$light" "$dark"
for i in $(seq 15 179); do put "$dark" $i; done
fade "$dark" "$light"

ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$work/%04d.png" \
	-c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart "$shots/banner.mp4"
# Ordered dithering keeps each frame's pixels where the last frame's were, so a frame stores only what moved: a smaller file.
ffmpeg -hide_banner -loglevel error -y -framerate 30 -i "$work/%04d.png" \
	-vf "fps=15,scale=$gif_width:-1:flags=lanczos,split[a][b];[a]palettegen=max_colors=256:stats_mode=diff[p];[b][p]paletteuse=dither=bayer:bayer_scale=4:diff_mode=rectangle" \
	-loop 0 "$shots/banner.gif"
ls -la "$shots/banner.mp4" "$shots/banner.gif"
