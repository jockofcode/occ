#ifndef __CONDITIONALMACROS__
#define __CONDITIONALMACROS__

/* Minimal stub for Apple ConditionalMacros.h — defines callback/API macros for ARM64 macOS */

#define FUNCTION_PASCAL             0
#define FUNCTION_DECLSPEC           0
#define FUNCTION_WIN32CC            0

#define EXTERN_API(_type)           extern _type
#define EXTERN_API_C(_type)         extern _type
#define EXTERN_API_STDCALL(_type)   extern _type
#define EXTERN_API_C_STDCALL(_type) extern _type

#define DEFINE_API(_type)           _type
#define DEFINE_API_C(_type)         _type
#define DEFINE_API_STDCALL(_type)   _type
#define DEFINE_API_C_STDCALL(_type) _type

#define CALLBACK_API(_type, _name)              _type (*_name)
#define CALLBACK_API_C(_type, _name)            _type (*_name)
#define CALLBACK_API_STDCALL(_type, _name)      _type (*_name)
#define CALLBACK_API_C_STDCALL(_type, _name)    _type (*_name)

#define pascal

#endif /* __CONDITIONALMACROS__ */
