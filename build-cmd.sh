#!/bin/bash

cd "$(dirname "$0")"

# turn on verbose debugging output for parabuild logs.
set -x
# make errors fatal
set -e

ZLIB_VERSION="1.2.8"
ZLIB_SOURCE_DIR="zlib"

if [ -z "$AUTOBUILD" ] ; then 
    fail
fi

if [ "$OSTYPE" = "cygwin" ] ; then
    export AUTOBUILD="$(cygpath -u $AUTOBUILD)"
fi

# load autobuild provided shell functions and variables
set +x
eval "$("$AUTOBUILD" source_environment)"
set -x

top="$(pwd)"
stage="$top"/stage

echo "${ZLIB_VERSION}" > "${stage}/VERSION.txt"

pushd "$ZLIB_SOURCE_DIR"
    case "$AUTOBUILD_PLATFORM" in

        "windows")
            load_vsvars

            # Okay, this invokes cmake then doesn't use the products.  Why?
            cmake -G"Visual Studio 12" .

            build_sln "contrib/vstudio/vc12/zlibvc.sln" "Debug|Win32"
            build_sln "contrib/vstudio/vc12/zlibvc.sln" "ReleaseWithoutAsm|Win32"
            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                build_sln "contrib/vstudio/vc12/zlibvc.sln" "Debug|Win32" "testzlib"
                ./contrib/vstudio/vc12/x86/TestZlibDebug/testzlib.exe README

                build_sln "contrib/vstudio/vc12/zlibvc.sln" "Release|Win32" "testzlib"
                ./contrib/vstudio/vc12/x86/TestZlibRelease/testzlib.exe README
            fi

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "contrib/vstudio/vc12/x86/ZlibStatDebug/zlibstat.lib" \
                "$stage/lib/debug/zlibd.lib"
            cp -a "contrib/vstudio/vc12/x86/ZlibStatReleaseWithoutAsm/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp -a zlib.h zconf.h "$stage/include/zlib"

            # minizip
            pushd contrib/minizip
                nmake /f Makefile.Linden.Win32.mak DEBUG=1
                cp -a minizip.lib "$stage"/lib/debug/
                nmake /f Makefile.Linden.Win32.mak DEBUG=1 clean

                nmake /f Makefile.Linden.Win32.mak
                cp -a minizip.lib "$stage"/lib/release/
                nmake /f Makefile.Linden.Win32.mak clean
            popd
        ;;
        "windows64")
            load_vsvars

            # Okay, this invokes cmake then doesn't use the products.  Why?
            cmake -G"Visual Studio 12 Win64" .

            build_sln "contrib/vstudio/vc12/zlibvc.sln" "Debug|x64" "zlibstat"
            build_sln "contrib/vstudio/vc12/zlibvc.sln" "ReleaseWithoutAsm|x64" "zlibstat"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                build_sln "contrib/vstudio/vc12/zlibvc.sln" "Debug|x64" "testzlib"
                ./contrib/vstudio/vc12/x64/TestZlibDebug/testzlib.exe README

                build_sln "contrib/vstudio/vc12/zlibvc.sln" "Release|x64" "testzlib"
                ./contrib/vstudio/vc12/x64/TestZlibRelease/testzlib.exe README
            fi

            mkdir -p "$stage/lib/debug"
            mkdir -p "$stage/lib/release"
            cp -a "contrib/vstudio/vc12/x64/ZlibStatDebug/zlibstat.lib" \
                "$stage/lib/debug/zlibd.lib"
            cp -a "contrib/vstudio/vc12/x64/ZlibStatReleaseWithoutAsm/zlibstat.lib" \
                "$stage/lib/release/zlib.lib"
            mkdir -p "$stage/include/zlib"
            cp -a zlib.h zconf.h "$stage/include/zlib"

            # minizip
            pushd contrib/minizip
                nmake /f Makefile.Linden.Win32.mak DEBUG=1
                cp -a minizip.lib "$stage"/lib/debug/
                nmake /f Makefile.Linden.Win32.mak DEBUG=1 clean

                nmake /f Makefile.Linden.Win32.mak
                cp -a minizip.lib "$stage"/lib/release/
                nmake /f Makefile.Linden.Win32.mak clean
            popd
        ;;
        "darwin")
            # Select SDK with full path.  This shouldn't have much effect on this
            # build but adding to establish a consistent pattern.
            #
            # sdk=/Developer/SDKs/MacOSX10.6.sdk/
            # sdk=/Developer/SDKs/MacOSX10.7.sdk/
            # sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.6.sdk/
            sdk=/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX10.10.sdk/

            # Keep min version back at 10.5 if you are using the
            # old llqtwebkit repo which builds on 10.5 systems.
            # At 10.6, zlib will start using __bzero() which doesn't
            # exist there.
            opts="${TARGET_OPTS:--arch i386 -arch x86_64 -iwithsysroot $sdk -mmacosx-version-min=10.8}"

            # Install name for dylibs based on major version number
            install_name="@executable_path/../Resources/libz.1.dylib"

            # Debug first
            CFLAGS="$opts -O0 -gdwarf-2 -fPIC -DPIC" \
                LDFLAGS="-Wl,-install_name,\"${install_name}\" -Wl,-headerpad_max_install_names" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install
            cp -a "$top"/libz_darwin_debug.exp "$stage"/lib/debug/libz_darwin.exp

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                # Build a Resources directory as a peer to the test executable directory
                # and fill it with symlinks to the dylibs.  This replicates the target
                # environment of the viewer.
                mkdir -p ../Resources
                ln -sf "${stage}/lib/debug"/*.dylib ../Resources

                make test

                # And wipe it
                rm -rf ../Resources
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O0 -gdwarf-2 -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/debug/
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            make distclean

            # Now release
            CFLAGS="$opts -O3 -gdwarf-2 -fPIC -DPIC" \
                LDFLAGS="-Wl,-install_name,\"${install_name}\" -Wl,-headerpad_max_install_names" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install
            cp -a "$top"/libz_darwin_release.exp "$stage"/lib/release/libz_darwin.exp

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                mkdir -p ../Resources
                ln -sf "${stage}"/lib/release/*.dylib ../Resources

                make test

                rm -rf ../Resources
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O3 -gdwarf-2 -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/release/
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            make distclean
        ;;            
            
        "linux")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target to 32-bit
            opts="${TARGET_OPTS:--m32}"
            HARDENED="-fstack-protector-strong -D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Debug first
            CFLAGS="$opts -Og -g -fPIC -DPIC" CXXFLAGS="$opts -Og -g -fPIC -DPIC" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/debug"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -Og -g -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/debug/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            # clean the build artifacts
            make distclean

            # Release last
            CFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" CXXFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" \
                ./configure --prefix="$stage" --includedir="$stage/include/zlib" --libdir="$stage/lib/release"
            make
            make install

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/release/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            # clean the build artifacts
            make distclean
        ;;
        "linux64")
            # Linux build environment at Linden comes pre-polluted with stuff that can
            # seriously damage 3rd-party builds.  Environmental garbage you can expect
            # includes:
            #
            #    DISTCC_POTENTIAL_HOSTS     arch           root        CXXFLAGS
            #    DISTCC_LOCATION            top            branch      CC
            #    DISTCC_HOSTS               build_name     suffix      CXX
            #    LSDISTCC_ARGS              repo           prefix      CFLAGS
            #    cxx_version                AUTOBUILD      SIGN        CPPFLAGS
            #
            # So, clear out bits that shouldn't affect our configure-directed build
            # but which do nonetheless.
            #
            # unset DISTCC_HOSTS CC CXX CFLAGS CPPFLAGS CXXFLAGS

            # Default target to 64-bit
            opts="${TARGET_OPTS:--m64}"
            HARDENED="-fstack-protector-strong -D_FORTIFY_SOURCE=2"

            # Handle any deliberate platform targeting
            if [ -z "$TARGET_CPPFLAGS" ]; then
                # Remove sysroot contamination from build environment
                unset CPPFLAGS
            else
                # Incorporate special pre-processing flags
                export CPPFLAGS="$TARGET_CPPFLAGS"
            fi

            # Debug first
            CFLAGS="$opts -Og -g -fPIC -DPIC" CXXFLAGS="$opts -Og -g -fPIC -DPIC" \
                ./configure --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/zlib" --libdir="\${prefix}/lib/debug"
            make
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -Og -g -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/debug/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            # clean the build artifacts
            make distclean

            # Release last
            CFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" CXXFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" \
                ./configure --prefix="\${AUTOBUILD_PACKAGES_DIR}" --includedir="\${prefix}/include/zlib" --libdir="\${prefix}/lib/release"
            make
            make install DESTDIR="$stage"

            # conditionally run unit tests
            if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                make test
            fi

            # minizip
            pushd contrib/minizip
                CFLAGS="$opts -O3 -g $HARDENED -fPIC -DPIC" make -f Makefile.Linden all
                cp -a libminizip.a "$stage"/lib/release/
                # conditionally run unit tests
                if [ "${DISABLE_UNIT_TESTS:-0}" = "0" ]; then
                    make -f Makefile.Linden test
                fi
                make -f Makefile.Linden clean
            popd

            # clean the build artifacts
            make distclean
        ;;
    esac
    mkdir -p "$stage/LICENSES"
    tail -n 31 README > "$stage/LICENSES/zlib.txt"
    pushd contrib/minizip
        mkdir -p "$stage"/include/minizip/
        cp -a ioapi.h zip.h unzip.h "$stage"/include/minizip/
    popd
popd

mkdir -p "$stage"/docs/zlib/
cp -a README.Linden "$stage"/docs/zlib/

pass

