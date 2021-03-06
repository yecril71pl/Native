### 
# IMPORTANT: KEEP THIS MODULE PSv3-COMPATIBLE.
# Notably:
#   * do not use .ForEach() / .Where()
#   * do not use ::new()
#   * do not use Get-ItemPropertyValue
#   * do not use New-TemporaryFile
### 

Set-StrictMode -Version 1

#region Define the ALIASES to EXPORT (must be referenced in the *.psd1 file).
Set-Alias ins Invoke-NativeShell
Set-Alias dbea Debug-ExecutableArguments
# Note: 'ie'  and 'iee' are *directly* used as the *function* names,
#       deliberately forgoing verbose names, for the reasons explained
#       in the comment-based help for 'ie'.
#endregion

# For older WinPS versions: set OS/edition flags (which in PSCore are automatically defined).
if (-not (Test-Path Variable:IsWindows)) { $IsWindows = $true }
if (-not (Test-Path Variable:IsCoreCLR)) { $IsCoreCLR = $false }

# Test if a workaround for PowerShell's broken argument passing to external
# programs as described in
#   https://github.com/PowerShell/PowerShell/issues/1995
# is still required.
$script:needQuotingWorkaround = if ($IsWindows) {
  (choice.exe /d Y /t 0 /m 'Nat "King" Cole') -notmatch '"'
}
else {
  (printf %s '"ab"') -ne '"ab"'
}

#region -- EXPORTED functions (must be referenced in the *.psd1 file)

