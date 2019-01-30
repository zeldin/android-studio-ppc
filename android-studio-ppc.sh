#! /bin/sh
set -e

if [ -z "$JAVA_HOME" ]; then
  echo >&2 'Please set $JAVA_HOME before running this script'
fi

BUILDDIR=build

JNI_INCLUDE="-I${JAVA_HOME}/include/"
PATH="${JAVA_HOME}/bin:${PATH}"
export PATH

STUDIO_FILENAME='android-studio-ide-182.5199772-linux.zip'
STUDIO_URL="https://dl.google.com/dl/android/studio/ide-zips/3.3.0.20/$STUDIO_FILENAME"
STUDIO_SHA1=15bc3a9a1ca6928560f9ff1370676c23eebdf983
STUDIO_DIR='android-studio'

IDEA_TAG='idea/182.5107.16'
IDEA_REPO_URL='https://github.com/JetBrains/intellij-community.git'
IDEA_SHA1=7368cc3cb9085e54afdc75f0f2d3734e9ba7d20b
IDEA_REPO_DIR='idea.git'

PUREJAVACOMM_REPO_URL='https://github.com/traff/purejavacomm'
PUREJAVACOMM_REPO_DIR='purejavacomm.git'
PUREJAVACOMM_SHA1=bcc9058f98b5b00cdbe31e0ea6589f1be465378e

JNA_TAG='4.5.0'
JNA_REPO_URL='https://github.com/java-native-access/jna.git'
JNA_REPO_DIR='jna.git'
JNA_SHA1=e30c71cfbf5d3f1c144d65b20bac43983bbfc41a

PTY4J_REPO_URL='https://github.com/traff/pty4j.git'
PTY4J_REPO_DIR='pty4j.git'
PTY4J_SHA1=c2022315f5d4b73d66a4a1f3711ad2835c4ae313

JAVAC="javac"
JAR="jar"

usage() {
  echo >&2 "Usage: $0 [--no-clean]"
}

msg() {
  echo " * $1"
}

NOCLEAN=
for arg; do
  case "$arg" in
    --no-clean) NOCLEAN=yes;;
    --help|-h) usage; exit 0;;
    *) echo >&2 "Unknown option $arg"; usage; exit 1;;
  esac
done

if test -n "$NOCLEAN"; then :; else
  msg 'Removing old build dir'
  rm -rf "$BUILDDIR"
fi

test -d "$BUILDDIR" || mkdir "$BUILDDIR"
cd "$BUILDDIR"

for variant in 32:powerpc 64:powerpc64; do
  abi=`echo "${variant}" | cut -d: -f1`
  arch=`echo "${variant}" | cut -d: -f2`
  result=""
  for cc in "${arch}-unknown-linux-gnu-gcc" "${arch}-linux-gnu-gcc" gcc; do
    if "${cc}" "-m${abi}" --version >/dev/null 2>&1; then
      result="${cc} -m${abi}"
      break
    fi
  done
  if [ -z "$result" ]; then
    echo >&2 "Failed to find a ${abi} bit compiler"
    exit 1
  fi
  msg "${abi} bit compiler: ${result}"
  eval "GCC${abi}="'"${result}"'
done
SYSROOT32="`${GCC32} -print-sysroot`"
SYSROOT64="`${GCC64} -print-sysroot`"
export SYSROOT32
export SYSROOT64

if test -d "$STUDIO_DIR"; then :; else

  if test -f "$STUDIO_FILENAME"; then :; else
    msg 'Downloading Android Studio distribution'
    wget "$STUDIO_URL"
  fi

  msg 'Checking distribution validity'
  sha1=`sha1sum -b "$STUDIO_FILENAME" | cut -d' ' -f1`
  if test -z "$sha1"; then
    echo >&2 "Unable to compute SHA1 checksum"
    exit 1
  fi
  if test x"$sha1" = x"$STUDIO_SHA1"; then :; else
    echo >&2 "Incorrect SHA1 $sha1 != $STUDIO_SHA1"
    exit 1
  fi

  msg 'Unpacking distribution'
  unzip -q "$STUDIO_FILENAME"

fi

if test -d "$IDEA_REPO_DIR"; then :; else
  msg 'Cloning intellij-community repository'
  git clone --bare -b "$IDEA_TAG" --depth=1 "$IDEA_REPO_URL" "$IDEA_REPO_DIR"
fi

if test -d platform/platform-impl/src; then :; else
  msg 'Extracting platform sources from repository'
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- platform/platform-impl/src ) | tar xf -
fi

