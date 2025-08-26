/*************************************************************************
  Grep        Search disk files for a specified string

  Author:     SemWare

  Date:       Summer, 1997 - Initial version

              Dec 2000 - KSW/SEM Fix problems that occur when grep fails
                    (e.g., *.foobar, no matching files)

              Jan 11, 2001 - Didn't handle temporary paths with spaces
                in the name.  Thanks to Bruce Riggins for reporting this.

              28 Feb 2009 SEM - Fix problem of not finding tee32.exe and
                grep.exe in certain cases where TSELOADDIR was used. Reported
                (along with a suggested fix) by Ross Barnes.
              15 Dec 2010 SEM - Fix problem in making the filename ViewFinds
                compatible.
              03 Nov 2023 SEM - Need to add a trailing null to the filename entries
                to be compatible with ViewFinds
              30 Nov 2023 SEM - rollback the 03 Nov 2023 change.
              19 Oct 2024 SEM - on dialog title, show abbreviated directory.

  Overview:

  This macro allows one to search a list of files for a specified
  string. Regular expressions are supported, as is searching in nested
  subdirectories.

  Usage notes:

  Upon running this macro, the user is given a menu from which to
  select the supported actions.

  Copyright 1992-1999 SemWare Corporation.  All Rights Reserved Worldwide.

  Use, modification, and distribution of this SAL macro is encouraged by
  SemWare provided that this statement, including the above copyright notice,
  is not removed; and provided that no fee or other remuneration is received
  for distribution.  You may add your own copyright notice to cover new matter
  you add to the macro, but SemWare Corporation will neither support nor
  assume legal responsibility for any material added or any changes made to
  the macro.

*************************************************************************/

string grep[_MAX_PATH_]
string tee32[_MAX_PATH_]

helpdef FileHelp
"                                         "
""
"  Enter a list of files to be searched."
"  The filenames can contain wild-cards."
""
"  Examples:"
""
"  *.c *.h *.s"
""
"  foo.bar test.it"
""
"  c:\win98\*.dll"
""
"  abc.abc c:\*.* d:\here\*.c"
""
""
""
""
""
""
""
""
""
""
""
""
""
""
""
""
""
end

helpdef OptionsHelp
""
""
"-0  display file names only"
"-1  display first matching line only"
"-b  blank before fn line"
"-c  show count of matching lines"
"-c- do not display copyright message"
"-f  display filename on each line"
"-f- do not display any filenames"
"-i  ignore case"
"-m  display only non-matching lines"
"-n  display line numbers"
"-s  search subdirectories (-d accepted too)"
"-v  verbose"
"-w  words only"
"-x  use regular expressions (same syntax as TSE Pro)"
"-_  remove '_' from the wordset - effects -w"
"-@ fn (must be last arg) adds files in 'fn' to list of files to search"
""
"\h - shortcut for: [0-9A-Fa-f]      a hexadecimal number"
"\H - shortcut for: [~0-9A-Fa-f]     anything except a hexadecimal number"
"\p - shortcut for: [\x20-\x7E]      a printable character"
"\P - shortcut for: [~\x20-\x7E]     anything except a printable character"
"\d - shortcut for: [0-9]            a digit"
"\D - shortcut for: [^0-9]           anything except a digit"
"\s - shortcut for: [ \f\r\n\t]      whitespace"
"\S - shortcut for: [^ \f\r\n\t]     anything except whitespace"
"\w - shortcut for: [a-zA-z0-9_]     an identifier"
"\W - shortcut for: [^a-zA-z0-9_]    anything except an identifier"
""
""
end

helpdef UnknownHelp
end

constant MAXPATH = 255

constant FN_POS = 7, OCCUR_LEN = 19
#define  VIEW_FINDS_CHAR    0x46        // 'F' in German version

