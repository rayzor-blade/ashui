// Futures settled from a plain OS thread, the way native GPU and IO
// libraries complete their async calls.
#define HL_NAME(n) futrepro_##n
#include <hl.h>
#include <dlfcn.h>
#include <pthread.h>
#include <stdlib.h>
#include <unistd.h>

typedef struct ash_future ash_future;
extern ash_future *hlp_future_create(void);
extern bool hlp_future_resolve(ash_future *future, vdynamic *value);
extern vdynamic *hlp_alloc_dynamic(hl_type *t);
extern hl_type *hlp_type_i32(void);

typedef ash_future *(*create_fn)(void);
typedef bool (*resolve_fn)(ash_future *, vdynamic *);

typedef struct {
	ash_future *future;
	resolve_fn resolve;
	int delay_us;
	bool boxed;
} job;

static void *settle(void *p) {
	job *j = (job *)p;
	if (j->delay_us > 0)
		usleep(j->delay_us);
	vdynamic *value = NULL;
	if (j->boxed) {
		// What hlwgpu resolves with: an Int boxed on this unregistered thread.
		value = hlp_alloc_dynamic(hlp_type_i32());
		value->v.i = 42;
	}
	j->resolve(j->future, value);
	free(j);
	return NULL;
}

// A future resolved by a new thread after `delay_us` microseconds, with
// null or with a boxed Int allocated on that thread. `lookup` finds the
// future functions with dlsym on the process, as hlwgpu does, instead of
// through this library's link to libhl.
HL_PRIM ash_future *HL_NAME(later)(int delay_us, bool boxed, bool lookup) {
	job *j = (job *)malloc(sizeof(job));
	create_fn create = hlp_future_create;
	j->resolve = hlp_future_resolve;
	if (lookup) {
		void *process = dlopen(NULL, RTLD_LAZY);
		create = (create_fn)dlsym(process, "hlp_future_create");
		j->resolve = (resolve_fn)dlsym(process, "hlp_future_resolve");
	}
	j->future = create();
	j->delay_us = delay_us;
	j->boxed = boxed;
	pthread_t thread;
	pthread_create(&thread, NULL, settle, j);
	pthread_detach(thread);
	return j->future;
}
DEFINE_PRIM(_ABSTRACT(ash_future), later, _I32 _BOOL _BOOL);

// Where `symbol` is found by a dlsym on the process.
HL_PRIM vbyte *HL_NAME(where)(vbyte *symbol) {
	Dl_info info;
	void *p = dlsym(dlopen(NULL, RTLD_LAZY), (char *)symbol);
	return (vbyte *)(p != NULL && dladdr(p, &info) ? info.dli_fname : "not found");
}
DEFINE_PRIM(_BYTES, where, _BYTES);
