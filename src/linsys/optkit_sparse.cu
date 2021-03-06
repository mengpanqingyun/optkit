#include "optkit_defs_gpu.h"
#include "optkit_thrust.hpp"
#include "optkit_sparse.h"

#ifdef __cplusplus
extern "C" {
#endif

/* struct for cusparse handle and cusparse matrix description*/
typedef struct ok_sparse_handle{
	cusparseHandle_t * hdl;
	cusparseMatDescr_t * descr;
} ok_sparse_handle;

ok_status sp_make_handle(void ** sparse_handle)
{
	ok_status err = OPTKIT_SUCCESS;
	ok_sparse_handle * ok_hdl;
	ok_hdl = (ok_sparse_handle *) malloc(sizeof(ok_sparse_handle));
	ok_hdl->hdl = (cusparseHandle_t *) malloc(sizeof(cusparseHandle_t));
	ok_hdl->descr = (cusparseMatDescr_t *) malloc(sizeof(
		cusparseMatDescr_t));
	err = OK_SCAN_CUSPARSE( cusparseCreate(ok_hdl->hdl) );

	OK_CHECK_ERR( err, OK_SCAN_CUSPARSE(
		cusparseCreateMatDescr(ok_hdl->descr) ) );

	if (!err)
		* sparse_handle = (void *) ok_hdl;
	else
		* sparse_handle = OK_NULL;
	return err;
}

ok_status sp_destroy_handle(void * sparse_handle)
{
	ok_status err = OPTKIT_SUCCESS;
	ok_sparse_handle * sp_hdl = (ok_sparse_handle *) sparse_handle;

	OK_CHECK_PTR(sparse_handle);
	err = OK_SCAN_CUSPARSE( cusparseDestroy(*sp_hdl->hdl) );
	OK_CHECK_ERR( err, OK_SCAN_CUSPARSE(
		cusparseDestroyMatDescr(*sp_hdl->descr) ) );

	ok_free(sp_hdl->descr);
	ok_free(sp_hdl->hdl);
	ok_free(sparse_handle);

	return err;
}

#ifdef __cplusplus
}
#endif

/* helper methods for CUDA */
template <typename T>
__global__ void __set(T * data, T val, size_t stride, size_t size)
{
	uint i, thread_id = blockIdx.x * blockDim.x + threadIdx.x;
	for (i = thread_id; i < size; i += gridDim.x * blockDim.x)
		data[i * stride] = val;
}

template <typename T>
ok_status __set_all(T * data, T val, size_t stride, size_t size)
{
	uint grid_dim = calc_grid_dim(size);
	OK_CHECK_PTR(data);
	__set<T><<<grid_dim, kBlockSize>>>(data, val, stride, size);
	cudaDeviceSynchronize();
	return OK_STATUS_CUDA;
}

template <typename T, typename I>
ok_status sp_matrix_alloc_(sp_matrix_<T, I> * A, size_t m, size_t n, size_t nnz,
	enum CBLAS_ORDER order)
{
	if (!A)
		return OK_SCAN_ERR( OPTKIT_ERROR_UNALLOCATED );
	if (A->val || A->ind || A->ptr)
		return OK_SCAN_ERR( OPTKIT_ERROR_OVERWRITE );
	/* Store forward and adjoint operators */
	A->size1 = m;
	A->size2 = n;
	A->nnz = nnz;
	A->ptrlen = (order == CblasColMajor) ? n + 1 : m + 1;
	OK_RETURNIF_ERR( ok_alloc_gpu(A->val, 2 * nnz * sizeof(T)) );
	OK_RETURNIF_ERR( ok_alloc_gpu(A->ind, 2 * nnz * sizeof(I)) );
	OK_RETURNIF_ERR( ok_alloc_gpu(A->ptr, (2 + m + n) * sizeof(I)) );
	A->order = order;
	return OPTKIT_SUCCESS;
}

