NPROC ?= 1

all:
	verilator --binary lisp.sv --build-jobs $(NPROC)

clean:
	rm -rf obj_dir
