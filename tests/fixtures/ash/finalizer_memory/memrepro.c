// A handle that owns native memory the collector cannot see: a finalizer
// block whose finalizer frees a malloc'd payload.
#define HL_NAME(n) memrepro_##n
#include <hl.h>
#include <stdlib.h>
#include <string.h>

typedef struct {
	void (*finalize)(void *);
	void *payload;
} handle;

static void release(void *p) {
	handle *h = (handle *)p;
	free(h->payload);
	h->payload = NULL;
}

HL_PRIM void *HL_NAME(make)(int bytes) {
	handle *h = (handle *)hl_gc_alloc_finalizer(sizeof(handle));
	h->finalize = release;
	h->payload = malloc(bytes);
	memset(h->payload, 1, bytes); // touch the pages so they count in RSS
	return h;
}
DEFINE_PRIM(_ABSTRACT(memrepro_handle), make, _I32);
