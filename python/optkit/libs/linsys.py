from numpy import float32, float64
from ctypes import c_int, c_uint, c_size_t, c_void_p, c_float, c_double, \
	POINTER, Structure
from optkit.libs.loader import OptkitLibs

class DenseLinsysLibs(OptkitLibs):
	def __init__(self):
		OptkitLibs.__init__(self, 'libok_dense_')
		self.attach_calls.append(attach_base_ctypes)
		self.attach_calls.append(attach_dense_linsys_ctypes)
		self.attach_calls.append(attach_base_ccalls)
		self.attach_calls.append(attach_vector_ccalls)
		self.attach_calls.append(attach_dense_linsys_ccalls)

class SparseLinsysLibs(OptkitLibs):
	def __init__(self):
		OptkitLibs.__init__(self, 'libok_sparse_')
		self.attach_calls.append(attach_base_ctypes)
		self.attach_calls.append(attach_dense_linsys_ctypes)
		self.attach_calls.append(attach_sparse_linsys_ctypes)
		self.attach_calls.append(attach_base_ccalls)
		self.attach_calls.append(attach_vector_ccalls)
		self.attach_calls.append(attach_sparse_linsys_ccalls)

def attach_base_ctypes(lib, single_precision=False):
	# low-level C types, as defined for optkit
	lib.ok_float = c_float if single_precision else c_double
	lib.ok_int = c_int
	lib.pyfloat = float32 if single_precision else float64

	# pointers to C types
	lib.c_int_p = POINTER(c_int)
	lib.c_size_t_p = POINTER(c_size_t)
	lib.ok_float_p = POINTER(lib.ok_float)
	lib.ok_int_p = POINTER(lib.ok_int)

def attach_dense_linsys_ctypes(lib, single_precision=False):
	if not 'ok_float' in lib.__dict__:
		attach_base_ctypes(lib, single_precision)

	ok_float = lib.ok_float
	ok_float_p = lib.ok_float_p
	c_size_t_p = lib.c_size_t_p

	# vector struct
	class ok_vector(Structure):
		_fields_ = [('size', c_size_t),
					('stride', c_size_t),
					('data', ok_float_p)]
	lib.vector = ok_vector
	lib.vector_p = POINTER(lib.vector)

	# index vector struct
	class ok_indvector(Structure):
		_fields_ = [('size', c_size_t),
					('stride', c_size_t),
					('data', c_size_t_p)]
	lib.indvector = ok_indvector
	lib.indvector_p = POINTER(lib.indvector)

	# matrix struct
	class ok_matrix(Structure):
		_fields_ = [('size1', c_size_t),
					('size2', c_size_t),
					('ld', c_size_t),
					('data', ok_float_p),
					('order', c_uint)]
	lib.matrix = ok_matrix
	lib.matrix_p = POINTER(lib.matrix)

def attach_sparse_linsys_ctypes(lib, single_precision=False):
	if not 'ok_float' in lib.__dict__:
		attach_base_ctypes(lib, single_precision)

	ok_float_p = lib.ok_float_p
	ok_int_p = lib.ok_int_p

	# sparse matrix struct
	class ok_sparse_matrix(Structure):
		_fields_ = [('size1', c_size_t),
					('size2', c_size_t),
					('nnz', c_size_t),
					('ptrlen', c_size_t),
					('val', ok_float_p),
					('ind', ok_int_p),
					('ptr', ok_int_p),
					('order', c_uint)]

	lib.sparse_matrix = ok_sparse_matrix
	lib.sparse_matrix_p = POINTER(lib.sparse_matrix)


def attach_base_ccalls(lib, single_precision=False):
	if not 'c_int_p' in lib.__dict__:
		attach_base_ctypes(lib, single_precision)

	c_int_p = lib.c_int_p

	lib.optkit_version.argtypes = [c_int_p, c_int_p, c_int_p, c_int_p]
	lib.optkit_version.restype = c_uint

	lib.ok_device_reset.argtypes = []
	lib.ok_device_reset.restype = c_uint

