import openai
import os   
from dotenv import load_dotenv

load_dotenv()
openai.api_key = os.getenv('OPENAI_API_KEY')

class TextGenerator:
    def __init__(self,model_name='gpt-4o-mini'):
        self.model_name = model_name

    def test_generator(self, contract):
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

        response = openai.ChatCompletion.create(model=self.model_name, messages=messages, temperature=0)
        return response["choices"][0]["message"]["content"].replace(". t",".t")
    
    def conclusion_generator(self, audit_information):

        preprompt = f'''
        I have run several tools in parallel, each generating its own output. These outputs are stored in a Python dictionary where the keys are the tool names, and the values are the corresponding outputs. Based on the following outputs, generate a concise conclusion that summarizes the key results, any patterns observed, and potential next steps. Here is the dictionary of outputs:

        {audit_information}

        Please focus on providing an insightful conclusion that highlights the most important findings.
        '''
        
        messages = [{"role": "system", "content": preprompt}]

        response = openai.ChatCompletion.create(model=self.model_name, messages=messages, temperature=0)
        return response["choices"][0]["message"]["content"].replace(". t",".t")
    