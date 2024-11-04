from langchain_community.llms import OpenAI
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain

import os   
from dotenv import load_dotenv

load_dotenv()
OPENAI_API_KEY=os.getenv('OPENAI_API_KEY')

def audit_contract(contract : str, solidity_version : str) -> str:
    llm = OpenAI(temperature=0.0, openai_api_key=OPENAI_API_KEY)

    prompt_template = PromptTemplate(
        input_variables = ['contract','solidity_version'],
        template = """
            You are an expert auditor in blockchain, you need to find the vulnerabities in the following contract.
            ```{contract}```
            It was develop with the following solidity_version: {solidity_version}
            """
    )

    llm_chain = LLMChain(llm=llm, prompt=prompt_template, output_key="vulnerabilities")

    return llm_chain({'contract': contract, 'solidity_version': solidity_version})["vulnerabilities"]
    
    