template <typename T, typename I>
ok_status sp_matrix_calloc_(sp_matrix_<T, I> * A, size_t m, size_t n,
	size_t nnz, enum CBLAS_ORDER order)
{
	OK_RETURNIF_ERR( (sp_matrix_alloc_<T, I>(A, m, n, nnz, order)) );
	OK_RETURNIF_ERR( __set_all<T>(A->val, static_cast<T>(0), 1, 2 * nnz) );
	OK_RETURNIF_ERR( __set_all<I>(A->ind, static_cast<I>(0), 1, 2 * nnz) );
	return OK_SCAN_ERR( __set_all<I>(A->ptr, static_cast<I>(0), 1,
		2 + A->size1 + A->size2) );
}

template <typename T, typename I>
ok_status sp_matrix_free_(sp_matrix_<T, I> * A)
{
	OK_CHECK_SPARSEMAT(A);
	OK_RETURNIF_ERR( ok_free_gpu(A->val) );
	OK_RETURNIF_ERR( ok_free_gpu(A->ind) );
	OK_RETURNIF_ERR( ok_free_gpu(A->ptr) );
	A->val = OK_NULL;
	A->ind = A->ptr = OK_NULL;
	A->size1 = (size_t) 0;
	A->size2 = (size_t) 0;
	A->nnz = (size_t) 0;
	A->ptrlen = (size_t) 0;
	return OPTKIT_SUCCESS;
}

template <typename T, typename I>
ok_status sp_matrix_memcpy_mm_(sp_matrix_<T, I> * A, const sp_matrix_<T, I> * B)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_SPARSEMAT(B);
	OK_RETURNIF_ERR( ok_memcpy_gpu(A->val, B->val,
		2 * A->nnz * sizeof(T)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(A->ind, B->ind,
		2 * A->nnz * sizeof(I)) );
	return OK_SCAN_ERR(
		ok_memcpy_gpu(A->ptr, B->ptr,
			(2 + A->size1 + A->size2) * sizeof(I)) );
}

template <typename T, typename I>
ok_status sp_matrix_memcpy_vals_mm_(sp_matrix_<T, I> * A,
	const sp_matrix_<T, I> * B)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_SPARSEMAT(B);
	return OK_SCAN_ERR(
		ok_memcpy_gpu(A->val, B->val, 2 * A->nnz * sizeof(T)) );
}

#ifdef __cplusplus
extern "C" {
#endif

static ok_status __transpose_inplace(void * sparse_handle, sp_matrix * A,
	SPARSE_TRANSPOSE_DIRECTION dir)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_PTR(sparse_handle);

	ok_status err = OPTKIT_SUCCESS;
	ok_sparse_handle * sp_hdl = (ok_sparse_handle *) sparse_handle;
	int size1, size2;
	ok_int * ptr, * ind, * ptr_T, * ind_T;
	ok_float * val, * val_T;

	if (dir == Forward2Adjoint) {
		size1 = (A->order == CblasRowMajor) ? A->size1 : A->size2;
		size2 = (A->order == CblasRowMajor) ? A->size2 : A->size1;
		ptr = A->ptr;
		ind = A->ind;
		val = A->val;
		ptr_T = A->ptr + A->ptrlen;
		ind_T = A->ind + A->nnz;
		val_T = A->val + A->nnz;
	} else {
		size1 = (A->order == CblasRowMajor) ? A->size2 : A->size1;
		size2 = (A->order == CblasRowMajor) ? A->size1 : A->size2;
		ptr = A->ptr + A->ptrlen;
		ind = A->ind + A->nnz;
		val = A->val + A->nnz;
		ptr_T = A->ptr;
		ind_T = A->ind;
		val_T = A->val;
	}

	err = OK_SCAN_CUSPARSE( CUSPARSE(csr2csc)(*(sp_hdl->hdl), size1, size2,
		(int) A->nnz, val, ptr, ind, val_T, ind_T, ptr_T,
		CUSPARSE_ACTION_NUMERIC, CUSPARSE_INDEX_BASE_ZERO) );
	cudaDeviceSynchronize();
	return err;
}

ok_status sp_matrix_alloc(sp_matrix * A, size_t m, size_t n, size_t nnz,
	enum CBLAS_ORDER order)
	{ return sp_matrix_alloc_<ok_float, ok_int>(A, m, n, nnz, order); }

ok_status sp_matrix_calloc(sp_matrix * A, size_t m, size_t n, size_t nnz,
	enum CBLAS_ORDER order)
	{ return sp_matrix_calloc_<ok_float, ok_int>(A, m, n, nnz, order); }

