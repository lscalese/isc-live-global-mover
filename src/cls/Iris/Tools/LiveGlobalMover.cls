/// The goal is moving data from a database to another database without stopping application.<br/>
/// Globals will be copied to the target database then a global mapping is setting up.<br/><br/>
/// <b>Usage :</b> <br/><br/>
/// <code>
/// Set mover = ##class(Iris.Tools.LiveGlobalMover).%New()<br/>
/// Set mover.global = $lb("^YourGlobalToMove")<br/>
/// Set mover.dbSource = "YOURSOURCEDB"<br/>
/// Set mover.dbTarget = "YOURTARGETDB"<br/>
/// Set sc = mover.move()<br/>
/// </code>
/// <br/>Requirements : <br/>
/// <ul><li>Journaling must be active.</li>
/// <li>Journal Freeze On Error must be SET to 1.</li>
/// </ul><br/>
/// <b>Warning</b><br/>
/// <b>This is experimental features, Use at your own risk.</b><br/>
/// <b>Don't use with an active mirror.</b>.<br/>
/// <b>Don't use with ECP (Never tested)</b>.<br/>
Class Iris.Tools.LiveGlobalMover Extends %RegisteredObject
{

/// Number of scan journal file.
Parameter NBPASS = 5;

/// A listbuild contain all globals to move. ex: $lb("^LiveGlobalMover.Test")
Property global As %List;

/// Internal use : contain the current global to move.
Property currentGlobal As %String [ Private ];

/// Name of the source Database .<br/>
/// All globals define in the property <b>global</b> must exist in <b>dbSource</b>.
Property dbSource As %String;

/// Name of the target Database where all globals define in <b>global</b> list will be moved.
Property dbTarget As %String;

/// Namespace used for global mapping setting.<br/>
/// Default is the current namespace.<br/>
Property namespace As %String [ InitialExpression = {$namespace} ];

/// Perform a DISABLE^%NOJRN before copy the globals.
Property disableJrn As %Boolean [ InitialExpression = 0 ];

/// contain the full path of dbSource
Property dbSourceDir As %String [ Private ];

/// contain the full path of dbTarget
Property dbTargetDir As %String [ Private ];

/// When the copy's started, a journal switch is done.<br/>
/// firstJrnToReload contain the path of the first journal to reload after the copy.
Property firstJrnToReload As %String(MAXLEN = 256);

Property currentJournal As %SYS.Journal.File [ Private ];

/// If true, Logs are also written to the current device.
Property verbose As %Boolean [ InitialExpression = 0 ];

Property lastJrnAddress As %String [ Private ];

Property deleteSourceDataAfterMoving As %Boolean [ InitialExpression = 0 ];

/// For internal use.
Property secureDeleteFlags As %List [ InitialExpression = {$lb(0,0)}, MultiDimensional, Private ];

/// Called by move method.<br/>
/// Calculate dbSourceDir and dbTargetDir (private property) <br/>
Method prepare() As %Status
{
	
	Set sc = $$$OK
	Try {
		Do ..log("[*] Prepare Global mover ...")
		Do ..log($c(9)_"dbSourceDir for "_..dbSource_"...")
		$$$TOE(sc,..dbSourceDirSet(..dbSource))
		Do ..log($c(9)_"dbSourceDir for "_..dbSource_" is set with value "_..dbSourceDir)
		Do ..log($c(9)_"dbTargetDir for "_..dbTarget_"...")
		$$$TOE(sc,..dbTargetDirSet(..dbTarget))
		Do ..log($c(9)_"dbTargetDir for "_..dbTarget_" is set with value "_..dbTargetDir)
	} Catch (ex) {
		Set sc = ex.AsStatus()
	}
	Return sc
}

/// Many checks for prevent error while the moving  ...<br/>
/// Called by move method.<br/>
/// You can call method prepare() and then validate() if you want validate before starting the moving.<br/>
/// The method move() always call prepare() and validate
Method validate() As %Status
{
	Set sc = $$$OK,ns=$namespace
	Return:..dbTargetDir=..dbSourceDir $$$ERROR(5001,"Target DB and Source DB must not the same")
	Return:..dbSourceDir="" $$$ERROR(5001,"dbSourceDir is not set.")
	Return:..dbTargetDir="" $$$ERROR(5001,"dbTargetDiris not set.")
	Return:'##class(%SYS.Namespace).Exists(..namespace) $$$ERROR(5001,$$$FormatText("Namespace %1 does not exist.",..namespace))
	Set ptr = 0
	While $Listnext(..global,ptr,value) {
		Set ..currentGlobal = value
		Zn "%SYS"
		If ##Class(Config.MapGlobals).Exists(..namespace,value){
			Zn ns
			Return $$$ERROR($$$GeneralError,$$$FormatText("Conflict global %1 is already mapped to %2.",..currentGlobal,..namespace))
		}
		Zn ns
		Set gbl = ##class(%Library.GlobalEdit).Open(..currentGlobal,..dbSourceDir,,,.sc)
		Set:$$$ISERR(sc) sc = $$$ERROR(5001,$$$FormatText("Global %1 does not exist in Database source %2",..currentGlobal,..dbSourceDir))
		Return:$$$ISERR(sc) sc
		Set sc = ##class(%Library.Routine).CheckSyntax(..getMergeLineForCurrentGbl())
		Return:$$$ISERR(sc) sc
	}
	Set ..currentGlobal=""
	
	;The moving will work only if journaling is active.  Otherwise, you must not use it.
	
	Set jrnState = ##class(%SYS.Journal.System).GetState() ; 0 = Enabled - 4 = Paused (during journal file switch)
	Return:'(jrnState=4||jrnState=0) $$$ERROR($$$GeneralError,$$$FormatText("Journaling is not active state %1",jrnState))
	
	Set ns = $namespace
	Zn "%SYS"
	Try{
		Set sc = ##class(Config.Journal).Get(.jrnProperties)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		If +jrnProperties("FreezeOnError")=0 {
			; This process can be used for moving large globals, It can take a while ...
			; What would happen if a journal error occurs while the moving process without freeze on error ...
			; You can't use this process safely.  Operation aborted...
			Zn ns
			Return $$$ERROR($$$GeneralError,$$$FormatText("FreezeOnError is not SET. Operation aborted."))
		}
		Kill jrnProperties
		
		Set dbs = ##class(SYS.Database).%OpenId(..dbSourceDir,,.sc)
		If $$$ISERR(sc) $$$ThrowStatus(sc)
		Zn ns
		Return:dbs.GlobalJournalState'=3 $$$ERROR($$$GeneralError,$$$FormatText("Journal is not active on %1 database, GlobalMover.OnLineMover can't guarantee data integrity. Operation aborted.",..dbSource))
		; Return:dbs.Mirrored $$$ERROR($$$GeneralError,"Currently unsupported for mirrored database.")
	} Catch (ex) {
		Zn ns
		Throw ex
	}
	Return sc
}

