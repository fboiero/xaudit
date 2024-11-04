import sys
import os
from config import ModelConfig
from src.Llama2_tool import audit_contract as llama2_audit_contract
from src.rawchatGPT_tool import audit_contract as rawchatGPT_audit_contract
from src.GPTLens_tool import audit_contract as GPTLens_audit_contract
from src.slither_tool import audit_contract as slither_audit_contract
from src.mythril_tool import audit_contract as mythril_audit_contract
from src.text_generator import TextGenerator
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
    try:
        tag = sys.argv[2]
    except:
        tag=''
    f = open(path_to_file, "r")
    solidity_version = ''
    for line in f:
        if 'pragma solidity' in line:
            solidity_version = line[line.find('.')-1:line.find(';')]
    f = open(path_to_file, "r")
    content = f.read()
    content = content.replace('"',"'")
    if model_config.use_rawGPT and not os.path.exists('output/'+tag+'/rawchatGPT.txt'):
        audit_information['rawchatGPT'] = rawchatGPT_audit_contract(content, solidity_version)
    if model_config.use_GPTLens and not os.path.exists('output/'+tag+'/GPTLens.txt'):
        audit_information['GPTLens'] = GPTLens_audit_contract(content, solidity_version)
    if model_config.use_rawLlama and not os.path.exists('output/'+tag+'/Llama2.txt'):
        audit_information['Llama2'] = llama2_audit_contract(content, solidity_version)
    if model_config.use_slither and not os.path.exists('output/'+tag+'/Slither.txt'):
        audit_information['Slither'] = slither_audit_contract(path_to_file, solidity_version)
    if model_config.use_mythril and not os.path.exists('output/'+tag+'/Mythril.txt'):
        audit_information['Mythril'] = mythril_audit_contract(path_to_file, solidity_version)
    suggested_tests = ''
    if model_config.include_unitary_test:
        suggested_tests += TextGenerator().test_generator(content)
    conclusion_text = ''
    if model_config.include_conclusion:
        conclusion_text = TextGenerator().conclusion_generator(audit_information)
    create_audit_in_pdf(audit_information, suggested_tests, conclusion_text, tag, config_module=model_config)
