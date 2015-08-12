_ = require 'lodash'
url = require 'url'
cors = require 'cors'
morgan = require 'morgan'
express = require 'express'
passport = require 'passport'
session = require 'cookie-session'
bodyParser = require 'body-parser'
errorHandler = require 'errorhandler'
MeshbluAuth = require 'express-meshblu-auth'
MeshbluAuthExpress = require 'express-meshblu-auth/src/meshblu-auth-express'
MeshbluHealthCheck = require 'express-meshblu-healthcheck'
MeshbluConfig = require 'meshblu-config'
MeshbluHttp = require 'meshblu-http'
debug = require('debug')('little-bits-cloud-proxy')

CredentialManager = require './src/models/credential-manager'
ProxyRequestModel = require './src/models/proxy-request-model'
LittleBitsOptionsBuilder = require './src/models/little-bits-options-builder'

meshbluConfig = new MeshbluConfig().toJSON()

PORT  = process.env.PORT || 80

passport.serializeUser (user, done) ->
  done null, JSON.stringify user

passport.deserializeUser (id, done) ->
  done null, JSON.parse id

app = express()
app.use cors()
app.use morgan('combined')
app.use errorHandler()
app.use MeshbluHealthCheck()
app.use session cookie: {secure: true}, secret: 'afa24e6f-6c8a-4748-a7ae-6c7a4f7ad6d9', name: 'twitter-proxy'
app.use passport.initialize()
app.use passport.session()
app.use bodyParser.urlencoded limit: '50mb', extended : true
app.use bodyParser.json limit : '50mb'
app.options '*', cors()

meshbluAuthorizer = MeshbluAuth
  server: meshbluConfig.server
  port: meshbluConfig.port


options =
  messageSchema: require './twitter-message-schema.json'
  messageFormSchemaUrl: './twitter-form.json'
  logo: 'https://cdn.octoblu.com/icons/devices/little-bits-cloud.svg'
  name: 'littleBits Cloud'

credentialManager = new CredentialManager options, meshbluConfig

app.post '/api/messages', meshbluAuthorizer, (req, res) ->
  proxyRequest = new ProxyRequestModel meshbluConfig, LittleBitsOptionsBuilder
  proxyRequest.sendMessage req.body, (error, message) =>
    debug 'sendMessage response', error, message
    return res.status(422).send(error.message) if error?

    res.status(201).send message

app.get '/api/authorize', (req, res) ->
  res.sendFile 'index.html', root: __dirname + '/public'

app.post '/api/callback', (req, res) ->
  credentialManager.findOrCreate req.session.userUuid, req.body.clientId, req.body.clientSecret, (error, result) =>
    return res.status(422).send(error.message) if error?

    if req.session.callbackUrl?
      callbackUrl = url.parse req.session.callbackUrl, true
      delete callbackUrl.search
      callbackUrl.query.uuid = result.uuid
      callbackUrl.query.creds_uuid = result.creds.uuid
      callbackUrl.query.creds_token = result.creds.token
      return res.redirect url.format(callbackUrl)

    res.status(201).send result

app.get '/', (req, res) ->
  res.status(422).send message: 'UUID is required'

app.get '/new/:uuid', (req, res) ->
  req.session.userUuid = req.params.uuid
  req.session.callbackUrl = req.query.callbackUrl
  debug 'callbackUrl', req.session.callbackUrl
  res.redirect '/api/authorize'

server = app.listen PORT, ->
  host = server.address().address
  port = server.address().port

  console.log "Server running on #{host}:#{port}"
