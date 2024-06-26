import Lake
open Lake DSL

def libcpp : String :=
  if System.Platform.isWindows then "libstdc++-6.dll"
  else if System.Platform.isOSX then "libc++.dylib"
  else "libstdc++.so.6"

package cvc5 {
  precompileModules := true
  moreGlobalServerArgs := #[s!"--load-dynlib={libcpp}"]
  extraDepTargets := #[`libcvc5]
}

@[default_target]
lean_lib cvc5 {
  moreLeanArgs := #[s!"--load-dynlib={libcpp}"]
}

def Lake.unzip (name : String) (file : FilePath) (dir : FilePath) : LogIO Unit := do
  logVerbose s!"Extracting {name}"
  proc {
    cmd := "unzip"
    args := #["-qd", dir.toString, file.toString]
  }

def cvc5.version : String := "v0.0.1"

def cvc5.os : String :=
  if System.Platform.isWindows then "Win64"
  else if System.Platform.isOSX then "macOS"
  else "Linux"

def cvc5.arch : String :=
  if System.Platform.target.startsWith "x86_64" then "x86_64"
  else "arm64"

target libcvc5 pkg : Unit := do
  if !(← (pkg.lakeDir / "cvc5").pathExists) then
    download "cvc5" s!"https://github.com/abdoo8080/cvc5/releases/download/{cvc5.version}/cvc5-{cvc5.os}-{cvc5.arch}-static.zip" (pkg.lakeDir / "cvc5.zip")
    unzip "cvc5" (pkg.lakeDir / "cvc5.zip") pkg.lakeDir
    IO.FS.removeFile (pkg.lakeDir / "cvc5.zip")
  return pure ()

def Lake.compileStaticLib' (name : String) (libFile : FilePath)
(oFiles : Array FilePath) (ar : FilePath := "ar") : BuildM Unit := do
  logStep s!"Creating {name}"
  createParentDirs libFile
  proc {
    cmd := ar.toString
    args := #["csqL", libFile.toString] ++ oFiles.map toString
  }

/-- Build a static library from object file jobs using the `ar` packaged with Lean. -/
def Lake.buildStaticLib' (libFile : FilePath)
(oFileJobs : Array (BuildJob FilePath)) : SchedulerM (BuildJob FilePath) :=
  let name := libFile.fileName.getD libFile.toString
  buildFileAfterDepArray libFile oFileJobs fun oFiles => do
    compileStaticLib' name libFile oFiles (← getLeanAr)

target ffiO pkg : FilePath := do
  let oFile := pkg.buildDir / "ffi" / "ffi.o"
  let srcJob ← inputFile <| pkg.dir / "ffi" / "ffi.cpp"
  let flags := #["-std=c++17", "-I", (← getLeanIncludeDir).toString, "-I", (pkg.lakeDir / "cvc5" / "include").toString, "-fPIC"]
  buildO "ffi.cpp" oFile srcJob flags

extern_lib libffi pkg := do
  let name := nameToStaticLib "ffi"
  let ffiO ← fetch (pkg.target ``ffiO)
  let libcadical := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "cadical")
  let libcvc5 := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "cvc5")
  let libcvc5parser := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "cvc5parser")
  let libgmp := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "gmp")
  let libpicpoly := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "picpoly")
  let libpicpolyxx := pure (pkg.lakeDir / "cvc5" / "lib" / nameToStaticLib "picpolyxx")
  let libFile := pkg.nativeLibDir / name
  buildStaticLib' libFile #[ffiO, libcadical, libcvc5, libcvc5parser, libgmp, libpicpoly, libpicpolyxx]
