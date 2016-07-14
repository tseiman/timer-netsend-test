
SUB_DIRS:=stress-ng
CLEAN_DIRS = $(SUB_DIRS:%=clean-%)


.PHONY: build_subdirs $(SUB_DIRS) $(CLEAN_DIRS)

all:	build_subdirs


build_subdirs: $(SUB_DIRS)

$(SUB_DIRS):
	cd $@; $(MAKE); cd ..


clean: $(CLEAN_DIRS)


$(CLEAN_DIRS):
	cd $(@:clean-%=%); $(MAKE) clean; cd ..

