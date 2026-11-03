#include <tcl.h>

#ifdef HAVE_STDLIB_H
#  include <stdlib.h>
#endif
#ifdef CVFS_ENCRYPTED
#  include <errno.h>
#  include <stdio.h>
#endif

typedef struct cvfs_data *(cmd_getData_t)(const char *, unsigned long);
typedef unsigned long (cmd_getChildren_t)(const char *, unsigned long *, unsigned long);

/* Your implementation must provide these; getCmdKey gives the key of an
 * encrypted VFS, or NULL */
static cmd_getData_t *getCmdData(const char *hashkey);
static cmd_getChildren_t *getCmdChildren(const char *hashkey);
static const unsigned char *getCmdKey(const char *hashkey);

/* Guards the one-time inflate of each file's shared data */
TCL_DECLARE_MUTEX(cvfsDataMutex)

#ifdef CVFS_ENCRYPTED
/* Leaves message in interp, with the error code {CVFS code} */
static void cvfs_error(Tcl_Interp *interp, const char *message, const char *code) {
	Tcl_SetObjResult(interp, Tcl_NewStringObj(message, -1));
	Tcl_SetErrorCode(interp, "CVFS", code, (char *) NULL);
}

/* Decrypts, and inflates if compressed, an encrypted file into a new byte
 * array of size_inflated bytes with a reference held, for cvfs_free_plain;
 * NULL with an error in interp if the file does not decrypt or inflate.
 * Nothing is returned before the tag check has passed.  Tcl_ZlibInflate is
 * given the exact size, so it allocates its output once; zlib's own window
 * (up to the last 32 KB of output) is freed without wiping */
static Tcl_Obj *cvfs_decode_encrypted(Tcl_Interp *interp, const char *path, const struct cvfs_data *finfo, const unsigned char *key) {
	Tcl_Obj *plain, *inflated, *ad;
	Tcl_Size length;
	int status;

	if (finfo->size < CVFS_BOX_OVERHEAD) {
		cvfs_error(interp, "Could not decrypt file", "DECRYPT");

		return(NULL);
	}

	plain = Tcl_NewByteArrayObj(NULL, finfo->size - CVFS_BOX_OVERHEAD);
	Tcl_IncrRefCount(plain);
	ad = Tcl_ObjPrintf("data:%" TCL_SIZE_MODIFIER "d:%s", finfo->size_inflated, path);
	Tcl_IncrRefCount(ad);

	status = cvfs_box_open(Tcl_GetByteArrayFromObj(plain, NULL), finfo->data, finfo->size, key, ad);
	Tcl_DecrRefCount(ad);
	if (status != 0) {
		Tcl_DecrRefCount(plain);
		cvfs_error(interp, "Could not decrypt file", "DECRYPT");

		return(NULL);
	}

	if ((finfo->type & CVFS_FILETYPE_COMPRESSED_FILE) == 0) {
		Tcl_GetByteArrayFromObj(plain, &length);
		if (length != finfo->size_inflated) {
			cvfs_free_plain(plain);
			cvfs_error(interp, "Could not decrypt file", "DECRYPT");

			return(NULL);
		}

		return(plain);
	}

	status = Tcl_ZlibInflate(interp, TCL_ZLIB_FORMAT_ZLIB, plain, finfo->size_inflated, NULL);
	cvfs_free_plain(plain);
	if (status != TCL_OK) {
		cvfs_error(interp, "Could not decompress file", "DECOMPRESS");

		return(NULL);
	}

	inflated = Tcl_GetObjResult(interp);
	Tcl_IncrRefCount(inflated);
	Tcl_ResetResult(interp);

	Tcl_GetByteArrayFromObj(inflated, &length);
	if (length != finfo->size_inflated) {
		cvfs_free_plain(inflated);
		cvfs_error(interp, "Could not decompress file", "DECOMPRESS");

		return(NULL);
	}

	return(inflated);
}