//EditPopWin(title, x1, y1, width, height, boxtype box)
integer proc PopWin(string title, integer width, integer height)
    integer x
    integer y = WhereY()

    x = max((Query(ScreenCols) - width) / 2, 1)

    // try to put on line above
    if y > height + 1
        y = y - height - 1
    else
        y = y + 1
    endif
    if y + height > Query(ScreenRows)
        y = Query(WindowRows) - height
    endif
    if EditPopWin(title, x, y, width, height, 1)
        return (TRUE)
    endif
    return (FALSE)
end PopWin

#define pSET_STATE      -3
#define pPREV_FIELD     -2
#define pNEXT_FIELD     -1
#define pABORT           0
#define pACCEPT          1

#define sSEARCH         0
#define sFILES          1
#define sOPTIONS        2
#define nSTATES         3

integer next_state, state

proc GetHelp()
    //Set(X1, wherex())
    //Set(Y1, wherey())
    case state
        when sSEARCH  Help("Regular Expression Operators")
        when sFILES   QuickHelp(FileHelp)
        when sOPTIONS QuickHelp(OptionsHelp)
        otherwise     QuickHelp(UnknownHelp)
    endcase
end

KeyDef GrepKeys
    <Shift Tab> EndProcess(pPREV_FIELD)
    <Tab>       EndProcess(pNEXT_FIELD)
    <Enter>     EndProcess(pACCEPT)
    <Escape>    EndProcess(pABORT)
    <Alt S>     next_state = sSEARCH     EndProcess(pSET_STATE)
    <Alt F>     next_state = sFILES      EndProcess(pSET_STATE)
    <Alt O>     next_state = sOPTIONS    EndProcess(pSET_STATE)
    <F1>        GetHelp()
end

proc EnableTheseKeys()
    if not Enable(GrepKeys)
        EndProcess(pABORT)
    endif
    BreakHookChain()
end

proc DisplayPromptInfo(integer x, integer y, string prompt, string s)
    VGotoXY(x,y)
    PutHelpLine(prompt)
    PutStrXY(x + 9,y,s,Query(MenuTextAttr))
end

string search [128] = ""
string files  [255] = "*.c *.h *.cpp *.hpp *.s"
string options[128] = "-i -x -s"

integer grep_id
forward proc ViewGrepResults(integer here_before)

string proc TempPath()
    string dir[MAXPATH]

    dir = GetEnvStr("TEMP")
    if dir == ""
        dir = GetEnvStr("TMP")
        if dir == ""
            dir = CurrDir()
        endif
    endif
    return (QuotePath(MakeTempName(dir)))
end

proc Main()
    integer n, exec, id, ok
    string grep_fn[MAXPATH], s_fn[MAXPATH]
    integer search_hist  = GetFreeHistory("grep:search")
    integer files_hist   = GetFreeHistory("grep:files")
    integer options_hist = GetFreeHistory("grep:options")

    search  = GetHistoryStr(search_hist, 1)
    files   = GetHistoryStr(files_hist, 1)
    options = GetHistoryStr(options_hist, 1)

    grep_fn = TempPath()
    exec = FALSE
    Set(Attr, Query(MenuTextAttr))

    if PopWin("Grep ["+SqueezePath(CurrDir(), _USE_HOME_PATH_)+"]", iif(Query(ScreenCols) > 68, 68, Query(ScreenCols)), 5)
        ClrScr()
        WindowFooter("{Enter}-Execute  {Escape}-Abort  {Tab}-Next field")
        DisplayPromptInfo(1,1,"{S}earch:" ,search)
        DisplayPromptInfo(1,2,"{F}iles:"  ,files)
        DisplayPromptInfo(1,3,"{O}ptions:",options)
        state = sSEARCH

        if Hook(_PROMPT_STARTUP_, EnableTheseKeys)
            loop
                VGotoXY(10,1 + state)
                case state
                    when sSEARCH
                        n = Read(search, search_hist)
                    when sFILES
                        n = Read(files, files_hist)
                    when sOPTIONS
                        n = Read(options, options_hist)
                endcase
                VGotoXY(8,1 + state)
                PutAttr(Query(MenuTextAttr),Query(PopWinCols) - 7)
                case n
                    when pPREV_FIELD
                        state = ((state - 1) + nSTATES) mod nSTATES
                    when pNEXT_FIELD
                        state = (state + 1) mod nSTATES
                    when pABORT
                        break
                    when pACCEPT
                        Exec = TRUE
                        break
                    when pSET_STATE
                        state = next_state
                endcase
            endloop
            UnHook(EnableTheseKeys)
        endif

        PopWinClose()
        if exec
