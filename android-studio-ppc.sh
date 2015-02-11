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

PTY4J_REPO_URL='https://github.com/traff/pty4j.git'
PTY4J_REPO_DIR='pty4j.git'
PTY4J_SHA1=c5cc21726b80a238bec54db4f83e82cc09fd3909

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
  ( cd "$IDEA_REPO_DIR" && git archive --format=tar "$IDEA_SHA1" -- platform/util/src ) | tar xf -
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

test -d classes || mkdir classes
JARS=
for jar in "$STUDIO_DIR"/lib/*.jar; do
  JARS="$JARS${JARS:+:}$jar"
done

msg 'Compiling fixed FileSystemUtil class'
$JAVAC -d classes -cp "$JARS" platform/util/src/com/intellij/openapi/util/io/FileSystemUtil.java

msg 'Injecting fixed classfile into util.jar'
$JAR uf "$STUDIO_DIR"/lib/util.jar -C classes 'com/intellij/openapi/util/io/FileSystemUtil$JnaUnixMediatorImpl.class'

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

if test -d "$PTY4J_REPO_DIR"; then :; else
  msg 'Cloning pty4j repository'
  git clone --bare "$PTY4J_REPO_URL" "$PTY4J_REPO_DIR"
fi

if test -d pty4j/native; then :; else
  msg 'Extracting pty4j sources from repository'
  ( cd "$PTY4J_REPO_DIR" && git archive --format=tar --prefix=pty4j/ "$PTY4J_SHA1" -- native os ) | tar xf -
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

if test -f pty4j/os/linux/ppc64/libpty.so; then :; else
  msg 'Building pty4j'
  cd pty4j/native
  make ARCH_X86=ppc ARCH_X86_64=ppc64 CFLAGS="-fpic -D_REENTRANT -D_GNU_SOURCE" ARCH_FLAG_X86=-m32 ARCH_FLAG_X86_64=-m64 -f Makefile_linux
  cd ../..
fi

msg 'Installing pty4j'
cp -r pty4j/os/linux/ppc* "$STUDIO_DIR"/lib/libpty/linux/

msg "All done, android studio can now be found in $BUILDDIR/$STUDIO_DIR"