ok_status sp_matrix_free(sp_matrix * A)
	{ return sp_matrix_free_<ok_float, ok_int>(A); }

ok_status sp_matrix_memcpy_mm(sp_matrix * A, const sp_matrix * B)
	{ return sp_matrix_memcpy_mm_<ok_float, ok_int>(A, B); }

ok_status sp_matrix_memcpy_ma(void * sparse_handle, sp_matrix * A,
	const ok_float * val, const ok_int * ind, const ok_int * ptr)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_PTR(sparse_handle);
	if (!val || !ind || !ptr)
		return OK_SCAN_ERR( OPTKIT_ERROR_UNALLOCATED );

	OK_RETURNIF_ERR( ok_memcpy_gpu(A->val, val, A->nnz * sizeof(*val)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(A->ind, ind, A->nnz * sizeof(*ind)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(A->ptr, ptr, A->ptrlen * sizeof(*ptr)) );

	return OK_SCAN_ERR(
		__transpose_inplace(sparse_handle, A, Forward2Adjoint) );
}

ok_status sp_matrix_memcpy_am(ok_float * val, ok_int * ind, ok_int * ptr,
	const sp_matrix * A)
{
	OK_CHECK_SPARSEMAT(A);
	if (!val || !ind || !ptr)
		return OK_SCAN_ERR( OPTKIT_ERROR_UNALLOCATED );

	OK_RETURNIF_ERR(ok_memcpy_gpu(val, A->val, A->nnz * sizeof(*val)) );
	OK_RETURNIF_ERR(ok_memcpy_gpu(ind, A->ind, A->nnz * sizeof(*ind)) );
	return OK_SCAN_ERR(
		ok_memcpy_gpu(ptr, A->ptr, A->ptrlen * sizeof(*ptr)) );
}

ok_status sp_matrix_memcpy_vals_mm(sp_matrix * A, const sp_matrix * B)
	{ return sp_matrix_memcpy_vals_mm_<ok_float, ok_int>(A, B); }


ok_status sp_matrix_memcpy_vals_ma(void * sparse_handle, sp_matrix * A,
	const ok_float * val)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_PTR(val);
	OK_CHECK_PTR(sparse_handle);

	OK_RETURNIF_ERR( ok_memcpy_gpu(A->val, val, A->nnz * sizeof(*val)) );
	return OK_SCAN_ERR(
		__transpose_inplace(sparse_handle, A, Forward2Adjoint) );
}

ok_status sp_matrix_memcpy_vals_am(ok_float * val, const sp_matrix * A)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_PTR(val);
	return OK_SCAN_ERR(
		ok_memcpy_gpu(val, A->val, A->nnz * sizeof(*val)) );
}

ok_status sp_matrix_abs(sp_matrix * A)
{
	OK_CHECK_SPARSEMAT(A);
	vector vals = (vector){2 * A->nnz, 1, A->val};
	__thrust_vector_abs(&vals);
	return OK_STATUS_CUDA;
}

ok_status sp_matrix_pow(sp_matrix * A, const ok_float x)
{
	OK_CHECK_SPARSEMAT(A);
	vector vals = (vector){2 * A->nnz, 1, A->val};
	__thrust_vector_pow(&vals, x);
	return OK_STATUS_CUDA;
}

ok_status sp_matrix_scale(sp_matrix * A, const ok_float alpha)
{
	OK_CHECK_SPARSEMAT(A);
	vector vals = (vector){2 * A->nnz, 1, A->val};
	__thrust_vector_scale(&vals, alpha);
	return OK_STATUS_CUDA;
}

/*
 * Always perform forward (non-transpose) scaling (contiguous blocks)
 * libcusparse uses csr, so for given (layout, scaling direction) pair:
 *
 *      csr, left scaling -> scale forward operator, transpose data F2A
 *      csr, right scaling -> scale adjoint operator, transpose data A2F
 *      csc, left scaling -> scale adjoint operator, transpose data A2F
 *      csc, right scaling -> scale forward operator, tranpose data F2A
 */
