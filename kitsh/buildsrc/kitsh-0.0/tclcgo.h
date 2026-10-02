#ifndef TCLCGO_H
#define TCLCGO_H

/*
 * Shared cgo glue for Go extensions.
 *
 * cgo cannot call C macros or express const pointer types. Every Tcl API
 * that is a macro in any supported Tcl version or build configuration has
 * a cgo_<Tcl function> wrapper here, with the documented parameters, that
 * just calls the Tcl function and lets the preprocessor pick the expansion.
 */

#include <tcl.h>

#ifndef TCL_SIZE_MAX
#  ifndef Tcl_Size
     typedef int Tcl_Size;
#  endif
#  define TCL_SIZE_MAX INT_MAX
#  define TCL_SIZE_MODIFIER ""
#endif

typedef Tcl_Obj *const *Tcl_ObjArgs;

static inline void cgo_Tcl_IncrRefCount(Tcl_Obj *objPtr) {
	Tcl_IncrRefCount(objPtr);
}

static inline void cgo_Tcl_DecrRefCount(Tcl_Obj *objPtr) {
	Tcl_DecrRefCount(objPtr);
}

static inline void cgo_Tcl_BounceRefCount(Tcl_Obj *objPtr) {
#if TCL_MAJOR_VERSION > 8
	Tcl_BounceRefCount(objPtr);
#else
	if (objPtr != NULL && objPtr->refCount == 0) {
		Tcl_DecrRefCount(objPtr);
	}
#endif
}

static inline int cgo_Tcl_IsShared(Tcl_Obj *objPtr) {
	return Tcl_IsShared(objPtr);
}

static inline char *cgo_Tcl_GetString(Tcl_Obj *objPtr) {
	return Tcl_GetString(objPtr);
}

static inline Tcl_UniChar *cgo_Tcl_GetUnicode(Tcl_Obj *objPtr) {
	return Tcl_GetUnicode(objPtr);
}

static inline unsigned char *cgo_Tcl_GetByteArrayFromObj(Tcl_Obj *objPtr, Tcl_Size *sizePtr) {
	return Tcl_GetByteArrayFromObj(objPtr, sizePtr);
}

static inline Tcl_Obj *cgo_Tcl_NewBooleanObj(int boolValue) {
	return Tcl_NewBooleanObj(boolValue);
}

static inline void cgo_Tcl_SetBooleanObj(Tcl_Obj *objPtr, int boolValue) {
	Tcl_SetBooleanObj(objPtr, boolValue);
}

static inline int cgo_Tcl_GetBoolean(Tcl_Interp *interp, const char *src, int *boolPtr) {
	return Tcl_GetBoolean(interp, src, boolPtr);
}

static inline int cgo_Tcl_GetBooleanFromObj(Tcl_Interp *interp, Tcl_Obj *objPtr, int *boolPtr) {
	return Tcl_GetBooleanFromObj(interp, objPtr, boolPtr);
}

static inline Tcl_Obj *cgo_Tcl_NewIntObj(int intValue) {
	return Tcl_NewIntObj(intValue);
}

static inline void cgo_Tcl_SetIntObj(Tcl_Obj *objPtr, int intValue) {
	Tcl_SetIntObj(objPtr, intValue);
}

static inline Tcl_Obj *cgo_Tcl_NewLongObj(long longValue) {
	return Tcl_NewLongObj(longValue);
}

static inline void cgo_Tcl_SetLongObj(Tcl_Obj *objPtr, long longValue) {
	Tcl_SetLongObj(objPtr, longValue);
}

static inline int cgo_Tcl_GetIndexFromObj(Tcl_Interp *interp, Tcl_Obj *objPtr,
		const char *const *tablePtr, const char *msg, int flags, int *indexPtr) {
	return Tcl_GetIndexFromObj(interp, objPtr, tablePtr, msg, flags, indexPtr);
}

