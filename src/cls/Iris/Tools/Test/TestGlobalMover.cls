Class Iris.Tools.Test.TestGlobalMover Extends %UnitTest.TestCase
{

Parameter TARGETDB = "targetdb";

Method OnBeforeAllTests() As %Status
{
    Do ..SomeThing()
    Return $$$OK
}

Method OnAfterAllTests() As %Status
{
    Return $$$OK
}

ClassMethod StartUnitTest()
{
    Set ns = $Namespace
    
    /// remove data and config due to a previous run rest.
    zn "%SYS"
    Do ##class(Config.MapGlobals).Delete(ns,"Global.ToMoveD")
    zn ns
    Do ..CleanTestData()
    Do ##class(%UnitTest.Manager).RunTest(,"/nodelete")
    Quit
}

/*Method TestMoveGlobal() As %Status
{
    Set tSc = $$$OK
    Try {
        Set timeOutGenData = 15
        Do $$$LogMessage($$$FormatText("Starting generate initial data ^Global.ToMoveD while %1 seconds.",timeOutGenData))
        $$$TOE(tSc,..GenerateData(timeOutGenData,$$$NO))
        Do $$$AssertStatusOK(tSc,$$$FormatText("Generate data while %1 sec.",timeOutGenData))
        Set tSc = ..MoveData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Global mover return a status: %1.",$SYSTEM.Status.GetOneErrorText(tSc)))
        Return:$$$ISERR(tSc) tSc
        Set tSc = ..CompareData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Check if data source and target are identical status : %1.",$SYSTEM.Status.GetOneErrorText(tSc)))
    } Catch (ex) {
        Set tSc = ex.AsStatus()
    }
    Return tSc
}*/
Method TestMoveGlobalWithConcurrentWrite() As %Status
{
    Set tSc = $$$OK
    Try {
        Set timeOutGenData = 15
        Do $$$LogMessage($$$FormatText("Starting generate initial data ^Global.ToMoveD while %1 seconds.",timeOutGenData))
        Set tSc = ..GenerateData(timeOutGenData,$$$NO) ; generate inital data
        Do $$$AssertStatusOK(tSc,$$$FormatText("Generate data while %1 sec.",timeOutGenData))
        Set timeOutGenData = 60
        Set start = $zh
        Do $$$LogMessage($$$FormatText("Starting a Job that generate data while global moving process.",timeOutGenData))
        Job ..GenerateData(timeOutGenData,$$$YES)::2   ; generate data while moving
        Set jobIsRunning = $Test
        Do $$$AssertEquals(jobIsRunning,1,"Job generate concurrent write : "_jobIsRunning)
        Do $$$LogMessage($$$FormatText("Starting global mover.",timeOutGenData))
        Set tSc = ..MoveData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Global mover return a status : %1",$System.Status.GetOneErrorText(tSc)))
        Hang:$d(^CacheTempGenData) (timeOutGenData+2)-($zh-start)
        Do $$$LogMessage($$$FormatText("Starting checking missing data.",timeOutGenData))
        Set tSc = ..CheckMissingData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Checking missing data a status %1.",$System.Status.GetOneErrorText(tSc)))
        Set ns = $Namespace
        zn "%SYS"
        Set existMapping = ##class(Config.MapGlobals).Exists(ns,"Global.ToMoveD")
        zn ns
        Do $$$AssertEquals(existMapping,1,$$$FormatText("Global mapping in namespace %1 for global %2 has been added ",$Namespace,))
    } Catch (ex) {
        Set tSc = ex.AsStatus()
    }
    Do $$$AssertStatusOK(tSc,$$$FormatText("Status %1.",$System.Status.GetOneErrorText(tSc)))
    Return tSc
}

Method MoveData() As %Status
{
    #dim mover As Iris.Tools.LiveGlobalMover
    Set mover = ##class(Iris.Tools.LiveGlobalMover).%New()
	Set mover.global = $lb("^Global.ToMoveD")
	Set mover.dbSource = ##class(Iris.Tools.DBUtils).getDefaultDBForNS($namespace,.tSc)
    If $$$ISERR(tSc) $$$ThrowStatus(tSc)
	Set mover.dbTarget = ..#TARGETDB
	Set mover.verbose = 1
	Set mover.disableJrn = 1
	Set mover.deleteSourceDataAfterMoving=0
    Set tSc = mover.prepare()
    Return:$$$ISERR(tSc) tSc
    Set tSc = mover.validate()
    Return:$$$ISERR(tSc) tSc
    Set tSc = mover.move()
    Return:$$$ISERR(tSc) tSc
    hang 3
    Set sourceDatabase = ##class(Iris.Tools.DBUtils).getDefaultDBForNS($namespace),
        sDbDir = ##class(Iris.Tools.DBUtils).getDbDir(sourceDatabase),
        tDbDir = ##class(Iris.Tools.DBUtils).getDbDir(..#TARGETDB),
        firstKeyDbTarget = $Order(^["^^"_tDbDir]Global.ToMoveD(""),1),
        lastKeyDbSource = $Order(^["^^"_sDbDir]Global.ToMoveD(""),-1),
        firstKeyDbSource = $Order(^["^^"_sDbDir]Global.ToMoveD(""),1),
        lastKeyDbTarget = $Order(^["^^"_tDbDir]Global.ToMoveD(""),-1),
        cntSource = ^["^^"_sDbDir]Global.ToMoveD,
        cntTarget = ^["^^"_tDbDir]Global.ToMoveD
    Do $$$LogMessage($$$FormatText("First key db source %1",firstKeyDbSource))
    Do $$$LogMessage($$$FormatText("Last key db source %1",lastKeyDbSource))
    Do $$$LogMessage($$$FormatText("First key db target %1",firstKeyDbTarget))
    Do $$$LogMessage($$$FormatText("Last key db target %1",lastKeyDbTarget))
    Do $$$LogMessage($$$FormatText("Counter db source %1",cntSource))
    Do $$$LogMessage($$$FormatText("Counter db target %1",cntTarget))
    Return tSc
}

ClassMethod CompareData() As %Status
{
    Set tSc = $$$OK,
        sourceDatabase = ##class(Iris.Tools.DBUtils).getDefaultDBForNS($namespace),
        sDbDir = ##class(Iris.Tools.DBUtils).getDbDir(sourceDatabase),
        tDbDir = ##class(Iris.Tools.DBUtils).getDbDir(..#TARGETDB)
    
    Set key = ""
    For  {
        Set key = $Order(^["^^"_sDbDir]Global.ToMoveD(key),1,sValue)
        Quit:key=""
        If '$Data(^["^^"_tDbDir]Global.ToMoveD(key),tValue) {
            Set tSc = $$$ERROR(5001,"Data not found in target database.")
            Quit
        } ElseIf $Listget(sValue,1)'=$Listget(tValue,1) {
            Set tSc = $$$ERROR(5001,"Data missmatch.")
            Quit
        }
    }

    Return tSc
}