function Invoke-NativeShell {
  <#
.SYNOPSIS
Executes a native shell command line. Aliased to: ins

.DESCRIPTION
Executes a command line or ad-hoc script using the platform-native shell,
on Unix optionally with pass-through arguments.

If no argument and no pipeline input is given, an interactive shell is entered.
Otherwise, pass a *single string* comprising one more commands for the native
shell to execute; e.g.:

  ins 'whoami && echo hi'

Add -ErrorOnFailure (-e) if you want a script-terminating error to be thrown
in case the native shell reports a nonzero exit code.

For command lines with tricky quoting, use here-strings; e.g., on Unix:

  ins @'
    printf '%s\n' "3\" of rain."
  '@

Use an interpolating (here-)string to incorporate PowerShell values; use `$
for $ characters to pass throug to the native shell; e.g., on Unix:

  ins @"
    printf 'PS version: %s\n' "$($PSVersionTable.PSVersion)"
  "@

The native shell's exit code will be reflected in $LASTEXITCODE; use only 
$LASTEXITCODE to infer success vs. failure, not $?, which always ends up 
$true.

Pipeline input is supported in two fundamental modes:

* The pipeline input is the *command line* to execute (`<commands> | ins`):

  * In this case, no -CommandLine argument must be passed, or, if pass-through
    arguments are specified, it must be '-' to explicitly signal that the
    command line is coming from the pipeline (stdin)
    (`<commands> | ins - passThruArg1 ...`).
    Alternatively, use parameeter -Args explicitly with an array of values to
    unambiguously identify them as pass-through arguments
    (`<commands> | ins -Args passThruArg1, ...`).

* The pipeline input is *data* to pass *to* the command line to execute
  (`<data> | ins <commands>`):

.PARAMETER CommandLine
The command line or ad-hoc script to pass to the native shell for execution.

Ad-hoc script means that the string you pass can act as a batch file / shell
script that is capable of receiving any pass-through arguments passed via
-ArgumentList (-Args) the usual way (e.g., %1 as the first argument on Windows,
and $1 on Unix).

You may omit this parameter and pass the command line via the pipeline instead.
If you use the pipeline this way on and you additionally want to specify
pass-through arguments positionally, you can pass '-' as the -CommandLine
argument to signal that the code is specified via the pipeline; alternatively,
use the -ArgumentList (-Args) parameter explicitly, in which case you must
specify the arguments as an *array*.

IMPORTANT:
  * On Windows, the command line isn't executed directly by cmd.exe, 
    but via a temporary *batch file*. This means that batch-file syntax rather
    than command-prompt syntax will be in effect, notably needing %% rather 
    than just % before `for` loop variables (e.g. %%i) and being able to escape
    verbatim "%" characters as "%%"

.PARAMETER ArgumentList
Any addtional arguments to pass through to the ad-hoc script passed to
-CommandLine or supplied via the pipeline.

Important:

* These arguments bind to the standard batch-file / shell-script 
  parameters starting with %1 / $1. See the NOTES section for more information.

* If you pass the pass-through arguments *individually, positionally*, 
  you may precede them with an extra '--' argument to avoid name conflicts with
  this function's own parameters (which includes the supported common
  parameters).

* If the command line is supplied via the pipeline, you must either pass '-'
  as -CommandLine or use -ArgumentList / -Args explicitly and specify the 
  pass-through arguments *as an array*.

.PARAMETER UseSh
Supported on Unix-like platforms only (ignored on Windows); aliased to -sh.

Uses /bin/sh rather than /bin/bash for execution.

Note that /bin/sh, which is the official system shell on Unix-like platforms, 
can be expected to support POSIX-compliant features only, which notably
precludes certain Bash features, such as [[ ... ]] conditionals, process
substitutions, <(...), and Bash-specific variables.

Conversely, if your command line does work with -UseSh, it can be assumed 
to work in any of the major POSIX-compatible shells: bash, dash, ksh, and zsh.

.PARAMETER ErrorOnFailure
Triggers a script-terminating error if the native shell indicates overall
failure of the command line's execution via a nonzero exit code; aliased to
-e.

IMPORTANT: This switch acts independently of PowerShell's error handling, 
which as of v7.1 does not act on nonzero exit codes reported by external
executables.
There is a pending RFC to change that:
  https://github.com/PowerShell/PowerShell-RFC/pull/88
Once it gets implemented, this commmand will
be subject to this new integration in the absence of -ErrorOnFailure (-e).

.PARAMETER InputObject
This is an auxiliary parameter required for technical reasons only.
Do not use it directly.

.EXAMPLE
ins 'ver & date /t & echo %CD%'

Windows example: Calls cmd.exe with the given command line, which ouputs 
cmd.exe version information and prints the current date and working directory.

.EXAMPLE
'ver & date /t & echo %CD%' | ins

Windows example: Equivalent command using pipeline input to pass the command
line.

.EXAMPLE
'foo', 'bar' | ins 'findstr bar & ver'

Windows example: Passes data to the command line via the pipeline (stdin).

.EXAMPLE
$msg = 'hi'; ins "echo $msg"

Uses string interpolation to incorporate a PowerShell variable value into
the native command line.

.EXAMPLE
ins -e 'whoami -nosuchoption'

Uses -e (-ErrorOnFailure) to request throwing an error if the native shell
reports a nonzero exit code, as is the case here.

.EXAMPLE
ins 'ls / | cat -n'

Unix example: Calls Bash with the given command line, which lists the files 
and directories in the root directory and numbers the output lines.

.EXAMPLE
ins 'ls "$1" | cat -n; echo "$2"' $HOME 'Hi there.'

Unix example: uses a pass-through argument to pass a PowerShell variable value
to the Bash command line.

.EXAMPLE
'ls "$1" | cat -n; echo "$2"' | ins -UseSh - $HOME 'Hi there.'

Unix example: Equivalent of the previous example with the command line passed 
via the pipeline, except that /bin/sh is used for execution.
Note that since the command line is provided via the pipeline and there are
pass-through arguments present, '-' must be passed as the -CommandLine argument.

.EXAMPLE
'one', 'two', 'three' | ins 'grep three | cat -n'

Unix example: Sends data through the pipeline to pass to the native command
line as stdin input.

.EXAMPLE
ins @'
  printf '%s\n' "6'1\" tall"
'@

Unix example: Uses a (verbatim) here-string to pass a command line with
complex quoting to Bash.

.NOTES

* By definition, calls to this function are *platform-specific*.
  To perform platform-agnostic calls to a single external executable, use the
  'ie' function that comes with this module.

* On Unix-like platforms, /bin/bash is used by default, due to its ubiquity.
  If you want to use the official system default shell, /bin/sh, instead, use 
  -UseSh. Without -UseSh, /bin/sh is also used as a fallback in the unlikely
  event that /bin/bash is not present.

* When /bin/bash and /bin/sh accept a command line as a CLI argument, it is via 
  the -c option, with subsequent positional arguments getting passed 
  *to the command line* being invoked; curiously, however, the first such 
  argument sets the *invocation name* that the command line sees as special 
  parameter $0; it is only the *second* argument that becomes $1, the first 
  true script parameter (argument).
  Since this is somewhat counterintuitive and since setting $0 in this scenaro 
  is rarely, if ever, needed, this function leaves $0 at its default (the path
  of the executing shell) and passes any pass-through arguments (specified via
  -ArgumentList / -Args or positionally) starting with parameter $1.

* On Windows, <systemRoot>\System32\cmd.exe is used, where <systemroot> is
  the Windows directory path as stored in the 'SystemRoot' registry value at
  'HKEY_LOCAL_MACHINE:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'; the 
  following options, which explicitly request cmd.exe's default behavior, are 
  used to ensure a predictable execution environment: /d /e:on /v:off

#>

  [CmdletBinding(PositionalBinding = $false)]
  param(
    [Parameter(Position = 1)]
    [string] $CommandLine
    ,
    [Parameter(Position = 2, ValueFromRemainingArguments = $true)]
    [Alias('Args')]
    [string[]] $ArgumentList
    ,
    [Alias('sh')]
    [switch] $UseSh
    ,
    [Alias('e')]
    [switch] $ErrorOnFailure
    ,
    [Parameter(ValueFromPipeline = $true)] # Dummy parameter to ensure that pipeline input is accepted, even though we use $input to process it.
    $InputObject
  )

  # Note: If -UseSh is passed on Windows, we *ignore* it rather than throwing an error.
  #       This makes it easier to create cross-platform commands in that only the command-line
  #       string must be provided via a variable (with platform-appropriate content).
  
  $nativeShellExePath = if ($IsWindows) {
    # For increased robustness, rely on the SystemRoot definition (typically, C:\Windows)
    # from the registry rather than $env:ComSpec, given that the latter could
    # have been (more easily) modified, even in-process.
    '{0}\System32\cmd.exe' -f $(try {
        (Get-Item -ErrorAction Stop -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion').GetValue('SystemRoot', 'C:\Windows')
      }
      catch {
        'C:\Windows'
      })
  }
  else {
    # Note: By default, due to its ubiquity, we use /bin/bash, unless -UseSh was passed or /bin/bash doesn't exist (unlikely).
    if ($UseSh -or -not (Test-Path -PathType Leaf '/bin/bash')) {
      # The de-facto standard location for the default system shell on Unix-like platforms.
      '/bin/sh'
    }
    else {
      '/bin/bash'
    }
  }

  # We invoke the native shell via 'ie' by default, or, if erroring out on
  # nonzero exit codes is requsted, via 'iee'
  $invokingFunction = ('ie', 'iee')[$ErrorOnFailure.IsPresent]

  $havePipelineInput = $MyInvocation.ExpectingInput
  $pipelineInputIsCommandLine = $havePipelineInput -and (-not $CommandLine -or $CommandLine -eq '-')

  if (-not $havePipelineInput -and -not $CommandLine) { 
    # If neither a command line nor pipeline input is given, enter an interactive
    # session of the target shell.
  
    Write-Verbose "Entering interactive $nativeShellExePath session..."
  
    & $invokingFunction $nativeShellExePath
  
  }
  else {
    # A command line / ad-hoc script must be passed to the native shell.

    # NOTE: For platform-specific reasons, we translate a code-via-stdin (pipeline) (`... | ins`)
    #       invocation to a code-by-argument / code-by-temporary-batch-file invocation.
    if ($pipelineInputIsCommandLine) {

      $pipelineInputIsCommandLine = $havePipelineInput = $false
      $CommandLine = @($Input) -join "`n" # Collect all pipeline input and join the (stringified) objects with newlines.

      # RATIONALE:
      # Windows:
      #   * cmd.exe doesn't properly support piping *commands* to it:
      #     The "logo" is always printed, and lines are executed one after, with
      #     the prompt string printed after each, and by default each command is 
      #     also echoed before execution (only this aspect can be controlled, with /q)
      #   * Similarly, passing multi-line strings to cmd /c isn't supported:
      #     Only the *first* line is processed, the rest are *ignored*.
      #   Since we're using a temporary *batch file* for invocation anyway, 
      #   we can offer the same code-via-pipeline experience as with bash/sh:
      #   Essentially, a multi-line ad-hoc batch file may be passed.
      #
      # Unix:
      #   * While bash/sh are perfectable cable of receiving ad-hoc scripts via
      #     stdin, we still translate the invocation into a `-c <string>`-based
      #     one, so as to support commands that ask for *interactive input*.
      #     If we used the pipeline/stdin, the *code itself*, by virtue of 
      #     being received via stdin, would be used to automatically respond to
      #     interactive prompts.

    }
    
    if ($IsWindows) {
      # On Windows, we use a temporary batch file to avoid re-quoting problems 
      # that would arise if the command line were passed to cmd /c as an *argument*.
      # This invariably means that batch-file rather than command-line syntax is 
      # expected, which, however, is arguably preferable anyway.

      Write-Verbose "Passing commands via a temporary batch file to $nativeShellExePath..."

      $tmpBatchFile = [IO.Path]::GetTempFileName() + '.cmd'

      # Write the command line to the temp. batch file.
      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value "@echo off`n$CommandLine"

      # To be safe, use an empty array rather than $null for array splatting below.
      if ($null -eq $ArgumentList) { $ArgumentList = @() }

      # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
      #            is present. If no input is present, PowerShell *still
      #            redirects* the target executable's stdin and simply makes it
      #            *empty*. This causes command lines with *interactive* prompts
      #            to malfunction.
      #            Also: We cannot use an intermediate script block invoked
      #                  with & here in order to avoid duplicating the actual
      #                  command: the pipeline input is then NOT passed through
      #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
      if ($havePipelineInput) { 
        # Note: For predictability, we use explicit switches in order to get what should be the default
        #       behavior of cmd.exe on a pristine system:
        #       /d == no auto-run, /e:on == enable command extensions; /v:off == disable delayed variable expansion
        # IMPORTANT: Changes to this call must be replicated in the `else` branch.
        $input | & $invokingFunction $nativeShellExePath /d /e:on /v:off /c $tmpBatchFile $ArgumentList
      } 
      else { 
        & $invokingFunction $nativeShellExePath /d /e:on /v:off /c $tmpBatchFile $ArgumentList
      }

      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile

    }
    else {
      # Unix

      Write-Verbose "Passing commands as an argument to $nativeShellExePath..."

      $passThruArgs = if ($ArgumentList.Count) {
        # POSIX-like shells interpret the first post `-c <code>` operand as $0,
        # which is both unexpected and rarely useful.
        # We abstract this behavior away by emulating the default $0 value (the
        # name/path of the shell being invoked) and by passing the 
        # the pass-through arguments starting with $1.
        , $nativeShellExePath + $ArgumentList
      }
      else {
        @()
      }
  
      # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
      #            is present. If no input is present, PowerShell *still
      #            redirects* the target executable's stdin and simply makes it
      #            *empty*. This causes command lines with *interactive* prompts
      #            to malfunction.
      #            Also: We cannot use an intermediate script block invoked
      #                  with & here in order to avoid duplicating the actual
      #                  command: the pipeline input is then NOT passed through.
      #                  (you'd have to use $input inside the script block too).
      if ($havePipelineInput) { 
        # IMPORTANT: Changes to this call must be replicated in the `else` branch.
        $input | & $invokingFunction $nativeShellExePath -c $CommandLine $passThruArgs
      } 
      else { 
        & $invokingFunction $nativeShellExePath -c $CommandLine $passThruArgs
      }

    }

  }
}