def attach_vector_ccalls(lib, single_precision=False):
	if not 'vector_p' in lib.__dict__:
		attach_dense_linsys_ctypes(lib, single_precision)

	ok_float = lib.ok_float
	ok_float_p = lib.ok_float_p
	c_size_t_p = lib.c_size_t_p
	vector_p = lib.vector_p
	indvector_p = lib.indvector_p

	lib.vector_alloc.argtypes = [vector_p, c_size_t]
	lib.vector_calloc.argtypes = [vector_p, c_size_t]
	lib.vector_free.argtypes = [vector_p]
	lib.vector_set_all.argtypes = [vector_p, ok_float]
	lib.vector_subvector.argtypes = [vector_p, vector_p, c_size_t,
										c_size_t]
	lib.vector_view_array.argtypes = [vector_p, ok_float_p, c_size_t]
	lib.vector_memcpy_vv.argtypes = [vector_p, vector_p]
	lib.vector_memcpy_va.argtypes = [vector_p, ok_float_p, c_size_t]
	lib.vector_memcpy_av.argtypes = [ok_float_p, vector_p, c_size_t]
	lib.vector_print.argtypes = [vector_p]
	lib.vector_scale.argtypes = [vector_p, ok_float]
	lib.vector_add.argtypes = [vector_p, vector_p]
	lib.vector_sub.argtypes = [vector_p, vector_p]
	lib.vector_mul.argtypes = [vector_p, vector_p]
	lib.vector_div.argtypes = [vector_p, vector_p]
	lib.vector_add_constant.argtypes = [vector_p, ok_float]
	lib.vector_abs.argtypes = [vector_p]
	lib.vector_recip.argtypes = [vector_p]
	lib.vector_sqrt.argtypes = [vector_p]
	lib.vector_pow.argtypes = [vector_p, ok_float]
	lib.vector_exp.argtypes = [vector_p]
	lib.vector_indmin.argtypes = [vector_p, c_size_t_p]
	lib.vector_min.argtypes = [vector_p, ok_float_p]
	lib.vector_max.argtypes = [vector_p, ok_float_p]

	lib.indvector_alloc.argtypes = [indvector_p, c_size_t]
	lib.indvector_calloc.argtypes = [indvector_p, c_size_t]
	lib.indvector_free.argtypes = [indvector_p]
	lib.indvector_set_all.argtypes = [indvector_p, ok_float]
	lib.indvector_subvector.argtypes = [indvector_p, indvector_p,
										c_size_t, c_size_t]
	lib.indvector_view_array.argtypes = [indvector_p, c_size_t_p,
										 c_size_t]
	lib.indvector_memcpy_vv.argtypes = [indvector_p, indvector_p]
	lib.indvector_memcpy_va.argtypes = [indvector_p, c_size_t_p,
										c_size_t]
	lib.indvector_memcpy_av.argtypes = [c_size_t_p, indvector_p,
										c_size_t]
	lib.indvector_print.argtypes = [indvector_p]
	lib.indvector_indmin.argtypes = [indvector_p, c_size_t_p]
	lib.indvector_max.argtypes = [indvector_p, c_size_t_p]
	lib.indvector_min.argtypes = [indvector_p, c_size_t_p]

	## return values
	lib.vector_alloc.restype = c_uint
	lib.vector_calloc.restype = c_uint
	lib.vector_free.restype = c_uint
	lib.vector_set_all.restype = c_uint
	lib.vector_subvector.restype = c_uint
	lib.vector_view_array.restype = c_uint
	lib.vector_memcpy_vv.restype = c_uint
	lib.vector_memcpy_va.restype = c_uint
	lib.vector_memcpy_av.restype = c_uint
	lib.vector_print.restype = c_uint
	lib.vector_scale.restype = c_uint
	lib.vector_add.restype = c_uint
	lib.vector_sub.restype = c_uint
	lib.vector_mul.restype = c_uint
	lib.vector_div.restype = c_uint
	lib.vector_add_constant.restype = c_uint
	lib.vector_abs.restype = c_uint
	lib.vector_recip.restype = c_uint
	lib.vector_sqrt.restype = c_uint
	lib.vector_pow.restype = c_uint
	lib.vector_exp.restype = c_uint
	lib.vector_indmin.restype = c_uint
	lib.vector_min.restype = c_uint
	lib.vector_max.restype = c_uint

	lib.indvector_alloc.restype = c_uint
	lib.indvector_calloc.restype = c_uint
	lib.indvector_free.restype = c_uint
	lib.indvector_set_all.restype = c_uint
	lib.indvector_subvector.restype = c_uint
	lib.indvector_view_array.restype = c_uint
	lib.indvector_memcpy_vv.restype = c_uint
	lib.indvector_memcpy_va.restype = c_uint
	lib.indvector_memcpy_av.restype = c_uint
	lib.indvector_print.restype = c_uint
	lib.indvector_indmin.restype = c_uint
	lib.indvector_min.restype = c_uint
	lib.indvector_max.restype = c_uint

