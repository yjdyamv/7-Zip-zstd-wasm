#include <stdio.h>
#include <string.h>
#include <sys/sysinfo.h>
#include <emscripten/heap.h>

int sysinfo(struct sysinfo *info)
{
  if (!info)
    return -1;
  memset(info, 0, sizeof(*info));
  info->mem_unit = 1;
  /* Report the maximum wasm heap size instead of a fake physical-RAM value.
     emscripten_get_heap_max() is the max WebAssembly memory size and
     already fits in wasm32's 32-bit unsigned long. */
  info->totalram = emscripten_get_heap_max();
  return 0;
}

int flush_all(void)
{
  return fflush(NULL);
}
