# Copyright (c) 2015-2025 Franco Fichtner <franco@opnsense.org>
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions
# are met:
#
# 1. Redistributions of source code must retain the above copyright
#    notice, this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright
#    notice, this list of conditions and the following disclaimer in the
#    documentation and/or other materials provided with the distribution.
#
# THIS SOFTWARE IS PROVIDED BY THE AUTHOR AND CONTRIBUTORS ``AS IS'' AND
# ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED.  IN NO EVENT SHALL THE AUTHOR OR CONTRIBUTORS BE LIABLE
# FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
# DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS
# OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION)
# HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
# LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY
# OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF
# SUCH DAMAGE.

all: check

.include "defaults.mk"

PLUGINSDIR?=		${.CURDIR}/../..
SCRIPTSDIR=		${PLUGINSDIR}/Scripts
TEMPLATESDIR=		${PLUGINSDIR}/Templates

.if exists(${GIT}) && exists(${GITVERSION})
PLUGIN_COMMIT!=		${GITVERSION}
.else
PLUGIN_COMMIT=		unknown 0 undefined
.endif

PLUGIN_HASH?=		${PLUGIN_COMMIT:[3]}

PLUGIN_DESC=		pkg-descr
PLUGIN_SCRIPTS=		+PRE_INSTALL +POST_INSTALL \
			+PRE_DEINSTALL +POST_DEINSTALL

PLUGIN_WWW?=		https://opnsense.org/
PLUGIN_LICENSE?=	BSD2CLAUSE
PLUGIN_TIER?=		3
PLUGIN_REVISION?=	0

PLUGIN_REQUIRES=	PLUGIN_NAME PLUGIN_VERSION PLUGIN_COMMENT \
			PLUGIN_MAINTAINER

check:
.for PLUGIN_REQUIRE in ${PLUGIN_REQUIRES}
.  if "${${PLUGIN_REQUIRE}}" == ""
.    error "${PLUGIN_REQUIRE} not set"
.  endif
.endfor

_PLUGIN_COMMENT:=	${PLUGIN_COMMENT}

.if defined(_PLUGIN_DEVEL)
PLUGIN_DEVEL?:=		${_PLUGIN_DEVEL}
.else
PLUGIN_DEVEL?=		yes
.endif

PLUGIN_PREFIX?=		os-
PLUGIN_SUFFIX?=		-devel

.for CONFLICT in ${PLUGIN_CONFLICTS}
PLUGIN_CONFLICTS+=	${CONFLICT}${PLUGIN_SUFFIX}
.endfor

.if !empty(PLUGIN_VARIANTS)
PLUGIN_VARIANT?=	${PLUGIN_VARIANTS:[1]}
.if "${PLUGIN_VARIANT}" == ""
.error Plugin variant cannot be empty
.else
PLUGIN_NAME:=		${${PLUGIN_VARIANT}_NAME}
.if empty(PLUGIN_NAME)
.error Plugin variant '${PLUGIN_VARIANT}' does not exist
.endif
.for _PLUGIN_VARIANT in ${PLUGIN_VARIANTS:N${PLUGIN_VARIANT}}
PLUGIN_CONFLICTS+=	${${_PLUGIN_VARIANT}_NAME}${PLUGIN_SUFFIX} \
			${${_PLUGIN_VARIANT}_NAME}
.endfor
PLUGIN_DEPENDS+=	${${PLUGIN_VARIANT}_DEPENDS}
.if !empty(${PLUGIN_VARIANT}_COMMENT)
_PLUGIN_COMMENT:=	${${PLUGIN_VARIANT}_COMMENT}
.endif
.endif
.endif

