" Only do this when not done yet
if exists("g:did_phpgetset_ftplugin")
  finish
endif
let g:did_phpgetset_ftplugin = 1

" Make sure we are in vim mode
let s:save_cpo = &cpo
set cpo&vim

" TEMPLATE SECTION:
" The templates can use the following placeholders which will be replaced
" with appropriate values when the template is invoked:
"
"   %varname%       The name of the property
"   %funcname%      The method name ("getXzy" or "setXzy")
"
" The templates consist of a getter and setter template.
"
" Getter Templates
if exists("g:phpgetset_getterTemplate")
  let s:phpgetset_getterTemplate = g:phpgetset_getterTemplate
else
  let s:phpgetset_getterTemplate =
    \ "\n".
    \ "   /**\n".
    \ "    * @return mixed %varname%\n".
    \ "    */\n".
    \ "   public function %funcname%()\n".
    \ "   {\n".
    \ "       return $this->%varname%;\n".
    \ "   }"
endif


" Setter Templates
if exists("g:phpgetset_setterTemplate")
  let s:phpgetset_setterTemplate = g:phpgetset_setterTemplate
else
  let s:phpgetset_setterTemplate = "".
    \ "\n".
    \ "   /**\n".
    \ "    * @param mixed $%varname%\n".
    \ "    *\n".
    \ "    * @return self\n".
    \ "    */\n".
    \ "   public function %funcname%($%varname%)\n".
    \ "   {\n".
    \ "       $this->%varname% = $%varname%;\n\n".
    \ "       return $this;\n".
    \ "   }".
    \ "\n"
endif


" Position where methods are inserted.  The possible values are:
"   0 - end of class
"   1 = above block / line
"   2 = below block / line
if exists("g:phpgetset_insertPosition")
  let s:phpgetset_insertPosition = g:phpgetset_insertPosition
else
  let s:phpgetset_insertPosition = 0
endif

" Script local variables that are used like globals.
"
" If set to 1, the user has requested that getters be inserted
let s:getter    = 0

" If set to 1, the user has requested that setters be inserted
let s:setter    = 0

" The current indentation level of the property (i.e. used for the methods)
let s:indent    = ''

" The name of the property
let s:varname   = ''

" The function name of the property (capitalized varname)
let s:funcname  = ''

" The first line of the block selected
let s:firstline = 0

" The last line of the block selected
let s:lastline  = 0

" Regular expressions used to match property statements
let s:phpname = '[a-zA-Z_$][a-zA-Z0-9_$]*'
let s:brackets = '\(\s*\(\[\s*\]\)\)\='
let s:variable = '\(\s*\)\(\(var\s\+\)*\)\$\(' . s:phpname . '\)\s*\(;\|=[^;]\+;\)'

if !exists("*s:StripTrailingWhitespace")
    function s:StripTrailingWhitespace()
        " Preparation: save last search, and cursor position.
        let _s=@/
        let l = line(".")
        let c = col(".")
        " do the business:
        %s/\s\+$//e
        " clean up: restore previous search history, and cursor position
        let @/=_s
        call cursor(l, c)
    endfunction
endif

" The main entry point. This function saves the current position of the
" cursor without the use of a mark (see note below)  Then the selected
" region is processed for properties.
"
" FIXME: I wanted to avoid clobbering any marks in use by the user, so I
" manually try to save the current position and restore it.  The only drag
" is that the position isn't restored correctly if the user opts to insert
" the methods ABOVE the current position.  Using a mark would solve this
" problem as they are automatically adjusted.  Perhaps I just haven't
" found it yet, but I wish that VIM would let a scripter save a mark and
" then restore it later.  Why?  In this case, I'd be able to use a mark
" safely without clobbering any user marks already set.  First, I'd save
" the contents of the mark, then set the mark, do my stuff, jump back to
" the mark, and finally restore the mark to what the user may have had
" previously set.  Seems weird to me that you can't save/restore marks.
"
if !exists("*s:InsertGetterSetter")
  function s:InsertGetterSetter(flag) range
    let restorepos = line(".") . "normal!" . virtcol(".") . "|"
    let s:firstline = a:firstline
    let s:lastline = a:lastline

    if s:DetermineAction(a:flag)
      call s:ProcessRegion(s:GetRangeAsString(a:firstline, a:lastline))
    endif

    execute restorepos

    " Not sure why I need this but if I don't have it, the drawing on the
    " screen is messed up from my insert.  Perhaps I'm doing something
    " wrong, but it seems to me that I probably shouldn't be calling
    " redraw.
    redraw!

    call s:StripTrailingWhitespace()
  endfunction
endif

" Set the appropriate script variables (s:getter and s:setter) to
" appropriate values based on the flag that was selected.  The current
" valid values for flag are: 'g' for getter, 's' for setter, 'b' for both
" getter/setter, and 'a' for ask/prompt user.
if !exists("*s:DetermineAction")
  function s:DetermineAction(flag)

    if a:flag == 'g'
      let s:getter = 1
      let s:setter = 0

    elseif a:flag == 's'
      let s:getter = 0
      let s:setter = 1

    elseif a:flag == 'b'
      let s:getter = 1
      let s:setter = 1

    else
      return 0
    endif

    return 1
  endfunction
endif

