/*
 * Tcl binding for Monocypher (https://monocypher.org).
 *
 *   monocypher::random count
 *   monocypher::hash data ?-size n?
 *   monocypher::verify publicKey message signature
 *   monocypher::key ?-random | -bytes key | -password pw -salt salt
 *                    ?-memory KiB? ?-passes n? ?-secret bytes? ?-ad bytes??
 *       encrypt data ?-ad bytes?, decrypt box ?-ad bytes?,
 *       mac data ?-size n?, verify data mac, export
 *   monocypher::keypair ?-random | -bytes secret?
 *       public, sharedkey theirPublic, export
 *   monocypher::signer ?-random | -seed seed?
 *       public, sign message, export
 *
 * The classes keep their secrets in C, as TclOO object metadata that is
 * wiped when the object is destroyed.  Data in and out are byte arrays.
 */

#include <limits.h>
#include <stdlib.h>
#include <string.h>

/* kitsh defines BUILD_tcl on Windows, and Tcl 8.6's tcl.h then declares the
 * TclOO functions MODULE_SCOPE, which only tclInt.h defines */
#ifndef MODULE_SCOPE
#  define MODULE_SCOPE extern
#endif
#include <tcl.h>
#include <tclOO.h>

#include "monocypher/monocypher.h"
#include "monocypher/monocypher-ed25519.h"

#ifdef _WIN32
#  include <windows.h>
#  include <bcrypt.h>
#elif defined(HAVE_GETENTROPY)
#  include <unistd.h>
#  ifdef HAVE_SYS_RANDOM_H
#    include <sys/random.h>
#  endif
#else
#  include <errno.h>
#  include <fcntl.h>
#  include <unistd.h>
#endif

/* Tcl 8.6 compatibility for Tcl 9 Tcl_Size type */
#ifndef TCL_SIZE_MAX
#  ifndef Tcl_Size
     typedef int Tcl_Size;
#  endif
#  define TCL_SIZE_MAX INT_MAX
#endif

#define KEY_SIZE      32
#define NONCE_SIZE    24
#define TAG_SIZE      16
#define BOX_VERSION   1
#define BOX_OVERHEAD  (1 + NONCE_SIZE + TAG_SIZE)

/* Argon2id defaults: RFC 9106, section 4, second recommended option */
#define ARGON2_MEMORY 65536
#define ARGON2_PASSES 3
#define ARGON2_LANES  4

typedef struct {
	uint8_t secret[64];
	uint8_t public[32];
} Secret;

static void
SecretDelete(
	void *metadata)
{
	crypto_wipe(metadata, sizeof(Secret));
	Tcl_Free((char *) metadata);
}

static int
SecretClone(
	Tcl_Interp *interp,
	void *srcMetadata,
	void **dstMetadataPtr)
{
	Secret *copy = (Secret *) Tcl_Alloc(sizeof(Secret));

	(void) interp;
	memcpy(copy, srcMetadata, sizeof(Secret));
	*dstMetadataPtr = copy;

	return TCL_OK;
}

/* Without a cloneProc, oo::copy would share the pointer and free it twice */
static const Tcl_ObjectMetadataType secretType = {
	TCL_OO_METADATA_VERSION_CURRENT, "monocypher secret", SecretDelete, SecretClone
};

static int
Error(
	Tcl_Interp *interp,
	const char *kind,
	const char *message)
{
	Tcl_SetObjResult(interp, Tcl_NewStringObj(message, -1));
	Tcl_SetErrorCode(interp, "MONOCYPHER", kind, (char *) NULL);

	return TCL_ERROR;
}

static int
LengthError(
	Tcl_Interp *interp,
	const char *what,
	int expected,
	Tcl_Size actual)
{
	Tcl_SetObjResult(interp, Tcl_ObjPrintf("%s must be %d bytes, got %ld",
		what, expected, (long) actual));
	Tcl_SetErrorCode(interp, "MONOCYPHER", "LENGTH", (char *) NULL);

	return TCL_ERROR;
}

