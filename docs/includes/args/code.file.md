<table class=docutils-wrap align=center width=95%>
   <caption>Arguments for a file-sourced <code>code</code> object</caption>
    <tr>
    <th><small>Name</small></th>
      <th><small>Required?</small></th>
      <th><small>Description</small></th>
      <th><small>Example</small></th>
    </tr>
    <tr>
        <td><code>file</code></td>
        <td>✅</td>
        <td class=wrap>File whose content becomes the code-object body.</td>
        <td>relative/path/to/file.py
        </td>
    </tr>
    <tr>
        <td><code>def</code></td>
        <td>—</td>
        <td class=wrap>Name of the target created.<br/>In CMK-lang this is the code-object name (<code>code NAME(..)</code>).</td>
        <td>def=testing</td>
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
        <td>—</td>
        <td class=wrap>
            Interpreter to use.
            <br/>Defaults to bash.
        </td>
        <td>entrypoint=bash</td>
    </tr>
    <tr>
        <td><code>cmd</code></td>
        <td>—</td>
        <td class=wrap>
            Arguments to pass to interpreter.
            <br/>Defaults to empty string.
            <br/>Filename is post-fixed to command.
        </td>
        <td>cmd=-x</td>
    </tr>
    <tr>
        <td><code>env</code></td>
        <td>—</td>
        <td class=wrap>
            Variables to pass through to container.
            <br/>Defaults to value from environment.
        </td>
        <td>env='foo bar'</td>
    </tr>
</table>
