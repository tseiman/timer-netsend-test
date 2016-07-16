/*
 * Copyright (C) 2016 Canonical, Ltd.
 *
 * This program is free software; you can redistribute it and/or
 * modify it under the terms of the GNU General Public License
 * as published by the Free Software Foundation; either version 2
 * of the License, or (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
 *
 * This code is a complete clean re-write of the stress tool by
 * Colin Ian King <colin.king@canonical.com> and attempts to be
 * backwardly compatible with the stress tool by Amos Waterland
 * <apw@rossby.metr.ou.edu> but has more stress tests and more
 * functionality.
 *
 * This stressor is loosely based on the STREAM Sustainable
 * Memory Bandwidth In High Performance Computers tool.
 *   https://www.cs.virginia.edu/stream/
 *   https://www.cs.virginia.edu/stream/FTP/Code/stream.c
 *
 * This is loosely based on a variant of the STREAM benchmark code,
 * so DO NOT submit results based on this as it is intended to 
 * stress memory and compute and NOT intended for STREAM accurate
 * tuned or non-tuned benchmarking whatsoever.  I believe this 
 * conforms to section 3a, 3b of the original License.
 *
 */
#define _GNU_SOURCE

#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <sys/mman.h>

#include "stress-ng.h"

static uint64_t opt_stream_L3_size = DEFAULT_STREAM_L3_SIZE;
static bool     set_stream_L3_size = false;

void stress_set_stream_L3_size(const char *optarg)
{
	set_stream_L3_size = true;
	opt_stream_L3_size = get_uint64_byte(optarg);
	check_range("stream-L3-size", opt_stream_L3_size,
		MIN_STREAM_L3_SIZE, MAX_STREAM_L3_SIZE);
}

static inline void OPTIMIZE3 stress_stream_copy(
	double *RESTRICT c,
	const double *RESTRICT a,
	const uint64_t n)
{
	register uint64_t i;

	for (i = 0; i < n; i++)
		c[i] = a[i];
}

static inline void OPTIMIZE3 stress_stream_scale(
	double *RESTRICT b,
	const double *RESTRICT c,
	const double q,
	const uint64_t n)
{
	register uint64_t i;

	for (i = 0; i < n; i++)
		b[i] = q * c[i];
}

static inline void OPTIMIZE3 stress_stream_add(
	const double *RESTRICT a,
	const double *RESTRICT b,
	double *RESTRICT c,
	const uint64_t n)
{
	register uint64_t i;

	for (i = 0; i < n; i++)
		c[i] = a[i] + b[i];
}

static inline void OPTIMIZE3 stress_stream_triad(
	double *RESTRICT a,
	const double *RESTRICT b,
	const double *RESTRICT c,
	const double q,
	const uint64_t n)
{
	register uint64_t i;

	for (i = 0; i < n; i++)
		a[i] = b[i] + (c[i] * q);
}

static void stress_stream_init_data(
	double *RESTRICT data,
	const uint64_t n)
{
	uint64_t i;

	for (i = 0; i < n; i++)
		data[i] = (double)mwc32() / (double)mwc64();
}

static inline void *stress_stream_mmap(const char *name, uint64_t sz)
{
	void *ptr;

	ptr = mmap(NULL, (size_t)sz, PROT_READ | PROT_WRITE,
#if defined(MAP_POPULATE)
		MAP_POPULATE |
#endif
		MAP_SHARED | MAP_ANONYMOUS, -1, 0);
	/* Coverity Scan believes NULL can be returned, doh */
	if (!ptr || (ptr == MAP_FAILED)) {
		pr_err(stderr, "%s: cannot allocate %" PRIu64 " bytes\n",
			name, sz);
		ptr = MAP_FAILED;
	}
	return ptr;
}

