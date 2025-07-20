<table class=docutils-wrap align=center width=95%>
   <caption>Arguments for `polyglot.import.file` and `polyglot.bind.file`</caption>
    <tr>
    <th><small>Name</small></th>
      <th><small>Required?</small></th>
      <th><small>Description</small></th>
      <th><small>Example</small></th>
    </tr>
    <tr>
        <td><code>file</code></td>
        <td>✅</td>
        <td class=wrap>Filename</td>
        <td>relative/path/to/file.py
        </td>
    </tr>
    <tr>
        <td><code>namespace</code></td>
        <td>✅</td>
        <td>Prefix used to find private target.<br/> Defaults to "self."</td>
        <td>prefix=.</td>
    </tr>
    <tr>
        <td><code>img</code></td>
        <td>✅</td>
        <td class=wrap>
            Image to use.
            <br/><i>Defaults to 1st positional-arg if kwargs not present.</i>
        </td>
        <td>img=...</td>
    </tr>
    <tr>
        <td><code>entrypoint</code></td>
        <td>❌</td>
        <td class=wrap>
            Interpreter to use.
            <br/>Defaults to bash.
        </td>
        <td>entrypoint=bash</td>
    </tr>
    <tr>
        <td><code>cmd</code></td>
        <td>❌</td>
        <td class=wrap>
            Arguments to pass to interpreter.
            <br/>Defaults to empty string.
            <br/>Filename is post-fixed to command.
        </td>
        <td>cmd=-x</td>
    </tr>
    <tr>
        <td><code>env</code></td>
        <td>❌</td>
        <td class=wrap>
            Variables to pass through to container.
            <br/>Defaults to value from environment.
        </td>
        <td>env='foo bar'</td>
    </tr>
</table>