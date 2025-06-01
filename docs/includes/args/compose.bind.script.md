<table class=docutils-wrap align=center width=95%>
   <caption>Arguments for `compose.bind.script`</caption>
    <tr>
    <th><small>Name</small></th>
      <th><small>Required?</small></th>
      <th><small>Description</small></th>
      <th><small>Example</small></th>
    </tr>
    <tr>
        <td><code>svc</code></td>
        <td>✅</td>
        <td class=wrap>
            Service / container to use.
        </td>
        <td>debian</td>
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
        <td><code>env</code></td>
        <td>❌</td>
        <td class=wrap>
            Variables to pass through to container.
            <br/>Defaults to value from environment
        </td>
        <td>env='foo bar'</td>
    </tr>
    <tr>
        <td><code>quiet</code></td>
        <td>❌</td>
        <td class=wrap>
            Whether to silence announcements re: compose-file and service name.
            <br/>Defaults to value from environment, or 0.
        </td>
        <td>quiet=1</td>
    </tr>
</table>