Method move() As %Status
{
	Set sc = $$$OK
	Lock +^LiveGlobalMover:2
	Return:'$Test $$$ERROR($$$GeneralError,"A LiveGlobalMover is already running, only one global moving at a time permitted")
	Try{
		
		$$$TOE(sc,..prepare())
		
		Do ..log("[*] Validate parameters...")
		$$$TOE(sc,..validate())
		
		Do ..log("[*] Switch journal...")
		$$$TOE(sc,..switchJournal())
		
		Do ..log($$$FormatText("[*] Copy global list to %1 started ...",..dbTargetDir))
		$$$TOE(sc,..copyGblList())
		
		Do ..log("[*] Loading journal ...")
		$$$TOE(sc,..loadDataFromJournal())
		
		If (..deleteSourceDataAfterMoving) {
			$$$TOE(sc,..deleteSourceData())
		}
	}Catch(ex) {
		Set sc = ex.AsStatus()
		Do ..log("ERROR "_$SYSTEM.Status.GetErrorText(sc))
	}
	Lock -^LiveGlobalMover
	Return sc
}

Method loadDataFromJournal() As %Status [ Private ]
{
	Set sc = $$$OK
	Set ..currentJournal = ##class(%SYS.Journal.File).%New()
	Set currentJrnFName = ..firstJrnToReload
	$$$TOE(sc,..currentJournal.Open(currentJrnFName))
	Set nbPass = ..#NBPASS
	Set:nbPass<3 nbPass = 3 ; force minimum 3 pass.
	For i=1:1:(nbPass-1) {
		Do ..log($c(9)_$$$FormatText("Journal pass %1 of %2, file %3, start after address %4",i,nbPass,..currentJournal.Name,..lastJrnAddress))
		$$$TOE(sc,..throughJournalRecord(..lastJrnAddress))
        Set newFName="", sc = ##class(%SYS.Journal.System).RollToNextFile(1,.newFName)   ; force switch to have a small last journal file to reload.
        Hang 2
	}
	Do ..log($c(9)_$$$FormatText("Journal pass %1 of %2, file %3, start after address %4 (last pass)",nbPass,nbPass,..currentJournal.Name,..lastJrnAddress))
	$$$TOE(sc,..lastPassProcess())
	Set $li(..secureDeleteFlags,2)=1
	Return sc
}

