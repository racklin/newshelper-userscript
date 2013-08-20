content-style = """
.newshelper-warning {
    background: hsl(0, 50%, 50%);
    color: white;
    font-size: large;
    text-align: center;
    width: 100%;
    padding: 5px 0;
}

.newshelper-warning-facebook {
background: hsl(50, 100%, 70%);
   color: hsl(0, 0%, 20%);
   font-size: medium;
   text-align: center;
   margin: 20px 0 10px 0;
   padding: 0 0 10px 0;
   -webkit-border-radius: 5px;
      -moz-border-radius: 5px;
           border-radius: 5px;
}

.newshelper-description {
  display: block;
  font-size: small;
  margin-top: 5px;
}

.newshelper-description a {
  color: hsl(0, 100%, 50%);
  font-weight: bold;
  padding-right: 20px;
  background: transparent url(data:image/gif;base64,R0lGODlhEQDcAKIAAP////8AAGYAmQAzZv///wAAAAAAAAAAACH5BAUUAAQALAAAAAARANwAAAPmSLrc/m7IOeEAON/x9gQXGGVa1XgSyRGSEpLa0qIUSH1w7HL0t7asnI7RS62IQsxRdrtBntCodEqtWq/YrHbL7Xq/4LB4TC6bz+i0es1uu9/wuHxOr9vv+Lx+zxcL/oCAEAI5hAIPhoAAhIsOjCSBjouKGYcEfwqPhQuYiYGen0mNmYegipaYl6KWDKZ/o62rjp+ffba3uLm6u7y9vr/AwcLDxMXGx8jJynIBzc7OEAE50gEP1M4A0tkO2iTP3NnYGdUEzQrd0wvm18/s7aLk5dXu2OTm5fDg7c3bDegw8dTt+7ZsSgIAOw==) no-repeat 100% -200px;
}

.arrow-up {
  width: 0;
  height: 0;
  border-left: 10px solid transparent;
  border-right: 10px solid transparent;
  border-bottom: 10px solid hsl(50, 100%, 70%);
  position: relative;
  top: -10px;
  margin: 0 auto;
}
"""

