from .kernel import ZigKernel


def main() -> None:
    from ipykernel.kernelapp import IPKernelApp

    IPKernelApp.launch_instance(kernel_class=ZigKernel)
