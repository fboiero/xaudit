import subprocess

def flatter_contract(path_to_file, solidity_version):
    try:
        subprocess.run(['solu',path_to_file,solidity_version,'--output','flat_contract.sol'])
        return "out/flat_contract.sol"
    except subprocess.CalledProcessError as e:
        return e.stderr

def remove_file(path_to_file):
    subprocess.run(['rm', '-r', 'out/'])

def remove_spaces(s):
    return ' '.join(s.split())