/*
 * The bytes of a byte array value.  Tcl 9 refuses values with characters
 * above U+00FF (Tcl_GetBytesFromObj); Tcl 8.6 would silently keep each
 * character's low byte, so refuse them there too, with Tcl 9's message
 * (generic/tclBinary.c).
 */
static unsigned char *
GetBytes(
	Tcl_Interp *interp,
	Tcl_Obj *objPtr,
	Tcl_Size *lengthPtr)
{
#if TCL_MAJOR_VERSION >= 9
	return Tcl_GetBytesFromObj(interp, objPtr, lengthPtr);
#else
	static const Tcl_ObjType *byteArrayType = NULL;
	const char *string, *p, *end;
	Tcl_UniChar ch = 0;
	int length, index;

	if (byteArrayType == NULL) {
		byteArrayType = Tcl_GetObjType("bytearray");
	}

	if (objPtr->typePtr != byteArrayType) {
		string = Tcl_GetStringFromObj(objPtr, &length);
		end = string + length;
		for (p = string, index = 0; p < end; index++) {
			p += Tcl_UtfToUniChar(p, &ch);
			if (ch > 0xFF) {
				Tcl_SetObjResult(interp, Tcl_ObjPrintf(
					"expected code point values below 0xff but value at byte offset %d was 0x%x",
					index, (unsigned) ch));
				Tcl_SetErrorCode(interp, "TCL", "VALUE", "BYTES", (char *) NULL);

				return NULL;
			}
		}
	}

	return Tcl_GetByteArrayFromObj(objPtr, lengthPtr);
#endif
}

static int
GetSize(
	Tcl_Interp *interp,
	Tcl_Obj *objPtr,
	int min,
	int max,
	int *sizePtr)
{
	if (Tcl_GetIntFromObj(interp, objPtr, sizePtr) != TCL_OK) {
		return TCL_ERROR;
	}

	if (*sizePtr < min || *sizePtr > max) {
		Tcl_SetObjResult(interp, Tcl_ObjPrintf("size must be from %d to %d, got %d",
			min, max, *sizePtr));
		Tcl_SetErrorCode(interp, "MONOCYPHER", "SIZE", (char *) NULL);

		return TCL_ERROR;
	}

	return TCL_OK;
}

static int
FillRandom(
	Tcl_Interp *interp,
	uint8_t *buffer,
	size_t length)
{
#ifdef _WIN32
	while (length > 0) {
		ULONG chunk = (length > 0x10000000) ? 0x10000000 : (ULONG) length;

		if (BCryptGenRandom(NULL, buffer, chunk, BCRYPT_USE_SYSTEM_PREFERRED_RNG) != 0) {
			return Error(interp, "RANDOM", "could not get random bytes from the system");
		}
		buffer += chunk;
		length -= chunk;
	}
#elif defined(HAVE_GETENTROPY)
	/* getentropy() returns at most 256 bytes per call */
	while (length > 0) {
		size_t chunk = (length > 256) ? 256 : length;

		if (getentropy(buffer, chunk) != 0) {
			return Error(interp, "RANDOM", "could not get random bytes from the system");
		}
		buffer += chunk;
		length -= chunk;
	}
#else
	int fd = open("/dev/urandom", O_RDONLY);

	if (fd < 0) {
		return Error(interp, "RANDOM", "could not open /dev/urandom");
	}
	while (length > 0) {
		ssize_t got = read(fd, buffer, length);

		if (got < 0 && errno == EINTR) {
			continue;
		}
		if (got <= 0) {
			close(fd);

			return Error(interp, "RANDOM", "could not read /dev/urandom");
		}
		buffer += got;
		length -= (size_t) got;
	}
	close(fd);
#endif

	return TCL_OK;
}

/*
 * Parses trailing "-option value" pairs against a table; values[i] is set
 * for each option given.
 */
static int
ParseOptions(
	Tcl_Interp *interp,
	int objc,
	Tcl_Obj *const objv[],
	const char *const options[],
	Tcl_Obj *values[])
{
	int i, index;

	for (i = 0; i < objc; i += 2) {
		if (Tcl_GetIndexFromObj(interp, objv[i], options, "option", 0, &index) != TCL_OK) {
			return TCL_ERROR;
		}
		if (i + 1 >= objc) {
			Tcl_SetObjResult(interp, Tcl_ObjPrintf("missing value for %s", options[index]));
			Tcl_SetErrorCode(interp, "TCL", "ARGUMENT", "MISSING", (char *) NULL);

			return TCL_ERROR;
		}
		values[index] = objv[i + 1];
	}

	return TCL_OK;
}