static inline uint64_t stream_L3_size(
	const char *name,
	const uint32_t instance)
{
	uint64_t cache_size = MEM_CACHE_SIZE;
#if defined(__linux__)
	cpus_t *cpu_caches = NULL;
	cpu_cache_t *cache = NULL;
	uint16_t max_cache_level;

	cpu_caches = get_all_cpu_cache_details();
	if (!cpu_caches) {
		if (!instance)
			pr_inf(stderr, "%s: using built-in defaults as unable to "
				"determine cache details\n", name);
		return cache_size;
	}
	max_cache_level = get_max_cache_level(cpu_caches);
	if ((max_cache_level > 0) && (max_cache_level < 3) && (!instance))
		pr_inf(stderr, "%s: no L3 cache, using L%" PRIu16 " size instead\n",
			name, max_cache_level);

	cache = get_cpu_cache(cpu_caches, max_cache_level);
	if (!cache) {
		if (!instance)
			pr_inf(stderr, "%s: using built-in defaults as no suitable "
				"cache found\n", name);
		free_cpu_caches(cpu_caches);
		return cache_size;
	}
	if (!cache->size) {
		if (!instance)
			pr_inf(stderr, "%s: using built-in defaults as unable to "
				"determine cache size\n", name);
		free_cpu_caches(cpu_caches);
		return cache_size;
	}
	cache_size = cache->size;

	free_cpu_caches(cpu_caches);
#else
	if (!instance)
		pr_inf(stderr, "%s: using built-in defaults as unable to "
			"determine cache details\n", name);
#endif
	return cache_size;
}

/*
 *  stress_stream()
 *	stress cache/memory/CPU with stream stressors
 */
int stress_stream(
	uint64_t *const counter,
	const uint32_t instance,
	const uint64_t max_ops,
	const char *name)
{
	int rc = EXIT_FAILURE;
	double *a, *b, *c;
	const double q = 3.0;
	double mb_rate, mb, fp_rate, fp, t1, t2, dt;
	uint64_t L3, sz, n;
	bool guess = false;

	L3 = (set_stream_L3_size) ? opt_stream_L3_size : stream_L3_size(name, instance);

	/* Have to take a hunch and badly guess size */
	if (!L3) {
		guess = true;
		L3 = stress_get_processors_configured() * DEFAULT_STREAM_L3_SIZE;
	}

	if (instance == 0) {
		pr_inf(stderr, "%s: stressor loosely based on a variant of the "
			"STREAM benchmark code\n", name);
		pr_inf(stderr, "%s: do NOT submit any of these results "
			"to the STREAM benchmark results\n", name);
		if (guess) {
			pr_inf(stderr, "%s: cannot determine CPU L3 cache size, "
				"defaulting to %" PRIu64 "K\n",
				name, L3 / 1024);
		} else {
			pr_inf(stderr, "%s: Using CPU cache size of %" PRIu64 "K\n",
				name, L3 / 1024);
		}
	}

	/* ..and shared amongst all the STREAM stressor instances */
	L3 /= stressor_instances(STRESS_STREAM);

	/*
	 *  Each array must be at least 4 x the
	 *  size of the L3 cache
	 */
	sz = (L3 * 4);
	n = sz / sizeof(double);

	a = stress_stream_mmap(name, sz);
	if (a == MAP_FAILED)
		goto err_a;
	b = stress_stream_mmap(name, sz);
	if (b == MAP_FAILED)
		goto err_b;
	c = stress_stream_mmap(name, sz);
	if (c == MAP_FAILED)
		goto err_c;

	stress_stream_init_data(a, n);
	stress_stream_init_data(b, n);
	stress_stream_init_data(c, n);

	t1 = time_now();
	do {
		stress_stream_copy(c, a, n);
		stress_stream_scale(b, c, q, n);
		stress_stream_add(c, b, a, n);
		stress_stream_triad(a, b, c, q, n);
		(*counter)++;
	} while (opt_do_run && (!max_ops || *counter < max_ops));
	t2 = time_now();

	mb = ((double)((*counter) * 10) * (double)sz) / (double)MB;
	fp = ((double)((*counter) * 4) * (double)sz) / (double)MB;
	dt = t2 - t1;
	if (dt >= 4.5) {
		mb_rate = mb / (dt);
		fp_rate = fp / (dt);
		pr_inf(stderr, "%s: memory rate: %.2f MB/sec, %.2f Mflop/sec"
			" (instance %" PRIu32 ")\n",
			name, mb_rate, fp_rate, instance);
	} else {
		if (instance == 0)
			pr_inf(stderr, "%s: run too short to determine memory rate\n", name);
	}

	rc = EXIT_SUCCESS;

	(void)munmap(c, sz);
err_c:
	(void)munmap(b, sz);
err_b:
	(void)munmap(a, sz);
err_a:

	return rc;
}