Method lastPassProcess() As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Do ..log($c(9,9)_"Switch mode 10")
		$$$TOE(sc,##class(Iris.Tools.Freeze).EnableSetSwitch10()) ; probably some changes here for ECP support.
		Set frzStart = $zh
		Do:..disableJrn DISABLE^%NOJRN
		$$$TOE(sc,..throughJournalRecord(..lastJrnAddress)) ; a last pass on journal file from last address treated.
		Do:..disableJrn ENABLE^%NOJRN
		Do ..log($c(9,9)_"Set global mapping...")
		$$$TOE(sc,..setAllGlobalMapping()) 
		Do ..log($c(9,9)_$$$FormatText("Time elapsed since freezeSystem %1 sec.",$j(($zh-frzStart),11,6)))
		Do ..log($c(9,9)_"Disable mode 10")
		Set newFName=""
		Do ##class(%SYS.Journal.System).RollToNextFile(1,.newFName)
		Set sc = ##class(Iris.Tools.Freeze).DisableSetSwitch10()	; probably some changes here for ECP support.
	}Catch(ex) {
		Set sc = ex.AsStatus()
		Do ##class(%SYS.System).WriteToConsoleLog("LiveGlobalMover : error while last pass processing "_$SYSTEM.Status.GetErrorText(sc),0,2)
		Do ##class(Iris.Tools.Freeze).DisableSetSwitch10()
	}
	Do:$Get(newFName)'="" ..log("[*] Journal roll to next file "_newFName)
	Return sc
}

Method throughJournalRecord(startAfterAddress As %Integer = "") As %Status [ Private ]
{
	#dim currentRecord As %SYS.Journal.SetKillRecord
	Set sc = $$$OK
	Set currentJrnFName = ..currentJournal.Name
	Set currentRecord = $s(startAfterAddress="":..currentJournal.FirstRecord,1:..currentJournal.GetRecordAfter(startAfterAddress))
	Set lowerDBSourceDir =$zcvt(..dbSourceDir,"l")
	For  {
		If '$isobject(currentRecord) {
			Quit:(currentJrnFName=##class(%SYS.Journal.System).GetCurrentFileName())
			$$$TOE(sc,##class(%SYS.Journal.File).GetNext(currentJrnFName,.nextFname))
			$$$TOE(sc,..currentJournal.Open(nextFname))
			Set currentJrnFName = nextFname
			Set ..lastJrnAddress=""
			Do ..log($c(9,9)_$$$FormatText("Loading Journal %1 ...",currentJrnFName))
			Set currentRecord=..currentJournal.FirstRecord
			Quit:'$isobject(currentRecord)
		}
		
		If (currentRecord.%ClassName(0)="SetKillRecord")||(currentRecord.%ClassName(0)="BitSetRecord")
				&&($lf(..global,$qs(currentRecord.GlobalNode,0))>0)
				&&($zcvt(currentRecord.DatabaseName,"l")=lowerDBSourceDir) {
			Set newRefGbl = "^[""^^"_..dbTargetDir_"""]"_$e(currentRecord.GlobalNode,2,*)
			If (currentRecord.TypeName="SET") {
				Set @newRefGbl=currentRecord.NewValue
			}ElseIf (currentRecord.TypeName="KILL"){
				Kill @newRefGbl
			}ElseIf (currentRecord.TypeName="ZKILL") {
				ZKill @newRefGbl
			}ElseIf (currentRecord.TypeName="KILLdes"){
			 	Kill @newRefGbl
			}
		}
		Set ..lastJrnAddress =currentRecord.Address
		Set currentRecord = currentRecord.Next
	}
	Return sc
}

Method switchJournal() As %Status [ Private ]
{
	Set newFName = ""
	Set sc = ##class(%SYS.Journal.System).RollToNextFile(1,.newFName)
	Set ..firstJrnToReload=newFName
	Return sc
}

Method copyGblList() As %Status [ Private ]
{
	Set sc = $$$OK
	Set ptr = 0
	While $listnext(..global,ptr,gbl) {
		Set ..currentGlobal = gbl
		Do ..log($c(9)_$$$FormatText("Starting Copy %1",..currentGlobal))
		$$$TOE(sc,..copyCurrentGlobal())
		Do ..log($c(9)_$$$FormatText("Copy %1 OK",..currentGlobal))
	}
	Set ..currentGlobal=""
	Set $li(..secureDeleteFlags,1)=1
	Return sc
}

Method deleteSourceData() As %Status [ Private ]
{
	Return:$lts(..secureDeleteFlags,",")'="1,1" $$$ERROR($$$GeneralError,"secureDeleteFlags reveal a problem, data are not deleted.")
	Set sc = $$$OK
	Set ptr = 0
	While $listnext(..global,ptr,gbl) {
		Do ..log($c(9)_$$$FormatText("Delete global %1 from source database",gbl))
		Do:..disableJrn DISABLE^%NOJRN
		Kill @("^[""^^"_..dbSourceDir_"""]"_$e(gbl,2,*))
		Do:..disableJrn ENABLE^%NOJRN
	}
	Return sc
}

/// Perfom a Merge command for the current global to move.
Method copyCurrentGlobal() As %Status [ Private ]
{
	Set sc = $$$OK
	Try {
		Do:..disableJrn DISABLE^%NOJRN
        Set mergeLine = ..getMergeLineForCurrentGbl()
        Do ..log(mergeLine)
		Xecute mergeLine	; I'll try to use GLBOCKCOPY instead Merge in a further version.
		Do:..disableJrn ENABLE^%NOJRN
	}Catch(ex) {
		Do:..disableJrn ENABLE^%NOJRN
		Throw ex
	}
	Return $$$OK
}

Method getMergeLineForCurrentGbl() As %String [ Private ]
{
	Return " Merge ^[""^^"_..dbTargetDir_"""]"_$e(..currentGlobal,2,*)_"="_"^[""^^"_..dbSourceDir_"""]"_$e(..currentGlobal,2,*)
}

