
SUB_DIRS:=kernelspace userspace scripts statistics tools
CLEAN_DIRS = $(SUB_DIRS:%=clean-%)


.PHONY: build_subdirs $(SUB_DIRS) $(CLEAN_DIRS)

all:	build_subdirs


build_subdirs: $(SUB_DIRS)

$(SUB_DIRS):
	cd $@; $(MAKE); cd ..


clean: $(CLEAN_DIRS)


$(CLEAN_DIRS):
	cd $(@:clean-%=%); $(MAKE) clean; cd ..


dist: clean
	rm -rf `cat .fname` .fname
	$(eval AUX_FILES := $(shell find . -maxdepth 1 -type f))
	sed -e 's/\s//' -e 's/\(.*\)/timer-netsend-test_\1/' VERSION >.fname
	mkdir `cat .fname`
	$(foreach dir,$(SUB_DIRS),cp -R $(dir) `cat .fname`;)
	cp $(AUX_FILES) `cat .fname`
	tar czvf `cat .fname`.tar.gz --exclude='*.tar.gz' `cat .fname`
	rm -rf `cat .fname` .fname
	

