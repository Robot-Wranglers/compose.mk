!!! warning "Deprecated"
    `docker.bind.script` / `mk.docker.bind.script` are superseded by **code-objects**: in raw make
    `$(call code, def=<define> img=<image> entrypoint=<interp>)`, or in CMK-lang
    `code <name>(img=<image> entrypoint=<interp>)(| body |)`, runs a define/body in a machine.
    See [`demos/cmk/elixir-1.cmk`](https://github.com/robot-wranglers/compose.mk/blob/master/demos/cmk/elixir-1.cmk)
    and the `demos/script-dispatch-*.mk` twins. The macros below remain functional for back-compat.

<table class=docutils-wrap align=center width=95%>
    <caption>
    Arguments for <code>docker.bind.script</code> & <code>mk.docker.bind.script</code>
    </caption>
    <tr>
    <th><small>Name</small></th>
        <th><small>Required?</small></th>
        <th><small>Description</small></th>
        <th><small>Example</small></th>
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
        <td><code>def</code></td>
        <td>✅</td>
        <td class=wrap>
            Name of code-block.  
            <br/>Implied for <a href={{_}}/cmk/compiler#dockerfile-example>CMK ⨖-syntax</a></i>
        </td>
        <td class=wrap>def=..</td>
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