/* A read-only channel on a plaintext byte array, which an encrypted VFS's
 * open command hands over and close wipes.  Reads use bytes, taken at open,
 * and only close touches the Tcl value, so the channel can move between
 * threads.  Seeks behave as for a native file; the data is always readable,
 * so readable events come from a timer (CrtChannel.3) */
#  define CVFS_WIDE_MAX ((Tcl_WideInt) (~(Tcl_WideUInt) 0 >> 1))

struct cvfs_channel {
	Tcl_Channel              channel;
	Tcl_Obj *                data;
	const unsigned char *    bytes;
	Tcl_WideInt              size;
	Tcl_WideInt              position;
	Tcl_TimerToken           timer;
};

static int cvfs_channel_input(void *instance, char *buffer, int buffer_size, int *error_code) {
	struct cvfs_channel *chan = instance;
	Tcl_WideInt count = 0;

	if (chan->position < chan->size) {
		count = chan->size - chan->position;
		if (count > buffer_size) {
			count = buffer_size;
		}

		memcpy(buffer, chan->bytes + chan->position, (size_t) count);
		chan->position += count;
	}

	return((int) count);
}

static Tcl_WideInt cvfs_channel_wide_seek(void *instance, Tcl_WideInt offset, int mode, int *error_code) {
	struct cvfs_channel *chan = instance;
	Tcl_WideInt base;

	switch (mode) {
		case SEEK_SET:
			base = 0;
			break;
		case SEEK_CUR:
			base = chan->position;
			break;
		case SEEK_END:
			base = chan->size;
			break;
		default:
			*error_code = EINVAL;

			return(-1);
	}

	if ((offset < 0 && base + offset < 0) || (offset > 0 && base > CVFS_WIDE_MAX - offset)) {
		*error_code = EINVAL;

		return(-1);
	}

	chan->position = base + offset;

	return(chan->position);
}

#  if TCL_MAJOR_VERSION < 9
/* Tcl 8.6 needs a seekProc as well as the wideSeekProc it prefers */
static int cvfs_channel_seek(void *instance, long offset, int mode, int *error_code) {
	return((int) cvfs_channel_wide_seek(instance, offset, mode, error_code));
}
#  endif

static void cvfs_channel_timer(void *instance) {
	struct cvfs_channel *chan = instance;

	/* The channel may be closed by the handlers Tcl_NotifyChannel runs */
	chan->timer = NULL;
	Tcl_NotifyChannel(chan->channel, TCL_READABLE);
}

static void cvfs_channel_watch(void *instance, int mask) {
	struct cvfs_channel *chan = instance;

	if ((mask & TCL_READABLE) != 0) {
		if (chan->timer == NULL) {
			chan->timer = Tcl_CreateTimerHandler(0, cvfs_channel_timer, chan);
		}
	} else if (chan->timer != NULL) {
		Tcl_DeleteTimerHandler(chan->timer);
		chan->timer = NULL;
	}
}

/* Timers belong to a thread; the next watch call in the new thread makes one */
static void cvfs_channel_thread_action(void *instance, int action) {
	struct cvfs_channel *chan = instance;

	if (action == TCL_CHANNEL_THREAD_REMOVE && chan->timer != NULL) {
		Tcl_DeleteTimerHandler(chan->timer);
		chan->timer = NULL;
	}
}

static int cvfs_channel_block_mode(void *instance, int mode) {
	return(0);
}

static int cvfs_channel_close2(void *instance, Tcl_Interp *interp, int flags) {
	struct cvfs_channel *chan = instance;

	if ((flags & (TCL_CLOSE_READ | TCL_CLOSE_WRITE)) != 0) {
		return(EINVAL);
	}

	if (chan->timer != NULL) {
		Tcl_DeleteTimerHandler(chan->timer);
	}

	cvfs_free_plain(chan->data);
	Tcl_Free((char *) chan);

	return(0);
}

