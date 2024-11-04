import subprocess


def set_solidity_version(version):
    try:
        subprocess.run(["solc-select", "install", version])
        subprocess.run(["solc-select", "use", version])
    except subprocess.CalledProcessError as e:
        return e.stderr


def run_slither(contract_path):
    try:
        result = subprocess.run(
            ["slither", contract_path], capture_output=True, text=True, check=True
        )
        return result.stdout
    except subprocess.CalledProcessError as e:
        return e.stderr


def audit_contract(contract_path, version):
    set_solidity_version(version)
    output = run_slither(contract_path)
    return output
