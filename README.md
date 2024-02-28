# wallpaper-finder

A zig utility to find wallpaper sized images on a disk. Only supports PNG and JPG.

## How it works

Just reads the file until it finds the encoded height and width, and checks if it matches 16x9 (roughly).

## Why

Imagemagick script wasn't fast enough, and loading a ton of files (i was searching 90k+ files of 375 GiB total). 
This program reads only the first few bytes of the file, and linux caching makes it almost instant for re-runs.

## Acknowledgements

the stackoverflow answerers (and the question askers) who helped me figure out how jpg and png are structured.

TODO: add the sources
