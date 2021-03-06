require 'colors'
program = require 'commander'
path = require 'path'
log = require('printit')
    prefix: 'cozy-dev   '
inquirer = require 'inquirer'
async = require 'async'

Client = require("request-json").JsonClient
Client::configure = (url, password, callback) ->
    @host = url
    @post "login", password: password, (err, res) ->
        if err? or res?.statusCode isnt 200
            log.error "Cannot get authenticated"
        else
            callback()

client = new Client ""

RepoManager = require('./repository').RepoManager
repoManager = new RepoManager()
ApplicationManager = new require('./application').ApplicationManager
appManager = new ApplicationManager()
ProjectManager = new require('./project').ProjectManager
projectManager = new ProjectManager()
VagrantManager = new require('./vagrant').VagrantManager
vagrantManager = new VagrantManager()

helpers = require './helpers'

appData = require '../package.json'

### Tasks ###
program
.version appData.version
.option '-u, --url <url>', 'Set url where lives your Cozy Cloud, default ' + \
        'to localhost'
.option '-g, --github <github>', 'Link new project to github account'
.option '-c, --coffee', 'Create app template with coffee script files ' + \
        'instead of JS files'

program
.command "install <app> <repo>"
.description "Install given application from its repository"
.action (app, repo) ->
    async.waterfall [
        helpers.promptPassword 'Cozy password'
        (password, cb) ->
            appManager.installApp app, program.url, repo, password, cb
    ], ->
        log.info "#{app} successfully installed.".green

program
.command "uninstall <app>"
.description "Uninstall given application"
.action (app) ->
    async.waterfall [
        helpers.promptPassword 'Cozy password'
        (password, cb) -> appManager.uninstallApp app, program.url, password, cb
    ], ->
        log.info "#{app} successfully uninstalled.".green

program
.command "update <app>"
.description "Update application (git + npm install) and restart it " + \
             "through haibu"
.action (app) ->
    async.waterfall [
        helpers.promptPassword 'Cozy password'
        (password, cb) ->
            appManager.updateApp app, program.url, password, cb
    ], ->
        log.info "#{app} successfully updated.".green

program
.command "status"
.description "Give current state of cozy platform applications"
.action ->
    async.waterfall [
        helpers.promptPassword 'Cozy password'
        (password, cb) -> appManager.checkStatus program.url, password, cb
    ], ->
        log.info "All apps have been checked.".green

program
.command "new <appname>"
.description "Create a new app suited to be deployed on a Cozy Cloud."
.action (appname) ->
    user = program.github
    isCoffee = program.coffee

    if user?
        log.info "Create repo #{appname} for user #{user}..."
        async.waterfall [
            helpers.promptPassword 'Github password'

            (password, cb) ->
                options =
                    type: 'input'
                    name: 'url'
                    message: 'Cozy URL'
                inquirer.prompt options, (answers) ->
                    cb null, password, answers.url

            (password, url, cb) ->
                projectManager.newProject(appname, isCoffee, url, user, \
                                         password, cb)

        ], ->
            log.info "Project creation finished.".green
            process.exit 0
    else
        log.info "Create project folder: #{appname}"
        repoManager.createLocalRepo appname, isCoffee, ->
            log.info "Project creation finished.".green

program
.command "deploy"
.description "Push code and deploy app located in current directory " + \
             "to Cozy Cloud url configured in configuration file."
.action ->
    config = require path.join(process.cwd(), ".cozy_conf.json")

    async.waterfall [
        helpers.promptPassword 'Cozy password'

        (password, cb) ->
            projectManager.deploy config, password, cb
    ], ->
        log.info "#{config.cozy.appName} successfully deployed.".green

program
.command "vm:init"
.description "Initialize the current folder to host a virtual machine " + \
             "with Vagrant. This will download the base box file."
.action ->
    log.info "Initializing the virtual machine in the folder..." + \
             "this may take a while."

    async.series [
        (cb) -> vagrantManager.checkIfVagrantIsInstalled cb
        (cb) -> vagrantManager.vagrantBoxAdd cb
        (cb) -> vagrantManager.vagrantInit cb
    ], ->
        msg = "The virtual machine has been successfully initialized."
        log.info msg.green

program
.command "vm:start"
.description "Starts the virtual machine with Vagrant."
.action ->
    async.series [
        (cb) -> vagrantManager.checkIfVagrantIsInstalled cb
        (cb) ->
            log.info "Starting the virtual machine...this may take a while."
            vagrantManager.vagrantUp (code) -> cb null, code
    ], (err, results) ->
        [_, code] = results

        if code is 0
            msg = "The virtual machine has been successfully started. " + \
                  "You can check everything is working by running cozy " + \
                  "vm:status."
            log.info msg.green
        else
            msg = "An error occurred while your VMs was starting."
            log.error msg.red

haltOption = "Properly stop the virtual machine instead of simply " + \
             "suspending its execution"
program
.command "vm:stop"
.option "-H, --halt", haltOption
.description "Stops the Virtual machine with Vagrant."
.action (args) ->
    option = args.halt or null
    if option? and option
        caller = vagrantManager.vagrantHalt
    else
        caller = vagrantManager.vagrantSuspend

    async.series [
        (cb) -> vagrantManager.checkIfVagrantIsInstalled cb
        (cb) ->
            log.info "Stopping the virtual machine...this may take a while."
            caller (code) -> cb null, code
    ], (err, results) ->
        [_, code] = results

        if code is 0
            msg = "The virtual machine has been successfully stopped."
            log.info msg.green
        else
            msg = "An error occurred while your VMs was shutting down."
            log.error msg.red
program
.command "vm:status"
.description "Tells which services of the VM are running and accessible."
.action ->
    async.series [
        (cb) -> vagrantManager.checkIfVagrantIsInstalled cb
        (cb) -> vagrantManager.virtualMachineStatus (code) -> cb null, code
    ], (err, results) ->
        [_, code] = results

        if code is 0
            log.info "All the core services are up and running.".green
        else
            log.error "One or more services are not running.".red

program
.command "vm:update"
.description "Updates the virtual machine with the latest version of " + \
             "the cozy PaaS and core applications"
.action ->
    async.series [
        (cb) -> vagrantManager.checkIfVagrantIsInstalled cb
        (cb) -> vagrantManager.update (code) -> cb null, code
    ], (err, results) ->
        [_, code] = results

        if code is 0
            log.info "VM updated.".green
        else
            log.error "An error occurred while updating the VM".red

program
.command "vm:destroy"
.description "Destroy the virtual machine. Data will be lost."
.action ->
    confirmMessage = "You are about to remove the virtual machine from " + \
                     "your computer. All data will be lost and a new " + \
                     "import will be required if you want to use the " + \
                     "VM again"

    async.waterfall [
        (cb) ->
            options =
                type: 'confirm'
                name: 'hasConfirm'
                message: confirmMessage
                default: true
            inquirer.prompt options, (answers) -> cb null, answers.hasConfirm

        (hasConfirm, cb) ->
            if hasConfirm
                vagrantManager.vagrantBoxDestroy cb
            else cb()
    ], ->
        msg = "The box has been successfully destroyed. Use " + \
                "cozy vm:init to be able to use the VM again."
        log.info msg.green
        process.exit()

program
.command "*"
.description "Display error message for an unknown command."
.action ->
    log.error 'Unknown command, run "cozy --help" to know the list of ' + \
              'available commands.'

program.parse process.argv