static inline int cgo_Tcl_GetIndexFromObjStruct(Tcl_Interp *interp, Tcl_Obj *objPtr,
		const void *tablePtr, Tcl_Size offset, const char *msg, int flags, int *indexPtr) {
	return Tcl_GetIndexFromObjStruct(interp, objPtr, tablePtr, offset, msg, flags, indexPtr);
}

static inline int cgo_Tcl_StringMatch(const char *str, const char *pattern) {
	return Tcl_StringMatch(str, pattern);
}

static inline int cgo_Tcl_Eval(Tcl_Interp *interp, const char *script) {
	return Tcl_Eval(interp, script);
}

static inline int cgo_Tcl_EvalObj(Tcl_Interp *interp, Tcl_Obj *objPtr) {
	return Tcl_EvalObj(interp, objPtr);
}

static inline int cgo_Tcl_GlobalEval(Tcl_Interp *interp, const char *command) {
	return Tcl_GlobalEval(interp, command);
}

static inline int cgo_Tcl_GlobalEvalObj(Tcl_Interp *interp, Tcl_Obj *objPtr) {
	return Tcl_GlobalEvalObj(interp, objPtr);
}

static inline void cgo_Tcl_SetResult(Tcl_Interp *interp, char *result, Tcl_FreeProc *freeProc) {
	Tcl_SetResult(interp, result, freeProc);
}

static inline const char *cgo_Tcl_GetStringResult(Tcl_Interp *interp) {
	return Tcl_GetStringResult(interp);
}

static inline void cgo_Tcl_AddErrorInfo(Tcl_Interp *interp, const char *message) {
	Tcl_AddErrorInfo(interp, message);
}

static inline void cgo_Tcl_AddObjErrorInfo(Tcl_Interp *interp, const char *message, Tcl_Size length) {
	Tcl_AddObjErrorInfo(interp, message, length);
}

static inline void cgo_Tcl_BackgroundError(Tcl_Interp *interp) {
	Tcl_BackgroundError(interp);
}

static inline const char *cgo_Tcl_GetVar(Tcl_Interp *interp, const char *varName, int flags) {
	return Tcl_GetVar(interp, varName, flags);
}

static inline const char *cgo_Tcl_SetVar(Tcl_Interp *interp, const char *varName,
		const char *newValue, int flags) {
	return Tcl_SetVar(interp, varName, newValue, flags);
}

static inline int cgo_Tcl_UnsetVar(Tcl_Interp *interp, const char *varName, int flags) {
	return Tcl_UnsetVar(interp, varName, flags);
}

static inline int cgo_Tcl_UpVar(Tcl_Interp *interp, const char *frameName,
		const char *varName, const char *localName, int flags) {
	return Tcl_UpVar(interp, frameName, varName, localName, flags);
}

static inline int cgo_Tcl_TraceVar(Tcl_Interp *interp, const char *varName, int flags,
		Tcl_VarTraceProc *proc, void *clientData) {
	return Tcl_TraceVar(interp, varName, flags, proc, clientData);
}

static inline void cgo_Tcl_UntraceVar(Tcl_Interp *interp, const char *varName, int flags,
		Tcl_VarTraceProc *proc, void *clientData) {
	Tcl_UntraceVar(interp, varName, flags, proc, clientData);
}

static inline void *cgo_Tcl_VarTraceInfo(Tcl_Interp *interp, const char *varName, int flags,
		Tcl_VarTraceProc *procPtr, void *prevClientData) {
	return Tcl_VarTraceInfo(interp, varName, flags, procPtr, prevClientData);
}

static inline Tcl_Trace cgo_Tcl_CreateObjTrace(Tcl_Interp *interp, Tcl_Size level, int flags,
		Tcl_CmdObjTraceProc *objProc, void *clientData, Tcl_CmdObjTraceDeleteProc *delProc) {
	return Tcl_CreateObjTrace(interp, level, flags, objProc, clientData, delProc);
}

static inline Tcl_Command cgo_Tcl_CreateObjCommand(Tcl_Interp *interp, const char *cmdName,
		Tcl_ObjCmdProc *proc, void *clientData, Tcl_CmdDeleteProc *deleteProc) {
	return Tcl_CreateObjCommand(interp, cmdName, proc, clientData, deleteProc);
}

