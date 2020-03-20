## What's new in this version

* Add unit test.  
* ^GBLOCKCOPY Usage instead Merge command (increase performance).  

# Global mover tool

The goal is moving a large global from a database to another while your application is running.  
When you use a GBLOKCOPY, you should stop your application (or a part of your application) to avoid writing into the copied global.  
Depending your global size and fragmentation, the copy can take while (a few seconds, minutes, hours ...).  

The easiest way is simply stop application, perform a GBLOCKCOPY and then apply a global mapping.  
Whatever the reason sometimes, you can't do that.  Stopping the application a few hours is just impossible (contractual up time reason, ...).  
When a GBLOKCOPY is not enough this tool could help you or just open your mind to other possibilities.  

## Typical use case

You have a large application with large databases\globals and you need to change the storage architecture.  

## How it work?

This is very simple, but there is a few steps : 

1. Before starting the copy, we perform a journal switch.
2. Copy the global from source database to target database.
3. When the copy is done, we check if there is any new global entries during the copy.  
   * We through journal files (3 pass) to look for any entries and perform the corresponding command (Set, Kill, ZKill) to the target database.  
   * After each pass a journal switch is performed in order to have the smallest possible journal file for the last pass.  
   * At the last pass, **the system is temporary switch to mode 10**.  We need to ensure there is no new global entries for a short time.
   * Setting up the global mapping.
   * Disable mode 10.
4. Everything is done, we perform a journal switch.  

# Limitations & Cautions

**Don't use with an active mirror!**  
After the copy, if a switch occurs to a node without the correct global mapping configuration, it would be disastrous.  

**Don't use with ECP!**  
Currently not tested with application server.  

**This is experimental, don't use without testing!**  
Under MIT License, use this tool at your own risk.  
Feel free to improve or modify as needed.  

**BACKUP your data before running**  
**Prepare a recovery plan related to this operation.**

**Run this operation during off-peak hours.**  


## Prerequisites
This needs to have git and docker installed.

# Installation 

1. Clone/git pull the repo into any local directory

```
$ git clone https://github.com/lscalese/isc-live-global-mover
```

2. Open the terminal in this directory and run:

```
$ docker-compose build
```

3. Run the IRIS container with your project:

```
$ docker-compose up -d
```

## Test installation

Open IRIS terminal:

```
docker exec -it isc-live-global-mover_iris_1 irissession iris
zn "IRISAPP"
Write ##class(Iris.Tools.Test.TestGlobalMover).SaySomeThing()
```

## Unit test

The unit test perform two operations : 

1. Write data into a global and move to another database.
2. Write initial data into a global and then start a job which write continuously in this global during the copy.  

See class Iris.Tools.Test.TestGlobalMover

Starting unit test : 
```
zn "IRISAPP"
Do ##class(Iris.Tools.Test.TestGlobalMover).StartUnitTest()
```

## Example

```
Set mover = ##class(Iris.Tools.LiveGlobalMover).%New()
Set mover.global = $lb("^YourGlobalToMoveD")
Set mover.dbSource = "irisapp"
Set mover.dbTarget = "targetdb"
Set tSc = mover.move()
```
Explore your data, check global mapping.  

Data aren't deleted by default from the source database.  
You should delete it manually or set mover.deleteSourceDataAfterMoving=1 for automatic deletion.

### Logs

Logs trace are stored in ^LiveGlobalMover.log.  Show log:  

```
Do ##class(Iris.Tools.LiveGlobalMover).outputLogToDevice($j)
```

Purge logs

```
Do ##class(Iris.Tools.LiveGlobalMover).purgeLog($j)
```

Or purge for all pid : 
```
Do ##class(Iris.Tools.LiveGlobalMover).purgeLog()
```

## Advice

* Expand the size of the target database in order to avoid expand during the copy.  


## Troubleshot

* Job error with journal restore or GBLOCKCOPY is due to a limite license with community edition.  
  Use an image base like intersystems/irishealth:2019.4.0.383.0 with a license to fix it.  

  

## How to start coding
This repository is ready to code in VSCode with ObjectScript plugin.
Install [VSCode](https://code.visualstudio.com/) and [ObjectScript](https://marketplace.visualstudio.com/items?itemName=daimor.vscode-objectscript) plugin and open the folder in VSCode.
Open /src/cls/PackageSample/ObjectScript.cls class and try to make changes - it will be compiled in running IRIS docker container.

Feel free to delete PackageSample folder and place your ObjectScript classes in a form
/src/cls/Package/Classname.cls

The script in Installer.cls will import everything you place under /src/cls into IRIS.

## What's inside the repo

# Dockerfile

The simplest dockerfile which starts IRIS and imports Installer.cls and then runs the Installer.setup method, which creates IRISAPP Namespace and imports ObjectScript code from /src folder into it.
Use the related docker-compose.yml to easily setup additional parametes like port number and where you map keys and host folders.
Use .env/ file to adjust the dockerfile being used in docker-compose.

# .vscode/settings.json

Settings file to let you immedietly code in VSCode with [VSCode ObjectScript plugin](https://marketplace.visualstudio.com/items?itemName=daimor.vscode-objectscript))

# .vscode/launch.json
Config file if you want to debug with VSCode ObjectScript