Method dbSourceDirSet(dbSource As %String = {..dbSource}) As %Status [ Private ]
{
	Set dbSourceDir = ##class(Iris.Tools.DBUtils).getDbDir(.dbSource)
	Set i%dbSourceDir=dbSourceDir
	Return $$$OK
}

Method dbTargetDirSet(dbTarget As %String = {..dbTarget}) As %Status [ Private ]
{
	Set dbTargetDir = ##class(Iris.Tools.DBUtils).getDbDir(.dbTarget)
	Set i%dbTargetDir=dbTargetDir
	Return $$$OK
}

/// Log a message in  ^LiveGlobalMover.log global.<br/>
/// The first key is the process id ^LiveGlobalMover.log($j)<br/>
/// If verbose property is set to 1, the log message is also written to the current device.<br/>
/// 
Method log(message As %String) As %Status
{
	Set logMsg = $Zdt($h,3,1)_" "_message,
	    ^LiveGlobalMover.log($i(^LiveGlobalMover.log($j)))=logMsg
	Write:..verbose !,logMsg
	Return $$$OK
}

ClassMethod purgeLog(pid As %String = "") As %Status
{
	If (pid'="") {
		Kill ^LiveGlobalMover.log(pid)
	}Else{
		Kill ^LiveGlobalMover.log
	}
	Return $$$OK
}

/// Create all globals mapping the list of globals in "global" property.
Method setAllGlobalMapping() As %Status [ Private ]
{
	Set ptr = 0
	While ($Listnext(..global,ptr,currentGbl)) {
		$$$TOE(sc,##class(Iris.Tools.DBUtils).setGlobalMapping(currentGbl,..namespace,..dbTarget))
	}
	Return $$$OK
}

/// Getter for dbSourceDir property.
Method dbSourceDirGet() As %String
{
	Return i%dbSourceDir
}

/// Getter for dbTargetDir property.
Method dbTargetDirGet() As %String
{
	Return i%dbTargetDir
}

Method %OnNew() As %Status [ Private, ServerOnly = 1 ]
{
	If ($SYSTEM.Version.SystemMode()="LIVE") {	;  security.
		$$$ThrowStatus($$$ERROR($$$GeneralError,"Operation not permitted on a live system!"))
	}
	Quit $$$OK
}

}
