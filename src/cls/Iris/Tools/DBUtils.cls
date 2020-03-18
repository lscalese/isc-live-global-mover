Class Iris.Tools.DBUtils
{

/// Return the default Data database for the given namespce.
ClassMethod getDefaultDBForNS(namespace As %String, ByRef sc As %Status) As %String
{
	Set ns = $namespace
	Zn "%SYS"
	Try{
		Set sc=##Class(Config.Namespaces).Get(namespace,.Properties)
		Zn ns
	}Catch(ex) {
		Zn ns
		Throw ex
	}
	Return:$$$ISERR(sc) ""
	Return Properties("Globals")
}

/// Return the DB Directory for the given Database name.
ClassMethod getDbDir(dbName As %String) As %String
{
	Set ns = $namespace, dbDir=""
	Try{
		Zn "%SYS"
		Set dbDir = ##class(Config.Databases).GetDirectory(dbName)
	}Catch(ex) {
		Zn ns
		Throw ex
	}
	Zn ns
	Return dbDir
}

/// Create the global mapping for the given global and the namespace (namespace property)
ClassMethod setGlobalMapping(globalName As %String, namespace As %String, dbTarget As %String) As %Status
{
	Set sc = $$$OK, ns = $namespace
	Set:$e(globalName,1)="^" globalName=$e(globalName,2,*)	; Remove the leading character ^
	ZN "%SYS"
	Try {
		Set Properties("Database")=dbTarget
		Set sc =##Class(Config.MapGlobals).Create(namespace,globalName,.Properties)
	}Catch(e) {
		Set sc = e.AsStatus()
	}
	ZN ns
	Return sc
}

ClassMethod syncGblockCopy(infile As %String, outfile As %String) As %Status
{
	Set tSc = $$$OK, successCopyFound = 0
	JOB ^GBLOCKCOPY:("%SYS"::infile:outfile):3
	If '$Test {
		Return $$$ERROR($$$GeneralError,"GBLOCKCOPY Job error.")
	}
	Set pid = $ZChild
	For  {
		; wait end of GBLOCKCOPY process
		Hang 2
		Quit:'##class(%SYS.ProcessQuery).%ExistsId(pid)
	}

	Set stream=##class(%Stream.FileCharacter).%New()
	Set tSc=stream.LinkToFile(outfile)
	Return:$$$ISERR(tSc) tSc
	While 'stream.AtEnd {
		Set line=stream.ReadLine()
		If line [ "Copy of data has completed" {
			Set successCopyFound = 1
			Quit
		}
	}
	Kill stream

	Set:'successCopyFound tSc = $$$ERROR($$$GeneralError,"Message ""Copy of data has completed "" is not found in output glblokcopy, check file : "_outfile)
	Return tSc
}

}