let $ = jQuery

  indexedDB = window.indexedDB or window.webkitIndexedDB or window.mozIndexedDB or window.msIndexedDB
  opened_db = null

  addStyle = ->
      GM_addStyle it

  get_newshelper_db = (cb) ->
    if null isnt opened_db
      cb opened_db
      return
    request = indexedDB.open(\newshelper, \6)
    request.onsuccess = (event) ->
      opened_db = request.result
      cb opened_db

    request.onerror = (event) ->
      console.log "IndexedDB error: #{event.target.errorCode}"

    request.onupgradeneeded = (event) ->
      try
        event.currentTarget.result.deleteObjectStore \read_news
      objectStore = event.currentTarget.result.createObjectStore \read_news, keyPath: \id, autoIncrement: true
      objectStore.createIndex \title, \title, unique: false
      objectStore.createIndex \link, \link, unique: true
      objectStore.createIndex \last_seen_at, \last_seen_at, unique: false

      try
        event.currentTarget.result.deleteObjectStore \report
      objectStore = event.currentTarget.result.createObjectStore \report, keyPath: \id
      objectStore.createIndex \news_title, \news_title, unique: false
      objectStore.createIndex \news_link, \news_link, unique: false
      objectStore.createIndex \updated_at, \updated_at, unique: false


  get_time_diff = (time) ->
    delta = Math.floor(new Date!getTime! / 1000) - time
    switch true
    | delta < 60 => "#delta 秒前"
    | delta < 60 * 60 => "#{Math.floor(delta / 60)} 分鐘前"
    | delta < 60 * 60 * 24 => "#{Math.floor(delta / 60 / 60)} 小時前"
    | _ => "#{Math.floor(delta / 60 / 60 / 24)} 天前"


  check_recent_seen = (report) ->
    get_newshelper_db (opened_db) ->
      transaction = opened_db.transaction(\read_news, \readonly)
      objectStore = transaction.objectStore(\read_news)
      index = objectStore.index("link")
      get_request = index.get(report.news_link)
      get_request.onsuccess = ->
        return  unless get_request.result

        # 如果已經被刪除了就跳過
        return  if parseInt(get_request.result.deleted_at, 10)
        chrome.extension.sendRequest {
          method: "add_notification"
          title: "新聞小幫手提醒您"
          body: "您於" + get_time_diff(get_request.result.last_seen_at) + " 看的新聞「" + get_request.result.title + "」 被人回報有錯誤：" + report.report_title
          link: report.report_link
        }, (response) ->



  get_recent_report = (cb) ->
    get_newshelper_db (opened_db) ->
      transaction = opened_db.transaction("report", "readonly")
      objectStore = transaction.objectStore("report")
      index = objectStore.index("updated_at")
      request = index.openCursor(null, "prev")
      request.onsuccess = ->
        if request.result
          cb request.result.value
          return
        cb null



  # 跟遠端 API server 同步回報資料
  sync_report_data = ->
    get_newshelper_db (opened_db) ->
      get_recent_report (report) ->
        cachedTime = if report?.updated_at? then parseInt report.updated_at else 0
        url = "http://newshelper.g0v.tw/index/data?time=#cachedTime"
        GM_xmlhttpRequest {
          method: \GET
          url: url
          onload: (xhr) ->
            ret = JSON.parse xhr.responseText
            transaction = opened_db.transaction("report", "readwrite")
            objectStore = transaction.objectStore("report")
            if ret.data
              i = 0

              while i < ret.data.length
                objectStore.put ret.data[i]

                # 檢查最近天看過的內容是否有被加進去的
                check_recent_seen ret.data[i]
                i++

            # 每 5 分鐘去檢查一次是否有更新
            setTimeout sync_report_data, 300000
        }

  log_browsed_link = (link, title) ->
    return  unless link
    get_newshelper_db (opened_db) ->
      transaction = opened_db.transaction("read_news", "readwrite")
      objectStore = transaction.objectStore("read_news")
      try
        request = objectStore.add(
          title: title
          link: link
          last_seen_at: Math.floor(new Date!getTime! / 1000)
        )
      catch {message}
        GM_log "Error #link , #title , #message"

      # link 重覆
      request.onerror = ->
        transaction = opened_db.transaction("read_news", "readwrite")
        objectStore = transaction.objectStore("read_news")
        index = objectStore.index("link")
        get_request = index.get(link)
        get_request.onsuccess = ->

          # update last_seen_at
          put_request = objectStore.put(
            id: get_request.result.id
            title: title
            last_seen_at: Math.floor(new Date!getTime! / 1000)
          )


  # 從 db 中判斷 title, url 是否是錯誤新聞，是的話執行 cb 並傳入資訊
  check_report = (title, url, cb) ->
    return  unless url
    get_newshelper_db (opened_db) ->
      transaction = opened_db.transaction("report", "readonly")
      objectStore = transaction.objectStore("report")
      index = objectStore.index("news_link")
      get_request = index.get(url)
      get_request.onsuccess = ->

        # 如果有找到結果，並且沒有被刪除
        cb get_request.result  if get_request.result and not parseInt(get_request.result.deleted_at, 10)


  buildWarningMessage = (options) ->
    "<div class=\"newshelper-warning-facebook\">" + "<div class=\"arrow-up\"></div>" + "注意！您可能是<b>問題新聞</b>的受害者" + "<span class=\"newshelper-description\">" + $("<span></span>").append($("<a></a>").attr(
      href: options.link
      target: "_blank"
    ).text(options.title)).html() + "</span>" + "</div>"


  censorFacebook = (baseNode) ->
    if window.location.host.indexOf("www.facebook.com") isnt -1

      # log browsing history into local database for further warning

      # add warning message to a Facebook post if necessary
      censorFacebookNode = (containerNode, titleText, linkHref) ->
        matches = ("" + linkHref).match("^http://www.facebook.com/l.php\\?u=([^&]*)")
        linkHref = decodeURIComponent(matches[1])  if matches
        containerNode = $(containerNode)
        className = "newshelper-checked"
        if containerNode.hasClass(className)
          return
        else
          containerNode.addClass className

        # 先看看是不是 uiStreamActionFooter, 表示是同一個新聞有多人分享, 那只要最上面加上就好了
        addedAction = false
        containerNode.parent("div[role=article]").find(".uiStreamActionFooter").each (idx, uiStreamSource) ->
          $(uiStreamSource).find("li:first").append "· " + buildActionBar(
            title: titleText
            link: linkHref
          )
          addedAction = true


        # 再看看單一動態，要加在 .uiStreamSource
        unless addedAction
          containerNode.parent("div[role=article]").find(".uiStreamSource").each (idx, uiStreamSource) ->
            $($("<span></span>").html(buildActionBar(
              title: titleText
              link: linkHref
            ))).insertBefore uiStreamSource

            # should only have one uiStreamSource
            console.error idx + titleText  unless idx is 0


        # log the link first
        log_browsed_link linkHref, titleText
        check_report titleText, linkHref, (report) ->
          containerNode.addClass className
          containerNode.append buildWarningMessage(
            title: report.report_title
            link: report.report_link
          )



      # my timeline
      $(baseNode).find(".uiStreamAttachments").each (idx, uiStreamAttachment) ->
        uiStreamAttachment = $(uiStreamAttachment)
        unless uiStreamAttachment.hasClass("newshelper-checked")
          titleText = uiStreamAttachment.find(".uiAttachmentTitle").text()
          linkHref = uiStreamAttachment.find("a").attr("href")
          censorFacebookNode uiStreamAttachment, titleText, linkHref


      # others' timeline, fan page
      $(baseNode).find(".shareUnit").each (idx, shareUnit) ->
        shareUnit = $(shareUnit)
        unless shareUnit.hasClass("newshelper-checked")
          titleText = shareUnit.find(".fwb").text()
          linkHref = shareUnit.find("a").attr("href")
          censorFacebookNode shareUnit, titleText, linkHref


      # post page (single post)
      $(baseNode).find("._6kv").each (idx, userContent) ->
        userContent = $(userContent)
        unless userContent.hasClass("newshelper-checked")
          titleText = userContent.find(".mbs").text()
          linkHref = userContent.find("a").attr("href")
          censorFacebookNode userContent, titleText, linkHref


  registerObserver = ->
    MutationObserver = window.MutationObserver or window.WebKitMutationObserver
    mutationObserverConfig =
      target: document.getElementsByTagName("body")[0]
      config:
        attributes: true
        childList: true
        characterData: true

    mutationObserver = new MutationObserver((mutations) ->
      mutations.forEach (mutation) ->
        censorFacebook mutation.target

    )
    mutationObserver.observe mutationObserverConfig.target, mutationObserverConfig.config

  buildActionBar = (options) ->
    url = "http://newshelper.g0v.tw"
    url += "?news_link=" + encodeURIComponent(options.link) + "&news_title= " + encodeURIComponent(options.title)  if "undefined" isnt typeof (options.title) and "undefined" isnt typeof (options.link)
    "<a href=\"" + url + "\" target=\"_blank\">回報給新聞小幫手</a>"


  do ->

    # add style
    addStyle content-style

    # fire up right after the page loaded
    censorFacebook document.body

    sync_report_data()

    # deal with changed DOMs (i.e. AJAX-loaded content)
    registerObserver()