static Secret *
GetSecret(
	Tcl_ObjectContext context)
{
	return (Secret *) Tcl_ObjectGetMetadata(Tcl_ObjectContextObject(context), &secretType);
}

static void
SetSecret(
	Tcl_ObjectContext context,
	Secret *secret)
{
	Tcl_ObjectSetMetadata(Tcl_ObjectContextObject(context), &secretType, secret);
}

static Tcl_Obj *
NewBytes(
	const uint8_t *bytes,
	size_t length)
{
	return Tcl_NewByteArrayObj(bytes, (Tcl_Size) length);
}

/* Commands */

static int
RandomCmd(
	void *clientData,
	Tcl_Interp *interp,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Obj *resultPtr;
	int count;

	(void) clientData;
	if (objc != 2) {
		Tcl_WrongNumArgs(interp, 1, objv, "count");

		return TCL_ERROR;
	}
	if (GetSize(interp, objv[1], 0, INT_MAX, &count) != TCL_OK) {
		return TCL_ERROR;
	}

	resultPtr = Tcl_NewObj();
	if (FillRandom(interp, Tcl_SetByteArrayLength(resultPtr, count), (size_t) count) != TCL_OK) {
		Tcl_DecrRefCount(resultPtr);

		return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, resultPtr);

	return TCL_OK;
}

static int
HashCmd(
	void *clientData,
	Tcl_Interp *interp,
	int objc,
	Tcl_Obj *const objv[])
{
	static const char *const options[] = {"-size", NULL};
	Tcl_Obj *values[1] = {NULL};
	uint8_t hash[64];
	unsigned char *data;
	Tcl_Size length;
	int size = 64;

	(void) clientData;
	if (objc != 2 && objc != 4) {
		Tcl_WrongNumArgs(interp, 1, objv, "data ?-size n?");

		return TCL_ERROR;
	}
	if (ParseOptions(interp, objc - 2, objv + 2, options, values) != TCL_OK
			|| (values[0] != NULL && GetSize(interp, values[0], 1, 64, &size) != TCL_OK)
			|| (data = GetBytes(interp, objv[1], &length)) == NULL) {
		return TCL_ERROR;
	}

	crypto_blake2b(hash, (size_t) size, data, (size_t) length);
	Tcl_SetObjResult(interp, NewBytes(hash, (size_t) size));

	return TCL_OK;
}

static int
VerifyCmd(
	void *clientData,
	Tcl_Interp *interp,
	int objc,
	Tcl_Obj *const objv[])
{
	unsigned char *publicKey, *message, *signature;
	Tcl_Size publicLength, messageLength, signatureLength;

	(void) clientData;
	if (objc != 4) {
		Tcl_WrongNumArgs(interp, 1, objv, "publicKey message signature");

		return TCL_ERROR;
	}
	if ((publicKey = GetBytes(interp, objv[1], &publicLength)) == NULL
			|| (message = GetBytes(interp, objv[2], &messageLength)) == NULL
			|| (signature = GetBytes(interp, objv[3], &signatureLength)) == NULL) {
		return TCL_ERROR;
	}
	if (publicLength != 32) {
		return LengthError(interp, "public key", 32, publicLength);
	}
	if (signatureLength != 64) {
		return LengthError(interp, "signature", 64, signatureLength);
	}

	Tcl_SetObjResult(interp, Tcl_NewBooleanObj(
		crypto_ed25519_check(signature, publicKey, message, (size_t) messageLength) == 0));

	return TCL_OK;
}

/* monocypher::key */