static const Tcl_ChannelType cvfs_channel_type = {
	"cvfs",
	TCL_CHANNEL_VERSION_5,
	TCL_CLOSE2PROC,
	cvfs_channel_input,
	NULL,
#  if TCL_MAJOR_VERSION < 9
	cvfs_channel_seek,
#  else
	NULL,
#  endif
	NULL,
	NULL,
	cvfs_channel_watch,
	NULL,
	cvfs_channel_close2,
	cvfs_channel_block_mode,
	NULL,
	NULL,
	cvfs_channel_wide_seek,
	cvfs_channel_thread_action,
	NULL
};

TCL_DECLARE_MUTEX(cvfsChannelMutex)
#endif /* CVFS_ENCRYPTED */

/* POSIX link count of a directory: 2 plus one per subdirectory.  Call with
 * cvfsDataMutex held, as it reads the children's type fields. */
static unsigned long countDirectoryLinks(cmd_getData_t *cmd_getData, cmd_getChildren_t *cmd_getChildren, const char *file) {
	struct cvfs_data *child;
	unsigned long num_children, idx, links = 2;
	unsigned long *children;

	num_children = cmd_getChildren(file, NULL, 0);
	if (num_children == 0) {
		return(links);
	}

	children = (void *) Tcl_Alloc(sizeof(*children) * num_children);
	num_children = cmd_getChildren(file, children, num_children);

	for (idx = 0; idx < num_children; idx++) {
		child = cmd_getData(NULL, children[idx]);

		if (child != NULL && (child->type & CVFS_FILETYPE_DIR) == CVFS_FILETYPE_DIR) {
			links++;
		}
	}

	Tcl_Free((void *) children);

	return(links);
}

/* Tcl Commands */
static int getMetadata(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
	cmd_getData_t *cmd_getData;
	cmd_getChildren_t *cmd_getChildren;
	struct cvfs_data *finfo = NULL;
	Tcl_Obj *items[20];
	unsigned long nlink;
	const char *hashkey;
	const char *file;
	int is_dir;

	if (objc != 3) {
		Tcl_WrongNumArgs(interp, 1, objv, "hashKey fileName");

		return(TCL_ERROR);
	}

	hashkey = Tcl_GetString(objv[1]);
	file = Tcl_GetString(objv[2]);

	cmd_getData = getCmdData(hashkey);
	cmd_getChildren = getCmdChildren(hashkey);

	if (cmd_getData == NULL || cmd_getChildren == NULL) {
		Tcl_SetResult(interp, "No such hashkey", TCL_STATIC);

		return(TCL_ERROR);
	}

	finfo = cmd_getData(file, 0);

	if (finfo == NULL) {
		Tcl_SetResult(interp, "No such file or directory", TCL_STATIC);

		return(TCL_ERROR);
	}

	/* getData may be changing other bits of the same type field */
	Tcl_MutexLock(&cvfsDataMutex);
	is_dir = ((finfo->type & CVFS_FILETYPE_DIR) == CVFS_FILETYPE_DIR);
	nlink = is_dir ? countDirectoryLinks(cmd_getData, cmd_getChildren, file) : 1;
	Tcl_MutexUnlock(&cvfsDataMutex);

	items[0] = Tcl_NewStringObj("type", -1);
	items[1] = Tcl_NewStringObj(is_dir ? "directory" : "file", -1);
	items[2] = Tcl_NewStringObj("mode", -1);
	items[3] = Tcl_NewWideIntObj(is_dir ? 040555 : 0444);
	items[4] = Tcl_NewStringObj("nlink", -1);
	items[5] = Tcl_NewWideIntObj((Tcl_WideInt) nlink);
	items[6] = Tcl_NewStringObj("ino", -1);
	items[7] = Tcl_NewWideIntObj((Tcl_WideInt) finfo->index);
	items[8] = Tcl_NewStringObj("size", -1);
	items[9] = Tcl_NewWideIntObj(finfo->size_inflated);

	/* A virtual file has no owner */
	items[10] = Tcl_NewStringObj("uid", -1);
	items[11] = Tcl_NewWideIntObj(0);
	items[12] = Tcl_NewStringObj("gid", -1);
	items[13] = Tcl_NewWideIntObj(0);

	items[14] = Tcl_NewStringObj("atime", -1);
	items[15] = Tcl_NewWideIntObj(finfo->mtime);
	items[16] = Tcl_NewStringObj("mtime", -1);
	items[17] = Tcl_NewWideIntObj(finfo->mtime);
	items[18] = Tcl_NewStringObj("ctime", -1);
	items[19] = Tcl_NewWideIntObj(finfo->mtime);

	Tcl_SetObjResult(interp, Tcl_NewListObj(sizeof(items) / sizeof(items[0]), items));

	return(TCL_OK);
}