function ie {
  <#
.SYNOPSIS
Invokes an external executable with robust argument passing.

.DESCRIPTION
Invokes an external executable with arguments passed through properly, even if
they contain embedded double quotes or they're the empty string.

'ie' stands for 'Invoke (External) Executable'. The related 'iee' wrapper
function additionally throws an error if the external executable indicated
failure via a nonzero process exit code.

Note: Since the invocation solely relies on PowerShell's own argument-mode
      syntax and since no other shell is involved (as in a direct call),
      this function is suitable for use in *cross-platform*  code, unlike calls
      to Invoke-NativeShell / ins.

Use this function by simply prefixing a call to an external executable with
'ie' as the command (if invocation via call operator '&' would
normally be necessary, use 'ie' *instead* of it). E.g., on Unix:

  ie printf '"%s" ' print these arguments quoted

IMPORTANT: 

* On Windows, this function also handles special quoting needs for 
  msiexec.exe / msdeploy.exe and batch files, so there should generally be no 
  need for --%, the stop-parsing symbol - which this function does *not* support.
  In other words: EITHER use this function OR, if you truly need --%, use it
  with direct invocation only.

* External executable in this context means any executable that PowerShell must
  invoke via a child process, which encompasses not just binary executables,
  but also batch files and other shells' or scripting languages' scripts.

* The only reason for this function's existence is that up to at least
  PowerShell 7.0, arguments passed to external programs are not passed
  correctly if they are either the empty string or have embedded double quotes.
  Should the underlying problem ever be fixed in PowerShell itself, this
  function will no longer apply its workarounds and will effectively act like 
  '&', the call operator. See the NOTES section for a link to more information.

* This function is intentially designed to be a minimalist stopgap that
  should be unobtrusive and simple to use. It is therefore implemented as 
  a *simple* function and does *not* support common parameters (just like
  you can't use common parameters with direct invocation).

CAVEATS:

  * While $LASTEXITCODE is set as usual, $? always ends up as $true.
    Only query $LASTEXITCODE to infer success vs. failure.

  * This function should work robustly in PowerShell Core, but in
    Windows PowerShell there are still edge cases with embedded double quotes
    that break if `\"` escaping (rather than `""`) must be used behind the
    scenes; whether `\"` must be used is inferred from the specific target
    executable being invoked.

.EXAMPLE
ie echoArgs.exe '' 'a&b' '3" of snow' 'Nat "King" Cole' 'c:\temp 1\' 'a \" b'

Calls the echoArgs.exe executable on Windows, which echoes the individual 
arguments it receives in diagnostic form as follows, showing that the arguments
were passed as intended:

    Arg 0 is <>
    Arg 1 is <a&b>
    Arg 2 is <3" of snow>
    Arg 3 is <Nat "King" Cole>
    Arg 4 is <c:\temp 1\>
    Arg 5 is <a \" b>

    Command line:
    "C:\ProgramData\chocolatey\lib\echoargs\tools\EchoArgs.exe" "" a&b "3\" of snow" "Nat \"King\" Cole" "c:\temp 1\\" "a \\\" b"

Note: echoArgs.exe is installable via Chocolatey using the following commmand
from an elevated session:

    choco install echoargs -y 

.NOTES

For background information on the broken argument handling, see:
https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

#>

  # Split into executable name/path and arguments.
  # Note: We can't assume that $argsForExe will be a flat array - see below.
  $exe, $argsForExe = $args

  if (-not $exe) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.Management.Automation.ParameterBindingException] "Missing mandary parameter: Please specify the external executable to invoke.",
          'MissingMandatoryParameter',
          'InvalidArgument',
          $null
        ))
    )
  }

  # Resolve to the underlying command (if it's an alias) and ensure that an external executable was specified.
  $app = try { Get-Command -ErrorAction Stop $exe } catch { throw }
  if ($app -and $app.ResolvedCommand) { $app = $app.ResolvedCommand }
  if ($app.CommandType -ne 'Application') {
    $exeDescr = '"{0}"' -f $exe
    if ($exe -ne "$app") { $exeDescr += ' ("{0}")' -f "$app" }
    # Throw "This command supports external executables only; $exeDescr isn't one." 
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [ArgumentException] "This command supports external executables (applications) only; $exeDescr is a command of type $($app.CommandType)",
          'InvalidCommandType',
          'InvalidArgument',
          $exe
        ))
    ) 
    # Note: 
    #  * Even if we wanted to support calls to PowerShell-native commands too, 
    #    we can't, given that this simple function is based on the array of positional arguments, $args. 
    #    While @args is built-in magic for passing even *named* arguments through,
    #    we need to split $args into executable name and remaining arguments here, and the magic doesn't work with custom arrays.
  }
  
  # Use the full path for invocation, to avoid having to re-resolve the executable as specified to the underlying full path.
  #  Note: Regrettably, Get-Command also reports *documents* as commands of type 'Application' - see https://github.com/PowerShell/PowerShell/issues/12625
  #        While we could do our own subsequent analysis to see if a true executable was specified, that doesn't seem worth the trouble.
  #        It's usually pointless to invoke a document directly *with additional arguments*, which are usually ignored.
  $exe = $app.Path

  # Flatten the array of arguments, because we also want to support invocations such as `ie $someArray foo bar`, 
  # i.e. a mix of array-splatting and indiv. args.
  $argsForExe = foreach ($potentialArrayArg in $argsForExe) { foreach ($arg in $potentialArrayArg) { $arg } }

  # See if a PowerShell CLI is being invoked, so we can detect whether a *script block* is among the arguments,
  # which causes PowerShell to transform the invocation into a Base64-encoded one using the -encodedCommand CLI parameter.
  $isPsCli = $exe -match '[\\/](?:pwsh|powershell)(?:\.exe)?$'

  # Construct the array of escaped arguments, if necessary.
  # Note: We cannot use .ForEach('GetType'), because we must remain PSv3-compatible.
  [array] $escapedArgs = 
  if ($null -eq $argsForExe) {
    # To be safe: If there are no arguments to pass, use an *empty array* for splatting so as
    #             to be sure that *no* arguments are passed. We don't want to rely on passing $null
    #             getting that same treatment in all future PS versions.
    @()
  }
  elseif (-not $script:needQuotingWorkaround -or ($isPsCli -and $(foreach ($el in $argsForExe) { if ($el -is [scriptblock]) { $true; break } }))) {
  
    # Use the array as-is if (a) the quoting workaround is no longer needed or (b) the engine itself will aply Base64-encoding behind the scenes
    # using the -encodedCommand CLI parameter.
    # Note: As of PowerShell Core 7.1.0-preview.5, the engine unexpectedly applies Base64-encoding in the presence of a [scriptblock] argument alone,
    #       irrespective of what executable is being invoked: see https://github.com/PowerShell/PowerShell/issues/4973
    #       In effect we're masking the bug by exhibiting more sensible behavior if the executable is NOT a PowerShell CLI (stringified script block, which may still not be the intent),
    #       in the hopes that the bug will get fixed and that direct execution will then exhibit the same behavior.
    $argsForExe
  
  }
  else {

    # Escape arguments properly properly to pass them through as seen verbatim by PowerShell.
    # Decide whether to escape embedded double quotes as \" or as "", based on the target executable.
    # * On Unix-like platforms, we always use \"
    # * On Windows, we use "" where we know it's safe to do. cmd.exe / batch files require "", and Microsoft compiler-generated executables do too, often in addition to supporting \",
    #   notably including Python and Node.js
    #   However, notable interpreters that support \" ONLY are Ruby and Perl (as well as PowerShell's own CLI, but it's better to call that with a script block from within PowerShell).
    #   Targeting a batch file triggers "" escaping, but note that in the case of stub batch files that simply relay to a different executable, that could still break
    #   if the ultimate target executable only supports \"
    $useDoubledDoubleQuotes = $IsWindows -and ($app.Source -match '[/\\]?(?<exe>cmd|py|pythonw?|node|msiexec|msdeploy)(?:\.exe)?$' -or $app.Source -match '\.(?<ext>cmd|bat|py|pyw)$')
    $doubleQuoteEscapeSequence = ('\"', '""')[$useDoubledDoubleQuotes]
    $isMsiStyleExe = $useDoubledDoubleQuotes -and $Matches['exe'] -in 'msiexec', 'msdeploy'
    $isBatchFile = $useDoubledDoubleQuotes -and $Matches['ext'] -in 'cmd', 'bat'

    foreach ($arg in $argsForExe) {
      if ($arg -isnot [string]) {
        $arg = "$arg"  # Make sure that each argument is a string, so we can analyze the the string representation with respect to quoting.
      }
      if ('' -eq $arg) { '""'; continue } # Empty arguments must be passed as `'""'`(!), otherwise they are omitted.
      $hasDoubleQuotes = $arg.Contains('"')
      $hasSpaces = $arg.Contains(' ')
      if ($hasDoubleQuotes) {
        # First, always double any preexisting `\` instances before embedded `"` chars.
        # so that `\"` isn't interpreted as an escaped `"`.
        $arg = $arg -replace '(\\+)"', '$1$1"'
        # Then, escape the embedded `"` chars. either as `\"` or as `""`.
        # If \" escaping is used:
        # * In PS Core, use of `\"` is safe, because its use triggers enclosing double-quoting (if spaces are also present).
        # * !! In WinPS, sadly, that isn't true, so something like `'foo="bar none"'` results in `foo=\"bar none\"` -
        #   !! which - due to the lack of enclosing "..." - is seen as *2* arguments by the target app, `foo="bar` and `none"`.
        #   !! Similarly, '3" of snow' would result in `3\" of snow`, which the target app receives as *3* arguments, `3"`, `of`, and `snow`.
        #   !! Even manually enclosing the value in *embedded* " doesn't help, because that then triggers *additional* double-quoting.
        $arg = $arg -replace '"', $doubleQuoteEscapeSequence
      }
      elseif ($isMsiStyleExe -and $arg -match '^(\w+)=(.* .*)$') {
        # An msiexec / msdeploy argument originally passed in the form `PROP="value with spaces"`, which PowerShell turned into `PROP=value with spaces`
        # This would be passed as `"PROP=value with spaces"`, which these programs, sadly, don't recognize (`PROP=valueWithoutSpaces` works fine, however).
        # We reconstruct the form `PROP="value with spaces"`, which both WinPS And PS Core pass through as-is.
        $arg = '{0}="{1}"' -f $Matches[1], $Matches[2]
      }
      # For batch files, explicitly enclose in "..." those arguments that PowerShell would pass unquoted due to absence of whitespace
      # *if they contain cmd.exe metachars.* Given that cmd.exe regrettably subjects batch-file arguments to its usual parsing even 
      # when *not* calling from inside cmd.exe, unquoted arguments such as `a&b` would *break* the call.      
      # Note: * Leaving the argument unquoted and instead individually ^-escaping the cmd.exe metacharacters
      #         is ultimately NOT the right solution, because the presence of such an argument breaks pass-through
      #         invocations with %*, which is the most important scenario we want to support.
      #       * Also, we do not perform this explicitly quoting for calls *directly to cmd.exe*, as the reasonable assumption
      #         there is that cmd.exe metacharacters then *should* have their usual, syntactic meaning (even though the problem
      #         would only arise in awkwardly formatted commands such as (from PowerShell) `cmd /c 'ver|findstr' V`. Ultimately,
      #         it seems that the point is moot, because - like PowerShell - `cmd.exe /c` seems to strip enclosing double quotes from
      #         individual arguments before interpreting the space-concatenated list of stripped arguments like a submitted-from-inside-cmd.exe
      #         command line.
      $manuallyEscapeForCmd = $isBatchFile -and -not $hasSpaces -and $arg -match '[&|<>^,;]'
      # In WinPS, double trailing `\` instances in arguments that have spaces and will therefore be "..."-enclosed,
      # so that `\"` isn't mistaken for an escaped `"` - in PS Core, this escaping happens automatically.
      if (-not $IsCoreCLR -and ($hasSpaces -or $manuallyEscapeForCmd) -and $arg -match '\\') {
        $arg = $arg -replace '\\+$', '$&$&'
      }
      if ($manuallyEscapeForCmd) {
        # Wrap in *embedded* enclosing double quotes, which both WinPS and PS Core pass through as-is.
        $arg = '"' + $arg + '"'
      }
      $arg
    }
  }

  # Invoke the executable with the properly escaped arguments, if any, possibly with pipeline input.  
  # Note: We must use @escapedArgs rather than $escapedArgs, otherwise PowerShell won't apply
  #       Base64 encoding in the presence of a script-block argument when its CLI is called.
  #       Use of @ also results in --% getting removed, but we don't support it meaningfully anyway.
  if ($MyInvocation.ExpectingInput) {
    # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
    #            is present. If no input is present, PowerShell *still
    #            redirects* the target executable's stdin and simply makes it
    #            *empty*. This causes command lines with *interactive* prompts
    #            to malfunction.
    #            Also: We cannot use an intermediate script block invoked
    #                  with & here in order to avoid duplicating the actual
    #                  command: the pipeline input is then NOT passed through
    #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
    # IMPORTANT: Changes to this call must be replicated in the `else` branch.
    $input | & $exe @escapedArgs
  }
  else {
    & $exe @escapedArgs
  }


}

