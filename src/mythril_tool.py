import subprocess

def run_mythril(contract_path):
    try:
        result = subprocess.run(['myth', 'analyze', contract_path],
                                capture_output=True,
                                text=True,
                                #check=True
                                )
        return result.stdout
    except subprocess.CalledProcessError as e:
        return e.stderr

def audit_contract(contract_path, version):
    output = run_mythril(contract_path)
    return output