static int getData(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
	struct cvfs_data *finfo = NULL;
	cmd_getData_t *cmd_getData;
	const unsigned char *data;
	const char *hashkey;
	const char *file;
	const char *end_str;
	Tcl_WideInt start = 0;
	Tcl_WideInt end = -1;
	Tcl_WideInt size;
	int tclGetLFO_ret;
	Tcl_Obj *decompressed;
	Tcl_Size decompressed_len = 0;
	unsigned char *decompressed_bytes, *inflated;

	if (objc < 3 || objc > 5) {
		Tcl_WrongNumArgs(interp, 1, objv, "hashKey fileName ?start? ?end?");

		return(TCL_ERROR);
	}

	hashkey = Tcl_GetString(objv[1]);
	file = Tcl_GetString(objv[2]);

	if (objc > 3) {
		tclGetLFO_ret = Tcl_GetWideIntFromObj(interp, objv[3], &start);

		if (tclGetLFO_ret != TCL_OK) {
			return(tclGetLFO_ret);
		}
	}

	if (objc > 4) {
		end_str = Tcl_GetString(objv[4]);
		if (strcmp(end_str, "end") == 0) {
			end = -1;
		} else {
			tclGetLFO_ret = Tcl_GetWideIntFromObj(interp, objv[4], &end);

			if (tclGetLFO_ret != TCL_OK) {
				return(tclGetLFO_ret);
			}
		}
	}

	cmd_getData = getCmdData(hashkey);

	if (cmd_getData == NULL) {
		Tcl_SetResult(interp, "No such hashkey", TCL_STATIC);

		return(TCL_ERROR);
	}

	finfo = cmd_getData(file, 0);

	if (finfo == NULL) {
		Tcl_SetResult(interp, "No such file or directory", TCL_STATIC);

		return(TCL_ERROR);
	}

#ifdef CVFS_ENCRYPTED
	/* An encrypted file's type never changes, so it needs no lock */
	if ((finfo->type & CVFS_FILETYPE_ENCRYPTED_FILE) != 0) {
		Tcl_Obj *plain;

		plain = cvfs_decode_encrypted(interp, file, finfo, getCmdKey(hashkey));
		if (plain == NULL) {
			return(TCL_ERROR);
		}

		size = (Tcl_WideInt) finfo->size_inflated;
		if (end == -1 || end > size) {
			end = size;
		}
		if (start < 0) {
			start = 0;
		}
		if (end < 0) {
			end = 0;
		}
		if (end < start) {
			cvfs_free_plain(plain);
			Tcl_SetResult(interp, "Invalid arguments, start must be less than end", TCL_STATIC);

			return(TCL_ERROR);
		}

		Tcl_SetObjResult(interp, Tcl_NewByteArrayObj(Tcl_GetByteArrayFromObj(plain, NULL) + start, (Tcl_Size) (end - start)));
		cvfs_free_plain(plain);

		return(TCL_OK);
	}
#endif

	Tcl_MutexLock(&cvfsDataMutex);

	if ((finfo->type & CVFS_FILETYPE_FILE) == 0) {
		Tcl_MutexUnlock(&cvfsDataMutex);
		Tcl_SetResult(interp, "Not a file", TCL_STATIC);

		return(TCL_ERROR);
	}

	if ((finfo->type & CVFS_FILETYPE_COMPRESSED_FILE) == CVFS_FILETYPE_COMPRESSED_FILE) {
		decompressed = Tcl_NewByteArrayObj(finfo->data, finfo->size);
		Tcl_IncrRefCount(decompressed);

		if (Tcl_ZlibInflate(interp, TCL_ZLIB_FORMAT_AUTO,
				    decompressed, finfo->size_inflated, NULL) != TCL_OK) {
			Tcl_MutexUnlock(&cvfsDataMutex);
			Tcl_SetResult(interp, "Could not decompress file", TCL_STATIC);
			Tcl_DecrRefCount(decompressed);

			return(TCL_ERROR);
		}
		Tcl_DecrRefCount(decompressed);

		decompressed = Tcl_GetObjResult(interp);
		Tcl_IncrRefCount(decompressed);

		decompressed_bytes = Tcl_GetByteArrayFromObj(decompressed, &decompressed_len);
		inflated = (unsigned char *) Tcl_Alloc(decompressed_len ? decompressed_len : 1);
		memcpy(inflated, decompressed_bytes, (size_t) decompressed_len);
		Tcl_DecrRefCount(decompressed);

		/* data pointed at the compressed bytes in the generated table */
		finfo->data = inflated;
		finfo->free = 1;
		finfo->size = decompressed_len;
		finfo->type &= ~CVFS_FILETYPE_COMPRESSED_FILE;
	}

	/* Once decoded, a file's data and size never change again */
	Tcl_MutexUnlock(&cvfsDataMutex);

	size = (Tcl_WideInt) finfo->size;
	data = finfo->data;

	if (end == -1 || end > size) {
		end = size;
	}

	if (start < 0) {
		start = 0;
	}

	if (end < 0) {
		end = 0;
	}

	if (end < start) {
		Tcl_SetResult(interp, "Invalid arguments, start must be less than end", TCL_STATIC);

		return(TCL_ERROR);
	}

	Tcl_SetObjResult(interp, Tcl_NewByteArrayObj(data + start, (Tcl_Size) (end - start)));

	return(TCL_OK);
}

