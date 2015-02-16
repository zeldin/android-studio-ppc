#! /bin/sh
set -e

BUILDDIR=build

JNI_INCLUDE="-I/opt/ibm-jdk-bin-1.6.0.9_p2/include/"

STUDIO_FILENAME='android-studio-ide-135.1641136-linux.zip'
STUDIO_URL="https://dl.google.com/dl/android/studio/ide-zips/1.0.1/$STUDIO_FILENAME"
STUDIO_SHA1=7c8f2d0cec21b98984cdba45ab5a25f26d67f23a
STUDIO_DIR='android-studio'

IDEA_TAG='idea/135.1288'
IDEA_REPO_URL='https://github.com/JetBrains/intellij-community.git'
IDEA_SHA1=a223e4319777c686f831b939aab424877d4333ce
IDEA_REPO_DIR='idea.git'

PUREJAVACOMM_REPO_URL='https://github.com/traff/purejavacomm'
PUREJAVACOMM_REPO_DIR='purejavacomm.git'
PUREJAVACOMM_SHA1=bcc9058f98b5b00cdbe31e0ea6589f1be465378e

PTY4J_REPO_URL='https://github.com/traff/pty4j.git'
PTY4J_REPO_DIR='pty4j.git'
PTY4J_SHA1=0501fed201bcb2099719c51c863536907ed1184c

SNAPPY_TAG='1.0.5'
SNAPPY_REPO_URL='https://github.com/xerial/snappy-java.git'
SNAPPY_SHA1=fde51d8317dcf92c66ebf151298cc604aff65db5
SNAPPY_REPO_DIR='snappy.git'

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

if test -d platform/util/src; then :; else
  msg 'Extracting platform sources from repository'
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- platform/util/src platform/platform-impl/src ) | tar xf -
fi

if test -f platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java.orig; then :; else
  msg 'Patching FileSystemUtil class'
  patch -b -z .orig platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java <<'EOF'
--- a/platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java
+++ b/platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java
@@ -360,6 +360,7 @@ public class FileSystemUtil {
     }
 
     private static final int[] LINUX_32 =  {16, 44, 72, 24, 28};
+    private static final int[] LINUX_32_PPC = {16, 48, 80, 24, 28};
     private static final int[] LINUX_64 =  {24, 48, 88, 28, 32};
     private static final int[] BSD_32 =    { 8, 48, 32, 12, 16};
     private static final int[] BSD_64 =    { 8, 72, 40, 12, 16};