def attach_dense_linsys_ccalls(lib, single_precision=False):
	if not 'vector_p' in lib.__dict__:
		attach_dense_linsys_ctypes(lib, single_precision)

	ok_float = lib.ok_float
	ok_float_p = lib.ok_float_p
	vector_p = lib.vector_p
	indvector_p = lib.indvector_p
	matrix_p = lib.matrix_p

	# Matrix
	# ------
	## arguments
	lib.matrix_alloc.argtypes = [matrix_p, c_size_t, c_size_t, c_uint]
	lib.matrix_calloc.argtypes = [matrix_p, c_size_t, c_size_t, c_uint]
	lib.matrix_free.argtypes = [matrix_p]
	lib.matrix_submatrix.argtypes = [matrix_p, matrix_p, c_size_t, c_size_t,
									 c_size_t, c_size_t]
	lib.matrix_row.argtypes = [vector_p, matrix_p, c_size_t]
	lib.matrix_column.argtypes = [vector_p, matrix_p, c_size_t]
	lib.matrix_diagonal.argtypes = [vector_p, matrix_p]
	lib.matrix_view_array.argtypes = [matrix_p, ok_float_p, c_size_t, c_size_t,
									  c_uint]
	lib.matrix_set_all.argtypes = [matrix_p, ok_float]
	lib.matrix_memcpy_mm.argtypes = [matrix_p, matrix_p]
	lib.matrix_memcpy_ma.argtypes = [matrix_p, ok_float_p, c_uint]
	lib.matrix_memcpy_am.argtypes = [ok_float_p, matrix_p, c_uint]
	lib.matrix_print.argtypes = [matrix_p]
	lib.matrix_scale.argtypes = [matrix_p, ok_float]
	lib.matrix_scale_left.argtypes = [matrix_p, vector_p]
	lib.matrix_scale_right.argtypes = [matrix_p, vector_p]
	lib.matrix_abs.argtypes = [matrix_p]
	lib.matrix_pow.argtypes = [matrix_p, ok_float]

	## return values
	lib.matrix_alloc.restype = c_uint
	lib.matrix_calloc.restype = c_uint
	lib.matrix_free.restype = c_uint
	lib.matrix_submatrix.restype = c_uint
	lib.matrix_row.restype = c_uint
	lib.matrix_column.restype = c_uint
	lib.matrix_diagonal.restype = c_uint
	lib.matrix_view_array.restype = c_uint
	lib.matrix_set_all.restype = c_uint
	lib.matrix_memcpy_mm.restype = c_uint
	lib.matrix_memcpy_ma.restype = c_uint
	lib.matrix_memcpy_am.restype = c_uint
	lib.matrix_print.restype = c_uint
	lib.matrix_scale.restype = c_uint
	lib.matrix_scale_left.restype = c_uint
	lib.matrix_scale_right.restype = c_uint
	lib.matrix_abs.restype = c_uint
	lib.matrix_pow.restype = c_uint

	# BLAS
	# ----

	## arguments
	lib.blas_make_handle.argtypes = [c_void_p]
	lib.blas_destroy_handle.argtypes = [c_void_p]
	lib.blas_axpy.argtypes = [c_void_p, ok_float, vector_p, vector_p]
	lib.blas_nrm2.argtypes = [c_void_p, vector_p, ok_float_p]
	lib.blas_scal.argtypes = [c_void_p, ok_float, vector_p]
	lib.blas_asum.argtypes = [c_void_p, vector_p, ok_float_p]
	lib.blas_dot.argtypes = [c_void_p, vector_p, vector_p, ok_float_p]
	lib.blas_gemv.argtypes = [c_void_p, c_uint, ok_float, matrix_p, vector_p,
							  ok_float, vector_p]
	lib.blas_trsv.argtypes = [c_void_p, c_uint, c_uint, c_uint, matrix_p,
							  vector_p]
	lib.blas_sbmv.argtypes = [c_void_p, c_uint, c_uint, c_size_t, ok_float,
							  vector_p, vector_p, ok_float, vector_p]
	lib.blas_diagmv.argtypes = [c_void_p, ok_float, vector_p, vector_p,
								ok_float, vector_p]
	lib.blas_syrk.argtypes = [c_void_p, c_uint, c_uint, ok_float, matrix_p,
							  ok_float, matrix_p]
	lib.blas_gemm.argtypes = [c_void_p, c_uint, c_uint, ok_float, matrix_p,
							  matrix_p, ok_float, matrix_p]
	lib.blas_trsm.argtypes = [c_void_p, c_uint, c_uint, c_uint, c_uint,
							  ok_float, matrix_p, matrix_p]

	## return values
	lib.blas_make_handle.restype = c_uint
	lib.blas_destroy_handle.restype = c_uint
	lib.blas_axpy.restype = c_uint
	lib.blas_nrm2.restype = c_uint
	lib.blas_scal.restype = c_uint
	lib.blas_asum.restype = c_uint
	lib.blas_dot.restype = c_uint
	lib.blas_gemv.restype = c_uint
	lib.blas_trsv.restype = c_uint
	lib.blas_sbmv.restype = c_uint
	lib.blas_diagmv.restype = c_uint
	lib.blas_syrk.restype = c_uint
	lib.blas_gemm.restype = c_uint
	lib.blas_trsm.restype = c_uint

	# LINALG
	# -------
	## arguments
	lib.linalg_cholesky_decomp.argtypes = [c_void_p, matrix_p]
	lib.linalg_cholesky_svx.argtypes = [c_void_p, matrix_p, vector_p]
	lib.linalg_matrix_row_squares.argtypes = [c_uint, matrix_p, vector_p]
	lib.linalg_matrix_broadcast_vector.argtypes = [matrix_p, vector_p, c_uint,
												   c_uint]
	lib.linalg_matrix_reduce_indmin.argtypes = [indvector_p, vector_p,
										 		matrix_p, c_uint]
	lib.linalg_matrix_reduce_min.argtypes = [vector_p, matrix_p, c_uint]
	lib.linalg_matrix_reduce_max.argtypes = [vector_p, matrix_p, c_uint]

	## return values
	lib.linalg_cholesky_decomp.restype = c_uint
	lib.linalg_cholesky_svx.restype = c_uint
	lib.linalg_matrix_row_squares.restype = c_uint
	lib.linalg_matrix_broadcast_vector.restype = c_uint
	lib.linalg_matrix_reduce_indmin.restype = c_uint
	lib.linalg_matrix_reduce_min.restype = c_uint
	lib.linalg_matrix_reduce_max.restype = c_uint