static int getChildren(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
	struct cvfs_data *finfo = NULL;
	cmd_getChildren_t *cmd_getChildren;
	cmd_getData_t *cmd_getData;
	unsigned long num_children, idx;
	unsigned long *children;
	const unsigned char *key;
	const char *hashkey;
	const char *file;
	Tcl_Obj *ret_list, *ret_curr_obj;

	if (objc != 3) {
		Tcl_WrongNumArgs(interp, 1, objv, "hashKey fileName");

		return(TCL_ERROR);
	}

	hashkey = Tcl_GetString(objv[1]);
	file = Tcl_GetString(objv[2]);

	cmd_getData = getCmdData(hashkey);
	cmd_getChildren = getCmdChildren(hashkey);
	key = getCmdKey(hashkey);
#ifndef CVFS_ENCRYPTED
	(void) key;
#endif

	if (cmd_getData == NULL || cmd_getChildren == NULL) {
		Tcl_SetResult(interp, "No such hashkey", TCL_STATIC);

		return(TCL_ERROR);
	}

	finfo = cmd_getData(file, 0);

	if (finfo == NULL) {
		Tcl_SetResult(interp, "No such file or directory", TCL_STATIC);

		return(TCL_ERROR);
	}

	/* getData may be changing other bits of the type fields read here */
	Tcl_MutexLock(&cvfsDataMutex);

	if ((finfo->type & CVFS_FILETYPE_DIR) == 0) {
		Tcl_MutexUnlock(&cvfsDataMutex);
		Tcl_SetResult(interp, "Not a directory", TCL_STATIC);

		return(TCL_ERROR);
	}

	num_children = cmd_getChildren(file, NULL, 0);

	if (num_children == 0) {
		Tcl_MutexUnlock(&cvfsDataMutex);
		Tcl_ResetResult(interp);

		return(TCL_OK);
	}

	ret_list = Tcl_NewListObj(0, NULL);

	children = (void *) Tcl_Alloc(sizeof(*children) * num_children);

	num_children = cmd_getChildren(file, children, num_children);

	Tcl_MutexUnlock(&cvfsDataMutex);

	for (idx = 0; idx < num_children; idx++) {
		finfo = cmd_getData(NULL, children[idx]);

		if (finfo == NULL) {
			continue;
		}

#ifdef CVFS_ENCRYPTED
		if (key != NULL) {
			Tcl_Obj *name;
			Tcl_Size name_length;
			const unsigned char *name_bytes;

			name = cvfs_name(finfo, key);
			if (name == NULL) {
				continue;
			}

			name_bytes = Tcl_GetByteArrayFromObj(name, &name_length);
			ret_curr_obj = Tcl_NewStringObj((const char *) name_bytes, name_length);
			cvfs_free_plain(name);
		} else
#endif
		{
			if (finfo->name == NULL) {
				continue;
			}

			ret_curr_obj = Tcl_NewStringObj(finfo->name, -1);
		}

		Tcl_ListObjAppendElement(NULL, ret_list, ret_curr_obj);
	}

	Tcl_Free((void *) children);

	Tcl_SetObjResult(interp, ret_list);

	return(TCL_OK);
}