if test -f platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.java.orig; then :; else
  msg 'Patching NativeFileWatcherImpl class'
  patch -b -z .orig platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.java <<'EOF'
--- platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.java.orig	2019-01-29 22:47:01.437061159 +0100
+++ platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.java	2019-01-29 22:49:04.905213901 +0100
@@ -139,6 +139,8 @@
       if ("linux-x86".equals(Platform.RESOURCE_PREFIX)) names = new String[]{"fsnotifier"};
       else if ("linux-x86-64".equals(Platform.RESOURCE_PREFIX)) names = new String[]{"fsnotifier64"};
       else if ("linux-arm".equals(Platform.RESOURCE_PREFIX)) names = new String[]{"fsnotifier-arm"};
+      else if ("linux-ppc64".equals(Platform.RESOURCE_PREFIX)) names = new String[]{"fsnotifier-ppc64"};
+      else if ("linux-ppc".equals(Platform.RESOURCE_PREFIX)) names = new String[]{"fsnotifier-ppc"};
     }
     if (names == null) return PLATFORM_NOT_SUPPORTED;
 
EOF
fi

test -d classes || mkdir classes
JARS=
for jar in "$STUDIO_DIR"/lib/*.jar; do
  JARS="$JARS${JARS:+:}$jar"
done

msg 'Compiling fixed NativeFileWatcherImpl class'
$JAVAC -d classes -cp "$JARS" platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.java

msg 'Injecting fixed classfile into platform-impl.jar'
$JAR uf "$STUDIO_DIR"/lib/platform-impl.jar -C classes 'com/intellij/openapi/vfs/impl/local/NativeFileWatcherImpl.class'

if test -d native/fsNotifier/linux; then :; else
  msg 'Extracting fsNotifier sources from repository'
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- native/fsNotifier/linux ) | tar xf -
fi

if test -f native/fsNotifier/linux/make.sh.orig; then :; else
  msg 'Patching make.sh'
  patch -b -z .orig native/fsNotifier/linux/make.sh <<'EOF'
--- linux/make.sh.orig	2019-01-28 10:31:25.933881985 +0100
+++ linux/make.sh	2019-01-28 13:17:06.937755495 +0100
@@ -5,12 +5,13 @@
 VER=$(date "+%Y%m%d.%H%M")
 sed -i.bak "s/#define VERSION .*/#define VERSION \"${VER}\"/" fsnotifier.h && rm fsnotifier.h.bak
 
-if [ -f "/usr/include/gnu/stubs-32.h" ] ; then
+
+if [ -f "${SYSROOT32}/usr/include/gnu/stubs-32.h" ] ; then
   echo "compiling 32-bit version"
-  clang -m32 ${CC_FLAGS} -o fsnotifier main.c inotify.c util.c && chmod 755 fsnotifier
+  clang --sysroot "${SYSROOT32:-/}" -m32 ${CC_FLAGS} -o fsnotifier main.c inotify.c util.c && chmod 755 fsnotifier
 fi
 
-if [ -f "/usr/include/gnu/stubs-64.h" ] ; then
+if [ -f "${SYSROOT64}/usr/include/gnu/stubs-64.h" -o -f "${SYSROOT64}/usr/include/gnu/stubs-64-v1.h" -o -f "${SYSROOT64}usr/include/gnu/stubs-64-v2.h" ] ; then
   echo "compiling 64-bit version"
-  clang -m64 ${CC_FLAGS} -o fsnotifier64 main.c inotify.c util.c && chmod 755 fsnotifier64
+  clang --sysroot "${SYSROOT64:-/}" -m64 ${CC_FLAGS} -o fsnotifier64 main.c inotify.c util.c && chmod 755 fsnotifier64
 fi
\ No newline at end of file
EOF
fi

if test -x native/fsNotifier/linux/fsnotifier; then :; else
  msg 'Building fsNotifier'
  cd native/fsNotifier/linux
  ./make.sh
  cd ../../..
fi

msg 'Installing fsNotifier'
cp native/fsNotifier/linux/fsnotifier "$STUDIO_DIR"/bin/fsnotifier-ppc
cp native/fsNotifier/linux/fsnotifier64 "$STUDIO_DIR"/bin/fsnotifier-ppc64

if test -d "$PUREJAVACOMM_REPO_DIR"; then :; else
  msg 'Cloning purejavacomm repository'
  git clone --bare "$PUREJAVACOMM_REPO_URL" "$PUREJAVACOMM_REPO_DIR"
fi

if test -d purejavacomm/src; then :; else
  msg 'Extracting jtermios sources from repository'
  ( cd "$PUREJAVACOMM_REPO_DIR" && git archive --format=tar --prefix=purejavacomm/ "$PUREJAVACOMM_SHA1" -- src/jtermios ) | tar xf -