function iee {
  <#
.SYNOPSIS
Invokes an external executable robustly and throws an error if its exit code is 
nonzero.

.DESCRIPTION
Like the 'ie' function it wraps, this function invokes an external executable 
with robust argument passing and additionally throws a script-terminating error
if the executable reports a nonzero process exit code (as reflected in the 
automatic $LASTEXITCODE variable).

NOTE: This function only works meaningfully with *console* (terminal) programs, 
      because only they run synchronously, which ensures that their exit code 
      is already known when the invocation returns.

.EXAMPLE
iee curl.exe -u jdoe 'https://api.github.com/user/repos' -d '{ "name": "foo"}'

Invokes the external curl utility to create a new GitHub repo.
If doing so fails, as indicated by curl's process exit code being nonzero,
an script-terminating error is thrown.

.NOTES

Once the following RFC is implemented, you'll be able to use a preference
variable to control how nonzero exit codes reported by external programs are
handled:

https://github.com/PowerShell/PowerShell-RFC/pull/88

#>

  if ($MyInvocation.ExpectingInput) {
    # IMPORTANT: We must only use `$input | ...` if actual pipeline input 
    #            is present. If no input is present, PowerShell *still
    #            redirects* the target executable's stdin and simply makes it
    #            *empty*. This causes command lines with *interactive* prompts
    #            to malfunction.
    #            Also: We cannot use an intermediate script block invoked
    #                  with & here in order to avoid duplicating the actual
    #                  command: the pipeline input is then NOT passed through
    #                  (you'd have to use $input inside the script block too, which amounts to a catch-22).
    # IMPORTANT: Changes to this call must be replicated in the `else` branch.
    $input | ie @args
  }
  else {
    ie @args
  }

  if ($LASTEXITCODE) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.Management.Automation.ApplicationFailedException] "`"$($args[0])`" terminated with nonzero exit code $LASTEXITCODE.",
          'NativeCommandFailed',
          'OperationStopped',
          "$args"  # Report the full command, though note that this is just a space-separated list of the verbatim arguments, without quoting and escaping.
        ))
    )
  }

}

function Debug-ExecutableArguments {
  <#
.SYNOPSIS
Debugs external-executable argument passing.

.DESCRIPTION
Acts as an external executable that prints the arguments passed to it in 
diagnostic form, similar to what the well-known third-party echoArgs.exe 
utility does on Windows.

On Windows, the whole command line is printed as well.
On Unix, there is no point in doing so, as processes there do not receive a
single command line that encodes all arguments, but an array of verbatim
strings.

The default output is formatted for easy readability by humans.
Using -Raw prints the raw argument values only.

This function is useful for diagnosing the problems with passing empty-string
arguments and arguments with embedded double quotes to external executables
that exist up to at least v7.0 and are detailed here:

https://github.com/PowerShell/PowerShell/issues/1995#issuecomment-562334606

You can avoid these problems altogether if you use the 'ie' function to call
external executables, whose use behind the scenes you can request with -UseIe.

Hidden helper executables / scripts, created on demand, are used to receive and
print the given arguments. By default, a helper binary is used on Windows, 
and an ad-hoc /bin/sh script on Unix.

On Windows, you can specify -UseBatchFile to use a batch file instead, or
-UseWrapperBatchFile to use an intermediate batch file to pass the arguments
through to the helper binary.

.PARAMETER ArgumentList
The arguments to pass - either with -ArgumentList / -Args as an *array*,
or more conveniently, as *individual*, positional arguments.

That is, the following two invocations are equivalent:

  Debug-ExecutableArguments one, two, three

and:

  Debug-ExecutableArguments one two three

In the latter form, in the unlikely event that you need to disambiguate
pass-through arguments from the parameters supported by this command itself,
prepend the pass-through arguments with a '--' argument; e.g., to pass
'-Raw` as a pass-through argument:

  Debug-ExecutableArguments -- -Raw one two three

