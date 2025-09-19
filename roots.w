@* Walk the roots for the garbage collector.

@(roots.h@>=
#ifndef _roots_
#define _roots_

#include "misc.h"

void local_roots (void (*copy_fn) (value *, value));


#endif /* |_roots_| */


@ @(roots.c@>=
#include "debugger.h"
#include "memory.h"
#include "misc.h"
#include "mlvalues.h"
#include "stacks.h"

@ @(roots.c@>=
void local_roots (copy_fn)
     void (*copy_fn) ();
{
  register value *sp;
  
  /* stack */
  for (sp = extern_sp; sp < stack_high; sp++) {
    copy_fn (sp, *sp);
  }

  /* C roots */
  {
    value *block;
    for (block = c_roots_head; block != NULL; block = (value *) block [1]){
      for (sp = block - (long) block [0]; sp < block; sp++){
	copy_fn (sp, *sp);
      }
    }
  }
}
