function showLog()
{
    let logElement = document.getElementById('logText')
    let logText = logElement.innerText
    let logArray = []
    let log = ''

    logElement.parentNode.removeChild(logElement)

    if (logText.charAt(logText.length - 1) === '|')
    {
        logText = logText.substring(0, logText.length - 1)
    }

    logText = logText.split('|')

    for (let i = 0; i < logText.length; i+=2)
    {
        let logEntry = {}

        logEntry.start = logText[i]
        logEntry.end = logText[i + 1]

        logArray.push(logEntry)
     }

    console.log(logArray)

    for (let i = logArray.length - 1; i >= 0; i--)
    {
        let logEntry = logArray[i]

        log += logEntry.start

        if (logEntry.end)
        {
            log += '\n'
            log += logEntry.end
        }

        if (i > 0)
        {
            log += '\n\n'
        }
    }

    document.getElementById('logField').value = log
}

window.onload = showLog