#if TCL_MAJOR_VERSION > 8
static inline Tcl_Command cgo_Tcl_CreateObjCommand2(Tcl_Interp *interp, const char *cmdName,
		Tcl_ObjCmdProc2 *proc2, void *clientData, Tcl_CmdDeleteProc *deleteProc) {
	return Tcl_CreateObjCommand2(interp, cmdName, proc2, clientData, deleteProc);
}
#endif

static inline Tcl_Interp *cgo_Tcl_CreateChild(Tcl_Interp *interp, const char *name, int isSafe) {
	return Tcl_CreateChild(interp, name, isSafe);
}

static inline Tcl_Interp *cgo_Tcl_GetChild(Tcl_Interp *interp, const char *name) {
	return Tcl_GetChild(interp, name);
}

static inline Tcl_Interp *cgo_Tcl_GetParent(Tcl_Interp *interp) {
	return Tcl_GetParent(interp);
}

static inline int cgo_Tcl_PkgProvide(Tcl_Interp *interp, const char *name, const char *version) {
	return Tcl_PkgProvide(interp, name, version);
}

static inline const char *cgo_Tcl_PkgRequire(Tcl_Interp *interp, const char *name,
		const char *version, int exact) {
	return Tcl_PkgRequire(interp, name, version, exact);
}

static inline const char *cgo_Tcl_PkgPresent(Tcl_Interp *interp, const char *name,
		const char *version, int exact) {
	return Tcl_PkgPresent(interp, name, version, exact);
}

static inline int cgo_Tcl_Close(Tcl_Interp *interp, Tcl_Channel chan) {
	return Tcl_Close(interp, chan);
}

static inline char *cgo_Tcl_DStringValue(Tcl_DString *dsPtr) {
	return Tcl_DStringValue(dsPtr);
}

static inline Tcl_Size cgo_Tcl_DStringLength(Tcl_DString *dsPtr) {
	return Tcl_DStringLength(dsPtr);
}

static inline Tcl_HashEntry *cgo_Tcl_FindHashEntry(Tcl_HashTable *tablePtr, const void *key) {
	return Tcl_FindHashEntry(tablePtr, key);
}

static inline Tcl_HashEntry *cgo_Tcl_CreateHashEntry(Tcl_HashTable *tablePtr, const void *key,
		int *newPtr) {
	return Tcl_CreateHashEntry(tablePtr, key, newPtr);
}

static inline void *cgo_Tcl_GetHashValue(Tcl_HashEntry *entryPtr) {
	return Tcl_GetHashValue(entryPtr);
}

static inline void cgo_Tcl_SetHashValue(Tcl_HashEntry *entryPtr, void *value) {
	Tcl_SetHashValue(entryPtr, value);
}

static inline void *cgo_Tcl_GetHashKey(Tcl_HashTable *tablePtr, Tcl_HashEntry *entryPtr) {
	return Tcl_GetHashKey(tablePtr, entryPtr);
}

static inline void cgo_Tcl_MutexLock(Tcl_Mutex *mutexPtr) {
	Tcl_MutexLock(mutexPtr);
}

static inline void cgo_Tcl_MutexUnlock(Tcl_Mutex *mutexPtr) {
	Tcl_MutexUnlock(mutexPtr);
}

static inline void cgo_Tcl_MutexFinalize(Tcl_Mutex *mutexPtr) {
	Tcl_MutexFinalize(mutexPtr);
}

static inline void cgo_Tcl_ConditionWait(Tcl_Condition *condPtr, Tcl_Mutex *mutexPtr,
		const Tcl_Time *timePtr) {
	Tcl_ConditionWait(condPtr, mutexPtr, timePtr);
}

static inline void cgo_Tcl_ConditionNotify(Tcl_Condition *condPtr) {
	Tcl_ConditionNotify(condPtr);
}

static inline void cgo_Tcl_ConditionFinalize(Tcl_Condition *condPtr) {
	Tcl_ConditionFinalize(condPtr);
}

#endif