//            rows = Query(ScreenRows)
//            cols = Query(ScreenCols)
//            if cols <> 80 and not (rows in 25,43,50)
//                SetVideoRowsCols(25, 80)
//            endif
            ok = lDOS(tee32, format(grep;options;"-n";QuotePath(search);files;">";grep_fn),_DONT_PROMPT_|_TEE_OUTPUT_)
//            SetVideoRowsCols(rows, cols)
            if ok
                PushPosition()
                id = EditFile(grep_fn, _DONT_LOAD_)
                if id and GotoBufferId(id)
                    grep_id = GetBufferId()
                    BufferType(_SYSTEM_)
                    ReplaceFile(grep_fn,_OVERWRITE_)
                    if lFind("File: ","^g")
                        repeat
                            GotoPos(FN_POS)
                            s_fn = GetText(FN_POS, MAXPATH)
                            s_fn = SqueezePath(s_fn, _USE_HOME_PATH_)
                            KillToEOL()
                            InsertText(QuotePath(s_fn), _OVERWRITE_)
                        until not lRepeatFind()
                    endif
                    EndFile()
                    while PosFirstNonWhite() == 0 and KillLine()
                    endwhile
                    BegFile()
                endif
                PopPosition()
                EraseDiskFile(grep_fn)
                ViewGrepResults(FALSE)
            endif
        endif
    endif
end

//proc ViewFindsStartup()
//    BufferType(_NORMAL_)
//end

//proc ViewFindsCleanup()
//    BufferType(_SYSTEM_)
//end

proc ViewGrepResults(integer here_before)
    integer save_id, errors, buffer_type

    errors = TRUE
    PushPosition()
    if GotoBufferId(grep_id)
        if NumLines() == 0
            AddLine("No matches found")
        elseif here_before or lFind("File: ","g")
            errors = FALSE
        endif
    endif
    PopPosition()

    if errors
        Alarm()
        PushPosition()
        if GotoBufferId(grep_id)
            buffer_type = BufferType(_NORMAL_)
            // width hack: width of footer, less 6 braces
            List("Grep Results", max(LongestLineInBuffer(), 49 - 6))
            BufferType(buffer_type)
        else
            Warn("View buffer does not exist")
        endif
        PopPosition()
    else
        save_id = Set(ViewFindsId, grep_id)
//        Hook(_LIST_STARTUP_, ViewFindsStartup)
//        Hook(_LIST_CLEANUP_, ViewFindsCleanup)
        ViewFinds()
//        UnHook(ViewFindsStartup)
//        UnHook(ViewFindsCleanup)
        Set(ViewFindsId, save_id)
    endif
end

/**************************************************************************
  See if the specified pgm exists in the actual (LoadDir(1)) or the
  (possibly redirected) LoadDir().
 **************************************************************************/
proc find_editor_program(string fn, var string path)
    path = SplitPath(LoadDir(1), _DRIVE_|_PATH_) + fn
    if not FileExists(path)
        path = LoadDir() + fn
        if not FileExists(path)
            path = ""
        endif
    endif
    path = QuotePath(path)
end

proc WhenLoaded()
    find_editor_program("grep.exe", grep)
    find_editor_program("tee32.exe", tee32)
end

//<Alt G>     Main()
<CtrlAlt G> ViewGrepResults(TRUE)
