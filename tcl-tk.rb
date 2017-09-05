class TclTk < Formula
  desc "Tool Command Language"
  homepage "https://www.tcl.tk/"
  url "https://downloads.sourceforge.net/project/tcl/Tcl/8.6.7/tcl8.6.7-src.tar.gz"
  mirror "ftp://ftp.tcl.tk/pub/tcl/tcl8_6/tcl8.6.7-src.tar.gz"
  version "8.6.7"
  sha256 "7c6b8f84e37332423cfe5bae503440d88450da8cc1243496249faa5268026ba5"

  bottle do
    sha256 "0a21606596e11bc27ae105548906cc161e0e8bd1ccd0546c1df0441ae2ab1a43" => :sierra
    sha256 "56d5506393587d99b78e458d3945833380682068091f75ea525c1d8a64d5ced9" => :el_capitan
    sha256 "4a3b7d78452c33e84d8c55eaf71bb758e25f0aa9e16112cdd6646ba458304baf" => :yosemite
  end

  keg_only :provided_by_osx,
    "Tk installs some X11 headers and OS X provides an (older) Tcl/Tk."

  deprecated_option "enable-threads" => "with-threads"

  option "with-threads", "Build with multithreading support"
  option "without-tcllib", "Don't build tcllib (utility modules)"
  option "without-tk", "Don't build the Tk (window toolkit)"
  option "with-x11", "Build X11-based Tk instead of Aqua-based Tk"

  depends_on :x11 => :optional
  depends_on "pkg-config" => :build if build.with? "x11"

  resource "tk" do
    url "https://downloads.sourceforge.net/project/tcl/Tcl/8.6.7/tk8.6.7-src.tar.gz"
    mirror "ftp://ftp.tcl.tk/pub/tcl/tcl8_6/tk8.6.7-src.tar.gz"
    version "8.6.7"
    sha256 "061de2a354f9b7c7d04de3984c90c9bc6dd3a1b8377bb45509f1ad8a8d6337aa"
  end

  resource "tcllib" do
    url "https://downloads.sourceforge.net/project/tcllib/tcllib/1.18/tcllib-1.18.tar.gz"
    sha256 "72667ecbbd41af740157ee346db77734d1245b41dffc13ac80ca678dd3ccb515"
  end

  # sqlite won't compile on Tiger due to missing function;
  # patch submitted upstream: http://thread.gmane.org/gmane.comp.db.sqlite.general/83257
  patch :DATA if MacOS.version < :leopard

  def install
    args = ["--prefix=#{prefix}", "--mandir=#{man}"]
    args << "--enable-threads" if build.with? "threads"
    args << "--enable-64bit" if MacOS.prefer_64_bit?

    cd "unix" do
      system "./configure", *args
      system "make"
      system "make", "install"
      system "make", "install-private-headers"
      ln_s bin/"tclsh8.6", bin/"tclsh"
    end

    if build.with? "tk"
      ENV.prepend_path "PATH", bin # so that tk finds our new tclsh

      resource("tk").stage do
        args = ["--prefix=#{prefix}", "--mandir=#{man}", "--with-tcl=#{lib}"]
        args << "--enable-threads" if build.with? "threads"
        args << "--enable-64bit" if MacOS.prefer_64_bit?

        if build.with? "x11"
          args << "--with-x"
        else
          args << "--enable-aqua=yes"
          args << "--without-x"
        end

        cd "unix" do
          system "./configure", *args
          system "make", "TK_LIBRARY=#{lib}"
          # system "make", "test"  # for maintainers
          system "make", "install"
          system "make", "install-private-headers"
          ln_s bin/"wish8.6", bin/"wish"
        end
      end
    end

    if build.with? "tcllib"
      resource("tcllib").stage do
        system "./configure", "--prefix=#{prefix}",
                              "--mandir=#{man}"
        system "make", "install"
      end
    end
  end

  test do
    assert_equal "honk", pipe_output("#{bin}/tclsh", "puts honk\n").chomp
  end
end

__END__
diff --git a/pkgs/sqlite3.8.8.3/generic/sqlite3.c b/pkgs/sqlite3.8.8.3/generic/sqlite3.c
index 7d513fa..b1d968a 100644
--- a/pkgs/sqlite3.8.8.3/generic/sqlite3.c
+++ b/pkgs/sqlite3.8.8.3/generic/sqlite3.c
@@ -16805,6 +16805,7 @@ SQLITE_PRIVATE void sqlite3MemSetDefault(void){
 #include <sys/sysctl.h>
 #include <malloc/malloc.h>
 #include <libkern/OSAtomic.h>
+
 static malloc_zone_t* _sqliteZone_;
 #define SQLITE_MALLOC(x) malloc_zone_malloc(_sqliteZone_, (x))
 #define SQLITE_FREE(x) malloc_zone_free(_sqliteZone_, (x));
@@ -16812,6 +16813,29 @@ static malloc_zone_t* _sqliteZone_;
 #define SQLITE_MALLOCSIZE(x) \
         (_sqliteZone_ ? _sqliteZone_->size(_sqliteZone_,x) : malloc_size(x))

+/*
+** If compiling for Mac OS X 10.4, the OSAtomicCompareAndSwapPtrBarrier
+** function will not be available, but individual 32-bit and 64-bit
+** versions will.
+*/
+
+#ifdef __MAC_OS_X_MIN_REQUIRED
+# include <AvailabilityMacros.h>
+#elif defined(__IPHONE_OS_MIN_REQUIRED)
+# include <Availability.h>
+#endif
+
+typedef int fc_atomic_int_t;
+#if (MAC_OS_X_VERSION_MIN_REQUIRED > MAC_OS_X_VERSION_10_4 || __IPHONE_VERSION_MIN_REQUIRED >= 20100)
+# define fc_atomic_ptr_cmpexch(O,N,P) OSAtomicCompareAndSwapPtrBarrier ((void *) (O), (void *) (N), (void **) (P))
+#else
+# if __ppc64__ || __x86_64__
+#  define fc_atomic_ptr_cmpexch(O,N,P) OSAtomicCompareAndSwap64Barrier ((int64_t) (O), (int64_t) (N), (int64_t*) (P))
+# else
+#  define fc_atomic_ptr_cmpexch(O,N,P) OSAtomicCompareAndSwap32Barrier ((int32_t) (O), (int32_t) (N), (int32_t*) (P))
+# endif
+#endif
+
 #else /* if not __APPLE__ */

 /*
@@ -16998,7 +17022,7 @@ static int sqlite3MemInit(void *NotUsed){
     malloc_zone_t* newzone = malloc_create_zone(4096, 0);
     malloc_set_zone_name(newzone, "Sqlite_Heap");
     do{
-      success = OSAtomicCompareAndSwapPtrBarrier(NULL, newzone,
+      success = fc_atomic_ptr_cmpexch(NULL, newzone,
                                  (void * volatile *)&_sqliteZone_);
     }while(!_sqliteZone_);
     if( !success ){
