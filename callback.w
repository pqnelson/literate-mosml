@* Registering ML values for access from C code.

@(callback.h@>=
#ifndef _callback_
#define _callback_

@ @(callback.h@>=
#include "mlvalues.h"		/* for Field, |Reference_tag| etc */
#include "fail.h"		/* for |failwith| */
#include "memory.h"		/* for |alloc_shr| */
#include "alloc.h"		/* for |copy_string| */
#include "minor_gc.h"		/* for |minor_collection| */
#include "interp.h"		/* for callback */

@ @(callback.h@>=
typedef value valueptr;		/* An 'a option ref */

@ @(callback.h@>=
EXTERN valueptr get_valueptr(char* nam);
EXTERN value get_value(valueptr mvp);
EXTERN value callbackptr(valueptr closureptr, value arg1);
EXTERN value callbackptr2(valueptr closureptr, value arg1, value arg2);
EXTERN value callbackptr3(valueptr closureptr, value arg1, value arg2, 
			  value arg3);
EXTERN void registervalue(char* nam, value mlval);
EXTERN void unregistervalue(char* nam);

EXTERN void registercptr(char* nam, void* cptr);

#endif /* |_callback_| */

@ @(callback.c@>=
#include "callback.h"
#include "mlvalues.h"		/* for Field, |Reference_tag| etc */
#include "fail.h"		/* for failwith */
#include "memory.h"		/* for |alloc_shr| */
#include "alloc.h"		/* for |copy_string| */
#include "minor_gc.h"		/* for |minor_collection| */
#include "interp.h"		/* for callback */


@ ML closures for the functions to look up, register and unregister values

@(callback.c@>=
static value get_valueptr_            = (value)NULL; 
static valueptr reg_mlvalueptr_ptr_   = (valueptr)NULL; 
static valueptr unreg_mlvalueptr_ptr_ = (valueptr)NULL; 
static valueptr reg_cptr_ptr_         = (valueptr)NULL; 

@ Obtain an ML value pointer from a string.  Return NULL if the name
   is not registered, or has been unregistered.

@(callback.c@>=
valueptr get_valueptr(char* nam) {
  /* opt is an ML option type */
  value opt = callback(get_valueptr_, copy_string(nam));
  if (opt == NONE) {
    return (valueptr)NULL;		/* Not an ML value     */
  } else
    return (valueptr)(Field(opt, 0));   /* res = SOME valueptr */
}

@ Obtain an ML value from a value pointer.  Fail if the value pointer
   is NULL.  Return NULL if the value has been unregistered.

@(callback.c@>=
value get_value(valueptr mvp) {
  value opt;
  if (mvp == (valueptr)NULL)
    failwith("get_value: null ML value pointer");
  opt = Field(mvp, 0);
  if (opt == NONE)
    return (value)NULL;	        /* Not an ML value */
  else
    return (value)(Field(opt, 0));	/* opt == SOME v   */
}  

@ @(callback.c@>=
value callbackptr(valueptr closureptr, value arg1) {
  value closure = get_value(closureptr);
  if (closure == (value)NULL)
    failwith("callbackptr: ML value has been unregistered");
  return callback(closure, arg1);
}

@ @(callback.c@>=
value callbackptr2(valueptr closureptr, value arg1, value arg2) {
  value closure = get_value(closureptr);
  if (closure == (value)NULL)
    failwith("callbackptr2: ML value has been unregistered");
  return callback2(closure, arg1, arg2);
}

@ @(callback.c@>=
value callbackptr3(valueptr closureptr, value arg1, value arg2, value arg3) {
  value closure = get_value(closureptr);
  if (closure == (value)NULL)
    failwith("callbackptr3: ML value has been unregistered");
  return callback3(closure, arg1, arg2, arg3);
}

@ This calls Callback.register

@(callback.c@>=
void registervalue(char* nam, value mlval) {
  value namval;
  Push_roots(r, 1);
  r[0] = mlval;
  namval = copy_string(nam);
  callback2(get_value(reg_mlvalueptr_ptr_), namval, r[0]);
  Pop_roots();
}

@ This calls Callback.unregister

@(callback.c@>=
void unregistervalue(char* nam) {
  value namval = copy_string(nam);
  callback(get_value(unreg_mlvalueptr_ptr_), namval);
}

@ Allocate a reference cell in the old heap, so it will not be moved.
   This is to be called from the ML side only: 

@(callback.c@>=
valueptr alloc_valueptr(value v) /* ML */
{
  value res;
  Push_roots(r, 1);
  r[0] = v;
  res = alloc_shr (1, Reference_tag); // An 'a ref
  initialize(&Field(res, 0), r[0]);
  Pop_roots();
  return res;
}

@ @(callback.c@>=
void registercptr(char* nam, void* cptr) {
  // A simple way to initialize the ML value pointer once
  if (reg_cptr_ptr_ == (valueptr)NULL)
    reg_cptr_ptr_ = get_valueptr("Callback.registercptr");     
  callbackptr2(reg_cptr_ptr_, copy_string(nam), (value)cptr);
}

@ Initialization.  This is to be called from the ML side when the
   Callback structure has been loaded, only then, and only once.  It
   saves the ML closure representing the registry lookup function, and
   then obtains pointers to the ML closures for the Callback.register
   and Callback.unregister functions. 

@ @(callback.c@>=
value sml_init_register(value v)	/* ML */
{
  /* The closure in v may be moved if it is not in the old heap.  We
     force it into the old heap by requesting a minor collection: */
  Push_roots(r, 1); 
  r[0] = v;
  minor_collection();		
  get_valueptr_         = r[0];
  Pop_roots();
  reg_mlvalueptr_ptr_   = get_valueptr("Callback.register"); 
  unreg_mlvalueptr_ptr_ = get_valueptr("Callback.unregister"); 
  return Val_unit;
}

@ Accessing C variables and functions from ML.  Used by Dynlib and Callback

@(callback.c@>=
value c_var(value symhdl) /* ML */
{
  return *((value *) symhdl);
}

@ @(callback.c@>=
value cfun_app1(value cfun, value arg)  /* ML */
{
  /* Due to the heavy typecasting, I had to declare a temp variable in
     order to get it right.  
  */
  value (*cp)(value) = (value (*)(value)) cfun;

  return (*cp)(arg);
}

@ @(callback.c@>=
value cfun_app2(value cfun, value arg1, value arg2)  /* ML */
{
  /* again a typecast value */
  value (*cp)(value,value) = (value (*)(value,value)) cfun;

  return (*cp)(arg1,arg2);
}

@ @(callback.c@>=
value cfun_app3(value cfun, value arg1, value arg2, value arg3)  /* ML */
{
  /* again a typecast value */
  value (*cp)(value,value,value) = (value (*)(value,value,value)) cfun;

  return (*cp)(arg1,arg2,arg3);
}

@ @(callback.c@>=
value cfun_app4(value cfun, value arg1, value arg2, value arg3, value arg4)  /* ML */
{
  /* again a typecast value */
  value (*cp)(value,value,value,value) = 
    (value (*)(value,value,value,value)) cfun;

  return (*cp)(arg1,arg2,arg3,arg4);
}

@ @(callback.c@>=
value cfun_app5(value args, int argc)  /* ML */
{
  value cfun = Field(args, 0);
  value arg1 = Field(args, 1);
  value arg2 = Field(args, 2);
  value arg3 = Field(args, 3);
  value arg4 = Field(args, 4);
  value arg5 = Field(args, 5);
  
  /* again a typecast value */
  value (*cp)(value,value,value,value,value) = 
    (value (*)(value,value,value,value,value)) cfun;

  return (*cp)(arg1,arg2,arg3,arg4,arg5);
}