.if !empty(PLUGIN_NAME)
PLUGIN_DIR?=		${.CURDIR:S/\// /g:[-2]}/${.CURDIR:S/\// /g:[-1]}
.endif

.if "${PLUGIN_DEVEL}" != ""
PLUGIN_CONFLICTS+=	${PLUGIN_NAME}
PLUGIN_PKGSUFFIX=	${PLUGIN_SUFFIX}
PLUGIN_TIER=		4
.else
PLUGIN_CONFLICTS+=	${PLUGIN_NAME}${PLUGIN_SUFFIX}
PLUGIN_PKGSUFFIX=	# empty
.endif

PLUGIN_CONFLICTS:=	${PLUGIN_CONFLICTS:S/^/${PLUGIN_PREFIX}/g:O}

PLUGIN_PKGNAME=		${PLUGIN_PREFIX}${PLUGIN_NAME}${PLUGIN_PKGSUFFIX}
PLUGIN_PKGNAMES=	${PLUGIN_CONFLICTS} ${PLUGIN_PKGNAME}

.if "${PLUGIN_REVISION}" != "" && "${PLUGIN_REVISION}" != "0"
PLUGIN_PKGVERSION=	${PLUGIN_VERSION}_${PLUGIN_REVISION}
.else
PLUGIN_PKGVERSION=	${PLUGIN_VERSION}
.endif

manifest: check
	@echo "name: ${PLUGIN_PKGNAME}"
	@echo "version: \"${PLUGIN_PKGVERSION}\""
	@echo "origin: opnsense/${PLUGIN_PKGNAME}"
	@echo "comment: \"${_PLUGIN_COMMENT}\""
	@echo "maintainer: \"${PLUGIN_MAINTAINER}\""
	@echo "categories: [ \"${.CURDIR:S/\// /g:[-2]}\" ]"
	@echo "www: \"${PLUGIN_WWW}\""
	@echo "prefix: \"${LOCALBASE}\""
	@echo "licenselogic: \"single\""
	@echo "licenses: [ \"${PLUGIN_LICENSE}\" ]"
.if defined(PLUGIN_NO_ABI)
	@echo "arch: \"${OSABIPREFIX:tl}:*:*\""
	@echo "abi: \"${OSABIPREFIX}:*:*\""
.endif
.if defined(PLUGIN_DEPENDS)
	@echo "deps: {"
	@for PLUGIN_DEPEND in ${PLUGIN_DEPENDS}; do \
		if ! ${PKG} query '  %n: { version: "%v", origin: "%o" }' \
		    $${PLUGIN_DEPEND}; then \
			echo ">>> Missing dependency: $${PLUGIN_DEPEND}" >&2; \
			exit 1; \
		fi; \
	done
	@echo "}"
.endif
	@if [ -f ${WRKSRC}${LOCALBASE}/opnsense/version/${PLUGIN_NAME} ]; then \
	    echo "annotations $$(cat ${WRKSRC}${LOCALBASE}/opnsense/version/${PLUGIN_NAME})"; \
	fi

# Package scripts generation handling 101:
#
# "auto" generates automatic hooks that a plugin may need in order to
# reload on the fly. ".pre" and ".post" suffixed files can be used to
# extend the auto-generated content.
#
# "manual" overwrites the automatic script and also ignores ".pre" and
# ".post" files since they do not make sense in manual mode.
#
# Furthermore, variable replacement via %%PLUGIN_VAR%% takes place in
# "manual" as well as ".pre" and ".post" scripts provided.

scripts: check scripts-pre scripts-auto scripts-post scripts-manual

scripts-pre:
	@for SCRIPT in ${PLUGIN_SCRIPTS}; do \
		rm -f ${DESTDIR}/$${SCRIPT}; \
		if [ -f ${.CURDIR}/$${SCRIPT}.pre ]; then \
			sed ${SED_REPLACE} -- ${.CURDIR}/$${SCRIPT}.pre > \
			    ${DESTDIR}/$${SCRIPT}; \
		fi; \
	done

scripts-auto:
	@if [ -d ${.CURDIR}/src/etc/rc.syshook.d ]; then \
		for SYSHOOK in early start; do \
			for FILE in $$(cd ${.CURDIR}/src/etc/rc.syshook.d && \
			    find -s . -type f -name "*.$${SYSHOOK}"); do \
				echo ${LOCALBASE}/etc/rc.syshook.d/$${FILE#./} >> \
				    ${DESTDIR}/+POST_INSTALL; \
			done; \
		done; \
	fi
	@if [ -d ${.CURDIR}/src/opnsense/service/conf/actions.d ]; then \
		cat ${TEMPLATESDIR}/actions.d >> ${DESTDIR}/+POST_INSTALL; \
	fi
	@if [ -d ${.CURDIR}/src/etc/rc.loader.d ]; then \
		for SCRIPT in +POST_INSTALL +POST_DEINSTALL; do \
			cat ${TEMPLATESDIR}/rc.loader.d >> \
			    ${DESTDIR}/$${SCRIPT}; \
		done; \
	fi
	@if [ -d ${.CURDIR}/src/opnsense/mvc/app/models ]; then \
		for FILE in $$(cd ${.CURDIR}/src/opnsense/mvc/app/models && \
		    find -s . -depth 2 -type d); do \
			cat ${TEMPLATESDIR}/models | \
			    sed "s:%%ARG%%:$${FILE#./}:g" >> \
			    ${DESTDIR}/+POST_INSTALL; \
		done; \
		for SCRIPT in +POST_INSTALL +POST_DEINSTALL; do \
			cat ${TEMPLATESDIR}/configure | \
			    sed "s:%%ARG%%:$${SCRIPT#+}:g" >> \
			    ${DESTDIR}/$${SCRIPT}; \
		done; \
	fi
	@if [ -d ${.CURDIR}/src/opnsense/service/templates ]; then \
		for FILE in $$(cd ${.CURDIR}/src/opnsense/service/templates && \
		    find -s . -depth 2 -type d); do \
			cat ${TEMPLATESDIR}/templates | \
			    sed "s:%%ARG%%:$${FILE#./}:g" >> \
			    ${DESTDIR}/+POST_INSTALL; \
		done; \
	fi
	@if [ -d ${.CURDIR}/src/opnsense/scripts/firmware/repos ]; then \
		for FILE in $$(cd ${.CURDIR}/src && find -s \
		    opnsense/scripts/firmware/repos -type f); do \
			echo "${LOCALBASE}/$${FILE#.}" >> ${DESTDIR}/+POST_INSTALL; \
		done \
	fi

scripts-post:
	@for SCRIPT in ${PLUGIN_SCRIPTS}; do \
		if [ -f ${.CURDIR}/$${SCRIPT}.post ]; then \
			sed ${SED_REPLACE} -- ${.CURDIR}/$${SCRIPT}.post >> \
			    ${DESTDIR}/$${SCRIPT}; \
		fi; \
	done

scripts-manual:
	@for SCRIPT in ${PLUGIN_SCRIPTS}; do \
		if [ -f ${.CURDIR}/$${SCRIPT} ]; then \
			sed ${SED_REPLACE} -- ${.CURDIR}/$${SCRIPT} > \
			    ${DESTDIR}/$${SCRIPT}; \
		fi; \
	done

install: check
	@mkdir -p ${DESTDIR}${LOCALBASE}/opnsense/version
	@(cd ${.CURDIR}/src 2> /dev/null && find * -type f) | while read FILE; do \
		tar -C ${.CURDIR}/src -cpf - "$${FILE}" | \
		    tar -C ${DESTDIR}${LOCALBASE} -xpf -; \
		if [ "$${FILE%%.in}" != "$${FILE}" ]; then \
			sed -i '' ${SED_REPLACE} "${DESTDIR}${LOCALBASE}/$${FILE}"; \
			mv "${DESTDIR}${LOCALBASE}/$${FILE}" "${DESTDIR}${LOCALBASE}/$${FILE%%.in}"; \
			FILE="$${FILE%%.in}"; \
		fi; \
		if [ "$${FILE%%.shadow}" != "$${FILE}" ]; then \
			mv "${DESTDIR}${LOCALBASE}/$${FILE}" \
			    "${DESTDIR}${LOCALBASE}/$${FILE%%.shadow}.sample"; \
		fi; \
		if [ "$${FILE%%/*}" == "man" ]; then \
			gzip -cn "${DESTDIR}${LOCALBASE}/$${FILE}" > \
			    "${DESTDIR}${LOCALBASE}/$${FILE}.gz"; \
			rm "${DESTDIR}${LOCALBASE}/$${FILE}"; \
		fi; \
	done
	@cat ${TEMPLATESDIR}/version | sed ${SED_REPLACE} > "${DESTDIR}${LOCALBASE}/opnsense/version/${PLUGIN_NAME}"

plist: check
	@(cd ${.CURDIR}/src 2> /dev/null && find * -type f) | while read FILE; do \
		if [ -f "$${FILE}.in" ]; then continue; fi; \
		FILE="$${FILE%%.in}"; PREFIX=""; \
		if [ "$${FILE%%.sample}" != "$${FILE}" ]; then \
			PREFIX="@sample "; \
		elif [ "$${FILE%%.shadow}" != "$${FILE}" ]; then \
			FILE="$${FILE%%.shadow}.sample"; \
			PREFIX="@shadow "; \
		fi; \
		if [ "$${FILE%%/*}" == "man" ]; then \
			FILE="$${FILE}.gz"; \
		fi; \
		echo "$${PREFIX}${LOCALBASE}/$${FILE}"; \
	done
	@echo "${LOCALBASE}/opnsense/version/${PLUGIN_NAME}"

description: check
	@if [ -f ${.CURDIR}/${PLUGIN_DESC} ]; then \
		cat ${.CURDIR}/${PLUGIN_DESC}; \
	fi

metadata: check
	@mkdir -p ${DESTDIR}
	@${MAKE} DESTDIR=${DESTDIR} scripts
	@${MAKE} DESTDIR=${DESTDIR} manifest > ${DESTDIR}/+MANIFEST
	@${MAKE} DESTDIR=${DESTDIR} description > ${DESTDIR}/+DESC
	@${MAKE} DESTDIR=${DESTDIR} plist > ${DESTDIR}/plist

collect: check
	@(cd ${.CURDIR}/src 2> /dev/null && find * -type f) | while read FILE; do \
		tar -C ${DESTDIR}${LOCALBASE} -cpf - "$${FILE}" | \
		    tar -C ${.CURDIR}/src -xpf -; \
	done

remove: check
	@(cd ${.CURDIR}/src 2> /dev/null && find * -type f) | while read FILE; do \
		rm -f "${DESTDIR}${LOCALBASE}/$${FILE}"; \
	done
	@(cd ${.CURDIR}/src 2> /dev/null && find * -type d -depth) | while read DIR; do \
		if [ -d "${DESTDIR}${LOCALBASE}/$${DIR}" ]; then \
			rmdir "${DESTDIR}${LOCALBASE}/$${DIR}" 2> /dev/null || true; \
		fi; \
	done

WRKDIR?=${.CURDIR}/work
WRKSRC?=${WRKDIR}/src
PKGDIR?=${WRKDIR}/pkg

ensure-workdirs:
	@mkdir -p ${WRKSRC} ${PKGDIR}

package: check
	@rm -rf ${WRKSRC}
	@mkdir -p ${WRKSRC} ${PKGDIR}
.for DEP in ${PLUGIN_DEPENDS}
	@if ! ${PKG} info ${DEP} > /dev/null; then ${PKG} install -yA ${DEP}; fi
.endfor
	@echo -n ">>> Staging files for ${PLUGIN_PKGNAME}-${PLUGIN_PKGVERSION}..."
	@${MAKE} DESTDIR=${WRKSRC} install
	@echo " done"
	@echo ">>> Generated version info for ${PLUGIN_PKGNAME}-${PLUGIN_PKGVERSION}:"
	@cat ${WRKSRC}${LOCALBASE}/opnsense/version/${PLUGIN_NAME}
	@echo -n ">>> Generating metadata for ${PLUGIN_PKGNAME}-${PLUGIN_PKGVERSION}..."
	@${MAKE} DESTDIR=${WRKSRC} metadata
	@echo " done"
	@echo ">>> Packaging files for ${PLUGIN_PKGNAME}-${PLUGIN_PKGVERSION}:"
	@PORTSDIR=${PLUGINSDIR} ${PKG} create -v -m ${WRKSRC} -r ${WRKSRC} \
	    -p ${WRKSRC}/plist -o ${PKGDIR}

upgrade-check: check
	@rm -rf ${PKGDIR}

upgrade: upgrade-check package
.for NAME in ${PLUGIN_PKGNAMES}
	@if ${PKG} info ${NAME} 2> /dev/null > /dev/null; then \
		${PKG} delete -fy ${NAME}; \
	fi
.endfor
	@${PKG} add ${PKGDIR}/*.pkg

mount: check
	mount_unionfs ${.CURDIR}/src ${DESTDIR}${LOCALBASE}

umount: check
	umount -f "<above>:${.CURDIR}/src"

clean: check
	@if [ -d ${.CURDIR}/src ]; then \
	    git reset -q ${.CURDIR}/src && \
	    git checkout -f ${.CURDIR}/src && \
	    git clean -xdqf ${.CURDIR}/src; \
	fi
	@rm -rf ${.CURDIR}/work

lint-desc: check
	@if [ ! -f ${.CURDIR}/${PLUGIN_DESC} ]; then \
		echo ">>> Missing ${PLUGIN_DESC}"; exit 1; \
	fi

lint-shell:
	@for FILE in $$(find ${.CURDIR}/src -name "*.sh" -type f); do \
	    if [ "$$(head $${FILE} | grep -c '^#!\/')" == "0" ]; then \
	        echo "Missing shebang in $${FILE}"; exit 1; \
	    fi; \
	    sh -n "$${FILE}" || exit 1; \
	done

lint-xml:
	@find ${.CURDIR}/src \
	    -name "*.xml" -type f -print0 | xargs -0 -n1 xmllint --noout

lint-model:
	@if [ -d ${.CURDIR}/src/opnsense/mvc/app/models ]; then for MODEL in $$(find ${.CURDIR}/src/opnsense/mvc/app/models -depth 3 \
	    -name "*.xml"); do \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and (not(Required) or Required="N") and Default]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} has a spurious default value set"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and Default=""]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} has an empty default value set"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and BlankDesc="None"]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} blank description is the default"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and BlankDesc and Required="Y"]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} blank description not applicable on required field"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and BlankDesc and Multiple="Y"]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} blank description not applicable on multiple field"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and Multiple="N"]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} Multiple=N is the default"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type and not(@type="ArrayField") and OptionValues[default[not(@value)] or multiple[not(@value)] or required[not(@value)]]]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} option element default/multiple/required without value attribute"; \
		done; \
		(xmllint $${MODEL} --xpath '//*[@type="CSVListField" and Mask and (not(MaskPerItem) or MaskPerItem=N)]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
			echo "$${MODEL}: $${LINE} uses Mask regex with MaskPerItem=N"; \
		done; \
		for TYPE in .\\AliasesField .\\DomainIPField HostnameField IPPortField NetworkField MacAddressField .\\RangeAddressField; do \
			(xmllint $${MODEL} --xpath '//*[@type="'$${TYPE}'" and FieldSeparator=","]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
				echo "$${MODEL}: $${LINE} FieldSeparator=, is the default"; \
			done; \
			(xmllint $${MODEL} --xpath '//*[@type="'$${TYPE}'" and AsList="N"]' 2> /dev/null | grep '^<' || true) | while read LINE; do \
				echo "$${MODEL}: $${LINE} AsList=N is the default"; \
			done; \
		done; \
	done; fi

ACLBIN?=	${.CURDIR}/../../../core/Scripts/dashboard-acl.sh

lint-acl: check
.if exists(${ACLBIN})
	@${ACLBIN} ${.CURDIR}/../../../core
.else
	@echo "Did not find ACLBIN, please provide a core repository"; exit 1
.endif

lint-exec: check
.for DIR in ${.CURDIR}/src/opnsense/scripts ${.CURDIR}/src/etc/rc.d ${.CURDIR}/src/etc/rc.syshook.d
.if exists(${DIR})
	@find ${DIR} -type f ! -name "*.xml" -print0 | \
	    xargs -0 -t -n1 test -x || \
	    (echo "Missing executable permission in ${DIR}"; exit 1)
.endif
.endfor

LINTBIN?=	${.CURDIR}/../../../core/contrib/parallel-lint/parallel-lint

lint-php: check
.if exists(${LINTBIN})
	@if [ -d ${.CURDIR}/src ]; then ${LINTBIN} src; fi
.else
	@echo "Did not find LINTBIN, please provide a core repository"; exit 1
.endif

lint: lint-desc lint-shell lint-xml lint-model lint-acl lint-exec lint-php

plist-fix:

sweep: check
	find ${.CURDIR}/src -type f -name "*.map" -print0 | \
	    xargs -0 -n1 rm
	find ${.CURDIR}/src ! -name "*.min.*" ! -name "*.svg" \
	    ! -name "*.ser" -type f -print0 | \
	    xargs -0 -n1 ${SCRIPTSDIR}/cleanfile
	find ${.CURDIR} -type f -depth 1 -print0 | \
	    xargs -0 -n1 ${SCRIPTSDIR}/cleanfile

glint: sweep style-fix plist-fix lint

revision:
	@MAKE=${MAKE} ${SCRIPTSDIR}/revbump.sh ${.CURDIR}

STYLEDIRS?=	src/etc/inc src/opnsense

style: check
	@: > ${.CURDIR}/.style.out
.for STYLEDIR in ${STYLEDIRS}
	@if [ -d ${.CURDIR}/${STYLEDIR} ]; then \
		(phpcs --standard=${PLUGINSDIR}/ruleset.xml \
		    ${.CURDIR}/${STYLEDIR} || true) > \
		    ${.CURDIR}/.style.out; \
	fi
.endfor
	@echo -n "Total number of style warnings: "
	@grep '| WARNING' ${.CURDIR}/.style.out | wc -l
	@echo -n "Total number of style errors:   "
	@grep '| ERROR' ${.CURDIR}/.style.out | wc -l
	@cat ${.CURDIR}/.style.out
	@rm ${.CURDIR}/.style.out

style-fix: check
.for STYLEDIR in ${STYLEDIRS}
	@if [ -d ${.CURDIR}/${STYLEDIR} ]; then \
		phpcbf --standard=${PLUGINSDIR}/ruleset.xml \
		    ${.CURDIR}/${STYLEDIR} || true; \
	fi
.endfor

style-python: check
	@if [ -d ${.CURDIR}/src ]; then \
		pycodestyle --ignore=E501 ${.CURDIR}/src || true; \
	fi

style-model:
	@if [ -d ${.CURDIR}/src/opnsense/mvc/app/models ]; then \
		for MODEL in $$(find ${.CURDIR}/src/opnsense/mvc/app/models -depth 3 \
		    -name "*.xml"); do \
			perl -i -pe 's/<default>(.*?)<\/default>/<Default>$$1<\/Default>/g' $${MODEL}; \
			perl -i -pe 's/<multiple>(.*?)<\/multiple>/<Multiple>$$1<\/Multiple>/g' $${MODEL}; \
			perl -i -pe 's/<required>(.*?)<\/required>/<Required>$$1<\/Required>/g' $${MODEL}; \
			perl -i -pe 's/<mask>(.*?)<\/mask>/<Mask>$$1<\/Mask>/g' $${MODEL}; \
			perl -i -pe 's/<asList>(.*?)<\/asList>/<AsList>$$1<\/AsList>/g' $${MODEL}; \
		done; \
	fi

test: check
	@if [ -d ${.CURDIR}/src/opnsense/mvc/tests ]; then \
		cd ${LOCALBASE}/opnsense/mvc/tests && \
		    phpunit --configuration PHPunit.xml \
		    ${.CURDIR}/src/opnsense/mvc/tests; \
	fi

commit: ensure-workdirs
	@/bin/echo -n "${.CURDIR:C/\// /g:[-2]}/${.CURDIR:C/\// /g:[-1]}: " > \
	    ${WRKDIR}/.commitmsg && git commit -eF ${WRKDIR}/.commitmsg .

.PHONY:	check plist-fix
