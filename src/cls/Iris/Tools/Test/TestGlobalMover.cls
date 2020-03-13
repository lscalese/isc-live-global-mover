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
    Do ..CleanTestData()
	Return $$$OK
}

Method TestMoveGlobal() As %Status
{
    Set tSc = $$$OK
    Try {
        $$$TOE(tSc,..GenerateData(15,$$$NO))
        Set tSc = ..MoveData()
        Do $$$AssertStatusOK(tSc,"Global mover return a status OK.")
        Return:$$$ISERR(tSc) tSc
        Set tSc = ..CompareData()
        Do $$$AssertStatusOK(tSc,"Check if data source and target are identical.")
    } Catch (ex) {
        Set tSc = ex.AsStatus()
    }
    Return tSc
}

Method TestMoveGlobalWithConcurrentWrite() As %Status
{
    Set tSc = $$$OK
    Try {
        Set timeOutGenData = 30
        Do $$$LogMessage($$$FormatText("Starting generate initial data ^Global.ToMoveD while %1 seconds.",timeOutGenData))
        Set tSc = ..GenerateData(timeOutGenData,$$$NO) ; generate inital data
        Do $$$AssertStatusOK(tSc,$$$FormatText("Generate data while %1 sec.",timeOutGenData))

        Set start = $zh
        Do $$$LogMessage($$$FormatText("Starting a Job that generate data while global moving process.",timeOutGenData))
        Job ..GenerateData(30,$$$YES)   ; generate data while moving
        Do $$$LogMessage($$$FormatText("Starting global mover.",timeOutGenData))
        Set tSc = ..MoveData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Global mover return a status : %1",$System.Status.GetOneErrorText(tSc)))
        Hang:$d(^CacheTempGenData) (timeOutGenData+2)-($zh-start)
        Do $$$LogMessage($$$FormatText("Starting checking missing data.",timeOutGenData))
        Set tSc = ..CheckMissingData()
        Do $$$AssertStatusOK(tSc,$$$FormatText("Global mover return a status %1.",$System.Status.GetOneErrorText(tSc)))
    } Catch (ex) {
        Set tSc = ex.AsStatus()
    }
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
    Return mover.move()
}

Method CompareData() As %Status
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

Method CheckMissingData() As %Status
{
    ;Date are added with a $increment key.
    ;all keys must be striclty continuous 1,2,3....end.
    Set tSc = $$$OK
    Set key = ""
    For  {
        Set prev = +key
        Set key = $Order(^["^^"_tDbDir]Global.ToMoveD(key))
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
    Set end = $zh + timeout, cnt = 0, total = 0, max = 10000, maxBeforeHang = $Random(max) + 1, ^CacheTempGenData=1
    
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

Method CleanTestData() As %Status
{
    /// todo ... Hahahah
    Return $$$OK
}

ClassMethod SomeThing() As %String
{
    Return "Ok, I check steam special offers ..."
}

ClassMethod SetUnitTestRoot(directory As %String) As %Status
{
    Set ^UnitTestRoot=##class(%File).NormalizeDirectory(directory)
    Return $$$OK
}

}
