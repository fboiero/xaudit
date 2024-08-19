import openai
import os   
from dotenv import load_dotenv

load_dotenv()
openai.api_key = os.getenv('OPENAI_API_KEY')

def test_generator(contract):
    f = open('examples/Xscrow_v2.sol','r')
    contract_example = f.read()
    f.close()
    f = open('examples/testXscrow_v2.sol','r')
    test_examples = f.read()
    f.close()
    
    preprompt = f'''
    Generate test cases for a smart contract.
    Do not specify the functionality of the contract. 
    Include a variety of test scenarios, covering input validation, edge cases, and potential corner cases. 
    The goal is to ensure comprehensive test coverage without revealing the specific functionality of the smart contract. 
    Provide both positive and negative test cases, considering different data types and possible contract states.
    An example for this contract:
    {contract_example}
    are the following tests:
    {test_examples}
    '''
    
    messages = [{"role": "system", "content": preprompt},
                {"role": "user", "content": f'suggest code function names for the test cases and an explanation of them for the following smart contract:\n {contract}'}]

    response = openai.ChatCompletion.create(model='gpt-3.5-turbo-1106', messages=messages, temperature=0)
    return response["choices"][0]["message"]["content"].replace(". t",".t")