.PARAMETER UseBatchFile
On Windows, uses a batch file rather than the helper binary to print the 
arguments it receives in diagnostic form.

Note that batch-file arguments are subject to cmd.exe's usual parsing rules.

.PARAMETER UseWrapperBatchFile
On Windows, uses an *intermediate* batch file that passes the
arguments it receives *through* to the helper binary.

This is useful for testing how CLIs that use a wrapper batch file as their 
entry point ultimately receive arguments. The Azure CLI is a prominent
example.

.PARAMETER Raw
Prints the arguments only, as-is, eacho on its own line. 
No delimiters are used and no other information is printed.

This makes the output suitable for programmatic processing, but only as long
none of the arguments span multiple lines.

.EXAMPLE
Debug-ExecutableArguments -u '' 'https://api.github.com/user/repos' -d '{ "name": "foo" }'

On Unix, you'll see the following output as of v7.0:

  4 argument(s) received (enclosed in <...> for delineation):

    <-u>
    <https://api.github.com/user/repos>
    <-d>
    <{ name: foo }>

Note the missing empty-string argument and the loss of the embedded " chars.

On Windows, you'll additionally see the following as of v7.0:

  Command line (executable omitted):
    -u https://api.github.com/user/repos -d "{ "name": "foo" }"

The command line shows that the empty-argument string was never passed, and
the lack of escaping the embedded " chars., when the argument was re-quoted
behind the scenes to use double quotes, resulted in their effective removal
(because the argument was intrepreted as a composite string composed of
double-quoted and unquoted parts).