def attach_sparse_linsys_ccalls(lib, single_precision=False):
	if not 'vector_p' in lib.__dict__:
		attach_dense_linsys_ctypes(lib, single_precision)
	if not 'sparse_matrix_p' in lib.__dict__:
		attach_sparse_linsys_ctypes(lib, single_precision)

	ok_float = lib.ok_float
	ok_float_p = lib.ok_float_p
	ok_int_p = lib.ok_int_p
	vector_p = lib.vector_p
	sparse_matrix_p = lib.sparse_matrix_p

	# Sparse Handle
	# -------------
	## arguments
	lib.sp_make_handle.argtypes = [c_void_p]
	lib.sp_destroy_handle.argtypes = [c_void_p]

	## return values
	lib.sp_make_handle.restype = c_uint
	lib.sp_destroy_handle.restype = c_uint

	# Sparse Matrix
	# -------------
	## arguments
	lib.sp_matrix_alloc.argtypes = [sparse_matrix_p, c_size_t, c_size_t,
									c_size_t, c_uint]
	lib.sp_matrix_calloc.argtypes = [sparse_matrix_p, c_size_t, c_size_t,
									 c_size_t, c_uint]
	lib.sp_matrix_free.argtypes = [sparse_matrix_p]
	lib.sp_matrix_memcpy_mm.argtypes = [sparse_matrix_p, sparse_matrix_p]
	lib.sp_matrix_memcpy_ma.argtypes = [c_void_p, sparse_matrix_p,
										ok_float_p, ok_int_p, ok_int_p]
	lib.sp_matrix_memcpy_am.argtypes = [ok_float_p, ok_int_p, ok_int_p,
										sparse_matrix_p]
	lib.sp_matrix_memcpy_vals_mm.argtypes = [sparse_matrix_p, sparse_matrix_p]
	lib.sp_matrix_memcpy_vals_ma.argtypes = [c_void_p, sparse_matrix_p,
											 ok_float_p]
	lib.sp_matrix_memcpy_vals_am.argtypes = [ok_float_p,sparse_matrix_p]
	lib.sp_matrix_abs.argtypes = [sparse_matrix_p]
	lib.sp_matrix_pow.argtypes = [sparse_matrix_p, ok_float]
	lib.sp_matrix_scale.argtypes = [sparse_matrix_p, ok_float]
	lib.sp_matrix_scale_left.argtypes = [c_void_p, sparse_matrix_p, vector_p]
	lib.sp_matrix_scale_right.argtypes = [c_void_p, sparse_matrix_p, vector_p]
	lib.sp_matrix_print.argtypes = [sparse_matrix_p]
	# lib.sp_matrix_print_transpose.argtypes = [sparse_matrix_p]

	## return values
	lib.sp_matrix_alloc.restype = c_uint
	lib.sp_matrix_calloc.restype = c_uint
	lib.sp_matrix_free.restype = c_uint
	lib.sp_matrix_memcpy_mm.restype = c_uint
	lib.sp_matrix_memcpy_ma.restype = c_uint
	lib.sp_matrix_memcpy_am.restype = c_uint
	lib.sp_matrix_memcpy_vals_mm.restype = c_uint
	lib.sp_matrix_memcpy_vals_ma.restype = c_uint
	lib.sp_matrix_memcpy_vals_am.restype = c_uint
	lib.sp_matrix_abs.restype = c_uint
	lib.sp_matrix_pow.restype = c_uint
	lib.sp_matrix_scale.restype = c_uint
	lib.sp_matrix_scale_left.restype = c_uint
	lib.sp_matrix_scale_right.restype = c_uint
	lib.sp_matrix_print.restype = c_uint
	# lib.sp_matrix_print_transpose.restype = None

	# Sparse BLAS
	# -----------
	## arguments
	lib.sp_blas_gemv.argtypes = [c_void_p, c_uint, ok_float, sparse_matrix_p,
								 vector_p, ok_float, vector_p]

	## return values
	lib.sp_blas_gemv.restype = c_uint