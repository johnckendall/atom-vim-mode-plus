# Refactoring status: 20%
module.exports =
class ModeManager
  mode: null

  constructor: (@vimState) ->
    {@editor, @editorElement} = @vimState

  isNormalMode: ->
    @mode is 'normal'

  isInsertMode: ->
    @mode is 'insert'

  isOperatorPendingMode: ->
    @mode is 'operator-pending'

  isVisualMode: ->
    @mode is 'visual'

  setMode: (@mode, @submode=null) ->
    for mode in ['normal', 'insert', 'visual', 'operator-pending']
      @editorElement.classList.remove "#{mode}-mode"
    @editorElement.classList.add "#{@mode}-mode"

  activateNormalMode: (options={}) ->
    @deactivateInsertMode()
    @deactivateVisualMode(options.restoreColumn)
    @setMode('normal')

    @vimState.operationStack.clear()
    for selection in @editor.getSelections()
      selection.clear(autoscroll: false)
    for cursor in @editor.getCursors()
      if cursor.isAtEndOfLine() and not cursor.isAtBeginningOfLine()
        cursor.moveLeft()
    @updateStatusBar()

  activateInsertMode: (submode=null) ->
    @setMode('insert', submode)
    @updateStatusBar()
    @editorElement.component.setInputEnabled(true)
    @setInsertionCheckpoint()

  activateReplaceMode: ->
    @activateInsertMode('replace')
    @editorElement.classList.add('replace-mode')

    @replaceModeCounter = 0
    @vimState.subscriptions.add @replaceModeListener = @editor.onWillInsertText @replaceModeInsertHandler
    @vimState.subscriptions.add @replaceModeUndoListener = @editor.onDidInsertText @replaceModeUndoHandler

  replaceModeInsertHandler: (event) =>
    chars = event.text?.split('') or []
    selections = @editor.getSelections()
    for char in chars
      continue if char is '\n'
      for selection in selections
        selection.delete() unless selection.cursor.isAtEndOfLine()
    return

  replaceModeUndoHandler: (event) =>
    @replaceModeCounter++

  replaceModeUndo: ->
    if @replaceModeCounter > 0
      @editor.undo()
      @editor.undo()
      @editor.moveLeft()
      @replaceModeCounter--

  setInsertionCheckpoint: ->
    @insertionCheckpoint ?= @editor.createCheckpoint()

  deactivateInsertMode: ->
    return unless @mode in [null, 'insert']
    @editorElement.component.setInputEnabled(false)
    @editorElement.classList.remove('replace-mode')
    @editor.groupChangesSinceCheckpoint(@insertionCheckpoint)
    changes = getChangesSinceCheckpoint(@editor.buffer, @insertionCheckpoint)
    @insertionCheckpoint = null
    if (item = @vimState.history[0]) and item.isInsert()
      item.confirmChanges(changes)
    for cursor in @editor.getCursors() when not cursor.isAtBeginningOfLine()
      cursor.moveLeft()
    if @replaceModeListener?
      @replaceModeListener.dispose()
      @vimState.subscriptions.remove @replaceModeListener
      @replaceModeListener = null
      @replaceModeUndoListener.dispose()
      @vimState.subscriptions.remove @replaceModeUndoListener
      @replaceModeUndoListener = null

  deactivateVisualMode: (restoreColumn=true) ->
    return unless @isVisualMode()
    if restoreColumn and @submode is 'linewise'
      @selectCharacterwise()
    for s in @editor.getSelections() when not (s.isEmpty() or s.isReversed())
      s.cursor.moveLeft()

  # Private: Used to enable visual mode.
  #
  # submode - One of 'characterwise', 'linewise' or 'blockwise'
  #
  # Returns nothing.
  activateVisualMode: (submode) ->
    # Already in 'visual', this means one of following command is
    # executed within `vim-mode.visual-mode`
    #  * activate-blockwise-visual-mode
    #  * activate-characterwise-visual-mode
    #  * activate-linewise-visual-mode
    if @isVisualMode()
      if @submode is submode
        @activateNormalMode()
        return

      @submode = submode
      if @submode is 'linewise'
        @selectLinewise()

      else if @submode in ['characterwise', 'blockwise']
        # Currently, 'blockwise' is not yet implemented.
        @selectCharacterwise()
    else
      @deactivateInsertMode()
      @setMode('visual', submode)

      if @submode is 'linewise'
        @selectLinewise()
      else if @editor.getSelectedText() is ''
        @editor.selectRight()
    @updateStatusBar()

  # Private: Select lines containing cursor with saving original column.
  selectLinewise: ->
    for selection in @editor.getSelections()
      # Keep original range as marker's property to restore column.
      originalRange = selection.getBufferRange()
      selection.marker.setProperties({originalRange})
      [start, end] = selection.getBufferRowRange()
      for row in [start..end]
        selection.selectLine(row)

  # Private: Set column of each selection to saved column.
  selectCharacterwise: ->
    for selection in @editor.getSelections()
      {originalRange} = selection.marker.getProperties()
      if originalRange
        [startRow, endRow] = selection.getBufferRowRange()
        originalRange.start.row = startRow
        originalRange.end.row   = endRow
        selection.setBufferRange(originalRange)

  # Private: Used to re-enable visual mode
  resetVisualMode: ->
    @activateVisualMode(@submode)

  # Private: Used to enable operator-pending mode.
  activateOperatorPendingMode: ->
    @deactivateInsertMode()
    @setMode('operator-pending')
    @updateStatusBar()

  # Private: Resets the normal mode back to it's initial state.
  #
  # Returns nothing.
  resetNormalMode: ->
    @vimState.operationStack.clear()
    @editor.clearSelections()
    @activateNormalMode()

  updateStatusBar: ->
    @vimState.statusBarManager.update(@mode, @submode)

# This uses private APIs and may break if TextBuffer is refactored.
# Package authors - copy and paste this code at your own risk.
getChangesSinceCheckpoint = (buffer, checkpoint) ->
  {history} = buffer

  if (index = history.getCheckpointIndex(checkpoint))?
    history.undoStack.slice(index)
  else
    []