" Gets a range specified by a first and last line and returns it as a
" single string that will eventually be parsed using regular expresssions.
" For example, if the following lines were selected:
"
"     // Age
"     var $age;
"
"     // Name
"     var $name;
"
" Then, the following string would be returned:
"
"     // Age    var $age;    // Name    var $name;
"
if !exists("*s:GetRangeAsString")
  function s:GetRangeAsString(first, last)
    let line = a:first
    let string = s:TrimRight(getline(line))

    while line < a:last
      let line = line + 1
      let string = string . s:TrimRight(getline(line))
    endwhile

    return string
  endfunction
endif

" Trim whitespace from right of string.
if !exists("*s:TrimRight")
  function s:TrimRight(text)
    return substitute(a:text, '\(\.\{-}\)\s*$', '\1', '')
  endfunction
endif

" Process the specified region indicated by the user.  The region is
" simply a concatenated string of the lines that were selected by the
" user.  This string is searched for properties (that match the s:variable
" regexp).  Each property is then processed.  For example, if the region
" was:
"
"     // Age    var $age;    // Name    var $name;
"
" Then, the following strings would be processed one at a time:
"
" var $age;
" var $name;
"
if !exists("*s:ProcessRegion")
  function s:ProcessRegion(region)
    let startPosition = match(a:region, s:variable, 0)
    let endPosition = matchend(a:region, s:variable, 0)

    while startPosition != -1
      let result = strpart(a:region, startPosition, endPosition - startPosition)

      "call s:DebugParsing(result)
      call s:ProcessVariable(result)

      let startPosition = match(a:region, s:variable, endPosition)
      let endPosition = matchend(a:region, s:variable, endPosition)
    endwhile

  endfunction
endif

" Process a single property.  The first thing this function does is
" break apart the property into the following components: indentation, name
" In addition, the following other components are then derived
" from the previous: funcname. For example, if the specified variable was:
"
" var $name;
"
" Then the following would be set for the global variables:
"
" indent    = '    '
" varname   = 'name'
" funcname  = 'Name'
"
if !exists("*s:ProcessVariable")
  function s:ProcessVariable(variable)
    let s:indent    = substitute(a:variable, s:variable, '\1', '')
    let s:varname   = substitute(a:variable, s:variable, '\4', '')
    let s:funcname  = toupper(s:varname[0]) . strpart(s:varname, 1)

    " If any getter or setter already exists, then just return as there
    " is nothing to be done.  The assumption is that the user already
    " made his choice.
    if s:AlreadyExists()
      return
    endif

    if s:getter
      call s:InsertGetter()
    endif

    if s:setter
      call s:InsertSetter()
    endif

  endfunction
endif

" Checks to see if any getter/setter exists.
if !exists("*s:AlreadyExists")
  function s:AlreadyExists()
    return search('\(get\|set\)' . s:funcname . '\_s*([^)]*)\_s*{', 'w')
  endfunction
endif

" Inserts a getter by selecting the appropriate template to use and then
" populating the template parameters with actual values.
if !exists("*s:InsertGetter")
  function s:InsertGetter()

    let method = s:phpgetset_getterTemplate


    let method = substitute(method, '%varname%', s:varname, 'g')
    let method = substitute(method, '%funcname%', 'get' . s:funcname, 'g')

    call s:InsertMethodBody(method)

  endfunction
endif

" Inserts a setter by selecting the appropriate template to use and then
" populating the template parameters with actual values.
if !exists("*s:InsertSetter")
  function s:InsertSetter()

    let method = s:phpgetset_setterTemplate

    let method = substitute(method, '%varname%', s:varname, 'g')
    let method = substitute(method, '%funcname%', 'set' . s:funcname, 'g')

    call s:InsertMethodBody(method)

  endfunction
endif

" Inserts a body of text using the indentation level.  The passed string
" may have embedded newlines so we need to search for each "line" and then
" call append separately.  I couldn't figure out how to get a string with
" newlines to be added in one single call to append (it kept inserting the
" newlines as ^@ characters which is not what I wanted).
if !exists("*s:InsertMethodBody")
  function s:InsertMethodBody(text)
    call s:MoveToInsertPosition()

    let pos = line('.')
    let string = a:text

    while 1
      let len = stridx(string, "\n")

      if len == -1
        call append(pos, s:indent . string)
        break
      endif

      call append(pos, s:indent . strpart(string, 0, len))

      let pos = pos + 1
      let string = strpart(string, len + 1)

    endwhile
  endfunction
endif

" Move the cursor to the insertion point.  This insertion point can be
" defined by the user by setting the g:phpgetset_insertPosition variable.
if !exists("*s:MoveToInsertPosition")
  function s:MoveToInsertPosition()

    " 1 indicates above the current block / line
    if s:phpgetset_insertPosition == 1
      execute "normal! " . (s:firstline - 1) . "G0"

    " 2 indicates below the current block / line
    elseif s:phpgetset_insertPosition == 2
      execute "normal! " . s:lastline . "G0"

    " 0 indicates end of class (and is default)
    else
      execute "normal! ?{\<CR>w99[{%k" | nohls

    endif

  endfunction
endif

if !exists(":InsertGetterOnly")
  command -range
    \ InsertGetterOnly
    \ :<line1>,<line2>call s:InsertGetterSetter('g')
endif
if !exists(":InsertSetterOnly")
  command -range
    \ InsertSetterOnly
    \ :<line1>,<line2>call s:InsertGetterSetter('s')
endif
if !exists(":InsertGetterSetter")
  command -range
    \ InsertGetterSetter
    \ :<line1>,<line2>call s:InsertGetterSetter('b')
endif


map <Leader>ig :InsertGetter<CR>
map <Leader>is :InsertSetter<CR>
map <Leader>ib :InsertGetterSetter<CR>