@@ -379,7 +380,7 @@ public class FileSystemUtil {
     private final boolean myCoarseTs = SystemProperties.getBooleanProperty(COARSE_TIMESTAMP, false);
 
     private JnaUnixMediatorImpl() throws Exception {
-      myOffsets = SystemInfo.isLinux ? (SystemInfo.is32Bit ? LINUX_32 : LINUX_64) :
+      myOffsets = SystemInfo.isLinux ? (SystemInfo.is32Bit ? ("ppc".equals(SystemInfo.OS_ARCH) ? LINUX_32_PPC : LINUX_32) : LINUX_64) :
                   SystemInfo.isMac | SystemInfo.isFreeBSD ? (SystemInfo.is32Bit ? BSD_32 : BSD_64) :
                   SystemInfo.isSolaris ? (SystemInfo.is32Bit ? SUN_OS_32 : SUN_OS_64) :
                   null;
@@ -393,13 +394,13 @@ public class FileSystemUtil {
     @Override
     protected FileAttributes getAttributes(@NotNull String path) throws Exception {
       Memory buffer = new Memory(256);
-      int res = SystemInfo.isLinux ? myLibC.__lxstat64(0, path, buffer) : myLibC.lstat(path, buffer);
+      int res = SystemInfo.isLinux ? myLibC.__lxstat64(1, path, buffer) : myLibC.lstat(path, buffer);
       if (res != 0) return null;
 
       int mode = (SystemInfo.isLinux ? buffer.getInt(myOffsets[OFF_MODE]) : buffer.getShort(myOffsets[OFF_MODE])) & LibC.S_MASK;
       boolean isSymlink = (mode & LibC.S_IFLNK) == LibC.S_IFLNK;
       if (isSymlink) {
-        res = SystemInfo.isLinux ? myLibC.__xstat64(0, path, buffer) : myLibC.stat(path, buffer);
+        res = SystemInfo.isLinux ? myLibC.__xstat64(1, path, buffer) : myLibC.stat(path, buffer);
         if (res != 0) {
           return FileAttributes.BROKEN_SYMLINK;
         }
@@ -436,7 +437,7 @@ public class FileSystemUtil {
     @Override
     protected boolean clonePermissions(@NotNull String source, @NotNull String target) throws Exception {
       Memory buffer = new Memory(256);
-      int res = SystemInfo.isLinux ? myLibC.__xstat64(0, source, buffer) : myLibC.stat(source, buffer);
+      int res = SystemInfo.isLinux ? myLibC.__xstat64(1, source, buffer) : myLibC.stat(source, buffer);
       if (res == 0) {
         int permissions = (SystemInfo.isLinux ? buffer.getInt(myOffsets[OFF_MODE]) : buffer.getShort(myOffsets[OFF_MODE])) & LibC.PERM_MASK;
         return myLibC.chmod(target, permissions) == 0;
EOF
fi

if test -f platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/FileWatcher.java.orig; then :; else
  msg 'Patching FileWatcher class'
  patch -b -z .orig platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/FileWatcher.java <<'EOF'
--- platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/FileWatcher.java.orig	2015-02-13 23:54:40.000000000 +0100
+++ platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/FileWatcher.java	2015-02-13 23:54:46.000000000 +0100
@@ -120,9 +120,6 @@
         }
       });
     }
-    else if (!isUpToDate(myExecutable)) {
-      notifyOnFailure(ApplicationBundle.message("watcher.exe.outdated"), null);
-    }
     else {
       try {
         startupProcess(false);
EOF
fi

test -d classes || mkdir classes
JARS=
for jar in "$STUDIO_DIR"/lib/*.jar; do
  JARS="$JARS${JARS:+:}$jar"
done

msg 'Compiling fixed FileSystemUtil class'
$JAVAC -d classes -cp "$JARS" platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java

msg 'Injecting fixed classfile into util.jar'
$JAR uf "$STUDIO_DIR"/lib/util.jar -C classes 'com/intellij/openapi/util/io/FileSystemUtil$JnaUnixMediatorImpl.class'

msg 'Compiling fixed FileWatcher class'
$JAVAC -d classes -cp "$JARS" platform/platform-impl/src/com/intellij/openapi/vfs/impl/local/FileWatcher.java

msg 'Injecting fixed classfile into idea.jar'
$JAR uf "$STUDIO_DIR"/lib/idea.jar -C classes 'com/intellij/openapi/vfs/impl/local/FileWatcher.class'

if test -d native/fsNotifier/linux; then :; else
  msg 'Extracting fsNotifier sources from repository'
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- native/fsNotifier/linux ) | tar xf -
fi

if test -f native/fsNotifier/linux/inotify.c.orig; then :; else
  msg 'Patching inotify.c'
  patch -b -z .orig native/fsNotifier/linux/inotify.c <<'EOF'
--- inotify.c.orig	2015-02-11 19:09:07.000000000 +0100
+++ inotify.c	2015-02-11 19:11:03.000000000 +0100
@@ -27,7 +27,9 @@
 #include <syslog.h>
 #include <unistd.h>
 
-#ifdef __amd64__
+#ifdef __powerpc64__
+__asm__(".symver memcpy,memcpy@GLIBC_2.3");
+#elif defined(__amd64__)
 __asm__(".symver memcpy,memcpy@GLIBC_2.2.5");
 #else
 __asm__(".symver memcpy,memcpy@GLIBC_2.0");
EOF
fi

if test -x native/fsNotifier/linux/fsnotifier; then :; else
  msg 'Building fsNotifier'
  cd native/fsNotifier/linux
  ./make.sh
  cd ../../..
fi

msg 'Installing fsNotifier'
cp native/fsNotifier/linux/fsnotifier native/fsNotifier/linux/fsnotifier64 "$STUDIO_DIR"/bin/

if test -d native/breakgen; then :; else
  msg 'Extracting breakgen sources from repository'
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- native/breakgen ) | tar xf -
fi

if test -f native/breakgen/libbreakgen64.so; then :; else
  msg 'Building breakgen'
  cd native/breakgen
  gcc -m32 ${JNI_INCLUDE} AppMain.c -shared -fPIC -o libbreakgen.so
  gcc -m64 ${JNI_INCLUDE} AppMain.c -shared -fPIC -o libbreakgen64.so
  cd ../..
fi

msg 'Installing breakgen'
cp native/breakgen/libbreakgen.so native/breakgen/libbreakgen64.so "$STUDIO_DIR"/bin/

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

if test -d "$PTY4J_REPO_DIR"; then :; else
  msg 'Cloning pty4j repository'
  git clone --bare "$PTY4J_REPO_URL" "$PTY4J_REPO_DIR"
fi

if test -d pty4j/native; then :; else
  msg 'Extracting pty4j sources from repository'
  ( cd "$PTY4J_REPO_DIR" && git archive --format=tar --prefix=pty4j/ "$PTY4J_SHA1" -- native os src/com/pty4j/util src/com/pty4j/unix/linux ) | tar xf -
fi

if test -f pty4j/native/Makefile_linux.orig; then :; else
  msg 'Patching Makefile_linux'
  patch -b -z .orig pty4j/native/Makefile_linux <<'EOF'
--- Makefile_linux.orig	2015-02-11 19:16:49.000000000 +0100
+++ Makefile_linux	2015-02-11 19:17:03.000000000 +0100
@@ -50,7 +50,7 @@
 
 $(LIB_NAME_FULL_PTY_LINUX_X86_64): $(OBJS_PTY_X86_64)
 	mkdir -p $(INSTALL_DIR_LINUX_X86_64)
-	$(CC) -g -shared -Wl,-soname,$(LIB_NAME_PTY) $(LDFLAGS) -o $(LIB_NAME_FULL_PTY_LINUX_X86_64) $(OBJS_PTY_X86_64)
+	$(CC) -m64 -g -shared -Wl,-soname,$(LIB_NAME_PTY) $(LDFLAGS) -o $(LIB_NAME_FULL_PTY_LINUX_X86_64) $(OBJS_PTY_X86_64)
 
 exec_pty_$(ARCH_X86).o: exec_pty.c
 	$(CC) $(CFLAGS) $(ARCH_FLAG_X86) $(CPPFLAGS) -c -o $@ exec_pty.c
EOF
fi

if test -f pty4j/src/com/pty4j/util/PtyUtil.java.orig; then :; else
  msg 'Patching PtyUtil.java'
  patch -b -z .orig pty4j/src/com/pty4j/util/PtyUtil.java <<'EOF'
--- src/com/pty4j/util/PtyUtil.java.orig	2015-02-11 21:11:16.000000000 +0100
+++ src/com/pty4j/util/PtyUtil.java	2015-02-11 21:16:08.000000000 +0100
@@ -16,6 +16,7 @@
  */
 public class PtyUtil {
   public static final String OS_VERSION = System.getProperty("os.version").toLowerCase();
+  public static final String OS_ARCH = System.getProperty("os.arch").toLowerCase();
 
   private final static String PTY_LIB_FOLDER = System.getenv("PTY_LIB_FOLDER");
 
@@ -100,9 +101,10 @@
   public static File resolveNativeFile(File parent, String fileName) {
     File path = new File(parent, getPlatformFolder());
 
-    path = isWinXp() ? new File(path, "xp") :
+    path = isWinXp() ? new File(path, "xp") :	
+	(OS_ARCH.startsWith("ppc") ? new File(path, OS_ARCH) :
             (Platform.is64Bit() ? new File(path, "x86_64") :
-                    new File(path, "x86"));
+                    new File(path, "x86")));
 
     return new File(path, fileName);
   }
EOF
fi

if test -f pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java.orig; then :; else
  msg 'Patching OSFacadeImpl.java'
  patch -b -z .orig pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java <<'EOF'
--- src/com/pty4j/unix/linux/OSFacadeImpl.java.orig	2015-02-16 19:38:01.000000000 +0100
+++ src/com/pty4j/unix/linux/OSFacadeImpl.java	2015-02-16 19:57:04.000000000 +0100
@@ -86,9 +86,19 @@
 
   // CONSTANTS
 
-  private static final int TIOCGWINSZ = 0x00005413;
-  private static final int TIOCSWINSZ = 0x00005414;
-  
+  private static final int TIOCGWINSZ;
+  private static final int TIOCSWINSZ;
+
+  static {
+    if (System.getProperty("os.arch").startsWith("ppc")) {
+      TIOCGWINSZ = 0x40087468;
+      TIOCSWINSZ = 0x80087467;
+    } else {
+      TIOCGWINSZ = 0x00005413;
+      TIOCSWINSZ = 0x00005414;
+    }
+  }
+ 
   // VARIABLES
 
   private static C_lib m_Clib = (C_lib)Native.loadLibrary("c", C_lib.class);
EOF
fi

if test -f pty4j/os/linux/ppc64/libpty.so; then :; else
  msg 'Building pty4j'
  cd pty4j/native
  make ARCH_X86=ppc ARCH_X86_64=ppc64 CFLAGS="-fpic -D_REENTRANT -D_GNU_SOURCE" ARCH_FLAG_X86=-m32 ARCH_FLAG_X86_64=-m64 -f Makefile_linux
  cd ../..
fi

msg 'Compiling fixed PtyUtil class'
$JAVAC -d classes -cp "$JARS" pty4j/src/com/pty4j/util/PtyUtil.java
msg 'Compiling fixed OSFacadeImpl class'
$JAVAC -d classes -cp "$JARS" pty4j/src/com/pty4j/unix/linux/OSFacadeImpl.java

msg 'Injecting fixed classfiles into pty4j-0.3.jar'
$JAR uf "$STUDIO_DIR"/lib/pty4j-0.3.jar -C classes 'com/pty4j/util/PtyUtil.class' -C classes 'com/pty4j/unix/linux/OSFacadeImpl.class'

msg 'Installing pty4j'
cp -r pty4j/os/linux/ppc* "$STUDIO_DIR"/lib/libpty/linux/

if test -d "$SNAPPY_REPO_DIR"; then :; else
  msg 'Cloning snappy-java repository'
  git clone --bare -b "$SNAPPY_TAG" --depth=1 "$SNAPPY_REPO_URL" "$SNAPPY_REPO_DIR"
fi

if test -d snappy-java/src; then :; else
  msg 'Extracting snappy-java sources from repository'
  ( cd "$SNAPPY_REPO_DIR" && git archive --format=tar --prefix=snappy-java/ "$SNAPPY_SHA1" -- ) | tar xf -
  sed -i -e 's/xvfz/xfz/' snappy-java/Makefile
fi

if test -f snappy-java/Makefile.common.orig; then :; else
  msg 'Patching Makefile.common'
  patch -b -z .orig snappy-java/Makefile.common <<'EOF'
--- a/Makefile.common
+++ b/Makefile.common
@@ -41,7 +41,7 @@ endif
 
 # os=Default is meant to be generic unix/linux
 
-known_os_archs := Linux-i386 Linux-amd64 Linux-arm Linux-armhf Mac-i386 Mac-x86_64 FreeBSD-amd64 Windows-x86 Windows-amd64
+known_os_archs := Linux-i386 Linux-amd64 Linux-ppc Linux-ppc64 Linux-arm Linux-armhf Mac-i386 Mac-x86_64 FreeBSD-amd64 Windows-x86 Windows-amd64
 os_arch := $(OS_NAME)-$(OS_ARCH)
 
 ifeq (,$(findstring $(strip $(os_arch)),$(known_os_archs)))
@@ -72,6 +72,20 @@ Linux-amd64_LINKFLAGS := -shared -static-libgcc -static-libstdc++
 Linux-amd64_LIBNAME   := libsnappyjava.so
 Linux-amd64_SNAPPY_FLAGS  := 
 
+Linux-ppc_CXX       := $(CROSS_PREFIX)g++
+Linux-ppc_STRIP     := $(CROSS_PREFIX)strip
+Linux-ppc_CXXFLAGS  := -include lib/inc_linux/jni_md.h -Djniport_h -DWORDS_BIGENDIAN -I$(JAVA_HOME)/include -O2 -fPIC -fvisibility=hidden -m32
+Linux-ppc_LINKFLAGS := -shared -static-libgcc -static-libstdc++
+Linux-ppc_LIBNAME   := libsnappyjava.so
+Linux-ppc_SNAPPY_FLAGS:= 
+
+Linux-ppc64_CXX       := $(CROSS_PREFIX)g++ 
+Linux-ppc64_STRIP     := $(CROSS_PREFIX)strip
+Linux-ppc64_CXXFLAGS  := -include lib/inc_linux/jni_md.h -Djniport_h -DWORDS_BIGENDIAN -I$(JAVA_HOME)/include -O2 -fPIC -fvisibility=hidden -m64
+Linux-ppc64_LINKFLAGS := -shared -static-libgcc -static-libstdc++
+Linux-ppc64_LIBNAME   := libsnappyjava.so
+Linux-ppc64_SNAPPY_FLAGS  := 
+
 # '-include lib/inc_linux/jni_md.h' is used to force the use of our version,
 # which defines JNIEXPORT differently; otherwise, since OpenJDK includes
 # jni_md.h in same directory as jni.h, the include path is ignored when
EOF
fi

cd snappy-java
if test -f target/classes/org/xerial/snappy/native/Linux/ppc/libsnappyjava.so; then :; else
  msg 'Building snappy-java (32 bit)'
  make -s native OS_NAME=Linux OS_ARCH=ppc
fi

if test -f target/classes/org/xerial/snappy/native/Linux/ppc64/libsnappyjava.so; then :; else
  msg 'Building snappy-java (64 bit)'
  make -s native OS_NAME=Linux OS_ARCH=ppc64
fi
cd ..

msg 'Injecting native libraries into snappy-java-1.0.5.jar'
$JAR uf "$STUDIO_DIR"/lib/snappy-java-1.0.5.jar -C snappy-java/target/classes 'org/xerial/snappy/native/Linux'

msg "All done, android studio can now be found in $BUILDDIR/$STUDIO_DIR"
