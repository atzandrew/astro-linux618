/* membw: memcpy and read bandwidth over a buffer far larger than the caches.
 * Single thread; run pinned (taskset). Usage: membw [MiB] [reps] */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

static double now(void)
{
	struct timespec t;
	clock_gettime(CLOCK_MONOTONIC, &t);
	return t.tv_sec + t.tv_nsec / 1e9;
}

int main(int argc, char **argv)
{
	size_t mib = argc > 1 ? atol(argv[1]) : 256, n = mib << 20;
	int reps = argc > 2 ? atoi(argv[2]) : 5;
	uint64_t *a = aligned_alloc(4096, n), *b = aligned_alloc(4096, n);
	if (!a || !b) return 1;
	memset(a, 1, n); memset(b, 2, n);
	double best_cp = 0, best_rd = 0;
	volatile uint64_t sink = 0;
	for (int r = 0; r < reps; r++) {
		double t = now();
		memcpy(b, a, n);
		t = now() - t;
		if (n / t > best_cp) best_cp = n / t;
		t = now();
		uint64_t s0 = 0, s1 = 0, s2 = 0, s3 = 0;
		for (size_t i = 0; i < n / 8; i += 4) {
			s0 += a[i]; s1 += a[i + 1]; s2 += a[i + 2]; s3 += a[i + 3];
		}
		t = now() - t;
		sink += s0 + s1 + s2 + s3;
		if (n / t > best_rd) best_rd = n / t;
	}
	/* memcpy moves 2n bytes (read + write) */
	printf("buffer %zu MiB: memcpy %.2f GB/s (copied), %.2f GB/s (bus), read %.2f GB/s\n",
	       mib, best_cp / 1e9, 2 * best_cp / 1e9, best_rd / 1e9);
	return (int)(sink & 0);
}
