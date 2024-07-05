#include <stdio.h>
#include <stdlib.h>
#include <math.h>

// <
#include <sys/types.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <sys/mman.h>

#include <sys/time.h>     /* struct timeval definition           */
#include <unistd.h>       /* declaration of gettimeofday()       */

#include <time.h>
// > library from teacher's chrono.c code

#include "./SourceCode/reductionCode.h"
#include "./SourceCode/inputHandler.h"
#include "./SourceCode/timeManager.h"
#include "./SourceCode/GPUhandler.h"