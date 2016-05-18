#!/bin/bash
FLOAT=${OPTKIT_TEST_FLOAT:-0}
GPU=${OPTKIT_TEST_GPU:-0}
TEST_TRANSPOSE=${OPTKIT_TEST_TRANSPOSE:-0}

# get script directory
HOME=`dirname $0`

# ARG 1: test level (if int) or test name (if string)
arg="${1:-0}"
level=${arg//[^0-9]}
level=${level:-\-1}
if [[ $arg = *+ ]]; then
floor=$level
else
floor=0
fi

# ARG 2: TODO: set default matrix if valid path provided
# if valid path provided, set TEST_TRANSPOSE=0

# run tests on (m x n) and (n x m) matrices (TEST_TRANSPOSE=1)
# or just a (m x n) matrix (TEST_TRANSPOSE=0), 
# for some random m, n generated by this script
if (( TEST_TRANSPOSE == 1 )); then
	TRANSPOSE_STATES=0 1
else
	TRANSPOSE_STATES=0
fi

# parse test level/test name
# level 0
if (( level >= 0 && floor <= 0 )) || [ $arg = "vector" ]; then
	VECTOR=1
fi
# level 1
if (( level >= 1 && floor <= 1 )) || [ $arg = "matrix" ]; then
	MATRIX=1
fi
if (( level >= 1 && floor <= 1 )) || [ $arg = "dense" ]; then
	DENSE=1
fi
if (( level >= 1 && floor <= 1 )) || [ $arg = "sparse" ]; then
	SPARSE=1
fi
if (( level >= 1 && floor <= 1 )) || [ $arg = "prox" ]; then
	PROX=1
fi
# level 2
if (( level >= 2 && floor <= 2 )) || [ $arg = "operator" ]; then
	OPERATOR=1
fi
if (( level >= 2 && floor <= 2 )) || [ $arg = "cluster" ]; then
	CLUSTER=1
fi
# level 3
if (( level >= 3 && floor <= 3 )) || [ $arg = "cg" ]; then
	CG=1
fi
if (( level >= 3 && floor <= 3 )) || [ $arg = "equil" ]; then
	EQUIL=1
fi
# level 4
if (( level >= 4 && floor <= 4 )) || [ $arg = "proj" ]; then
	PROJECTOR=1
fi
# level 5
if (( level >= 5 && floor <= 5 )) || [ $arg = "pogs" ]; then
	POGS_DENSE=1
fi
if (( level >= 5 && floor <= 5 )) || [ $arg = "apogs" ]; then
	POGS_ABSTRACT=1
fi

# generate random problem size in R^{m~U[500,1000) x n~U[500,1000)}
dim1=$(($RANDOM % 500 + 500))
dim2=$(($RANDOM % 500 + 500))

mkdir -p ${HOME}/build
export OPTKIT_C_TESTING=1
config=${GPU/0/cpu}
config=${config/1/gpu}
config=${config}${FLOAT/0/64}
config=${config/1/32}

for transpose in ${TRANSPOSE_STATES}; do
	if (( transpose > 0 )); then
		export OPTKIT_TESTING_DEFAULT_NROWS=$dim1
		export OPTKIT_TESTING_DEFAULT_NCOLS=$dim2
	else
		export OPTKIT_TESTING_DEFAULT_NROWS=$dim2
		export OPTKIT_TESTING_DEFAULT_NCOLS=$dim1
	fi

	msg=TEST\ MATRIX\ SIZE:\ \(DIM1\ x\ DIM2\)
	msg=${msg/DIM1/$OPTKIT_TESTING_DEFAULT_NROWS}
	msg=${msg/DIM2/$OPTKIT_TESTING_DEFAULT_NCOLS}

	testprefix=./python/optkit/tests/C/test_
	suffix=.py\ --nocapture

	if [[ ${VECTOR:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libok_dense_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libok_dense FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING VECTOR CALLS
		nosetests ${testprefix}vector${suffix}
	fi 

	if [[ ${MATRIX:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libok_dense_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libok_dense FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING MATRIX CALLS: ${msg}
		nosetests ${testprefix}matrix${suffix}
	fi

	if [[ ${DENSE:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libok_dense_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libok_dense FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING \(DENSE\) LINSYS CALLS: ${msg}
		nosetests ${testprefix}linsys_dense${suffix}
	fi

	if [[ ${SPARSE:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libok_sparse_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libok_sparse FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING \(SPARSE\) LINSYS CALLS: ${msg}
		nosetests ${testprefix}linsys_sparse${suffix}
	fi

	if [[ ${PROX:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libprox_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libprox FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING PROX CALLS
		nosetests ${testprefix}prox${suffix}
	fi

	if [[ ${OPERATOR:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep liboperator_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make liboperator FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING OPERATOR CALLS: ${msg}
		nosetests ${testprefix}operator${suffix}
	fi

	if [[ ${CLUSTER:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libcluster_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libcluster FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING CLUSTER CALLS: ${msg}
		nosetests ${testprefix}clustering${suffix}
	fi

	if [[ ${CG:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libcg_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libcg FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING CG CALLS: ${msg}
		nosetests ${testprefix}cg${suffix}
	fi

	if [[ ${EQUIL:-0} -eq 1 ]]; then	
		lib=$(ls ${HOME}/build | grep libequil_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libequil FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING EQUILIBRATION CALLS: ${msg}
		nosetests ${testprefix}equilibration${suffix}
	fi 

	if [[ ${PROJECTOR:-0} -eq 1 ]]; then
		lib=$(ls ${HOME}/build | grep libprojector_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libprojector FLOAT=$FLOAT GPU=$GPU
		fi
		echo TESTING PROJECTOR CALLS: ${msg}
		nosetests ${testprefix}projector${suffix}
	fi
				
	if [[ ${POGS_DENSE:-0} -eq 1 ]]; then
		export OPTKIT_DEBUG_PYTHON=1
		lib=$(ls ${HOME}/build | grep libpogs_dense_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libpogs_dense FLOAT=$FLOAT GPU=$GPU
		fi
		export OPTKIT_DEBUG_PYTHON=0
		echo TESTING \(DENSE\) POGS CALLS: ${msg}
		nosetests ${testprefix}pogs${suffix}
	fi

	if [[ ${POGS_ABSTRACT:-0} -eq 1 ]]; then
		export OPTKIT_DEBUG_PYTHON=1
		lib=$(ls ${HOME}/build | grep libpogs_abstract_${config})
		if [[ -d ./build ]] && [[ ${lib:-""} = "" ]]; then
			make libpogs_abstract FLOAT=$FLOAT GPU=$GPU
		fi
		export OPTKIT_DEBUG_PYTHON=0
		echo TESTING \(ABSTRACT\) POGS CALLS: ${msg}
		nosetests ${testprefix}abstract_pogs${suffix}
	fi

done
export OPTKIT_C_TESTING=0