/// Records are added with a $increment key.<br/>
/// All keys must be striclty continuous 1,2,3....end.<br/>
/// This method check if there is a missing key Global.ToMoveD
Method CheckMissingData() As %Status
{
    
    Set tSc = $$$OK,
        tDbDir = ##class(Iris.Tools.DBUtils).getDbDir(..#TARGETDB),
        key = ""
    For  {
        Set prev = +key,
            key = $Order(^["^^"_tDbDir]Global.ToMoveD(key))
        Quit:key=""
        If '(key=(prev + 1)) {
            Set tSc = $$$ERROR(5001,$$$FormatText("Missing key(s) between %1 and %2",prev,key))
            Quit
        }
    }
    Return tSc
}

/// Generate record in ^Global.ToMoveD global <br/>
ClassMethod GenerateData(timeout As %Integer = 30, randomHang As %Boolean = 1) As %Status
{
    Set end = $zh + timeout, cnt = 0, total = 0, max = 15000, maxBeforeHang = $Random(max) + 1, ^CacheTempGenData=1
    
    For  {
        Set ^Global.ToMoveD($Increment(^Global.ToMoveD))=$Listbuild(^Global.ToMoveD),
            cnt=$Increment(cnt)
        If cnt =  maxBeforeHang {
            Set total = (total + cnt), cnt = 0, maxBeforeHang = $Random(max) + 1    ; setup for random hang
            hang:randomHang 1  ; reduce the IO usage.
            Quit:$zh>end ; check timeout ...
        }
    }
    kill ^CacheTempGenData
	Return $$$OK
}

ClassMethod CleanTestData() As %Status
{
    Set tDbDir = ##class(Iris.Tools.DBUtils).getDbDir(..#TARGETDB),
        sourceDatabase = ##class(Iris.Tools.DBUtils).getDefaultDBForNS($namespace),
        sDbDir = ##class(Iris.Tools.DBUtils).getDbDir(sourceDatabase)
    Kill ^["^^"_tDbDir]Global.ToMoveD, ^["^^"_sDbDir]Global.ToMoveD
    Return $$$OK
}

ClassMethod SomeThing() As %String
{
    Set arr(0)="Ok, I check steam special offers ..."
    Set arr(1)="I have a coffee."
    Return arr($r($o(arr(""),-1)))
}

ClassMethod SetUnitTestRoot(directory As %String) As %Status
{
    Set ^UnitTestRoot=##class(%File).NormalizeDirectory(directory)
    Return $$$OK
}

}