.NOTES

On Windows, a helper executable is created on demand in the following location:

  $env:TEMP\f7fd420a-47e4-4216-bd57-c88696123608\dbea.exe

You can delete it anytime, but note that you'll pay a performance penalty for
the re-creation on the next invocation.

#>

  [CmdletBinding(PositionalBinding = $false, DefaultParameterSetName = 'Default')]
  param(
    [Parameter(Mandatory, ValueFromRemainingArguments)]
    [Alias('Args')]
    $ArgumentList
    ,
    [Parameter(ParameterSetName = 'BatchFile', Mandatory)]
    [switch] $UseBatchFile
    ,
    [Parameter(ParameterSetName = 'WrapperBatchFile', Mandatory)]
    [switch] $UseWrapperBatchFile
    ,
    [Alias('ie')]
    [switch] $UseIe
    ,
    [switch] $Raw
  )
  
  if (($UseBatchFile -or $UseWrapperBatchFile) -and -not $IsWindows) {
    Throw (
      (New-Object System.Management.Automation.ErrorRecord (
          [System.PlatformNotSupportedException] "The -UseBatchFile and -UseWrapperBatchFile parameters are supported on Windows only.", 
          'PlatformNotSupportedException', 
          'InvalidArgument', 
          $null
        ))
    )
  }

  # Communicate -Raw, i.e. the desire to print just the raw arguments recived -
  # via an *environment variable* to the helper executable / scripts.
  if ($Raw) { $env:_dbea_raw = 1 }

  if ($IsWindows) {
    
    # Note: Unless explicitly requested to use a batch file only, we need a 
    #       binary helper executable to robustly replicate what external executables 
    #       will receive as arguments, so we create a .NET console application on demand, 
    #       using inline C# code.
    #       Note: This application will invariably recognize "" as an alternative to \"
    #             escaping, which most, but not all CLIs on Windows do.
    $helperBinary = if (-not $UseBatchFile) { get-WinHelperBinaryPath }

    if ($UseBatchFile -or $UseWrapperBatchFile) {
  
      $tmpBatchFile = [IO.Path]::GetTempFileName() + '.cmd'
    
      $content = if ($UseWrapperBatchFile) {
        # The wrapper batch file simply passes all args through to the helper binary.
        "@$helperBinary %*"
        Write-Verbose "Executing helper binary `"$helperBinary`" via temporary wrapper batch file `"$tmpBatchFile`""
      }
      else {
        # Create the argument-echoing batch file on demand.
        if ($Raw) {
          @'
@echo off
:for_arg

  if %1.==. goto :eof

  echo %1

  shift
goto for_arg
'@
        }
        else {
          @'
@echo off
setlocal

call :count_args %*
echo %ReturnValue% argument(s) received (enclosed in ^<...^> for delineation):
echo.

:for_arg

  if %1.==. goto for_arg_done

  echo   ^<%1^>

  shift
goto for_arg
:for_arg_done

echo.

goto :eof

:count_args
  set /a ReturnValue = 0
  :count_args_for

    if %1.==. goto :eof

    set /a ReturnValue += 1

    shift
  goto count_args_for
'@
          Write-Verbose "Executing argument-echoing batch file: $tmpBatchFile"
        }
      }
      Set-Content -Encoding Oem -LiteralPath $tmpBatchFile -Value $content
    
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because we want to support --%, the stop-parsing symbol.
      if ($UseIe) {
        ie $tmpBatchFile @ArgumentList
      }
      else {
        & $tmpBatchFile @ArgumentList
      }
    
      Remove-Item -ErrorAction Ignore -LiteralPath $tmpBatchFile
    
    }
    else {
      # Note: We explicitly use @ArgumentList rather than $ArgumentList,
      #       because (on Windows) we want to support --%, the stop-parsing symbol.
      Write-Verbose "Executing helper binary: $helperBinary"
      if ($UseIe) {
        ie $helperBinary @ArgumentList
      }
      else {
        & $helperBinary @ArgumentList
      }
    }

  }
  else {
    # Unix

    Write-Verbose "Executing ad-hoc in-memory /bin/sh script."

    # No need for a binary executable - a shell script will do.
    # Note: For consistency, and since --% is technically (albeit mostly uselessly)
    #       supported on Unix too, we also use @ArgumentList rather than $ArgumentList on Unix.
    $script = @'
if [ -z "$_dbea_raw" ]; then
  printf '%s\n\n' "$# argument(s) passed (enclosed in <...> for delineation):"
fi

for a; do 
  if [ -z "$_dbea_raw" ]; then
    printf '%s\n' "  <$a>"
  else
    printf '%s\n' "$a"
  fi
done

if [ -z "$_dbea_raw" ]; then
  printf '%s\n'
fi
'@
    if ($UseIe) {
      $script | ie /bin/sh -s -- @ArgumentList
    } 
    else {
      $script | /bin/sh -s -- @ArgumentList
    }

  }

  if ($Raw) { $env:_dbea_raw = $null }

}

