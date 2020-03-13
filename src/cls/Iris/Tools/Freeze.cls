Class Iris.Tools.Freeze
{

/// Freeze system -> switch to mode 10.
ClassMethod EnableSetSwitch10() As %Status
{
	Set ns = $namespace, sc = $$$OK
	Zn "%SYS"
	Try {
		Set res=$SYSTEM.Util.GetSwitch(10)
		If +res {
			$$$ThrowStatus($$$ERROR($$$GeneralError,"System already in mode 10"))
		}
		Do $SYSTEM.Util.SetSwitch(10,1)
		Do ##class(%SYS.System).WriteToConsoleLog("Switch mode 10 successful PID: "_$JOB)
		Zn ns
	}Catch(ex) {
		Zn ns
		Set sc = ex.AsStatus()
	}
	Return sc
}

/// Restore system state<br/>
/// Disable mode 10.
ClassMethod DisableSetSwitch10() As %Status
{
	Set ns = $namespace, sc = $$$OK
	Zn "%SYS"
	Try{
		Set sw=$SYSTEM.Util.GetSwitch(10)
		If +$Piece(sw,",",2)=+$Job {	; Check if the SetSwitch has been done by this job.
			Do $SYSTEM.Util.SetSwitch(10,0)
			Do ##class(%SYS.System).WriteToConsoleLog("Switch mode 10 disabled.  PID: "_$JOB)
		}
		;Do:'$$CURRENT^%NOJRN() ENABLE^%NOJRN
		Zn ns
	}Catch(ex) {
		Zn ns
		Set sc = ex.AsStatus()
		Do ##class(%SYS.System).WriteToConsoleLog("Disable mode 10 error "_$SYSTEM.Status.GetErrorText(sc),0,3)
		Throw ex
	}
	Return sc
}

}
