fs            = require 'fs'
{ isAllowed } = require './grouptoenvmapping'

generatePodDef = ->

  '''
  apiVersion: v1
  kind: Pod
  metadata:
    name: backend
    namespace: koding
  spec:
    restartPolicy: Never
    containers:
  '''

generateContainerSection = (app, options = {}) ->

  container =
    name          : app
    image         : options.kubernetes.image
    workingDir    : '/opt/koding'
    command       : options.kubernetes.command
    env           : generateEnvvarsSection options.kubernetes.envVariables?, options
    ports					: generatePortsSection options.kubernetes.ports?, options
    mounts        : generateMountSection options.kubernetes.mounts?, options

  containerSection =
  """
  \n    - name: #{container.name}
        image: #{container.image}
        workingDir: #{container.workingDir}
        command:  #{container.command}
  """
  if container.env isnt '' then containerSection += "\n      #{container.env}"
  if container.ports isnt '' then containerSection += "\n      #{container.ports}"

  containerSection += container.mounts

generateEnvvarsSection = (envVarsExist, options) ->
  envConf = ''
  if envVarsExist
    envConf = 'env:\n'
    for key in options.kubernetes.envVariables
      # converting {'s and }'s to ('s and )'s for k8s environment variable usage convention
      if key.value.search(/{/) isnt -1 and key.value.search(/}/) isnt -1
        key.value = '$(' + key.value.slice(2, key.value.search(/}/)) + ')' + key.value.slice(key.value.search(/}/) + 1, key.value.length)
      envConf += "        - name: #{key.name}\n"
      envConf += "          value: #{key.value}\n"

  return envConf

generatePortsSection = (portsExist, options) ->
  portsConf = ''
  if portsExist
    portsConf += 'ports:'
    portsConf +=
      """
      \t
              - containerPort: #{options.kubernetes.ports.containerPort}
                hostPort: #{options.kubernetes.ports.hostPort}
      """
    portsConf += '\n'
  return portsConf

generateMountSection = (mounts, options) ->
  mountConf = '\n      volumeMounts:\n'

  volumes = [
      {
        mountPath : '/opt/koding'
        name : 'koding-working-tree'
      }
      {
        mountPath : '/root/.kite/'
        name : 'root-kite-volume'
      }
      {
        mountPath : '/opt/koding/generated'
        name : 'generated-volume'
      }
      {
        mountPath : '/usr/share/nginx/html'
        name : 'assets'
      }
    ]

  for key, i in volumes
    if mounts and volumes[i].name in options.kubernetes.mounts
      mountConf += "        - mountPath: #{key.mountPath}\n"
      mountConf += "          name: #{key.name}\n"
  return mountConf


generateVolumesSection = ->
  projectRootVar = process.env.PWD
  homeVar = process.env.HOME
  volumePaths =
  """
  \n
    volumes:
    - name: generated-volume
      hostPath:
        path: #{projectRootVar}/generated
    - name: root-kite-volume
      hostPath:
        path: #{homeVar}/.kite/
    - name: koding-working-tree
      hostPath:
        path: #{projectRootVar}
    - name: assets
      hostPath:
        path: #{projectRootVar}/website
  """
  return volumePaths

module.exports.create = (KONFIG) ->
  conf = generatePodDef()

  # for every worker create their container configs
  for name, options of KONFIG.workers when options.kubernetes?.command?

    unless isAllowed options.group, KONFIG.ebEnvName
      continue

    conf += generateContainerSection name, options

  conf += generateVolumesSection()

  # removing line breaks
  conf = conf.replace(/^\s*\n/gm, '')

  return conf

module.exports.createWorkerServices = (name, options) ->
  serviceConf =
    """
    apiVersion: v1
    kind: Service
    metadata:
      name: #{name}
      namespace: koding
    spec:
      type: NodePort
      ports:
      - name: ""
        port: #{options.kubernetes.ports.containerPort}
        protocol: ""
        targetPort: #{options.kubernetes.ports.containerPort}
      selector:
        service: #{name}
    """

  return serviceConf