static int
KeyConstructor(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	enum { OPT_AD, OPT_BYTES, OPT_MEMORY, OPT_PASSES, OPT_PASSWORD, OPT_RANDOM, OPT_SALT, OPT_SECRET };
	static const char *const options[] = {
		"-ad", "-bytes", "-memory", "-passes", "-password", "-random", "-salt", "-secret", NULL
	};
	Tcl_Obj *values[8] = {NULL, NULL, NULL, NULL, NULL, NULL, NULL, NULL};
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context);
	Secret *secret;
	int i, index, sources;

	(void) clientData;

	/* -random takes no value; the others are option-value pairs */
	for (i = (int) skip; i < objc; i++) {
		if (Tcl_GetIndexFromObj(interp, objv[i], options, "option", 0, &index) != TCL_OK) {
			return TCL_ERROR;
		}
		if (index == OPT_RANDOM) {
			values[OPT_RANDOM] = objv[i];
			continue;
		}
		if (++i >= objc) {
			Tcl_SetObjResult(interp, Tcl_ObjPrintf("missing value for %s", options[index]));
			Tcl_SetErrorCode(interp, "TCL", "ARGUMENT", "MISSING", (char *) NULL);

			return TCL_ERROR;
		}
		values[index] = objv[i];
	}

	sources = (values[OPT_RANDOM] != NULL) + (values[OPT_BYTES] != NULL)
		+ (values[OPT_PASSWORD] != NULL);
	if (sources > 1) {
		return Error(interp, "ARGUMENT", "use only one of -random, -bytes and -password");
	}
	if (values[OPT_PASSWORD] == NULL && (values[OPT_SALT] != NULL || values[OPT_MEMORY] != NULL
			|| values[OPT_PASSES] != NULL || values[OPT_SECRET] != NULL || values[OPT_AD] != NULL)) {
		return Error(interp, "ARGUMENT", "-salt, -memory, -passes, -secret and -ad need -password");
	}

	secret = (Secret *) Tcl_Alloc(sizeof(Secret));
	memset(secret, 0, sizeof(Secret));

	if (values[OPT_BYTES] != NULL) {
		unsigned char *bytes;
		Tcl_Size length;

		if ((bytes = GetBytes(interp, values[OPT_BYTES], &length)) == NULL) {
			goto error;
		}
		if (length != KEY_SIZE) {
			LengthError(interp, "key", KEY_SIZE, length);
			goto error;
		}
		memcpy(secret->secret, bytes, KEY_SIZE);
	} else if (values[OPT_PASSWORD] != NULL) {
		crypto_argon2_config config;
		crypto_argon2_inputs inputs;
		crypto_argon2_extras extras;
		unsigned char *password, *salt, *pepper = NULL, *ad = NULL;
		Tcl_Size passwordLength, saltLength, pepperLength = 0, adLength = 0;
		int memory = ARGON2_MEMORY, passes = ARGON2_PASSES;
		void *workArea;

		if (values[OPT_SALT] == NULL) {
			Error(interp, "ARGUMENT", "-password needs -salt");
			goto error;
		}
		if ((password = GetBytes(interp, values[OPT_PASSWORD], &passwordLength)) == NULL
				|| (salt = GetBytes(interp, values[OPT_SALT], &saltLength)) == NULL
				|| (values[OPT_MEMORY] != NULL && GetSize(interp, values[OPT_MEMORY],
					8 * ARGON2_LANES, INT_MAX / 1024, &memory) != TCL_OK)
				|| (values[OPT_PASSES] != NULL && GetSize(interp, values[OPT_PASSES],
					1, INT_MAX, &passes) != TCL_OK)
				|| (values[OPT_SECRET] != NULL
					&& (pepper = GetBytes(interp, values[OPT_SECRET], &pepperLength)) == NULL)
				|| (values[OPT_AD] != NULL
					&& (ad = GetBytes(interp, values[OPT_AD], &adLength)) == NULL)) {
			goto error;
		}
		if (saltLength < 8) {
			Error(interp, "LENGTH", "salt must be at least 8 bytes");
			goto error;
		}

		workArea = Tcl_AttemptAlloc((size_t) memory * 1024);
		if (workArea == NULL) {
			Error(interp, "MEMORY", "not enough memory for -memory");
			goto error;
		}

		config.algorithm = CRYPTO_ARGON2_ID;
		config.nb_blocks = (uint32_t) memory;
		config.nb_passes = (uint32_t) passes;
		config.nb_lanes = ARGON2_LANES;
		inputs.pass = password;
		inputs.salt = salt;
		inputs.pass_size = (uint32_t) passwordLength;
		inputs.salt_size = (uint32_t) saltLength;
		extras.key = pepper;
		extras.ad = ad;
		extras.key_size = (uint32_t) pepperLength;
		extras.ad_size = (uint32_t) adLength;
		crypto_argon2(secret->secret, KEY_SIZE, workArea, config, inputs, extras);

		crypto_wipe(workArea, (size_t) memory * 1024);
		Tcl_Free((char *) workArea);
	} else if (FillRandom(interp, secret->secret, KEY_SIZE) != TCL_OK) {
		goto error;
	}

	SetSecret(context, secret);

	return TCL_OK;

  error:
	SecretDelete(secret);

	return TCL_ERROR;
}

