from langchain_community.llms import OpenAI
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain
from langchain.chains import SequentialChain

import os   
from dotenv import load_dotenv

load_dotenv()
OPENAI_API_KEY=os.getenv('OPENAI_API_KEY')

def summarize_audit_information(audit_information : dict) -> str:
    template = template_creation(audit_information).replace('{', '{{').replace('}', '}}')
    llm = OpenAI(temperature=0.0, openai_api_key=OPENAI_API_KEY)
    prompt_template = PromptTemplate(
        input_variables = [],
        template = template
    )
    llm_chain = LLMChain(llm=llm, prompt=prompt_template, output_key="vulnerabilities")
    return llm_chain({})["vulnerabilities"]

def template_creation(audit_information : dict):
    template = """
    Write an auditor inform to be human readable to be part of a section call 'Analysis Findings and Recommendations'.
    in an audit document. Please note that all possible vulnerabilities were detected by the following tools:\n\n 
    """
    for k,v in audit_information.items():
        template += f'Tool {k}: \n {v} \n \n '
    template += "Not include 'Analysis Findings and Recommendations:' in the answer."
    return template