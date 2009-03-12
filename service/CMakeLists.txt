#####
# A CMake build file for the ruby PSTORE corelet which allows you to
# persistently store lots of data on the client side.
# 
# Author: Steve Spencer
# (c) Yahoo 2007, all rights reserved
#####

# looser syntax
SET(CMAKE_ALLOW_LOOSE_LOOP_CONSTRUCTS 1)

SET(coreletName JSONRequest)

SET(SCRIPT_FILE JSONRequest.rb)

# Name our project
PROJECT(${coreletName}Ruby)

# desired output directory
SET (outputDir "${CMAKE_CURRENT_BINARY_DIR}/${coreletName}")

# build up the corelet dir
FILE(MAKE_DIRECTORY ${outputDir})

CONFIGURE_FILE("${CMAKE_CURRENT_SOURCE_DIR}/manifest.json"
               "${outputDir}/manifest.json")  

# ship all *.rb files
FILE(GLOB_RECURSE srcs RELATIVE "${CMAKE_CURRENT_SOURCE_DIR}" "*.rb")

SET(allDeps)

FOREACH(src ${srcs})
  SET(mySrc "${CMAKE_CURRENT_SOURCE_DIR}/${src}")
  SET(myDst "${outputDir}/${src}")

  ADD_CUSTOM_COMMAND(
    OUTPUT ${myDst}
    DEPENDS ${mySrc}		  
    COMMAND ${CMAKE_COMMAND} -E copy_if_different ${mySrc} ${myDst}
  )
  SET(allDeps ${allDeps} ${myDst})
ENDFOREACH()

ADD_CUSTOM_TARGET(${coreletName} ALL DEPENDS ${allDeps})

SETUP_CORELET_PUBLISHING(${coreletName})
