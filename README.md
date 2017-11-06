# Fetch

Fetch is a proof of concept package manager for Debian (and derivatives) based Docker containers. It's implemented in POSIX sh and AWK, while it uses only a handful of the most basic shell tools (tar, grep, cut, tr, wget). It works well with the busybox version of these tools.

Fetch provides a similar command line interface to apt, but only offers the most basic features (update, install). The number one caveat compared to apt is that fetch does not execute installation scripts in deb files, only unpacks. The scripts assume that they run on a properly configured distribution which is not the case with minimal docker images, and they don't play well with the busybox command set. Unpacking usually works well in practice, manual fixups are rarely required.  

#### Status
Fetch is right now a proof of concept.