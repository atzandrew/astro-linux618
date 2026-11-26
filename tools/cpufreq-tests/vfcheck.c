/*
 * vfcheck: sample (Vproc, PLL rate, Vproc) for both CPU clusters and flag any
 * sample where neither voltage reading covers the stock FY voltage for the
 * PLL rate read between them. Read only (/dev/mem + regulator sysfs).
 * Run pinned to a CPU whose load does not move the cluster under test.
 *   vfcheck SAMPLES INTERVAL_US BIG_REG_DIR LITTLE_REG_DIR
 * docs/cpufreq-stock.md (C2).
 */
#include <fcntl.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mman.h>
#include <unistd.h>

struct opp { unsigned mhz, uv; };
static const struct opp ll[] = { {500,600000},{650,600000},{756,625000},{862,643750},
	{968,668750},{1075,693750},{1181,712500},{1358,750000},{1500,781250},{1541,800000},
	{1625,818750},{1687,837500},{1750,856250},{1812,868750},{1875,887500},{2000,925000} };
static const struct opp bl[] = { {774,600000},{841,618750},{925,637500},{1008,656250},
	{1091,675000},{1175,700000},{1258,718750},{1383,750000},{1548,800000},{1633,806250},
	{1716,831250},{1800,850000},{1850,868750},{1900,887500},{1950,906250},{2000,925000} };

/* lowest table voltage for an OPP at or above the rate (rate in kHz) */
static unsigned need(const struct opp *t, unsigned khz)
{
	for (int i = 0; i < 16; i++)
		if (t[i].mhz * 1000 + 1 >= khz)
			return t[i].uv;
	return 2000000;
}

static int rd_uv(int fd)
{
	char b[32];
	ssize_t n = pread(fd, b, sizeof(b) - 1, 0);
	if (n <= 0) return -1;
	b[n] = 0;
	return atoi(b);
}

static unsigned khz(volatile uint32_t *apm, volatile uint32_t *mcu, unsigned con1, unsigned mux, int *sel)
{
	uint32_t c = apm[con1 / 4], m = mcu[mux / 4];
	*sel = (m >> 9) & 3;
	if (*sel == 0) return 26000;
	if (*sel != 1 || ((m >> 17) & 31) != 8) return 0;
	uint64_t pcw = c & 0x3fffff;
	return (unsigned)(pcw * 26000 / 16384 >> ((c >> 24) & 7));
}

int main(int argc, char **argv)
{
	if (argc < 5) { fprintf(stderr, "usage: vfcheck N US BIGREG LITREG\n"); return 2; }
	long n = atol(argv[1]), us = atol(argv[2]);
	char p[256];
	snprintf(p, sizeof(p), "%s/microvolts", argv[3]); int fb = open(p, O_RDONLY);
	snprintf(p, sizeof(p), "%s/microvolts", argv[4]); int fl = open(p, O_RDONLY);
	int mem = open("/dev/mem", O_RDONLY | O_SYNC);
	if (fb < 0 || fl < 0 || mem < 0) { perror("open"); return 1; }
	volatile uint32_t *apm = mmap(0, 4096, PROT_READ, MAP_SHARED, mem, 0x1000c000);
	volatile uint32_t *mcu = mmap(0, 4096, PROT_READ, MAP_SHARED, mem, 0x0c53a000);
	if (apm == MAP_FAILED || mcu == MAP_FAILED) { perror("mmap"); return 1; }
	long bad = 0, hist_b[17] = {0}, hist_l[17] = {0}, odd = 0;
	for (long i = 0; i < n; i++) {
		int s, v1, v2, w1, w2;
		v1 = rd_uv(fb); unsigned fbk = khz(apm, mcu, 0x21c, 0x2a4, &s); v2 = rd_uv(fb);
		if (fbk == 0) odd++;
		else if (s == 1) {
			unsigned r = need(bl, fbk);
			if ((v1 > v2 ? v1 : v2) < (int)r) {
				bad++; printf("LOW big %u kHz needs %u, read %d / %d\n", fbk, r, v1, v2);
			}
			for (int k = 0; k < 16; k++) if (bl[k].mhz * 1000 + 1 >= fbk) { hist_b[k]++; break; }
		}
		w1 = rd_uv(fl); unsigned flk = khz(apm, mcu, 0x20c, 0x2a0, &s); w2 = rd_uv(fl);
		if (flk == 0) odd++;
		else if (s == 1) {
			unsigned r = need(ll, flk);
			if ((w1 > w2 ? w1 : w2) < (int)r) {
				bad++; printf("LOW little %u kHz needs %u, read %d / %d\n", flk, r, w1, w2);
			}
			for (int k = 0; k < 16; k++) if (ll[k].mhz * 1000 + 1 >= flk) { hist_l[k]++; break; }
		}
		if (us) usleep(us);
	}
	printf("samples %ld, LOW %ld, mux/div unexpected %ld\nbig:", n, bad, odd);
	for (int k = 0; k < 16; k++) if (hist_b[k]) printf(" %u:%ld", bl[k].mhz, hist_b[k]);
	printf("\nlittle:");
	for (int k = 0; k < 16; k++) if (hist_l[k]) printf(" %u:%ld", ll[k].mhz, hist_l[k]);
	printf("\n");
	return bad ? 1 : 0;
}
