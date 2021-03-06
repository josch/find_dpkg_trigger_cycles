Running
=======

Just start `./setup.sh`. It will do the following:

1. download apt sources and apt-file data for the amd64 Debian sid snapshot at
   `20141211T041251Z` and store them in a directory tree rooted at
   `./debian-sid-amd64`
2. go through all binary packages which have a file `DEBIAN/triggers` in their
   control archive (the list is retrieved from binarycontrol.debian.net)
   and for each package:
  1. download and unpack its control archive
  2. store all interest-await file triggers in the file `interested-file`
  3. store all interest-await explicit triggers in the file `interested-explicit`
  4. store all activate-await file triggers in the file `activated-file`
  5. store all activate-await explicit triggers in the file `activated-explicit`
  6. remove the downloaded binary package and unpacked control archive
3. go through `interested-file` and for each line:
  1. calculate the dependency closure for the binary package and for
     each package in the closure:
    1. use `apt-file` to get all files of the package
    2. check if the current file trigger matches any file in the package
    3. store any hits in the file `result-file`
4. go through `interested-file` and for each line:
  1. calculate the dependency closure for the binary package and for
     each package in the closure:
    1. check if the package activates the current file trigger
    2. append any hits to the file `result-file`
5. go through `interested-explicit` and for each line:
  1. calculate the dependency closure for the binary package and for
     each package in the closure:
    1. check if the package activate the current explicit trigger
    2. store any hits in the file `result-explicit`

Files
=====

interested-file
---------------

Associates binary packages to file triggers they are interested in. The first
column is the binary package, the second column is either `interest` or
`interest-await` and the last column the path they are interested in.

interested-explicit
-------------------

Associates binary packages to explicit triggers they are interested in. The
first column is the binary package, the second column is either `interest` or
`interest-await` and the last column the name of the explicit trigger they are
interested in.

activated-file
--------------

Associates binary packages to file triggers they activate. The first column is
the binary package, the second column is either `activate` or `activate-await`
and the last column the path they activate.

activate-explicit
-----------------

Associates binary packages to explicit triggers they activate. The first column
is the binary package, the second column is either `activate` or
`activate-await` and the last column the explicit trigger they activate.

result-file
-----------

Associates binary packages with other binary packages they can form a file
trigger cycle with. The first column is the binary package containing the file
trigger, the second column is the file trigger, the third column is a binary
package providing a path that triggers the binary package in the first column,
the fourth column is the triggering path of provided by the binary package in
the third column.

result-explicit
---------------

Associates binary packages with other binary packages they can form an explicit
trigger cycle with. The first column is the binary package interested in the
explicit trigger, the second column is the name of the explicit trigger, the
third column is the binary package activating the trigger.
