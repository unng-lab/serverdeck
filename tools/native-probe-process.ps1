function Close-NativeFixtureChild {
    param([object]$Child, [bool]$Started)
    try {
        if ($Started -and -not $Child.HasExited) {
            $Child.Kill()
            if (-not $Child.WaitForExit(10000)) { throw 'Owned native probe cleanup incomplete.' }
        }
    } finally {
        $Child.Dispose()
    }
}