fi

if test -f purejavacomm/src/jtermios/linux/JTermiosImpl.java.orig; then :; else
  msg 'Patching JTermiosImpl.java'
  patch -b -z .orig purejavacomm/src/jtermios/linux/JTermiosImpl.java <<'EOF'
--- a/src/jtermios/linux/JTermiosImpl.java
+++ b/src/jtermios/linux/JTermiosImpl.java
@@ -59,8 +59,7 @@ import static jtermios.JTermios.JTermiosLogging.log;
 public class JTermiosImpl implements jtermios.JTermios.JTermiosInterface {
 	private static String DEVICE_DIR_PATH = "/dev/";
 	private static final boolean IS64B = NativeLong.SIZE == 8;
-	static Linux_C_lib_DirectMapping m_ClibDM = new Linux_C_lib_DirectMapping();
-	static Linux_C_lib m_Clib = m_ClibDM;
+	static Linux_C_lib m_Clib = (Linux_C_lib)Native.loadLibrary("c", Linux_C_lib.class, YJPFunctionMapper.OPTIONS);
 
 	private final static int TIOCGSERIAL = 0x0000541E;
 	private final static int TIOCSSERIAL = 0x0000541F;
@@ -488,9 +487,9 @@ public class JTermiosImpl implements jtermios.JTermios.JTermiosInterface {
 		s[i] = n;
 		// the native call depends on weather this is 32 or 64 bit arc
 		if (IS64B)
-			m_ClibDM.memcpy(d, s, (long) 4);
+			m_Clib.memcpy(d, s, (long) 4);
 		else
-			m_ClibDM.memcpy(d, s, (int) 4);
+			m_Clib.memcpy(d, s, (int) 4);
 		return d[0];
 	}
 
EOF
fi

msg 'Compiling fixed JTermiosImpl class'
$JAVAC -d classes -cp "$JARS" purejavacomm/src/jtermios/linux/JTermiosImpl.java

msg 'Injecting fixed classfile into purejavacomm.jar'
$JAR uf "$STUDIO_DIR"/lib/purejavacomm.jar -C classes 'jtermios/linux/JTermiosImpl.class'

if test -d "$JNA_REPO_DIR"; then :; else
  msg 'Cloning jna repository'
  git clone --bare -b "$JNA_TAG" --depth=1 "$JNA_REPO_URL" "$JNA_REPO_DIR"
fi

if test -d jna/native; then :; else
  msg 'Extracting jna sources from repository'
  ( cd "$JNA_REPO_DIR" && git archive --format=tar --prefix=jna/ "$JNA_SHA1" ) | tar xf -
fi

if test -f jna/build/classes/com/sun/jna/linux-ppc64/libjnidispatch.so; then :; else
  msg 'Building missing ppc64 lib'
  cd jna
  ant -S -Dos.prefix=linux-ppc64 native
  cd ..  
fi

msg 'Injecting missing ppc64 lib into jna.jar'
$JAR uf "$STUDIO_DIR"/lib/jna.jar -C jna/build/classes 'com/sun/jna/linux-ppc64/libjnidispatch.so'

if test -d "$PTY4J_REPO_DIR"; then :; else
  msg 'Cloning pty4j repository'
  git clone --bare "$PTY4J_REPO_URL" "$PTY4J_REPO_DIR"
fi

if test -d pty4j/native; then :; else
  msg 'Extracting pty4j sources from repository'
  ( cd "$PTY4J_REPO_DIR" && git archive --format=tar --prefix=pty4j/ "$PTY4J_SHA1" -- native os src/com/pty4j/util src/com/pty4j/unix ) | tar xf -
fi

if test -f pty4j/src/com/pty4j/util/PtyUtil.java.orig; then :; else
  msg 'Patching PtyUtil.java'
  patch -b -z .orig pty4j/src/com/pty4j/util/PtyUtil.java <<'EOF'
--- src/com/pty4j/util/PtyUtil.java.orig	2018-05-29 13:12:51.000000000 +0200
+++ src/com/pty4j/util/PtyUtil.java	2019-01-28 11:24:35.713225816 +0100
@@ -16,6 +16,7 @@
  */
 public class PtyUtil {
   public static final String OS_VERSION = System.getProperty("os.version").toLowerCase();
+  public static final String OS_ARCH = System.getProperty("os.arch").toLowerCase();
 
   private final static String PTY_LIB_FOLDER = System.getenv("PTY_LIB_FOLDER");
 
@@ -101,7 +102,9 @@
   public static File resolveNativeFile(File parent, String fileName) {
     final File path = new File(parent, getPlatformFolder());
 
-    String arch = Platform.is64Bit() ? "x86_64" : "x86";
+    String arch =
+	(OS_ARCH.startsWith("ppc") ? OS_ARCH :
+	 Platform.is64Bit() ? "x86_64" : "x86");
     String prefix = isWinXp() ? "xp" : arch;
 
     if (new File(parent, prefix).exists()) {
EOF
fi

if test -f pty4j/src/com/pty4j/unix/Pty.java.orig; then :; else
  msg 'Patching Pty.java'
  patch -b -z .orig pty4j/src/com/pty4j/unix/Pty.java <<'EOF'
--- pty4j/src/com/pty4j/unix/Pty.java.orig	2019-01-30 18:18:59.062074491 +0100
+++ pty4j/src/com/pty4j/unix/Pty.java	2019-01-30 18:19:55.855011491 +0100
@@ -321,14 +321,14 @@
 
   private static boolean poll(int pipeFd, int fd) {
     // each {int, short, short} structure is represented by two ints
-    int[] poll_fds = new int[]{pipeFd, JTermios.POLLIN, fd, JTermios.POLLIN};
+    int[] poll_fds = new int[]{pipeFd, JTermios.POLLIN_IN, fd, JTermios.POLLIN_IN};
     while (true) {
       if (JTermios.poll(poll_fds, 2, -1) > 0) break;
 
       int errno = JTermios.errno();
       if (errno != JTermios.EAGAIN && errno != JTermios.EINTR) return false;
     }
-    return ((poll_fds[3] >> 16) & JTermios.POLLIN) != 0;
+    return (poll_fds[3] & JTermios.POLLIN_OUT) != 0;
   }
 
   private static boolean select(int pipeFd, int fd) {
EOF
fi

if test -f pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java.orig; then :; else
  msg 'Patching OSFacadeImpl.java'
  patch -b -z .orig pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java <<'EOF'
--- src/com/pty4j/unix/linux/OSFacadeImpl.java.orig	2019-01-28 11:21:48.254805662 +0100
+++ src/com/pty4j/unix/linux/OSFacadeImpl.java	2019-01-28 11:23:41.500210453 +0100
@@ -87,8 +87,18 @@
 
   // CONSTANTS
 
-  private static final long TIOCGWINSZ = 0x00005413L;
-  private static final long TIOCSWINSZ = 0x00005414L;
+  private static final long TIOCGWINSZ;
+  private static final long TIOCSWINSZ;
+  
+  static {
+    if (System.getProperty("os.arch").startsWith("ppc")) {
+      TIOCGWINSZ = 0x40087468L;
+      TIOCSWINSZ = 0x80087467L;
+    } else {
+      TIOCGWINSZ = 0x00005413L;
+      TIOCSWINSZ = 0x00005414L;
+    }
+  }
   
   // VARIABLES
 
EOF
fi

if test -f pty4j/os/linux/ppc64/libpty.so; then :; else
  msg 'Building pty4j'
  cd pty4j/native
  make -s CC="${GCC32}" ARCH_X86=ppc CFLAGS="-fpic -D_REENTRANT -D_GNU_SOURCE" ARCH_FLAG_X86="-m32" -f Makefile_linux linux_x86
  make -s CC="${GCC64}" ARCH_X86_64=ppc64 CFLAGS="-fpic -D_REENTRANT -D_GNU_SOURCE" ARCH_FLAG_X86_64=-m64 -f Makefile_linux linux_x86_64
  cd ../..
fi

msg 'Compiling fixed PtyUtil class'
$JAVAC -d classes -cp "$JARS" pty4j/src/com/pty4j/util/PtyUtil.java
msg 'Compiling fixed Pty class'
$JAVAC -d classes -cp "$JARS" pty4j/src/com/pty4j/unix/Pty.java
msg 'Compiling fixed OSFacadeImpl class'
$JAVAC -d classes -cp "$JARS" pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java

msg 'Injecting fixed classfiles into pty4j-0.7.5.jar'
$JAR uf "$STUDIO_DIR"/lib/pty4j-0.7.5.jar -C classes 'com/pty4j/util/PtyUtil.class' -C classes 'com/pty4j/unix/Pty.class' -C classes 'com/pty4j/unix/linux/OSFacadeImpl.class'

msg 'Installing pty4j'
cp -r pty4j/os/linux/ppc* "$STUDIO_DIR"/lib/libpty/linux/

msg "All done, android studio can now be found in $BUILDDIR/$STUDIO_DIR"
