traverse              = require 'traverse'
os                    = require 'os'

module.exports = (KONFIG, options, credentials) ->
  GOBIN = '%(ENV_KONFIG_PROJECTROOT)s/go/bin'
  GOPATH = '%(ENV_KONFIG_PROJECTROOT)s/go'

  GOBIN_K8S = "#{KONFIG.projectRoot}/go/bin"
  GOPATH_K8S = "#{KONFIG.projectRoot}/go"

  nodeProgram = if options.watchNode then './watch-node' else 'node'

  socialapiEnvVariables = [
      {
        name        : 'KONFIG_REDIS_HOST'
        value       : '${REDIS_SERVICE_HOST}'
      }
      {
        name        : 'KONFIG_REDIS_URL'
        value       : '${KONFIG_REDIS_HOST}:6379'
      }
      {
        name        : 'KONFIG_SOCIALAPI_MONGO'
        value       : '${MONGO_SERVICE_HOST}:27017/koding'
      }
      {
        name        : 'KONFIG_SOCIALAPI_POSTGRES_HOST'
        value       : '${POSTGRES_SERVICE_HOST}'
      }
      {
        name        : 'KONFIG_SOCIALAPI_MQ_HOST'
        value       : '${RABBITMQ_SERVICE_HOST}'
      }
      {
        name        : 'KONFIG_SOCIALAPI_MQ_LOGIN'
        value       : 'test'
      }
      {
        name        : 'KONFIG_SOCIALAPI_MQ_PASSWORD'
        value       : 'test'
      }
    ]

  workers =
    nginx               :
      group             : 'external'
      supervisord       :
        command         : 'nginx -c %(ENV_KONFIG_PROJECTROOT)s/nginx.conf'
        stopsignal      : 'QUIT'
      kubernetes        :
        image           : 'nginx'
        command         : " [ \"nginx\", \"-c\", \"#{KONFIG.projectRoot}/nginx.conf\" ] "
        mounts          : [ 'koding-working-tree', 'assets' ]
        ports						:
          containerPort : "#{KONFIG.domains.port}"
          hostPort      : "#{KONFIG.domains.port}"

    bucketproxies       :
      group             : 'bucket'
      nginx             :
        s3bucket        : yes
        locations       : [
          {
            location    : '@assets'
            proxyPass   : 'http://s3.amazonaws.com/koding-assets$uri'
          }
          {
            location    : '~^/cdn/(koding-client|koding-assets|kodingdev-client|kodingdev-assets)/(.*)'
            proxyPass   : 'http://s3.amazonaws.com/$1/$2'
          }
          { # redirect /d/* to koding-dl S3 bucket; used to distributed kd/klient installers
            location    : '~^/d/(.*)$'
            proxyPass   : 'https://s3.amazonaws.com/koding-dl/$1'
          }
          { # redirect /d/kd to KD installer for development channel
            location    : '/c/d/kd'
            proxyPass   : 'https://s3.amazonaws.com/koding-kd/development/install-kd.sh'
          }
          { # redirect /p/kd to KD installer for production channel
            location    : '/c/p/kd'
            proxyPass   : 'https://s3.amazonaws.com/koding-kd/production/install-kd.sh'
          }
        ]

    assets              :
      group             : 'static'
      nginx             :
        static          : yes
        locations       : [
          {
            location      : '/a/'
            proxyPass     : '$uri @assets'
            relativePath  : '/website/'
            expires       : if options.environment in ['default', 'dev'] then '-1' else '1M' # set -1 to disable.
            extraParamsStr: 'location ~* \.(map)$ { return 404; access_log off; }'
          }
          {
            location    : '/apidocs'
            proxyPass   : '$uri $uri/ =404'
            relativePath: '/website/'
            expires     : '-1'
          }
          {
            location    : '/swagger.json'
            proxyPass   : '$uri @assets'
            relativePath: '/website/'
            expires     : '-1'
          }
        ]

    kontrol             :
      group             : 'environment'
      ports             :
        incoming        : "#{KONFIG.kontrol.port}"
      supervisord       :
        command         : "#{GOBIN}/kontrol"
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : '~^/kontrol/(.*)'
            proxyPass   : 'http://kontrol/$1$is_args$args'
          }
        ]
      healthCheckURLs   : [ "http://localhost:#{KONFIG.kontrol.port}/healthCheck" ]
      versionURL        : "http://localhost:#{KONFIG.kontrol.port}/version"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/kontrol\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume', 'generated-volume' ]
        ports						:
          containerPort : "#{KONFIG.kontrol.port}"
          hostPort      : "#{KONFIG.kontrol.port}"
        envVariables    : [
          {
            name        : 'KONFIG_KONTROL_MONGOURL'
            value       : '${MONGO_SERVICE_HOST}:27017/koding'
          }
          {
            name        : 'KONFIG_KONTROL_POSTGRES_HOST'
            value       : '${POSTGRES_SERVICE_HOST}'
          }
        ]

    countly             :
      group             : 'webserver'
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : '/countly/'
            proxyPass   : "#{credentials.countly.host}/"
            extraParams : [
              'proxy_hide_header X-Frame-Options;'
              'proxy_hide_header X-XSS-Protection;'
              'proxy_hide_header Strict-Transport-Security;'
            ]
          }
        ]

    kloud               :
      group             : 'environment'
      ports             :
        incoming        : "#{KONFIG.kloud.port}"
      supervisord       :
        command         : "#{GOBIN}/kloud"
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : '~^/kloud/(.*)'
            proxyPass   : 'http://kloud/$1$is_args$args'
          }
        ]
      healthCheckURLs   : [ "http://localhost:#{KONFIG.kloud.port}/healthCheck" ]
      versionURL        : "http://localhost:#{KONFIG.kloud.port}/version"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/kloud\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume', 'generated-volume' ]
        ports:
          containerPort : "#{KONFIG.kloud.port}"
          hostPort      : "#{KONFIG.kloud.port}"
        envVariables    : [
          {
            name        : 'KONFIG_KLOUD_MONGOURL'
            value       : '${MONGO_SERVICE_HOST}:27017/koding'
          }
          {
            name        : 'KONFIG_KLOUD_POSTGRES_HOST'
            value       : '${POSTGRES_SERVICE_HOST}'
          }
        ]

    terraformer         :
      group             : 'environment'
      supervisord       :
        command         : "#{GOBIN}/terraformer"
      healthCheckURLs   : [ "http://localhost:#{KONFIG.terraformer.port}/healthCheck" ]
      versionURL        : "http://localhost:#{KONFIG.terraformer.port}/version"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/terraformer\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume', 'generated-volume' ]

    webserver           :
      group             : 'webserver'
      ports             :
        incoming        : "#{KONFIG.webserver.port}"
        outgoing        : "#{KONFIG.webserver.kitePort}"
      supervisord       :
        command         : "#{nodeProgram} %(ENV_KONFIG_PROJECTROOT)s/servers/index.js"
      healthCheckURLs   : [
          "http://localhost:#{options.publicPort}/swagger.json"
          "http://localhost:#{options.publicPort}/apidocs"
      ]
      nginx             :
        locations       : [
          {
            location    : '/-/healthCheck'
          }
          {
            location    : '~*(^(\/(Pricing|About|Legal|Features|Blog|Docs)))'
            extraParams : [ 'if ($host !~* ^(dev|default|sandbox|latest|www)) { return 301 /; }' ]
          }
          {
            location    : '~ /-/api/(.*)'
            proxyPass   : 'http://webserver/-/api/$1$is_args$args'
          }
          {
            location    : '/'
            cors        : on
            auth        : if options.environment is 'sandbox' then yes else no
          }
        ]
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{nodeProgram}\", \"#{KONFIG.projectRoot}/servers/index.js\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume', 'generated-volume' ]
        ports						:
          containerPort : "#{KONFIG.webserver.k8sPort}"
          hostPort      : "#{KONFIG.webserver.k8sPort}"
        envVariables    : [
          {
            name        : 'KONFIG_REDIS_HOST'
            value       : '${REDIS_SERVICE_HOST}'
          }
          {
            name        : 'KONFIG_REDIS_URL'
            value       : '${KONFIG_REDIS_HOST}:6379'
          }
          {
            name        : 'KONFIG_MONGO'
            value       : '${MONGO_SERVICE_HOST}:27017/koding'
          }
          {
            name        : 'KONFIG_WEBSERVER_PORT'
            value       : "\"#{KONFIG.webserver.k8sPort}\""
          }
        ]

    socialworker        :
      group             : 'webserver'
      ports             :
        incoming        : "#{KONFIG.social.port}"
        outgoing        : "#{KONFIG.social.kitePort}"
      supervisord       :
        command         : "#{nodeProgram} %(ENV_KONFIG_PROJECTROOT)s/workers/social/index.js"
      nginx             :
        locations       : [
          { location: '/xhr' }
          { location: '/remote.api' }
        ]
      healthCheckURLs   : [ "http://localhost:#{KONFIG.social.port}/healthCheck" ]
      versionURL        : "http://localhost:#{KONFIG.social.port}/version"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{nodeProgram}\", \"#{KONFIG.projectRoot}/workers/social/index.js\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume', 'generated-volume' ]
        ports:
          containerPort   : "#{KONFIG.social.port}"
          hostPort        : "#{KONFIG.social.port}"
        envVariables    : [
          {
            name        : 'KONFIG_REDIS_HOST'
            value       : '${REDIS_SERVICE_HOST}'
          }
          {
            name        : 'KONFIG_REDIS_URL'
            value       : '${KONFIG_REDIS_HOST}:6379'
          }
          {
            name        : 'KONFIG_MONGO'
            value       : '${MONGO_SERVICE_HOST}:27017/koding'
          }
        ]

    emailer             :
      group             : 'webserver'
      disabled          : yes
      supervisord       :
        command         :
          run           : 'node %(ENV_KONFIG_PROJECTROOT)s/workers/emailer'
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{nodeProgram}\", \"#{KONFIG.projectRoot}/workers/emailer\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : [
          {
            name        : 'KONFIG_MQ_HOST'
            value       : '${RABBITMQ_SERVICE_HOST)'
          }
        ]

    notification        :
      group             : 'webserver'
      disabled          : yes
      supervisord       :
        command         :
          run           : 'node %(ENV_KONFIG_PROJECTROOT)s/workers/notification -p 4560'
      ports             :
        incoming        : '4560'
      nginx             :
        websocket       : yes
        locations       : [
          { location    : '/notify' }
          {
            location    : '~ /api/social/private/dispatcher/(.*)' # handle dispatcher requests
            proxyPass   : 'http://notification/$1$is_args$args'
            internalOnly: yes
          }
        ]
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{nodeProgram}\", \"#{KONFIG.projectRoot}/workers/notification\", \"-p\", \"4560\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        ports						:
          containerPort : '4560'
          hostPort			: '4560'
        envVariables    : [
          {
            name        : 'KONFIG_REDIS_HOST'
            value       : '${REDIS_SERVICE_HOST}'
          }
          {
            name        : 'KONFIG_REDIS_URL'
            value       : '${KONFIG_REDIS_HOST}:6379'
          }
          {
            name        : 'KONFIG_MONGO'
            value       : '${MONGO_SERVICE_HOST}:27017/koding'
          }
          {
            name        : 'KONFIG_MQ_HOST'
            value       : '${RABBITMQ_SERVICE_HOST}'
          }
        ]
      # if it's required to have more than 1 instance of notification worker
      # sticky sessions should be enabled on the load balancer if it's willing
      # to use long polling (xhr-polling/stream) ~ GG
      instances         : 1
      instanceAsArgument: '-i'

    socialapi           :
      group             : 'socialapi'
      instances         : 1
      ports             :
        incoming        : "#{KONFIG.socialapi.port}"
      supervisord       :
        command         :
          run           : "#{GOBIN}/api -port=#{KONFIG.socialapi.port}"
          watch         : 'make -C %(ENV_KONFIG_PROJECTROOT)s/go/src/socialapi apidev'
      healthCheckURLs   : [ "#{KONFIG.socialapi.proxyUrl}/healthCheck" ]
      versionURL        : "#{KONFIG.socialapi.proxyUrl}/version"
      nginx             :
        locations       : [
          # location ordering is important here. if you are going to need to change it or
          # add something new, thoroughly test it in sandbox. Most of the problems are not occuring
          # in dev environment
          {
            location    : '~ /api/social/channel/(.*)/history/count'
            proxyPass   : 'http://socialapi/channel/$1/history/count$is_args$args'
          }
          {
            location    : '~ /api/social/channel/(.*)/history'
            proxyPass   : 'http://socialapi/channel/$1/history$is_args$args'
          }
          {
            location    : '~ /api/social/channel/(.*)/list'
            proxyPass   : 'http://socialapi/channel/$1/list$is_args$args'
          }
          {
            location    : '~ /api/social/channel/by/(.*)'
            proxyPass   : 'http://socialapi/channel/by/$1$is_args$args'
          }
          {
            location    : '~ /api/social/collaboration/ping'
            proxyPass   : 'http://socialapi/collaboration/ping$1$is_args$args'
          }
          {
            location    : '~ /api/social/search-key'
            proxyPass   : 'http://socialapi/search-key$1$is_args$args'
          }
          {
            location    : '~ /api/social/sshkey'
            proxyPass   : 'http://socialapi/sshkey$1$is_args$args'
          }
          {
            location    : '~ /api/social/account/channels'
            proxyPass   : 'http://socialapi/account/channels$is_args$args'
          }
          {
            location    : '~ /api/social/payment/(.*)'
            proxyPass   : 'http://socialapi/payment/$1$is_args$args'
          }
          {
            location    : '~ /api/social/presence/(.*)'
            proxyPass   : 'http://socialapi/presence/$1$is_args$args'
          }
          {
            location    : '~* ^/api/social/slack/(.*)'
            proxyPass   : 'http://socialapi/slack/$1$is_args$args'
            extraParams : [ 'proxy_buffering off;' ] # appearently slack sends a big header
          }
          {
            location    : '~ /api/social/(.*)'
            proxyPass   : 'http://socialapi/$1$is_args$args'
            internalOnly: yes
          }
        ]
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/api\", \"-port=7000\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        ports						:
          containerPort : "#{KONFIG.socialapi.port}"
          hostPort      : "#{KONFIG.socialapi.port}"
        envVariables    : socialapiEnvVariables

    realtime            :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/realtime"
          watch         : "#{GOBIN}/watcher -run socialapi/workers/cmd/realtime -watch socialapi/workers/realtime"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/realtime\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    presence            :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/presence"
          watch         : "#{GOBIN}/watcher -run socialapi/workers/cmd/presence -watch socialapi/workers/presence"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/presence\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    collaboration       :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/collaboration -kite-init=true"
          watch         : "#{GOBIN}/watcher -run socialapi/workers/cmd/collaboration -watch socialapi/workers/collaboration -kite-init=true"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/collaboration\", \"-kite-init=true\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    gatekeeper          :
      group             : 'socialapi'
      ports             :
        incoming        : "#{KONFIG.gatekeeper.port}"
      supervisord       :
        command         :
          run           : "#{GOBIN}/gatekeeper"
          watch         : 'make -C %(ENV_KONFIG_PROJECTROOT)s/go/src/socialapi gatekeeperdev'
      healthCheckURLs   : [ "#{options.customDomain.local}/api/gatekeeper/healthCheck" ]
      versionURL        : "#{options.customDomain.local}/api/gatekeeper/version"
      nginx             :
        locations       : [
          location      : '~ /api/gatekeeper/(.*)'
          proxyPass     : 'http://gatekeeper/$1$is_args$args'
        ]
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/gatekeeper\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        ports						:
          containerPort : "#{KONFIG.gatekeeper.port}"
          hostPort      : "#{KONFIG.gatekeeper.port}"
        envVariables    : socialapiEnvVariables

    dispatcher          :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/dispatcher"
          watch         : 'make -C %(ENV_KONFIG_PROJECTROOT)s/go/src/socialapi dispatcherdev'
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/dispatcher\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    mailsender          :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/emailsender"
          watch         : "#{GOBIN}/watcher -run socialapi/workers/cmd/emailsender -watch socialapi/workers/emailsender"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/emailsender\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    team                :
      group             : 'socialapi'
      supervisord       :
        command         :
          run           : "#{GOBIN}/team"
          watch         : "#{GOBIN}/watcher -run socialapi/workers/cmd/team -watch socialapi/workers/team"
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/team\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        envVariables    : socialapiEnvVariables

    tunnelproxymanager  :
      group             : 'proxy'
      supervisord       :
        command         : "#{GOBIN}/tunnelproxymanager"

    tunnelserver        :
      group             : 'proxy'
      supervisord       :
        command         : "#{GOBIN}/tunnelserver"
      ports             :
        incoming        : "#{KONFIG.tunnelserver.port}"
      healthCheckURLs   : [ 'http://tunnelserver/healthCheck' ]
      versionURL        : 'http://tunnelserver/version'
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : '~ /tunnelserver/(.*)'
            proxyPass   : 'http://tunnelserver/$1'
          }
        ]
      kubernetes        :
        image           : 'koding/base'
        command         : " [ \"./run\", \"exec\", \"#{GOBIN_K8S}/tunnelserver\" ] "
        mounts          : [ 'koding-working-tree', 'root-kite-volume' ]
        ports						:
          containerPort : "#{KONFIG.tunnelserver.port}"
          hostPort      : "#{KONFIG.tunnelserver.port}"
        envVariables    : socialapiEnvVariables

    userproxies         :
      group             : if options.environment is 'default' then 'webserver' else 'proxy'
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : '~ ^\\/-\\/prodproxy\\/(?<ip>.+?)\\/(?<rest>.*)'
            proxyPass   : 'http://$ip:56789/$rest'
            extraParams : [
              'proxy_read_timeout 21600s;'
              'proxy_send_timeout 21600s;'
            ]
          }
          {
            location    : '~ ^\\/-\\/devproxy\\/(?<ip>.+?)\\/(?<rest>.*)'
            proxyPass   : 'http://$ip:56789/$rest'
            extraParams : [
              'proxy_read_timeout 21600s;'
              'proxy_send_timeout 21600s;'
            ]
          }
        ]

    tunnelproxies:
      group             : 'proxy'
      nginx             :
        websocket       : yes
        locations       : [
          {
            location    : "~ ^\\/-\\/prodtunnel\\/(?<tunnel>.+?)\.#{KONFIG.tunnelserver.hostedzone}(?<rest>.*)"
            proxyPass   : "http://$tunnel.#{KONFIG.tunnelserver.hostedzone}$rest"
            host        : "$tunnel.#{KONFIG.tunnelserver.hostedzone}"
            extraParams : [
              'proxy_read_timeout 21600s;'
              'proxy_send_timeout 21600s;'
              'resolver 8.8.8.8;'
            ]
          }
          {
            location    : "~ ^\\/-\\/devtunnel\\/(?<tunnel>.+?)\.#{KONFIG.tunnelserver.hostedzone}(?<rest>.*)"
            proxyPass   : "http://$tunnel.#{KONFIG.tunnelserver.hostedzone}$rest"
            host        : "$tunnel.#{KONFIG.tunnelserver.hostedzone}"
            extraParams : [
              'proxy_read_timeout 21600s;'
              'proxy_send_timeout 21600s;'
              'resolver 8.8.8.8;'
            ]
          }
        ]

  # if requested disable workers
  disabledWorkers = options?.disabledWorkers ? []
  for worker in disabledWorkers
    delete workers[worker]

  # if not enabled then disable the one should be disabled
  enabledWorkers = options?.enabledWorkers ? []
  for key, worker of workers when worker.disabled
    if key in enabledWorkers
      worker.disabled = no
    else
      delete workers[key]

  return workers