static int
KeyEncrypt(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	static const char *const options[] = {"-ad", NULL};
	Tcl_Obj *values[1] = {NULL}, *resultPtr;
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length, adLength = 0;
	unsigned char *data, *ad = NULL;
	uint8_t *box;
	Secret *secret = GetSecret(context);

	(void) clientData;
	if (objc != skip + 1 && objc != skip + 3) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "data ?-ad bytes?");

		return TCL_ERROR;
	}
	if (ParseOptions(interp, objc - (int) skip - 1, objv + skip + 1, options, values) != TCL_OK
			|| (data = GetBytes(interp, objv[skip], &length)) == NULL
			|| (values[0] != NULL && (ad = GetBytes(interp, values[0], &adLength)) == NULL)) {
		return TCL_ERROR;
	}
	if (length > TCL_SIZE_MAX - BOX_OVERHEAD) {
		return Error(interp, "LENGTH", "data too long");
	}

	/* version, nonce, tag, ciphertext */
	resultPtr = Tcl_NewObj();
	box = Tcl_SetByteArrayLength(resultPtr, length + BOX_OVERHEAD);
	box[0] = BOX_VERSION;
	if (FillRandom(interp, box + 1, NONCE_SIZE) != TCL_OK) {
		Tcl_DecrRefCount(resultPtr);

		return TCL_ERROR;
	}
	crypto_aead_lock(box + BOX_OVERHEAD, box + 1 + NONCE_SIZE, secret->secret, box + 1,
		ad, (size_t) adLength, data, (size_t) length);
	Tcl_SetObjResult(interp, resultPtr);

	return TCL_OK;
}

static int
KeyDecrypt(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	static const char *const options[] = {"-ad", NULL};
	Tcl_Obj *values[1] = {NULL}, *resultPtr;
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length, adLength = 0;
	unsigned char *box, *ad = NULL;
	uint8_t *plain;
	Secret *secret = GetSecret(context);

	(void) clientData;
	if (objc != skip + 1 && objc != skip + 3) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "box ?-ad bytes?");

		return TCL_ERROR;
	}
	if (ParseOptions(interp, objc - (int) skip - 1, objv + skip + 1, options, values) != TCL_OK
			|| (box = GetBytes(interp, objv[skip], &length)) == NULL
			|| (values[0] != NULL && (ad = GetBytes(interp, values[0], &adLength)) == NULL)) {
		return TCL_ERROR;
	}
	if (length < BOX_OVERHEAD || box[0] != BOX_VERSION) {
		return Error(interp, "DECRYPT", "not an encrypted box");
	}

	resultPtr = Tcl_NewObj();
	plain = Tcl_SetByteArrayLength(resultPtr, length - BOX_OVERHEAD);
	if (crypto_aead_unlock(plain, box + 1 + NONCE_SIZE, secret->secret, box + 1,
			ad, (size_t) adLength, box + BOX_OVERHEAD, (size_t) (length - BOX_OVERHEAD)) != 0) {
		Tcl_DecrRefCount(resultPtr);

		return Error(interp, "DECRYPT", "wrong key or associated data, or the box was changed");
	}
	Tcl_SetObjResult(interp, resultPtr);

	return TCL_OK;
}

