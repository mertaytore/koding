# this file was once nice and tidy (see https://github.com/koding/koding/blob/dd4e70d88795fe6d0ea0bfbb2ef0e4a573c08999/client/Social/Activity/sidebar/activitysidebar.coffee)
# once we merged two sidebars into one
# activity sidebar became the mainsidebar
# and unfortunately we have too mcuh goin on here right now.
# vm menu and activity menu should be separated,
# needs a little refactor. - SY

class ActivitySidebar extends KDCustomHTMLView

  typeMap =
    privatemessage : 'Message'
    topic          : 'Topic'
    post           : 'Post'
    chat           : 'Chat'

  slugProps =
    SocialMessage : 'slug'
    SocialChannel : 'name'

  revive = (data) ->

    return switch data.typeConstant
      when 'post'  then KD.singletons.socialapi.message.revive message: data  #mapActivity
      when 'topic' then KD.singletons.socialapi.channel.revive data
      else data


  constructor: (options = {}) ->

    options.cssClass     = 'activity-sidebar'
    options.maxListeners = 20

    super options

    {
      notificationController
      computeController
      socialapi
      router
    } = KD.singletons

    @sections     = {}
    @itemsById    = {}
    @itemsBySlug  = {}
    @itemsByName  = {}
    @selectedItem = null

    @workspaceItemChannelMap = {}

    # @appsList = new DockController

    # router
    #   .on "RouteInfoHandled",          @bound 'deselectAllItems'

    notificationController
      .on 'AddedToChannel',            @bound 'accountAddedToChannel'
      .on 'RemovedFromChannel',        @bound 'accountRemovedFromChannel'
      .on 'MessageAddedToChannel',     @bound 'messageAddedToChannel'
      .on 'MessageRemovedFromChannel', @bound 'messageRemovedFromChannel'
      .on 'ReplyAdded',                @bound 'replyAdded'

      .on 'MessageListUpdated',        @bound 'setPostUnreadCount'
      .on 'ParticipantUpdated',        @bound 'handleGlanced'
      # .on 'ReplyRemoved',              (update) -> log update.event, update
      # .on 'ChannelUpdateHappened',     @bound 'channelUpdateHappened'

    computeController
      .on 'MachineDataModified',       @bound 'updateMachineTree'
      .on 'RenderMachines',            @bound 'renderMachines'
      .on 'MachineBeingDestroyed',     @bound 'invalidateWorkspaces'

    @on 'MoreWorkspaceModalRequested', @bound 'handleMoreWorkspacesClick'
    @on 'ReloadMessagesRequested',     @bound 'handleReloadMessages'

  # event handling

  messageAddedToChannel: (update) ->

    { channel, channelMessage, unreadCount } = update

    if KD.utils.isChannelCollaborative channel
      if channelMessage.payload['system-message'] in ['start', 'stop']
        @fetchMachines => @fetchWorkspaces =>
          @setWorkspaceUnreadCount channel, unreadCount

    switch update.channel.typeConstant
      when 'pinnedactivity' then @replyAdded update
      else  @handleFollowedFeedUpdate update


  messageRemovedFromChannel: (update) ->

    {id} = update.channelMessage

    @removeItem id


  handleGlanced: (update) -> @selectedItem?.setUnreadCount? update.unreadCount


  glanceChannelWorkspace: (channel) ->

    @setWorkspaceUnreadCount channel, 0


  setUnreadCount: (item, data, unreadCount) ->

    return  unless item

    {windowController, appManager} = KD.singletons

    app = appManager.getFrontApp()

    if app?.getOption('name') is 'Activity'
      pane    = app.getView().tabs.getActivePane()
      channel = pane.getData()

      return  unless channel

      inCurrentPane = channel.id is data.id

      if inCurrentPane and windowController.isFocused() and pane.isPageAtBottom()
        return pane.glance()
      else
        pane.putNewMessageIndicator()

    item.setUnreadCount? unreadCount


  setWorkspaceUnreadCount: (data, unreadCount) ->

    workspaceItem = @workspaceItemChannelMap[data._id]

    return  unless workspaceItem

    workspaceItem.child.setUnreadCount unreadCount

    return  unless unreadCount is 0

    { socialapi } = KD.singletons

    socialapi.channel.updateLastSeenTime channelId : data._id, noop


  handleFollowedFeedUpdate: (update) ->

    # WARNING: WRONG NAMING ON THE METHODS
    # these are the situations where we end up here
    #
    # when a REPLY is added to a PRIVATE MESSAGE
    # when a new PRIVATE MESSAGE is posted (because of above i think)
    # when an ACTIVITY is posted to a FOLLOWED TOPIC

    {socialapi}   = KD.singletons
    {unreadCount} = update
    {id}          = update.channel

    socialapi.cacheable 'channel', id, (err, data) =>

      return KD.showError err  if err

      index = switch data.typeConstant
        when 'topic'        then 2
        when 'group'        then 2
        when 'announcement' then 2
        else 0

      if KD.utils.isChannelCollaborative data
        @setWorkspaceUnreadCount data, unreadCount
      else
        item = @addItem data, index
        @setUnreadCount item, data, unreadCount


  # when a comment is added to a post
  replyAdded: (update) ->

    {socialapi}   = KD.singletons
    {unreadCount} = update
    {id}          = update.channelMessage
    type          = 'post'

    # so we fetch respectively
    socialapi.cacheable type, id, (err, data) =>

      return KD.showError err  if err

      # when someone replies to a user's post, we locally mark that post, and
      # any cached copies as "followed" by that user.
      socialapi.eachCached data.getId(), (it) -> it.isFollowed = yes
      # and add to the sidebar
      # (if the item is already on sidebar, it's handled on @addItem)
      item = @addItem data, 0
      @setUnreadCount item, data, unreadCount


  accountAddedToChannel: (update) ->

    # WARNING: WRONG NAMING ON THE METHODS
    # these are the situations where we end up here
    #
    # when a new PRIVATE MESSAGE is posted
    # when a TOPIC is followed

    {socialapi}                     = KD.singletons
    {unreadCount, participantCount} = update
    {id, typeConstant}              = update.channel

    socialapi.cacheable typeConstant, id, (err, channel) =>

      return warn err  if err

      channel.isParticipant    = yes
      channel.participantCount = participantCount
      channel.emit 'update'

      isPrivateMessage = typeConstant is 'privatemessage'

      index = 0  if isPrivateMessage

      if KD.utils.isChannelCollaborative channel
        @fetchMachines => @fetchWorkspaces =>
          @setWorkspaceUnreadCount channel, unreadCount
      else
        item = @addItem channel, index
        @setUnreadCount item, channel, unreadCount


  accountRemovedFromChannel: (update) ->

    {id} = update.channel

    return  if update.isParticipant

    @removeItem id

    if @workspaceItemChannelMap[id]
      @fetchMachines => @fetchWorkspaces()

    # TODO update participants in sidebar


  channelUpdateHappened: (update) -> warn 'dont use this, :::educational purposes only!:::', update


  setPostUnreadCount: (data) ->

    {unreadCount, channelMessage} = data
    return  unless channelMessage

    {typeConstant, id} = channelMessage

    listController = @getListController typeConstant
    item = listController.itemForId id

    # if we are getting updates about a message it means we are following it
    item.isFollowed = yes if item

    # if we are getting updates about a message that is not in the channel it
    # should be added into list
    @replyAdded data  unless item

    @setUnreadCount item, data, unreadCount


  getItems: ->

    items = []
    items = items.concat @sections.channels.listController.getListItems()
    items = items.concat @sections.conversations.listController.getListItems()
    items = items.concat @sections.messages.listController.getListItems()

    return items


  getListController: (type) ->

    section = switch type
      when 'topic'                  then @sections.channels
      when 'pinnedactivity', 'post' then @sections.conversations
      when 'privatemessage'         then @sections.messages
      else {}

    return section.listController


  getItemByData: (data) ->

    item = @itemsById[data.id] or
           @itemsBySlug[data.slug] or
           @itemsByName[data.name]

    return item or null


  # dom manipulation

  addItem: (data, index) ->

    listController = @getListController data.typeConstant
    item = @getItemByData data

    # add the new topic item in sidebar
    return listController.addItem data, index  unless item

    # since announcement is fixed in sidebar no need to add/move it
    return item  if data.typeConstant is 'announcement'

    # move the channel to the given index
    listController.moveItemToIndex item, index  if index?

    return item


  removeItem: (id) ->

    if item = @itemsById[id]

      data           = item.getData()
      listController = @getListController data.typeConstant

      item.bindTransitionEnd()
      item.once 'transitionend', -> listController.removeItem item
      item.setClass 'out'


  bindItemEvents: (listView) ->

    listView.on 'ItemWasAdded',   @bound 'registerItem'
    listView.on 'ItemWasRemoved', @bound 'unregisterItem'


  registerItem: (item) ->

    data = item.getData()

    @itemsById[data.id]     = item  if data.id
    @itemsBySlug[data.slug] = item  if data.slug
    @itemsByName[data.name] = item  if data.name


  unregisterItem: (item) ->

    data = item.getData()

    if data.id
      @itemsById[data.id] = null
      delete @itemsById[data.id]

    if data.slug
      @itemsBySlug[data.slug] = null
      delete @itemsBySlug[data.id]

    if data.name
      @itemsByName[data.name] = null
      delete @itemsByName[data.name]


  updateTopicFollowButtons: (id, state) ->

    return # until we have either fav or hot lists back - SY

    item  = @sections.hot.listController.itemForId id
    state = if state then 'Unfollow' else 'Follow'
    item?.followButton.setState state


  # fixme:
  # this item selection is a bit tricky
  # depends on multiple parts:
  # - sidebaritem's lastTimestamp
  # - the item which is being clicked
  # - and what the route suggests
  # needs to be simplified
  selectItemByRouteOptions: (type, slug_) ->

    @deselectAllItems()

    type       = 'privatemessage'  if type is 'message'
    type       = 'group'           if slug_ is 'public'
    candidates = []

    for own name_, {listController} of @sections

      for item in listController.getListItems()

        data = item.getData()
        {typeConstant, id, name , slug} = data

        if typeConstant is type and slug_ in [id, name, slug]
          candidates.push item

    candidates.sort (a, b) -> a.lastClickedTimestamp < b.lastClickedTimestamp

    if candidates.first
      listController.selectSingleItem candidates.first
      @selectedItem = candidates.first


  deselectAllItems: ->

    # @selectedItem = null

    # @machineTree.deselectAllNodes()

    # for own name, {listController} of @sections
    #   listController.deselectAllItems()


  viewAppended: ->

    super

    @addMachineList()
    @addFollowedTopics()
    @addConversations()

    KD.getSingleton 'computeController'
      .ready @lazyBound 'fetchWorkspaces', @lazyBound 'addMessages'


  initiateFakeCounter: ->

    KD.utils.wait 5000, =>
      publicLink = @sections.channels.listController.getListItems().first
      publicLink.setClass 'unread'
      publicLink.unreadCount.updatePartial 1
      publicLink.unreadCount.show()

      publicLink.on 'click', ->
        KD.utils.wait 177, ->
          publicLink.unsetClass 'unread'
          publicLink.unreadCount.hide()


  # workspacesFetched  = no
  fetchingWorkspaces = no

  fetchWorkspaces: do (callbackQueue = []) -> (callback = noop) ->

    activitySidebar = this

    # return callback null, KD.userWorkspaces  if workspacesFetched
    return callbackQueue.push callback       if fetchingWorkspaces

    fetchingWorkspaces = yes

    # put first callback to queue as well.
    callbackQueue.push callback

    KD.remote.api.JWorkspace.fetchByMachines()

      .then (workspaces) =>
        fetchingWorkspaces = no

        {socialapi} = KD.singletons

        otherMachineUIds = []
        myMachineUIds    = []

        KD.userMachines.forEach (m) ->
          if m.isMine() or m.isPermanent()
          then myMachineUIds.push m.uid
          else otherMachineUIds.push m.uid

        otherWorkspaces  = workspaces.filter (ws) -> return ws.channelId and ws.machineUId in otherMachineUIds
        myWorkspaces     = workspaces.filter (ws) -> return ws.machineUId in myMachineUIds

        myChannels = []
        queue      = []
        otherWorkspaces.forEach (ws) ->
          queue.push ->
            socialapi.channel.byId id : ws.channelId, (err, channel) ->
              myChannels.push channel.id  if channel
              queue.fin()

        Bongo.dash queue, =>
          workspacesIHaveAccess = otherWorkspaces.filter (ws) -> ws.channelId in myChannels
          userWorkspaces        = myWorkspaces.concat workspacesIHaveAccess

          KD.userMachines.forEach (machine) =>
            return  unless machine.isMine()

            for workspace in userWorkspaces \
              when workspace.slug is 'my-workspace' \
              and workspace.machineUId is machine.uid
                return

            userWorkspaces.push @getDummyWorkspace machine

          KD.userWorkspaces     = userWorkspaces
          # workspacesFetched     = yes
          activitySidebar.updateMachineTree()

          callbackQueue.forEach (fn) -> fn null, userWorkspaces
          callbackQueue = []

      .error (rest...) ->
        fetchingWorkspaces = no
        callbackQueue.forEach (fn) -> fn rest...
        callbackQueue = []



  listMachines: (machines) ->

    treeData = []
    nickname = KD.nick()

    for machine in machines

      treeData.push machine

      unless machine.isPermanent()
        treeData.push
          title        : 'Workspaces'
          type         : 'title'
          parentId     : machine.getId()
          id           : machine.getData().getId()
          machineUId   : machine.uid
          machineLabel : machine.slug or machine.label

      ideRoute     = "/IDE/#{machine.slug or machine.label}/my-workspace"
      machineOwner = machine.getOwner()
      isMyMachine  = machine.isMine()
      ideRoute     = "#{ideRoute}/#{machineOwner}"  unless isMyMachine
      hasWorkspace = (KD.userWorkspaces.filter ({name, machineUId}) -> return name is 'My Workspace' and machineUId is machine.uid).length > 0

      if machine.isMine() and not hasWorkspace
        KD.userWorkspaces.push @getDummyWorkspace machine

      @sortWorkspaces KD.userWorkspaces

      KD.userWorkspaces.forEach (workspace) ->

        unless workspace instanceof KD.remote.api.JWorkspace
          workspace = KD.remote.revive workspace

        if workspace.machineUId is machine.uid
          ideRoute = "/IDE/#{machine.slug or machine.label}/#{workspace.slug}"
          title    = "#{workspace.name}"

          unless isMyMachine
            if channelId = workspace.channelId
            then ideRoute = "/IDE/#{channelId}"
            else
              return

          if not workspace.isDefault or workspace.slug isnt 'my-workspace'
            title += "<span class='ws-settings-icon'></span>"

          treeData.push
            title        : title
            type         : 'workspace'
            href         : ideRoute
            machineLabel : machine.slug or machine.label
            data         : workspace
            id           : workspace._id
            parentId     : machine.getId()

    # for data in treeData

    #   node = @machineTree.addNode data

    #   @mapWorkspaceWithChannel data, node  if data.type is 'workspace'

    @emit 'MachinesListed'


  getDummyWorkspace: (machine) ->

    new KD.remote.api.JWorkspace
      _id          : "#{machine.getId()}-my-workspace"
      isDummy      : yes
      isDefault    : yes
      originId     : KD.whoami()._id # In case JAccount is not revived yet
      slug         : 'my-workspace'
      machineUId   : machine.uid
      machineLabel : machine.label
      name         : 'My Workspace'


  sortWorkspaces: (workspaces) ->

    workspaces.sort (a, b) ->
      switch
        when a.slug is 'my-workspace' then -1
        when b.slug is 'my-workspace' then 1
        when a.slug < b.slug then -1
        when a.slug > b.slug then 1
        else 0


  mapWorkspaceWithChannel: (data, node) ->

    return  unless data.data?.channelId?

    { channelId } = data.data

    @workspaceItemChannelMap[channelId] = node


  selectWorkspace: (data) ->

    # data = @latestWorkspaceData or {}  unless data
    # { workspace, machine } = data

    # return if not machine or not workspace

    # tree = @machineTree

    # for key, node of tree.nodes
    #   nodeData         = node.getData()
    #   isSameMachine    = nodeData.uid is machine.uid
    #   isMachineRunning = machine.status.state is Machine.State.Running

    #   if node.type is 'machine'
    #     if isSameMachine
    #       if isMachineRunning
    #         tree.expand node
    #       else
    #         tree.selectNode node
    #         @watchMachineState workspace, machine
    #     else
    #       tree.collapse node

    #   else if node.type is 'workspace'
    #     if isMachineRunning and nodeData.machineLabel is (machine.slug or machine.label)
    #       slug = nodeData.data?.slug or KD.utils.slugify nodeData.title
    #       tree.selectNode node  if slug is workspace.slug

    # @latestWorkspaceData = data

    # localStorage = KD.getSingleton("localStorageController").storage "IDE"

    # minimumDataToStore =
    #   machineLabel     : machine.slug or machine.label
    #   workspaceSlug    : workspace.slug
    #   channelId        : data.channelId

    # localStorage.setValue 'LatestWorkspace', minimumDataToStore


  watchMachineState: (workspace, machine) ->
    @watchedMachines  or= {}
    computeController   = KD.getSingleton 'computeController'
    appManager          = KD.getSingleton 'appManager'
    {Running}           = Machine.State

    return  if @watchedMachines[machine._id]

    callback = (state) =>
      if state.status is Running
        machine.status.state = Running
        if appManager.getFrontApp().mountedMachineUId is machine.uid
          @selectWorkspace { workspace, machine }
          delete @watchedMachines[machine._id]

    computeController.on "public-#{machine._id}", callback
    @watchedMachines[machine._id] = yes


  fetchMachines: (callback) ->

    {computeController} = KD.singletons

    # force refetch from server everytime machines fetched.
    computeController.reset()
    computeController.fetchMachines (err, machines)=>
      if err
        return new KDNotificationView title : 'Couldn\'t fetch your VMs'

      callback machines


  # addVMTree: ->

  #   @addSubView section = new KDCustomHTMLView
  #     tagName  : 'section'
  #     cssClass : 'vms'

  #   @machineTree = new JTreeViewController
  #     type                : 'main-nav'
  #     treeItemClass       : NavigationItem
  #     addListsCollapsed   : yes

  #   @machineTree.getView().unsetClass 'kdscrollview'

  #   # This is temporary, we will create a separate TreeViewController
  #   # for this and put this logic into there ~ FIXME ~ GG
  #   @machineTree.dblClick = (nodeView, event)->
  #     machine = nodeView.getData()
  #     if machine.status?.state is Machine.State.Running
  #       @toggle nodeView

  #   section.addSubView header = new KDCustomHTMLView
  #     tagName  : 'h3'
  #     cssClass : 'sidebar-title'
  #     partial  : 'VMs'
  #     click    : @bound 'handleMoreVMsClick'

  #   header.addSubView new CustomLinkView
  #     cssClass : 'add-icon buy-vm'
  #     title    : ' '

  #   section.addSubView @machineTree.getView()

  #   @machineTree.on 'NodeWasAdded', (machineItem) =>
  #     machineItem.on 'click', @lazyBound 'handleMachineItemClick', machineItem

  #   if KD.userMachines.length
  #   then @listMachines (new Machine machine: (KD.remote.revive machine) for machine in KD.userMachines)
  #   else @fetchMachines @bound 'listMachines'


   addMachineList: ->

    @addSubView new SidebarOwnMachinesList


  handleMachineItemClick: (machineItem, event) ->

    machine  = machineItem.getData()
    {status} = machine
    {Building, Running} = Machine.State

    @activityLink?.unsetClass 'selected'

    if event.target.nodeName is 'SPAN'

      if status?.state is Running
        KD.utils.stopDOMEvent event
        KD.singletons.mainView.openMachineModal machine, machineItem
      else return

    else if machineItem.getData().status?.state is Machine.State.Building

      return


  # handleMoreVMsClick: (ev) ->

  #   KD.utils.stopDOMEvent ev

  #   if 'add-icon' in ev.target.classList
  #   then ComputeHelpers.handleNewMachineRequest()
  #   else new MoreVMsModal {}, KD.userMachines


  handleMoreWorkspacesClick: (data) ->
    workspaces = for workspace in KD.userWorkspaces when workspace.machineUId is data.machineUId
      workspace.machineLabel = data.machineLabel
      workspace

    data.workspaces = workspaces or []

    new MoreWorkspacesModal {}, data


  addFollowedTopics: ->

    limit = 10

    @addSubView @sections.channels = new ActivitySideView
      title      : 'Channels'
      cssClass   : 'followed topics'
      itemClass  : SidebarTopicItem
      dataPath   : 'followedChannels'
      delegate   : this
      noItemText : 'You don\'t follow any topics yet.'
      searchLink : '/Activity/Topic/Following'
      limit      : limit
      headerLink : new CustomLinkView
        cssClass : 'add-icon'
        title    : ' '
        href     : KD.utils.groupifyLink '/Activity/Topic/All'
      dataSource : (callback) ->
        KD.singletons.socialapi.channel.fetchFollowedChannels
          limit : limit
        , callback
      countSource: (callback) ->
        KD.remote.api.SocialChannel.fetchFollowedChannelCount {}, callback

    if KD.singletons.mainController.isFeatureDisabled 'channels'
      @sections.channels.hide()


  addConversations: ->

    @addSubView @sections.conversations = new ActivitySideView
      title      : 'Threads'
      cssClass   : 'conversations hidden'
      itemClass  : SidebarPinnedItem
      dataPath   : 'pinnedMessages'
      delegate   : this
      noItemText : 'You didn\'t participate in any conversations yet.'
      headerLink : KD.utils.groupifyLink '/Activity/Post/All'
      dataSource : (callback) ->
        KD.singletons.socialapi.channel.fetchPinnedMessages
          limit : 5
        , callback

    if KD.singletons.mainController.isFeatureDisabled 'threads'
      @sections.conversations.hide()


  addMessages: ->

    limit = 10

    @addSubView @sections.messages = new ActivitySideView
      title      : 'Messages'
      cssClass   : 'messages'
      itemClass  : SidebarMessageItem
      searchClass: ChatSearchModal
      dataPath   : 'privateMessages'
      delegate   : this
      noItemText : 'nothing here.'
      searchLink : '/Activity/Chat/All'
      limit      : limit
      headerLink : new CustomLinkView
        cssClass : 'add-icon'
        title    : ' '
        href     : KD.utils.groupifyLink '/Activity/Message/New'
      dataSource : (callback) ->
        KD.singletons.socialapi.message.fetchPrivateMessages
          limit  : limit
        , callback
      countSource: (callback) ->
        KD.remote.api.SocialMessage.fetchPrivateMessageCount {}, callback

    @sections.messages.on 'DataReady', @bound 'handleWorkspaceUnreadCounts'

    if KD.singletons.mainController.isFeatureDisabled 'private-messages'
      @sections.messages.hide()


  handleReloadMessages: -> @fetchWorkspaces => @sections.messages.reload()


  machinesListed = no
  whenMachinesRendered: ->

    new Promise (resolve) =>
      return resolve()  if machinesListed
      @once 'MachinesListed', ->
        machinesListed = yes
        resolve()


  handleWorkspaceUnreadCounts: (chatData) ->

    @whenMachinesRendered().then =>
      chatData
        .filter  (data) => @workspaceItemChannelMap[data._id]
        .forEach (data) => @setWorkspaceUnreadCount data, data.unreadCount


  addNewWorkspace: (machineData) ->
    return if @addWorkspaceView

    {machineUId, machineLabel, delegate} = machineData
    type     = 'new-workspace'
    parentId = machineUId
    id       = "#{machineUId}-input"
    data     = { type, machineUId, machineLabel, parentId, id }
    tree     = @machineTree

    @addWorkspaceView = delegate.addItem { type, machineUId, machineLabel }

    @addWorkspaceView.child.once 'KDObjectWillBeDestroyed', =>
      delegate.removeItem @addWorkspaceView
      @addWorkspaceView = null

    KD.utils.wait 177, => @addWorkspaceView.child.input.setFocus()


  createNewWorkspace: (options = {}) ->
    {name, machineUId, rootPath, machineLabel} = options
    {computeController, router } = KD.singletons
    layout = {}

    if not name or not machineUId
      return warn 'Missing options to create a new workspace'

    machine = m for m in computeController.machines when m.uid is machineUId
    data    = { name, machineUId, machineLabel, rootPath, layout }

    return warn "Machine not found."  unless machine

    KD.remote.api.JWorkspace.create data, (err, workspace) =>
      if err
        @emit 'WorkspaceCreateFailed'
        return KD.showError "Couldn't create your new workspace"

      folderOptions  =
        type         : 'folder'
        path         : workspace.rootPath
        recursive    : yes
        samePathOnly : yes

      machine.fs.create folderOptions, (err, folder) =>
        if err
          @emit 'WorkspaceCreateFailed'
          return KD.showError "Couldn't create your new workspace"

        filePath   = "#{workspace.rootPath}/README.md"
        readMeFile = FSHelper.createFileInstance { path: filePath, machine }

        readMeFile.save IDE.contents.workspace, (err) =>
          if err
            @emit 'WorkspaceCreateFailed'
            return KD.showError "Couldn't create your new workspace"

          for nodeData in @machineTree.indexedNodes when nodeData.uid is machine.uid
            parentId = nodeData.id

          view    = @addWorkspaceView
          data    =
            title : "#{workspace.name} <span class='ws-settings-icon'></span>"
            type  : 'workspace'
            href  : "/IDE/#{machine.slug or machine.label}/#{workspace.slug}"
            data  : workspace
            id    : workspace._id
            machineLabel : machineLabel
            parentId: parentId

          if view
            list  = view.getDelegate()
            list.removeItem view  if view
          else
            for key, node of @machineTree.nodes when node.type is 'title'
              list = node.getDelegate()

          KD.userWorkspaces.push workspace
          @sortWorkspaces KD.userWorkspaces

          index = 1 + KD.userWorkspaces
            .filter (w) -> w.machineUId is machine.uid
            .map    (w) -> w.slug
            .indexOf workspace.slug

          @machineTree.addNode data, index

          router.handleRoute data.href
          @emit 'WorkspaceCreated', workspace


  updateMachineTree: (callback = noop) ->

    @fetchMachines (machines) =>

      @renderMachines machines, callback


  renderMachines: (machines, callback = noop)->

    # @machineTree.removeAllNodes()
    # @listMachines machines

    # @selectWorkspace()
    callback()


  invalidateWorkspaces: (machine)->

    return  unless machine?

    KD.remote.api.JWorkspace.deleteByUid machine.uid, (err)=>

      return warn err  if err?

      KD.userWorkspaces =
        ws for ws in KD.userWorkspaces when ws.machineUId isnt machine.uid

      @updateMachineTree()


  removeMachineNode: (machine) ->
    # {nodes}    = @machineTree
    # {jMachine} = machine

    # for nodeId, node of nodes when node.data?.jMachine is jMachine
    #   @machineTree.removeNode nodeId