#endregion -- EXPORTED functions


# Internal Windows-only function that returns the path to the helper binary, 
# which is created on demand.
function get-WinHelperBinaryPath() {

  # Create a unique temp. dir. Note: the GUID is the one from the *.psd1 file
  # and is assumed not to change.
  $dir = Join-Path $env:TEMP 'f7fd420a-47e4-4216-bd57-c88696123608'
  $null = New-Item -ErrorAction Stop -Force -Type Directory $dir

  $exePath = "$dir\dbea.exe" # Use the alias name as the base file name.

  # If the executable already doesn't exist yet or is older than this module,
  # (re)create it.
  $itm = Get-Item -LiteralPath $exePath -ErrorAction Ignore
  $mustCreate = -not $itm -or $itm.LastWriteTime -lt (Get-Item -LiteralPath $PSCommandPath).LastWriteTime

  if ($mustCreate) {
    Write-Verbose "Creating helper binary: $exePath"
    if ($itm) { Remove-Item -ErrorAction Stop -Force -LiteralPath $exePath }
    # Define a script block that creates the binary via Add-Type -OutputType ConsoleApplication
    # from inline C# code.
    # IMPORTANT: Since in PS Core the script block must be passed to the WinPS CLI (see below),
    #            it *must not contain references to the caller's variables*, except via *parameters*.
    $sb = { 
      param([string] $exePath)

      Add-Type -ErrorAction Stop -OutputType ConsoleApplication -OutputAssembly $exePath -TypeDefinition @'
using System;
using System.Text.RegularExpressions;

static class ConsoleApp {
  static int Main(string[] args) {

    bool raw = "1" == Environment.GetEnvironmentVariable("_dbea_raw", EnvironmentVariableTarget.Process);

    if (! raw) 
    {
      Console.WriteLine("{0} argument(s) received (enclosed in <...> for delineation):\n", args.Length);
    }

    for (int i = 0; i < args.Length; ++i) {
      if (raw)
      {
        Console.WriteLine(args[i]);
      }
      else
      {
        Console.WriteLine("  <{0}>", args[i]);
      }
    }

    if (! raw)
    {
      // Get the full command line and strip the executable (which is either
      //  - when invoked by PowerShell: the full, double-quoted path.
      //  - when invoked via a batch file: the path is not necessarily quoted.
      string cmdLine = Environment.CommandLine;
      cmdLine = cmdLine.Substring(Regex.Match(cmdLine, "\".+?\"|[^\\s]+").Value.Length).TrimStart();
  
      Console.WriteLine("\nCommand line (helper executable omitted):\n\n  {0}\n", cmdLine);
    }

    return 0;
  }
}
'@
    }
    if ($IsCoreCLR) {
      # !! As of PowerShell Core 7.1.0-preview.5, -OutputType ConsoleApplication produces
      # !! broken executables in PowerShel *Core* - see https://github.com/PowerShell/PowerShell/issues/13344
      # !! The workaround is to delegate to Windows PowerShell.
      iee powershell.exe -noprofile -c $sb -args $exePath
    }
    else {
      # Windows PowerShell: execute the script block directly.
      & $sb $exePath
    }
  
  } 

  $exePath # Return the executable's path.

}