static int
KeyMac(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	static const char *const options[] = {"-size", NULL};
	Tcl_Obj *values[1] = {NULL};
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length;
	unsigned char *data;
	uint8_t mac[64];
	int size = 64;
	Secret *secret = GetSecret(context);

	(void) clientData;
	if (objc != skip + 1 && objc != skip + 3) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "data ?-size n?");

		return TCL_ERROR;
	}
	if (ParseOptions(interp, objc - (int) skip - 1, objv + skip + 1, options, values) != TCL_OK
			|| (values[0] != NULL && GetSize(interp, values[0], 1, 64, &size) != TCL_OK)
			|| (data = GetBytes(interp, objv[skip], &length)) == NULL) {
		return TCL_ERROR;
	}

	crypto_blake2b_keyed(mac, (size_t) size, secret->secret, KEY_SIZE, data, (size_t) length);
	Tcl_SetObjResult(interp, NewBytes(mac, (size_t) size));

	return TCL_OK;
}

static int
KeyVerify(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length, macLength, i;
	unsigned char *data, *given;
	uint8_t mac[64], difference = 0;
	Secret *secret = GetSecret(context);

	(void) clientData;
	if (objc != skip + 2) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "data mac");

		return TCL_ERROR;
	}
	if ((data = GetBytes(interp, objv[skip], &length)) == NULL
			|| (given = GetBytes(interp, objv[skip + 1], &macLength)) == NULL) {
		return TCL_ERROR;
	}
	if (macLength < 1 || macLength > 64) {
		return Error(interp, "LENGTH", "mac must be 1 to 64 bytes");
	}

	/* Compared in constant time */
	crypto_blake2b_keyed(mac, (size_t) macLength, secret->secret, KEY_SIZE, data, (size_t) length);
	for (i = 0; i < macLength; i++) {
		difference |= mac[i] ^ given[i];
	}
	Tcl_SetObjResult(interp, Tcl_NewBooleanObj(difference == 0));

	return TCL_OK;
}

static int
SecretExport(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context);

	(void) clientData;
	if (objc != skip) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, NULL);

		return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, NewBytes(GetSecret(context)->secret, KEY_SIZE));

	return TCL_OK;
}

static int
SecretPublic(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context);

	(void) clientData;
	if (objc != skip) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, NULL);

		return TCL_ERROR;
	}
	Tcl_SetObjResult(interp, NewBytes(GetSecret(context)->public, 32));

	return TCL_OK;
}

/*
 * Constructor arguments for keypair and signer: nothing or "-random", or the
 * option in options[1] (-bytes, -seed) with 32 bytes.  Leaves the 32 secret
 * bytes in secret->secret.
 */
static const char *const keypairOptions[] = {"-random", "-bytes", NULL};
static const char *const signerOptions[] = {"-random", "-seed", NULL};

static int
ParseSecretSource(
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[],
	const char *const options[],
	Secret *secret)
{
	const char *bytesOption = options[1];
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length;
	unsigned char *bytes;
	int index;

	if (objc == skip) {
		return FillRandom(interp, secret->secret, 32);
	}
	if (Tcl_GetIndexFromObj(interp, objv[skip], options, "option", 0, &index) != TCL_OK) {
		return TCL_ERROR;
	}
	if (index == 0 && objc == skip + 1) {
		return FillRandom(interp, secret->secret, 32);
	}
	if (index == 1 && objc == skip + 2) {
		if ((bytes = GetBytes(interp, objv[skip + 1], &length)) == NULL) {
			return TCL_ERROR;
		}
		if (length != 32) {
			return LengthError(interp, bytesOption + 1, 32, length);
		}
		memcpy(secret->secret, bytes, 32);

		return TCL_OK;
	}

	Tcl_WrongNumArgs(interp, (int) skip, objv, Tcl_GetString(Tcl_ObjPrintf("?-random | %s bytes?", bytesOption)));

	return TCL_ERROR;
}

/* monocypher::keypair */

