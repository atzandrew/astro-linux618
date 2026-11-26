/*
 * tetime: time the DSI external TE flag (DSI_INTSTA bit 4, EXT_TE_RDY) by
 * clearing it and polling every 0.5 ms; prints the interval between
 * re-assertions. Measurement poke only (write-0-to-clear of a status bit),
 * astro-linux618 docs/frame-pacing.md. Run as root, display idle.
 *   tetime [SECONDS]
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sys/mman.h>
#include <time.h>
#include <unistd.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	double secs = argc > 1 ? atof(argv[1]) : 1.0;
	int fd = open("/dev/mem", O_RDWR | O_SYNC);
	volatile uint32_t *dsi = mmap(0, 4096, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0x14010000);
	if (dsi == MAP_FAILED) { perror("mmap"); return 1; }
	volatile uint32_t *intsta = dsi + 0x0c / 4;
	double t0 = now(), last = 0;
	int n = 0;
	*intsta = *intsta & ~0x10u;
	while (now() - t0 < secs) {
		uint32_t v = *intsta;
		if (v & 0x10) {
			double t = now();
			if (last)
				printf("%.2f ", (t - last) * 1000);
			last = t; n++;
			*intsta = v & ~0x10u;
		}
		usleep(500);
	}
	printf("\n%d TE edges in %.1f s\n", n, secs);
	return 0;
}