ok_status __sp_matrix_scale_diag(void * sparse_handle, sp_matrix * A,
	const vector * v, enum CBLAS_SIDE side)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_VECTOR(v);
	OK_CHECK_PTR(sparse_handle);

	ok_status err = OPTKIT_SUCCESS;
	size_t i, offset, offsetnz, stop;
	vector Asub = (vector){0, 1, OK_NULL};
	ok_float scal;
	ok_int ptr_host[2 + A->size1 + A->size2];
	SPARSE_TRANSPOSE_DIRECTION dir;

	if ((side == CblasLeft && A->size1 != v->size ) ||
		(side == CblasRight && A->size2 != v->size))
		return OK_SCAN_ERR( OPTKIT_ERROR_DIMENSION_MISMATCH );
	OK_RETURNIF_ERR( ok_memcpy_gpu(ptr_host, A->ptr,
		(2 + A->size1 + A->size2) * sizeof(ok_int)) );

	if (side == CblasLeft) {
		offsetnz = (A->order == CblasRowMajor) ? 0 : A->nnz;
		offset = (A->order == CblasRowMajor) ? 0 : A->ptrlen;
		stop = (A->order == CblasRowMajor) ?
		       A->ptrlen - 1 : 1 + A->size1 + A->size2;
		dir = (A->order == CblasRowMajor) ?
		      Forward2Adjoint : Adjoint2Forward;
	} else {
		offsetnz = (A->order == CblasRowMajor) ? A->nnz : 0;
		offset = (A->order == CblasRowMajor) ? A->ptrlen : 0;
		stop = (A->order == CblasRowMajor) ?
		       1 + A->size1 + A->size2 : A->ptrlen - 1;
		dir = (A->order == CblasRowMajor) ?
		       Adjoint2Forward : Forward2Adjoint;
	}

	for (i = offset; i < stop && !err; ++i) {
		if (ptr_host[i + 1] == ptr_host[i])
			continue;
		OK_CHECK_ERR( err, ok_memcpy_gpu(&scal,
			v->data + (i - offset) * v->stride, sizeof(ok_float)) );

		Asub.size = ptr_host[i + 1] - ptr_host[i];
		Asub.data = A->val + offsetnz + ptr_host[i];
		__thrust_vector_scale(&Asub, scal);
		OK_MAX_ERR( err, OK_STATUS_CUDA );

	}
	OK_CHECK_ERR( err, __transpose_inplace(sparse_handle, A, dir) );
	return err;
}

ok_status sp_matrix_scale_left(void * sparse_handle, sp_matrix * A,
	const vector * v)
	{ return __sp_matrix_scale_diag(sparse_handle, A, v, CblasLeft); }

ok_status sp_matrix_scale_right(void * sparse_handle, sp_matrix * A,
	const vector * v)
	{ return __sp_matrix_scale_diag(sparse_handle, A, v, CblasRight); }

