#!/usr/bin/awk -f

# Terminology:
# Set: associative array where only the keys matter, values are empty strings
#
# Globals:
#  - installSet: set of packages to be installed (cmdline argument)
#  - toBeInstalled: the above set extended with all the dependencies
#  - dependencies: associative array; key: package name, value: comma separated dependency list
#  - filename: associative array; key: package name, value: filename in repo


# todo:
# - create a parsepackagelist fun for Dep/Provides
# - [low] add support for suggests/recommends
# - [low] add support for versioning
# - print download/installed size

# limitations:
# - install only
# - does not run scripts in .deb, only unpacks them
# - does not track package version constraints
# - does not consider alternatives in dependency list


#####################
# Utility functions #
#####################


# join a Set into a single comma separated string
function joinSet(set,    i,ret,sep) {
    ret = sep = ""

    for (i in set) {
        ret = ret sep i
        sep = ","
    }
    return ret
}

# split a comma separated list into a Set (only adds to the set) -> kikapcsolva, miert kellett egyaltalan?
function splitSet(list,ret,    i,tmp) {
    split(list, tmp, ",")
    delete ret

    for (i in tmp) {
        ret[ tmp[i] ]
    }
}

# append an item to a string with comma-space separator
function appendWithSep(list, item) {
    if (length(list) == 0) {
        return item
    } else {
        return list ", " item
    }
}

# walk dependecy tree, writes: toBeInstalled, reads: dependencies, maskSet
function walk(package,    i,tmp) {
    #print "Processing " package

    # skip masked packages (normal or virtual)
    if (package in maskSet) {
        #print "Masked: " package
        return
    }

    # skip already installed packages
    if (package in installedSet) {
        #print "Already installed: " package
        return
    }

    # return if package is already in toBeInstalled (breaks circular dependencies)
    if (package in toBeInstalled) {
        #print "Already considered for installation " package
        return
    }

    if ( !(package in dependencies) ) {

        if ( package in providers ) {
            print "Ambiguous dependency tree! Required virtual package " package ", provided by: " providers[package]
            print "Please explicitly select a provider by adding it to the install list"
            exit(1)
        } else {
            print "Unknown package: " package
            exit(1)
        }
    }

    # add current package to installSet
    toBeInstalled[package]

    # recurse for all dependencies
    splitSet( dependencies[package], tmp )
    for (i in tmp) {
        #print "do " i " dep of " package
        walk(i)
    }
}


###################
# Pre-parse setup #
###################


BEGIN {
    FS = ": "
}


##########################
# Package parse matchers #
##########################


# match on a package name
/^Package:/ {
    packageName = $2
}


# match on filename tag
/^Filename:/ {
    packageFile = $2
}


# match on a dependency tags
/^Depends:/ || /^Pre-Depends:/  {
#    print "Dep: " $2

    # Split colon separated dependency list
    split($2, deps, ", ");

    for (i in deps) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(deps[i], depClean, " ")

#        print depClean[1]
        # use array as set to remove possible duplicates due to same
        # dependency in both Depends and Pre-Depends (eg. Package: dpkg)
        packageDepSet[ depClean[1] ]
    }
}

# match on provided virtual packages
/^Provides:/ {
#    print "Provides: " $2

    # Split colon separated virtual package list
    split($2, vpkg, ", ");


    for (i in vpkg) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(vpkg[i], vpkgClean, " ")

#        print vpkgClean[1]
        # use array as set to remove possible duplicates due to same
        # dependency in bot Depends and Pre-Depends (eg. Package: dpkg)
        packageProvides[ vpkgClean[1] ]
    }
}

# match on a package separator newline
/^$/ {
    if (packageName != "") {
        dependencies[packageName] = joinSet(packageDepSet)
        filename[packageName] = packageFile
        provides[packageName] = joinSet(packageProvides)

        # create a virtual package provider map for user messages
        for (i in packageProvides) {
            providers[i] = appendWithSep( providers[i], packageName )
        }

#        print "P: " packageName
#        print "D: " dependencies[ packageName ]
#        print "F: " filename[ packageName ]
#        print ""
    }

    # blank state
    delete packageDepSet
    delete packageProvides
    # mawk doesn't support deleting ordinary variables
    #delete packageName
    #delete packageFile
    
}

#########################
# Post parse processing #
#########################


END {
    #print "end"

#    for (i in providers) {
#        print i " provided by " providers[i]
#    }

#    exit(0)


    # quit if install argument is not present
    if (install == "") {
        print "Error: install list is missing" > "/dev/stderr"
        exit(1)
    }


    ######
    # process package mask if present (no validity check on items)
    splitSet(mask, maskSet)

    ######
    # process installed packages if present (no validity check on items)
    splitSet(installed, installedSet)
    
    # mark all virtual packages as installed
    for (i in installedSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            #print "Adding virtual package to installedSet: " j
            installedSet[j]
        }
    }


    ######
    # process install request
    splitSet(install, installSet)
    
    # add virtual packages provided by the installSet to the maskSet to
    # avoid dependency tracking on them (no validity check on items)
    for (i in installSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            #print "Adding virtual package to maskSet: " j
            maskSet[j]
        }
    }
    
    # walk dependecy tree (die on invalid items)
    for (i in installSet) {
        walk(i)
    }

    #print "Minimal connected set:"
    OFS=","
    for (i in toBeInstalled) {
        print i, filename[i]
    }
}