#ifdef CVFS_ENCRYPTED
/* open hashKey fileName: a read-only channel on the file's plaintext, which
 * is wiped when the channel closes.  Each VFS has its own counter, so the
 * name includes the hash key: Tcl panics on a duplicate channel name */
static int openFile(ClientData cd, Tcl_Interp *interp, int objc, Tcl_Obj *const objv[]) {
	static unsigned long channel_count = 0;
	struct cvfs_channel *chan;
	struct cvfs_data *finfo;
	cmd_getData_t *cmd_getData;
	const unsigned char *key;
	const char *hashkey;
	const char *file;
	Tcl_Obj *plain, *name;

	if (objc != 3) {
		Tcl_WrongNumArgs(interp, 1, objv, "hashKey fileName");

		return(TCL_ERROR);
	}

	hashkey = Tcl_GetString(objv[1]);
	file = Tcl_GetString(objv[2]);

	cmd_getData = getCmdData(hashkey);
	key = getCmdKey(hashkey);

	if (cmd_getData == NULL || key == NULL) {
		Tcl_SetResult(interp, "No such hashkey", TCL_STATIC);

		return(TCL_ERROR);
	}

	finfo = cmd_getData(file, 0);

	if (finfo == NULL) {
		Tcl_SetResult(interp, "No such file or directory", TCL_STATIC);

		return(TCL_ERROR);
	}

	if ((finfo->type & CVFS_FILETYPE_FILE) == 0 || (finfo->type & CVFS_FILETYPE_ENCRYPTED_FILE) == 0) {
		Tcl_SetResult(interp, "Not a file", TCL_STATIC);

		return(TCL_ERROR);
	}

	plain = cvfs_decode_encrypted(interp, file, finfo, key);
	if (plain == NULL) {
		return(TCL_ERROR);
	}

	chan = (struct cvfs_channel *) Tcl_Alloc(sizeof(*chan));
	chan->data = plain;
	chan->bytes = Tcl_GetByteArrayFromObj(plain, NULL);
	chan->size = (Tcl_WideInt) finfo->size_inflated;
	chan->position = 0;
	chan->timer = NULL;

	Tcl_MutexLock(&cvfsChannelMutex);
	name = Tcl_ObjPrintf("cvfs%s%lu", hashkey, channel_count++);
	Tcl_MutexUnlock(&cvfsChannelMutex);

	chan->channel = Tcl_CreateChannel(&cvfs_channel_type, Tcl_GetString(name), chan, TCL_READABLE);
	Tcl_RegisterChannel(interp, chan->channel);
	Tcl_SetObjResult(interp, name);

	return(TCL_OK);
}
#endif