static int
KeypairConstructor(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Secret *secret = (Secret *) Tcl_Alloc(sizeof(Secret));

	(void) clientData;
	memset(secret, 0, sizeof(Secret));
	if (ParseSecretSource(interp, context, objc, objv, keypairOptions, secret) != TCL_OK) {
		SecretDelete(secret);

		return TCL_ERROR;
	}
	crypto_x25519_public_key(secret->public, secret->secret);
	SetSecret(context, secret);

	return TCL_OK;
}

/*
 * The shared secret hashed with both public keys, as in
 * crypto_x25519(3monocypher); the keys in sorted order, so both sides get the
 * same key.  Returns a new monocypher::key object (clientData is its class).
 */
static int
KeypairSharedKey(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Class keyClass = (Tcl_Class) clientData;
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length;
	unsigned char *theirs;
	const uint8_t *first, *second;
	uint8_t shared[32], zero[32];
	crypto_blake2b_ctx hash;
	Secret *secret = GetSecret(context), *derived;
	Tcl_Object keyObject;

	if (objc != skip + 1) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "theirPublic");

		return TCL_ERROR;
	}
	if ((theirs = GetBytes(interp, objv[skip], &length)) == NULL) {
		return TCL_ERROR;
	}
	if (length != 32) {
		return LengthError(interp, "public key", 32, length);
	}

	crypto_x25519(shared, secret->secret, theirs);
	memset(zero, 0, sizeof(zero));
	if (crypto_verify32(shared, zero) == 0) {
		return Error(interp, "KEYEXCHANGE", "invalid public key");
	}

	if (memcmp(secret->public, theirs, 32) <= 0) {
		first = secret->public;
		second = theirs;
	} else {
		first = theirs;
		second = secret->public;
	}

	keyObject = Tcl_NewObjectInstance(interp, keyClass, NULL, NULL, 0, NULL, 0);
	if (keyObject == NULL) {
		crypto_wipe(shared, sizeof(shared));

		return TCL_ERROR;
	}

	derived = (Secret *) Tcl_Alloc(sizeof(Secret));
	memset(derived, 0, sizeof(Secret));
	crypto_blake2b_init(&hash, KEY_SIZE);
	crypto_blake2b_update(&hash, shared, sizeof(shared));
	crypto_blake2b_update(&hash, first, 32);
	crypto_blake2b_update(&hash, second, 32);
	crypto_blake2b_final(&hash, derived->secret);
	crypto_wipe(shared, sizeof(shared));

	/* Replaces (and wipes) the random key the constructor made */
	Tcl_ObjectSetMetadata(keyObject, &secretType, derived);
	Tcl_SetObjResult(interp, Tcl_GetObjectName(interp, keyObject));

	return TCL_OK;
}

/* monocypher::signer */

static int
SignerConstructor(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Secret *secret = (Secret *) Tcl_Alloc(sizeof(Secret));
	uint8_t seed[32];

	(void) clientData;
	memset(secret, 0, sizeof(Secret));
	if (ParseSecretSource(interp, context, objc, objv, signerOptions, secret) != TCL_OK) {
		SecretDelete(secret);

		return TCL_ERROR;
	}

	/* crypto_ed25519_key_pair wipes the seed it is given, and writes the
	 * 64-byte secret key (seed, then public key) */
	memcpy(seed, secret->secret, 32);
	crypto_ed25519_key_pair(secret->secret, secret->public, seed);
	SetSecret(context, secret);

	return TCL_OK;
}

static int
SignerSign(
	void *clientData,
	Tcl_Interp *interp,
	Tcl_ObjectContext context,
	int objc,
	Tcl_Obj *const objv[])
{
	Tcl_Size skip = Tcl_ObjectContextSkippedArgs(context), length;
	unsigned char *message;
	uint8_t signature[64];

	(void) clientData;
	if (objc != skip + 1) {
		Tcl_WrongNumArgs(interp, (int) skip, objv, "message");

		return TCL_ERROR;
	}
	if ((message = GetBytes(interp, objv[skip], &length)) == NULL) {
		return TCL_ERROR;
	}

	crypto_ed25519_sign(signature, GetSecret(context)->secret, message, (size_t) length);
	Tcl_SetObjResult(interp, NewBytes(signature, sizeof(signature)));

	return TCL_OK;
}

