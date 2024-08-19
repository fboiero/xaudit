import sys
from config import ModelConfig
from src.Llama2_tool import audit_contract as llama2_audit_contract
from src.rawchatGPT_tool import audit_contract as rawchatGPT_audit_contract
from src.GPTLens_tool import audit_contract as GPTLens_audit_contract
from src.slither_tool import audit_contract as slither_audit_contract
from src.mythril_tool import audit_contract as mythril_audit_contract
from src.test_generator import test_generator
from src.utils import flatter_contract, remove_file
from src.audit_generator import create_audit_in_pdf
import warnings
warnings.filterwarnings('ignore')

if __name__ == '__main__':
    if len(sys.argv) < 3:
        print('python main.py <<file_with_contract>> <<solidity_version>>')
    model_config = ModelConfig()
    audit_information = {}
    path_to_file = sys.argv[1]
    solidity_version = sys.argv[2]
    flatter_contract_path = flatter_contract(path_to_file, solidity_version)
    f = open(flatter_contract_path, "r")
    content = f.read()
    if model_config.use_rawGPT:
        audit_information['rawchatGPT'] = rawchatGPT_audit_contract(content, solidity_version)
    if model_config.use_GPTLens:
        audit_information['GPTLens'] = GPTLens_audit_contract(content, solidity_version)
    if model_config.use_rawLlama:
        audit_information['Llama2'] = llama2_audit_contract(content, solidity_version)
    if model_config.use_slither:
        audit_information['Slither'] = slither_audit_contract(flatter_contract_path, solidity_version)
    if model_config.use_mythril:
        audit_information['Mythril'] = mythril_audit_contract(flatter_contract_path, solidity_version)
    remove_file(flatter_contract_path)
    suggested_tests = ''
    

    if model_config.include_unitary_test:
        suggested_tests += test_generator(content)
    create_audit_in_pdf(audit_information, suggested_tests, model_config)