#!/usr/bin/awk -f

# Terminology:
# Set: an awk associative array where only the keys are used, values are empty strings
# Map: an awk associative array
#
# Commandline params (set with -v)
# - install: comma separated list of packages to be installed (MANDATORY)
# - installed: comma separated list of packages already installed (OPTIONAL)
# - mask: comma separated list of packages that shouldn't be installed (OPTIONAL)

# Globals:
# - maskSet: cmdline arg as Set
# - installSet: cmdline arg as Set
# - installedSet: cmdline arg as Set
# - dependencies: Map of package dependencies, key: package name, value: comma separated list of dependencies
# - filename: Map of package filenames, key: package name, value: filename
# - provides: Map of package provided virtuals, key: package name, value: comma separated list of provided virt-packages
# - virtuals: Map of virtuals, key: virt-package name, value: comma-space separated list of real packages providing the virtual in the key


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


# send debug message to stderr (conditional)
function log_debug(msg) {
#    if (debug == 1) {
    if (1) {
        print "D " msg > "/dev/stderr"
    }
}

# send error msg to stderr
function log_error(msg) {
        print "E " msg > "/dev/stderr"
}

# join a Set into a single comma separated string
function joinSet(set,    i,ret,sep) {
    ret = sep = ""

    for (i in set) {
        ret = ret sep i
        sep = ","
    }
    return ret
}

# split a comma separated list into a Set, args:
#   list(in): comma separated list
#   ret(out): Set containing the list items
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

function walk(package,requiredby,    i,tmp) {
    # skip masked packages (normal or virtual)
    if (package in maskSet) {
        return
    }

    # skip already installed packages
    if (package in installedSet) {
        return
    }

    # return if package is already in toBeInstalled (breaks circular dependencies)
    if (package in toBeInstalled) {
        return
    }

    if ( !(package in dependencies) ) {

        if ( package in virtuals ) {
            log_error( "Ambiguous dependency tree! Required virtual package " package ", provided by: " virtuals[package] )
            log_error( "Please explicitly select a provider by adding it to the install list" )
            exit(1)
        } else {
            log_error( "Unknown package: " package )
            exit(1)
        }
    }

    # add current package to installSet
    log_debug("Selecting " package " (required by: " requiredby ")" )
    toBeInstalled[package]

    # recurse for all dependencies
    splitSet( dependencies[package], tmp )
    for (i in tmp) {
        walk(i, package)
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
    # Split colon separated dependency list
    split($2, deps, ", ");

    for (i in deps) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(deps[i], depClean, " ")

        packageDepSet[ depClean[1] ]
    }
}

# match on provided virtual packages
/^Provides:/ {
    # Split colon separated virtual package list
    split($2, vpkg, ", ");


    for (i in vpkg) {
        # split dependecy along space and keep only the first part (strip version info and alternatives)
        split(vpkg[i], vpkgClean, " ")

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
            virtuals[i] = appendWithSep( virtuals[i], packageName )
        }
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

    # quit if install argument is not present
    if (install == "") {
        log_error( "Error: install list is missing" )
        exit(1)
    }


    ######
    # process package mask if present (no validity check on items)
    splitSet(mask, maskSet)

    ######
    # process installed packages if present (no validity check on items)
    splitSet(installed, installedSet)
    
    # mark all virtual packages as installed if an already installed package provides them
    for (i in installedSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            log_debug( "Adding virtual package to installedSet: " j " (provided by installed: " i ")" )
            installedSet[j]
        }
    }


    ######
    # process install request
    splitSet(install, installSet)
    
    # add virtual packages provided by the installSet to the maskSet to
    # avoid dependency tracking on them (no validity check on items)
    # eg: install=bash,gawk (bash depends on awk, which is provided by gawk)
    # NOTE: the item could be added to installedSet instead of maskSet, or a new virtInstallSet
    # The point is to break the processing of this virtual dependency in walk()
    for (i in installSet) {
        splitSet(provides[i], tmp)
        for (j in tmp) {
            log_debug( "Adding virtual package to maskSet: " j " (provided by install req: " i ")" )
            maskSet[j]
        }
    }
    
    # walk dependecy tree (die on invalid items)
    for (i in installSet) {
        walk(i, "<user>")
    }

    OFS=","
    for (i in toBeInstalled) {
        print i, filename[i]
    }
}