/* Initialisation */

typedef struct {
	const char *name;
	Tcl_MethodCallProc *proc;
} MethodDef;

static const Tcl_MethodType keyConstructorType = {TCL_OO_METHOD_VERSION_CURRENT, "constructor", KeyConstructor, NULL, NULL};
static const Tcl_MethodType keypairConstructorType = {TCL_OO_METHOD_VERSION_CURRENT, "constructor", KeypairConstructor, NULL, NULL};
static const Tcl_MethodType signerConstructorType = {TCL_OO_METHOD_VERSION_CURRENT, "constructor", SignerConstructor, NULL, NULL};

#define METHOD_TYPE(var, name, proc) \
	static const Tcl_MethodType var = {TCL_OO_METHOD_VERSION_CURRENT, name, proc, NULL, NULL}

METHOD_TYPE(encryptType, "encrypt", KeyEncrypt);
METHOD_TYPE(decryptType, "decrypt", KeyDecrypt);
METHOD_TYPE(macType, "mac", KeyMac);
METHOD_TYPE(verifyType, "verify", KeyVerify);
METHOD_TYPE(exportType, "export", SecretExport);
METHOD_TYPE(publicType, "public", SecretPublic);
METHOD_TYPE(sharedkeyType, "sharedkey", KeypairSharedKey);
METHOD_TYPE(signType, "sign", SignerSign);

static Tcl_Class
CreateClass(
	Tcl_Interp *interp,
	const char *name,
	const Tcl_MethodType *constructor,
	const Tcl_MethodType *const methods[],
	void *clientData)
{
	Tcl_Object object;
	Tcl_Class classPtr;
	int i;

	if (Tcl_EvalObjEx(interp, Tcl_ObjPrintf("::oo::class create %s", name), 0) != TCL_OK) {
		return NULL;
	}
	object = Tcl_GetObjectFromObj(interp, Tcl_GetObjResult(interp));
	if (object == NULL) {
		return NULL;
	}
	classPtr = Tcl_GetObjectAsClass(object);

	Tcl_ClassSetConstructor(interp, classPtr, Tcl_NewMethod(interp, classPtr, NULL, 1, constructor, NULL));
	for (i = 0; methods[i] != NULL; i++) {
		Tcl_NewMethod(interp, classPtr, Tcl_NewStringObj(methods[i]->name, -1), 1, methods[i], clientData);
	}
	Tcl_ResetResult(interp);

	return classPtr;
}

int
Monocypher_Init(
	Tcl_Interp *interp)
{
	static const Tcl_MethodType *const keyMethods[] = {
		&encryptType, &decryptType, &macType, &verifyType, &exportType, NULL
	};
	static const Tcl_MethodType *const keypairMethods[] = {&publicType, &sharedkeyType, &exportType, NULL};
	static const Tcl_MethodType *const signerMethods[] = {&publicType, &signType, &exportType, NULL};
	Tcl_Class keyClass;

	if (Tcl_OOInitStubs(interp) == NULL) {
		return TCL_ERROR;
	}

	if (Tcl_CreateNamespace(interp, "::monocypher", NULL, NULL) == NULL) {
		return TCL_ERROR;
	}
	Tcl_CreateObjCommand(interp, "::monocypher::random", RandomCmd, NULL, NULL);
	Tcl_CreateObjCommand(interp, "::monocypher::hash", HashCmd, NULL, NULL);
	Tcl_CreateObjCommand(interp, "::monocypher::verify", VerifyCmd, NULL, NULL);

	keyClass = CreateClass(interp, "::monocypher::key", &keyConstructorType, keyMethods, NULL);
	if (keyClass == NULL
			|| CreateClass(interp, "::monocypher::keypair", &keypairConstructorType, keypairMethods, keyClass) == NULL
			|| CreateClass(interp, "::monocypher::signer", &signerConstructorType, signerMethods, NULL) == NULL) {
		return TCL_ERROR;
	}

	return Tcl_PkgProvide(interp, "monocypher", KIT_MONOCYPHER_VERSION);
}
