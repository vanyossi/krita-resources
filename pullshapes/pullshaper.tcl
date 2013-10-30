#!/usr/bin/tclsh
#
#
# ---------------:::: Pullshaper ::::-----------------------
#  Version: 1.0.0
#  Author:IvanYossi / http://colorathis.wordpress.com ghevan@gmail.com
#  License: GPLv2 
# -----------------------------------------------------------
#  Goal : Create pullshapes brushes from svg catalogs easily
#   Dependencies: >=imagemagick-6.7.5, tcl 8.5 inkscape gimp
# 
# ---------------------::::::::::::::------------------------
#
set version "Version 1.0"
set ::help_msg [format {
	Pullshaper: Small sript to create .gih files from svg shape libraries
	
	Usage: pullshaper.tcl [INPUT svg|pdf] ?[INPUT svg|pdf]...? [OPTIONS...] [OUTPUT file.gih]
	
	-s              set brush resolution size in pixels
	-n              Brush name, as it will appear on program (gimp, krita)
	-spacing        Brush spacing, default 100
	-v              Print version and exit
	--help          Print this message
	
	If no output given, name will be used as output name
	
	Example:
	  pullshaper.tcl tangram.svg deevad_shaped.svg -s 64 -spacing 58 tangram_deevad_64.gih
	  (Combines shapes from 2 files into a single pack)
	
	%s
	
	Author: Ivan Yossi
	Website: http://colorathis.wordpress.com
} $::version ]
set ::pullshape_Files [list]

# Sets options from arguments lists
# returns nothing, populates global array.
proc reviewArgs { args } {
	array set ::options {}
	foreach arg $args {
		# Add file to input filelist if svg pdf or ai
		if { ([regexp {^(.svg|.ai|.pdf)$} [file extension $arg]] ) && [file exists $arg ] } {
			lappend ::options(input) $arg
			continue
		}
		switch -exact -- $arg {
			"--help" { 
				puts $::help_msg
				exit
			}
			"-v" {
				puts $::version
				exit
			}
			"-s" { set name "size" }
			"-n" { set name "name" }
			"-spacing" { set name "spacing" }
			"default" { continue }
		}
		if { [catch {set ::options($name) [getArgValue $arg $args]} error_msg] } {
			puts $error_msg
		}

	}
	if { ![llength $::options(input)] > 0 } {
		puts "No input files found! existing..."
		exit
	}
	# last argument file exists, set as output
	if { [file extension [lindex $args end]] eq ".gih" } {
		set ::options(output) [lindex $args end]
	}
}

# Validates options given
# key = option, plist = list of values
# returns the value if valid, else returns error code
proc getArgValue { key plist } {
	set index [lsearch $plist $key]
	set value [lindex $plist $index+1]
	switch -exact -- $key {
		"-spacing"	-
		"-s" {
			if { ![string is integer $value] || $value eq {} } {
				return -code error "$key must be a integer number!"
			}
		}
		"-n" {
			if { ![string is ascii $value] || $value eq {} } {
				return -code error "$key, letters and numbers only!"
			}
		}
	}
	return $value
}
# Reads an svg file to get shape list
# f = filename
# returns path name list
proc extractShapes { f } {
	set filename [file normalize $f]
	set command [list inkscape $filename -z -S]
	set rawdata [exec {*}$command]
	
	set plist {}
	if {[lsearch $rawdata {pull*}] >= 0 } {
		set filter {pull}
		set for_list $rawdata
	} else {
		set filter {path|rect|pull}
		
		set rawdata [lreverse $rawdata]
		set index [lsearch -regexp $rawdata {^(g|layer|svg)(.*)$}]
		set for_list [lrange $rawdata 0 $index]
	}
	# foreach item [lsearch -inline -all -regexp $rawdata {^(path|rect|pull)(.*)$}] \{
	foreach item [lsearch -inline -all -regexp $for_list [format {^(%s)(.*)$} $filter] ] {
		lappend plist [lindex [split $item ,] 0]
	}
	return $plist
}

# Iterates plist to generate a path png render from each
# f = filename, s = size in pixels, plist = path names list
# returns image names list
proc processShapes { f plist {s 250} } {
	set command [list inkscape $f -i %s -w $s -e %s]
	set dir [file dirname [file normalize $f]]
	set flist {}
	foreach path $plist {
		set output [file join $dir pbuild_${path}.png]
		exec {*}[format $command $path $output]
		lappend flist $output
	}
	return $flist
}

# Modifies shapes to fit inside a square and to grayscale colorspace
# flist = file to iterate (images), size = integer desired square size
proc normalizeSizes { flist {size 250} } {
	set command {convert -quiet -size %s xc:white -colorspace RGB -gravity Center "%s" -resize %s -compose Over -define compose:args=100 -composite -colorspace Gray "%s"}
	
	set resize [join [list $size $size] {x}]
	foreach image $flist {
		set imgcmd [format $command $resize $image $resize $image ]
		exec {*}$imgcmd
	}
}

# count members of list to process
# return integer
proc getTotalPaths { flist } {
	return [llength $flist]
}

