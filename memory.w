@* Allocation macros and functions.

@(memory.h@>=
/* Allocation macros and functions */

#ifndef _memory_
#define _memory_


#include "config.h"
#include "gc.h"
#include "major_gc.h"
#include "minor_gc.h"
#include "misc.h"
#include "mlvalues.h"

@ @(memory.h@>=
EXTERN value *c_roots_head;

void init_c_roots (void);
EXTERN value alloc_shr (mlsize_t, tag_t);
void adjust_gc_speed (mlsize_t, mlsize_t);
EXTERN void modify (value *, value);
EXTERN void initialize (value *, value);
EXTERN char * stat_alloc (asize_t);	         /* Size in bytes. */
EXTERN void stat_free (char *);
EXTERN char * stat_resize (char *, asize_t);     /* Size in bytes. */


@ @(memory.h@>=
#define Alloc_small(result, wosize, tag) {				      \
  char *_res_ = young_ptr;						      \
  young_ptr += Bhsize_wosize (wosize);					      \
  if (young_ptr > young_end){						      \
    Setup_for_gc;							      \
    minor_collection ();						      \
    Restore_after_gc;							      \
    _res_ = young_ptr;							      \
    young_ptr += Bhsize_wosize (wosize);				      \
  }									      \
  Hd_hp (_res_) = Make_header ((wosize), (tag), Black);			      \
  (result) = Val_hp (_res_);						      \
}

@ You must use |Modify| to change a field of an existing shared block,
   unless you are sure the value being overwritten is not a shared block and
   the value being written is not a young block.

|Modify| never calls the GC.

@(memory.h@>=
#define Modify(fp, val) {						      \
  value _old_ = *(fp);							      \
  *(fp) = (val);							      \
  if (Is_in_heap (fp)){							      \
    if (gc_phase == Phase_mark) darken (_old_);				      \
    if (Is_block (val) && Is_young (val)				      \
	&& ! (Is_block (_old_) && Is_young (_old_))){			      \
      *ref_table_ptr++ = (fp);						      \
      if (ref_table_ptr >= ref_table_limit){				      \
        Assert (ref_table_ptr == ref_table_limit);			      \
	realloc_ref_table ();						      \
      }									      \
    }									      \
  }									      \
}

@ |Push_roots| and |Pop_roots| are used for \CEE/ variables that are GC roots.
  It must contain all values in \CEE/ local variables at the time the minor GC is
  called.
  
  Usage:
  At the end of the declarations of your \CEE/ local variables, add\par
   \centerline{|Push_roots (variable_name, size);|}\par
  The size is the number of declared roots.  They are accessed as\par
   \centerline{|variable_name [0] ... variable_name [size - 1]|}\par
  The |variable_name| and the |size| must not be | _ |.
  Just before the function return, add a call to |Pop_roots|.
 

@(memory.h@>=
#define Push_roots(name, size)						      \
   value name [(size) + 2];						      \
   { long _; for (_ = 0; _ < (size); name [_++] = Val_long (0)); }	      \
   name [(size)] = (value) (size);					      \
   name [(size) + 1] = (value) c_roots_head;				      \
   c_roots_head = &(name [(size)]);

#define Pop_roots() {c_roots_head = (value *) c_roots_head [1]; }


#endif /* |_memory_| */

@ @(memory.c@>=
#include <string.h>
#include <stdlib.h>
#include "mlvalues.h"
#include "debugger.h"
#include "fail.h"
#include "freelist.h"
#include "gc.h"
#include "gc_ctrl.h"
#include "major_gc.h"
#include "memory.h"
#include "minor_gc.h"
#include "misc.h"

@ @(memory.c@>=
value *c_roots_head;

@ Allocate more memory from malloc for the heap.
   Return a block of at least the requested size (in words).
   Return |NULL| when out of memory.

@(memory.c@>=
static char *expand_heap (mlsize_t request)
{
  char *mem, *orig_ptr;
  asize_t malloc_request;
  asize_t i;

  malloc_request = round_heap_chunk_size (Bhsize_wosize (request));
  gc_message ("Growing heap to %ldk\n",
	      (stat_heap_size + malloc_request) / 1024);
  mem = aligned_malloc (malloc_request + sizeof (heap_chunk_head),
                        sizeof (heap_chunk_head));
  if (mem == NULL){
    gc_message ("No room for growing heap\n", 0);
    return NULL;
  }
  orig_ptr = ((char **)mem)[0];
  mem += sizeof (heap_chunk_head);
  (((heap_chunk_head *) mem) [-1]).size = malloc_request;
  Assert (Wosize_bhsize (malloc_request) >= request);
  Hd_hp (mem) = Make_header (Wosize_bhsize (malloc_request), 0, Blue);

#ifndef SIXTEEN
  if (mem < heap_start){
    (((heap_chunk_head *) mem) [-1]).next = heap_start;
    heap_start = mem;
  } else {
    char **last;
    char *cur;

    if (mem >= heap_end) heap_end = mem + malloc_request;
    last = &heap_start;
    cur = *last;
    while (cur != NULL && cur < mem){
      last = &((((heap_chunk_head *) cur) [-1]).next);
      cur = *last;
    }
    (((heap_chunk_head *) mem) [-1]).next = cur;
    *last = mem;
  }
#else  /* |defined(SIXTEEN_BITS)| Simplified version for the 8086 */
  {
    char **last;
    char *cur;

    last = &heap_start;
    cur = *last;
    while (cur != NULL && (char huge *) cur < (char huge *) mem){
      last = &((((heap_chunk_head *) cur) [-1]).next);
      cur = *last;
    }
    (((heap_chunk_head *) mem) [-1]).next = cur;
    *last = mem;
  }
#endif /* |SIXTEEN_BITS| */
  p_table_add_pages(mem, mem+malloc_request);  
  stat_heap_size += malloc_request;
  return Bp_hp (mem);
}

@ @(memory.c@>=
EXTERN value alloc_shr (mlsize_t wosize, tag_t tag)
{
  char *hp, *new_block;

  hp = fl_allocate (wosize);
  if (hp == NULL){
    new_block = expand_heap (wosize);
    if (new_block == NULL) raise_out_of_memory ();
    fl_add_block (new_block);
    hp = fl_allocate (wosize);
    if (hp == NULL) fatal_error ("alloc_shr: expand heap failed\n");
  }

  Assert (Is_in_heap (Val_hp (hp)));

  if (gc_phase == Phase_mark || (addr)hp >= (addr)gc_sweep_hp){
    Hd_hp (hp) = Make_header (wosize, tag, Black);
  }else{
    Hd_hp (hp) = Make_header (wosize, tag, White);
  }
  allocated_words += Whsize_wosize (wosize);
  if (allocated_words > Wsize_bsize (minor_heap_size)) force_minor_gc ();
  return Val_hp (hp);
}

@ Use this function to tell the major GC to speed up when you use
   finalized objects to automatically deallocate extra-heap objects.
   The GC will do at least one cycle every |max| allocated words;
   |mem| is the number of words allocated this time.
   Note that only |mem/max| is relevant.  You can use numbers of bytes
   (or kilobytes, ...) instead of words.  You can change units between
   calls to |adjust_collector_speed|.

@(memory.c@>=
void adjust_gc_speed (mlsize_t mem, mlsize_t max)
{
  if (max == 0) max = 1;
  if (mem > max) mem = max;
  extra_heap_memory += ((float) mem / max) * stat_heap_size;
  if (extra_heap_memory > stat_heap_size){
    extra_heap_memory = stat_heap_size;
  }
  if (extra_heap_memory > Wsize_bsize (minor_heap_size) / 2) force_minor_gc ();
}

@ You must use |initialize| to store the initial value in a field of
   a shared block, unless you are sure the value is not a young block.
   A block value $v$ is a shared block if and only if |Is_in_heap (v)|
   is true.

Also, |initialize| never calls the GC, so you may call it while an object is
   unfinished (i.e. just after a call to |alloc_shr|.)

@(memory.c@>=
void initialize (value * fp, value val)
{
  *fp = val;
  Assert (Is_in_heap (fp));
  if (Is_block (val) && Is_young (val)){
    *ref_table_ptr++ = fp;
    if (ref_table_ptr >= ref_table_limit){
      realloc_ref_table ();
    }
  }
}

@ You must use |modify| to change a field of an existing shared block,
   unless you are sure the value being overwritten is not a shared block and
   the value being written is not a young block.
 Never calls the GC.

@(memory.c@>=
EXTERN void modify (value * fp, value val)
{
  Modify (fp, val);
}

@ @(memory.c@>=
char *stat_alloc(asize_t sz)
{
  char *result = (char *) malloc (sz);

  if (result == NULL) raise_out_of_memory ();
  return result;
}

@ @(memory.c@>=
void stat_free(char * blk)
{
  free (blk);
}

@ @(memory.c@>=
char *stat_resize (char * blk, asize_t sz)
{
  char *result = (char *) realloc (blk, sz);

  if (result == NULL) raise_out_of_memory ();
  return result;
}

@ @(memory.c@>=
void init_c_roots (void)
{
  c_roots_head = NULL;
}
