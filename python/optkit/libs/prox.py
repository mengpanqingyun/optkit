from ctypes import CDLL, c_int, c_size_t, c_void_p
from optkit.types import ok_float, ok_float_p
from optkit.types.lowlevel import function_p, function_vector_p
from optkit.defs import GPU_TAG as DEVICE__, \
						FLOAT_TAG as PRECISION__, OK_HOME


proxlib = CDLL('{}build/libprox_{}{}.dylib'.format(
	OK_HOME,DEVICE__,PRECISION__))


# Function Vector 
# ------
## arguments
proxlib.function_vector_alloc.argtypes=[function_vector_p, c_size_t]
proxlib.function_vector_calloc.argtypes=[function_vector_p, c_size_t]
proxlib.function_vector_free.argtypes=[function_vector_p]

## return values
proxlib.function_vector_alloc.restype=None
proxlib.function_vector_calloc.restype=None
proxlib.function_vector_free.restype=None

# Prox & Function
# ---------------
## arguments
proxlib.ProxEvalVector.argtypes=[function_vector_p, ok_float, ok_float_p, c_size_t, ok_float_p, c_size_t]
proxlib.FuncEvalVector.argtypes=[function_vector_p, ok_float_p, c_size_t]

## return values
proxlib.ProxEvalVector.restype=None
proxlib.FuncEvalVector.restype=ok_float
