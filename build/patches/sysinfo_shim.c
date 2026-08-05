#include <stdio.h>
#include <string.h>
#include <sys/sysinfo.h>

int sysinfo(struct sysinfo *info)
{
  if (!info)
    return -1;
  memset(info, 0, sizeof(*info));
  info->mem_unit = 1;
  info->totalram = (unsigned long)4 * 1024 * 1024 * 1024;
  return 0;
}

int flush_all(void)
{
  return fflush(NULL);
}
