# GNU Make assumed below
# TODO: convert project to automake?

HTML_DOCS = README.html TODO.html
ASCIIDOC = asciidoc

%.html : %.asciidoc
	$(ASCIIDOC) -b html $< > $@

all: doc
# pkg rpm

clean:
	rm -rf build/ $(HTML_DOCS)

doc: $(HTML_DOCS)

#pkg, rpm:
# 1) Prepare the install-tree as expected by solaris/linux packaging
# 2) Adapt provided packaging files (e.g. embed Git commit as version)
# 2) Use platform packaging files to build the package