# return max width and height of layers as list
# psdfile = psd to read
proc getSizeMax { psdfile } {
	set command [list identify -quiet -format "%w %h " $psdfile]
	set layers [exec {*}$command]
	foreach {width height} $layers {
		lappend width_list $width
		lappend height_list $height
	}
	set max_w [expr max([join $width_list {,}]) ]
	set max_h [expr max([join $height_list {,}]) ]
	
	return [list $max_w $max_h]
}

proc getSize { {size 250} } {
	if {[info exists ::options(size)]} {
		set size $::options(size)
	}
	return $size
}

# Call imagemagick tu unite all renders into a psd file
# flist = png filelist
# return psd file name
# TODO integrate to script-fu function
proc makePSD { flist {dir .} } {
	set fname "tmp_pullshaper_colection.psd"
	set output [file join $dir $fname]
	set command [list convert -quiet {*}$flist -depth 8 -density 96x96 -adjoin $output]
	exec {*}$command
	return $output
}

# Verifies user set an output name, if it didn't set the name as brush
# name args, if nor arg name given, set a default name based on vector source
# global option name, and name args
# return string, name of file
proc validateOutputName { vector_name } {
	set oname {}
	# test for existance of user set variables
	if {[info exists ::options(output)]} {
		set oname $::options(output)
	} elseif {[info exists ::options(name)] } {
		append oname $::options(name) ".gih"
	} else {
		append oname [file root [file tail $vector_name]] ".gih"
	}
	return [join $oname "_"]
}

# Verifies user set the name brush arg, if not, append svg name to "pull_shape"
# return string, name of brush
proc validateNameArg { vector_name } {
	set oname {}
	# test for existance
	if { [info exists ::options(name)] } {
		set oname $::options(name)
	} else {
		set oname [file root [file tail $vector_name]]
	}
	return [join $oname "_"]
}

# Add file paths to delete file list
# flist, path list
proc addToDelete { flist } {
	set ::pullshape_Files [concat $::pullshape_Files $flist]
}

proc deletePullShapes { flist } {
	catch {file delete -- {*}$flist}
}
# Execute gimp to create brush file
# psdfile = sourcefile PSD, ranktotal = layers, size = max w and h,
# spacing = brush spacing, name = brushname, outname = out	put file "gih"
proc makeBrush { flist ranktotal size {spacing 100} {description "Pull_shapes"} {outname pull_shapes.gih} } {
	set full_outname [file normalize $outname]
	set cell_width $size
	set cell_height $size
	set dimension 1
	
	foreach el $flist {
		lappend findex [incr layercount]
	}
	
	foreach index $findex image $flist {
		append layerlist [format {(layer%.0f (car (gimp-file-load-layer 1 image "%s")))} $index $image]
		append loadlist [format {(gimp-image-insert-layer image layer%.0f 0 -1)} $index]
	}
	
	set scriptfu [format {(let* (
		(ranks (cons-array 1 'double))
		(sel (list "random"))
		(image (car (gimp-image-new 500 500 1)))
		%s
		(drawable (car (gimp-image-get-active-layer image)) )
	)
		%s
		(set! drawable (car (gimp-image-get-active-layer image)) )
		(aset ranks 0 %s)
		(file-gih-save 1 image drawable "%s" "%s" %s "%s" %s %s 1 1 %s ranks %s sel)
		)(gimp-quit 0) } $layerlist $loadlist $ranktotal $full_outname $full_outname $spacing $description $cell_width $cell_height $dimension $dimension]
		
	#set scriptfu [format {(let* (
	#	(ranks (cons-array 1 'double))
	#	(sel (list "random"))
	#	(image (car (gimp-file-load 1 "%s" "%s" )) )
	#	(drawable (car (gimp-image-get-layers image)) )
	#)
	#	(aset ranks 0 %s)
	#	(file-gih-save 1 image drawable "%s" "%s" %s "%s" %s %s 1 1 %s ranks %s sel)
	#	)(gimp-quit 0) } $psdfile $psdfile $ranktotal $full_outname $full_outname $spacing $description $cell_width $cell_height $dimension $dimension]
		
	# [format [concat {"%s"} $b ] vars]
	#puts $scriptfu
	catch { exec gimp -i -b "$scriptfu" } msg
	
	# if {$::errorCode != "NONE"} {
	#	puts $msg
	#}
	return $outname
}

proc startProcess { args } {
	
	reviewArgs {*}$args
	
	set flist {}
	foreach source_file $::options(input) {
		puts "Extracting shapes from vector source:  $source_file..."
		set plist [extractShapes $source_file]
		lappend flist {*}[processShapes $source_file $plist $::options(size)]
	}
	addToDelete $flist
	
	puts "Conforming images to desired size..."
	normalizeSizes $flist $::options(size)
	
	puts "Calculating sizes..."
	# set psdfile [makePSD $flist [file dirname $::options(input)]]
	set size [getSize]
	set ranks [getTotalPaths $flist]
	
	puts "Rendering brush file..."
	set brush_title [validateNameArg [join $::options(input) {_}]]
	set output_file [validateOutputName [join $::options(input) {_}]]
	set brushName [makeBrush $flist $ranks $size $::options(spacing) $brush_title $output_file]
	
	puts "Deleting temporary files..."
	deletePullShapes $::pullshape_Files
	
	puts "$brushName created"
	catch {puts "Thank you $::env(USER)"}
}
startProcess {*}$argv