ok_status sp_matrix_print(const sp_matrix * A)
{
	OK_CHECK_SPARSEMAT(A);
	size_t i;
	ok_int j, ptr1, ptr2;
	ok_float val_host[A->nnz];
	ok_int ind_host[A->nnz];
	ok_int ptr_host[A->ptrlen];

	OK_RETURNIF_ERR( ok_memcpy_gpu(val_host, A->val,
		A->nnz * sizeof(ok_float)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(ind_host, A->ind,
		A->nnz * sizeof(ok_int)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(ptr_host, A->ptr,
		A->ptrlen * sizeof(ok_int)) );

	if (A->order == CblasRowMajor)
		printf("sparse CSR matrix:\n");
	else
		printf("sparse CSC matrix:\n");

	printf("dims: %u, %u\n", (uint) A->size1, (uint) A->size2);
	printf("# nonzeros: %u\n", (uint) A->nnz);

	if (A->order == CblasRowMajor)
		for(i = 0; i < A->ptrlen - 1; ++ i) {
			ptr1 = ptr_host[i];
			ptr2 = ptr_host[i + 1];
			for(j = ptr1; j < ptr2; ++j)
				printf("(%i, %i)\t%e\n", (int) i,  ind_host[j],
					val_host[j]);
		}
	else
		for(i = 0; i < A->ptrlen - 1; ++ i) {
			ptr1 = ptr_host[i];
			ptr2 = ptr_host[i + 1];
			for(j = ptr1; j < ptr2; ++j)
				printf("(%i, %i)\t%e\n", ind_host[j], (int) i,
					val_host[j]);
		}
	printf("\n");
	return OPTKIT_SUCCESS;
}

ok_status sp_matrix_print_transpose(const sp_matrix * A)
{
	OK_CHECK_SPARSEMAT(A);
	size_t i;
	size_t ptrlen = A->size1 + A->size2 + 2 - A->ptrlen;
	ok_int j, ptr1, ptr2;
	ok_float val_host[A->nnz];
	ok_int ind_host[A->nnz];
	ok_int ptr_host[ptrlen];

	OK_RETURNIF_ERR( ok_memcpy_gpu(val_host, A->val + A->nnz,
		A->nnz * sizeof(ok_float)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(ind_host, A->ind + A->nnz,
		A->nnz * sizeof(ok_int)) );
	OK_RETURNIF_ERR( ok_memcpy_gpu(ptr_host, A->ptr + A->ptrlen,
		ptrlen * sizeof(ok_int)) );

	if (A->order == CblasRowMajor)
		printf("sparse CSC matrix:\n");
	else
		printf("sparse CSR matrix:\n");

	printf("dims: %u, %u\n", (uint) A->size1, (uint) A->size2);
	printf("# nonzeros: %u\n", (uint) A->nnz);

	if (A->order == CblasRowMajor)
		for(i = 0; i < ptrlen - 1; ++ i) {
			ptr1 = ptr_host[i];
			ptr2 = ptr_host[i + 1];
			for(j = ptr1; j < ptr2; ++j)
				printf("(%i, %i)\t%e\n", ind_host[j], (int) i,
					val_host[j]);
		}
	else
		for(i = 0; i < ptrlen - 1; ++ i) {
			ptr1 = ptr_host[i];
			ptr2 = ptr_host[i + 1];
			for(j = ptr1; j < ptr2; ++j)
				printf("(%i, %i)\t%e\n", (int) i,  ind_host[j],
					val_host[j]);
		}
	printf("\n");
	return OPTKIT_SUCCESS;
}

/*
 * Always perform forward (non-transpose) operations
 * cusparse library uses csr layout, so for given (layout, op):
 *      csr, forward op -> apply stored forward operator
 *      csr, adjoint op -> apply stored adjoint operator
 *      csc, forward op -> apply stored adjoint operator
 *      csc, adjoint op -> apply stored forward operator
 */
ok_status sp_blas_gemv(void * sparse_handle, enum CBLAS_TRANSPOSE transA,
	ok_float alpha, sp_matrix * A, vector * x, ok_float beta, vector * y)
{
	OK_CHECK_SPARSEMAT(A);
	OK_CHECK_VECTOR(x);
	OK_CHECK_VECTOR(y);
	OK_CHECK_PTR(sparse_handle);

	if ((transA == CblasNoTrans &&
		(A->size1 != y->size || A->size2 != x->size)) ||
	    (transA == CblasTrans &&
	    	(A->size1 != x->size || A->size2 != y->size)))
	    	return OK_SCAN_ERR( OPTKIT_ERROR_DIMENSION_MISMATCH );

	ok_status err = OPTKIT_SUCCESS;
	ok_sparse_handle * sp_hdl = (ok_sparse_handle *) sparse_handle;
	int forward = ((A->order == CblasRowMajor) == (transA == CblasNoTrans));
	int size1 = (transA == CblasNoTrans) ? (int) A->size1 : (int) A->size2;
	int size2 = (transA == CblasNoTrans) ? (int) A->size2 : (int) A->size1;
	size_t offset = forward ? 0 : A->nnz;
	size_t offset_ptr = forward ? 0 : A->ptrlen;

	err = OK_SCAN_CUSPARSE( CUSPARSE(csrmv)( *(sp_hdl->hdl),
		CUSPARSE_OPERATION_NON_TRANSPOSE, size1, size2, (int) A->nnz,
		&alpha, *(sp_hdl->descr), A->val + offset, A->ptr + offset_ptr,
		A->ind + offset, x->data, &beta, y->data) );
	cudaDeviceSynchronize();
	return err;
}

#ifdef __cplusplus
}
#endif
