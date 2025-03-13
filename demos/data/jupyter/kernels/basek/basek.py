import os
import subprocess
import tempfile

from ipykernel.kernelbase import Kernel


class BaseK(Kernel):
    implementation = "Container"
    implementation_version = "1.0"
    language = "no-op"
    language_version = "0.1"
    language_info = {
        "name": "Any text",
        "mimetype": "text/plain",
        "file_extension": ".txt",
    }
    banner = "Experimental BaseK kernel"

    def do_execute(
        self, code, silent, store_history=True, user_expressions=None, allow_stdin=False
    ):
        """
        Execute the content of the Jupyter cell, write it to a file,
        and then run the file using a subprocess, returning the output.
        """
        workspace = os.environ.get("workspace", ".")
        os.chdir(workspace)
        with tempfile.NamedTemporaryFile(dir=None, prefix=".tmp.ipy.cmk") as tmpfile:
            fname = os.path.basename(tmpfile.name)
            self.log.debug(f"tmpfile: {fname}")
            try:
                with open(fname, "w") as f:
                    f.write(code)
                cmd = os.environ.get("cmd", "cat .")
                cmd = f"{cmd}/{fname}"
                self.log.warning(f"starting subprocess: {cmd}")
                result = subprocess.run(cmd, shell=True, capture_output=True, text=True)
                output = result.stdout
                stderr = result.stderr
                if result.returncode != 0:
                    output += stderr
                if not silent:
                    resp = (
                        self.iopub_socket,
                        "stream",
                        {"name": "stdout", "text": output},
                    )
                    self.send_response(*resp)
                if result.returncode != 0:
                    self.log.critical(f"stderr: {stderr}")
                    return {
                        "status": "error",
                        "traceback": [],
                        "ename": "failed",
                        "execution_count": self.execution_count,
                        "evalue": f"{result.returncode}",
                    }
                else:
                    os.remove(fname)
                    return {
                        "status": "ok",
                        "user_expressions": {},
                        "payload": [],
                        "execution_count": self.execution_count,
                    }
            except Exception as e:
                resp = "stream", {"name": "stderr", "text": str(e)}
                if not silent:
                    self.send_response(self.iopub_socket, *resp)
                return {
                    "status": "error",
                    "evalue": str(e),
                    "execution_count": self.execution_count,
                    "ename": type(e).__name__,
                    "traceback": [],
                }


if __name__ == "__main__":
    from ipykernel.kernelapp import IPKernelApp

    IPKernelApp.launch_instance(kernel_class=BaseK)
