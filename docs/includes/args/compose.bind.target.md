
<table class=docutils-wrap align=center width=95%>
   <caption>Arguments for `compose.bind.target`</caption>
    <tr>
    <th><small>Name</small></th>
      <th><small>Required?</small></th>
      <th><small>Description</small></th>
      <th><small>Example</small></th>
    </tr>
    <tr>
        <td><i>1st pos arg</i></td>
        <td>✅</td>
        <td class=wrap>Service-name / Where to run target</td>
        <td>debian</td>
    </tr>
    <tr>
        <td><code>prefix</code></td>
        <td>❌</td>
        <td>Prefix used to find private target.<br/> Defaults to "self."</td>
        <td>prefix=.</td>
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
        <td class=wrap>Defaults to value from environment, or 0</td>
        <td>quiet=1</td>
    </tr>
</table>

