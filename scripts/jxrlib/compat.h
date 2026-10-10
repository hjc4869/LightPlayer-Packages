#pragma once

#include <stdlib.h>
#include <wchar.h>

#ifdef _MSC_VER
#include <sal.h>
#ifndef __in_win
#define __in_win _In_
#endif
#ifndef __out_win
#define __out_win _Out_
#endif
#endif

unsigned int photos_jxr_byteswap_ulong(unsigned int value);