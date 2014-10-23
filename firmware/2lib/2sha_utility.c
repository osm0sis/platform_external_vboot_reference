/* Copyright (c) 2014 The Chromium OS Authors. All rights reserved.
 * Use of this source code is governed by a BSD-style license that can be
 * found in the LICENSE file.
 *
 * Utility functions for message digest functions.
 */

#include "2sysincludes.h"
#include "2common.h"
#include "2rsa.h"
#include "2sha.h"

#if VB2_SUPPORT_SHA1
#define CTH_SHA1 VB2_HASH_SHA1
#else
#define CTH_SHA1 VB2_HASH_INVALID
#endif

#if VB2_SUPPORT_SHA256
#define CTH_SHA256 VB2_HASH_SHA256
#else
#define CTH_SHA256 VB2_HASH_INVALID
#endif

#if VB2_SUPPORT_SHA512
#define CTH_SHA512 VB2_HASH_SHA512
#else
#define CTH_SHA512 VB2_HASH_INVALID
#endif

static const uint8_t crypto_to_hash[] = {
	CTH_SHA1,
	CTH_SHA256,
	CTH_SHA512,
	CTH_SHA1,
	CTH_SHA256,
	CTH_SHA512,
	CTH_SHA1,
	CTH_SHA256,
	CTH_SHA512,
	CTH_SHA1,
	CTH_SHA256,
	CTH_SHA512,
};

/**
 * Convert vb2_crypto_algorithm to vb2_hash_algorithm.
 *
 * @param algorithm	Crypto algorithm (vb2_crypto_algorithm)
 *
 * @return The hash algorithm for that crypto algorithm, or VB2_HASH_INVALID if
 * the crypto algorithm or its corresponding hash algorithm is invalid or not
 * supported.
 */
enum vb2_hash_algorithm vb2_crypto_to_hash(uint32_t algorithm)
{
	if (algorithm < ARRAY_SIZE(crypto_to_hash))
		return crypto_to_hash[algorithm];
	else
		return VB2_HASH_INVALID;
}

int vb2_digest_size(enum vb2_hash_algorithm hash_alg)
{
	switch (hash_alg) {
#if VB2_SUPPORT_SHA1
	case VB2_HASH_SHA1:
		return VB2_SHA1_DIGEST_SIZE;
#endif
#if VB2_SUPPORT_SHA256
	case VB2_HASH_SHA256:
		return VB2_SHA256_DIGEST_SIZE;
#endif
#if VB2_SUPPORT_SHA512
	case VB2_HASH_SHA512:
		return VB2_SHA512_DIGEST_SIZE;
#endif
	default:
		return 0;
	}
}

int vb2_digest_init(struct vb2_digest_context *dc,
		    enum vb2_hash_algorithm hash_alg)
{
	dc->hash_alg = hash_alg;

	switch (dc->hash_alg) {
#if VB2_SUPPORT_SHA1
	case VB2_HASH_SHA1:
		vb2_sha1_init(&dc->sha1);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA256
	case VB2_HASH_SHA256:
		vb2_sha256_init(&dc->sha256);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA512
	case VB2_HASH_SHA512:
		vb2_sha512_init(&dc->sha512);
		return VB2_SUCCESS;
#endif
	default:
		return VB2_ERROR_SHA_INIT_ALGORITHM;
	}
}

int vb2_digest_extend(struct vb2_digest_context *dc,
		      const uint8_t *buf,
		      uint32_t size)
{
	switch (dc->hash_alg) {
#if VB2_SUPPORT_SHA1
	case VB2_HASH_SHA1:
		vb2_sha1_update(&dc->sha1, buf, size);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA256
	case VB2_HASH_SHA256:
		vb2_sha256_update(&dc->sha256, buf, size);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA512
	case VB2_HASH_SHA512:
		vb2_sha512_update(&dc->sha512, buf, size);
		return VB2_SUCCESS;
#endif
	default:
		return VB2_ERROR_SHA_EXTEND_ALGORITHM;
	}
}

int vb2_digest_finalize(struct vb2_digest_context *dc,
			uint8_t *digest,
			uint32_t digest_size)
{
	if (digest_size < vb2_digest_size(dc->hash_alg))
		return VB2_ERROR_SHA_FINALIZE_DIGEST_SIZE;

	switch (dc->hash_alg) {
#if VB2_SUPPORT_SHA1
	case VB2_HASH_SHA1:
		vb2_sha1_finalize(&dc->sha1, digest);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA256
	case VB2_HASH_SHA256:
		vb2_sha256_finalize(&dc->sha256, digest);
		return VB2_SUCCESS;
#endif
#if VB2_SUPPORT_SHA512
	case VB2_HASH_SHA512:
		vb2_sha512_finalize(&dc->sha512, digest);
		return VB2_SUCCESS;
#endif
	default:
		return VB2_ERROR_SHA_FINALIZE_ALGORITHM;
	}
}
