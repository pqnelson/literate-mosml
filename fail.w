@* Raising exceptions from C.

@(fail.h@>=
#ifndef _fail_
#define _fail_

#include <setjmp.h>
#include "misc.h"
#include "mlvalues.h"

struct longjmp_buffer {
  jmp_buf buf;
};

extern struct longjmp_buffer * external_raise;
extern value exn_bucket;

EXTERN Noreturn mlraise(value);
EXTERN Noreturn raiseprimitive0(int exnindex);
EXTERN Noreturn raiseprimitive1(int exnindex, value arg);
EXTERN Noreturn raise_with_string(int exnindex, char * msg);
EXTERN Noreturn failwith(char *);
EXTERN Noreturn invalid_argument(char *);
EXTERN Noreturn raise_overflow(void);
EXTERN Noreturn raise_out_of_memory(void);
extern volatile int float_exn;

extern double maxdouble;

#endif /* |_fail_| */


@ @(fail.c@>=
#if !defined(WIN32) && (defined(__unix__) || defined(unix)) && !defined(USG)
#include <sys/param.h>
#endif

@ @(fail.c@>=
#if defined(__MWERKS__) || defined(WIN32)
#define MAXDOUBLE 1.7976931348623157081e+308
#else
#include <float.h>
#define MAXDOUBLE DBL_MAX
#endif

@ @(fail.c@>=
#include "alloc.h"
#include "fail.h"
#include "memory.h"
#include "mlvalues.h"
#include "signals.h"
#include "globals.h"


@ |float_exn| is an exception index from globals.h.  The exception
   (Fail "floating point error") will be raised if |float_exn| has not
   been initialized before a floating point error occurs.

@ @(fail.c@>=
volatile int float_exn = SYS__EXN_FAIL;

double maxdouble = MAXDOUBLE/2;

struct longjmp_buffer * external_raise;
value exn_bucket;		/* ML type: string ref * 'a */

@ @(fail.c@>=
EXTERN void mlraise(value v)
{
  in_blocking_section = 0;
  exn_bucket = v;
  longjmp(external_raise->buf, 1);
}

@ Raise a unary pervasive exception with the given argument

@(fail.c@>=
void raiseprimitive1(int exnindex, value arg) {
  value exn;
  Push_roots(r, 1);  
  r[0] = arg;  
  exn = alloc_tuple(2);
  modify(&Field(exn, 0), Field(global_data, exnindex));
  modify(&Field(exn, 1), r[0]);
  Pop_roots();
  mlraise(exn);
}

@ @(fail.c@>=
void raiseprimitive0(int exnindex) {
  raiseprimitive1(exnindex, Val_unit);
}

@ @(fail.c@>=
EXTERN void raise_with_string(int exnindex, char * msg) {
  raiseprimitive1(exnindex, copy_string(msg));
}

@ @(fail.c@>=
EXTERN void failwith (char* msg) {
  raise_with_string(SYS__EXN_FAIL, msg);
}

@ @(fail.c@>=
void invalid_argument (char * msg) {
  raise_with_string(SYS__EXN_ARGUMENT, msg);
}

@ @(fail.c@>=
void raise_out_of_memory() {
  raiseprimitive0(SYS__EXN_MEMORY);
}

@ @(fail.c@>=
void raise_overflow() {
  raiseprimitive0(SYS__EXN_OVERFLOW);
}
