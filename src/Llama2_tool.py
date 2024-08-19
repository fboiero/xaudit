import os
import torch
from langchain_community.llms.huggingface_pipeline import HuggingFacePipeline
from langchain.prompts import PromptTemplate
from langchain.chains import LLMChain
from transformers import AutoModelForCausalLM, AutoTokenizer, GenerationConfig, pipeline
from huggingface_hub import login
from dotenv import load_dotenv

load_dotenv()
HUGGINGFACE_API_KEY = os.getenv('HUGGINGFACE_API_KEY')


def audit_contract(contract : str, solidity_version : str) -> str:
    
    llm = load_llama_model()
    prompt_template = PromptTemplate(
        input_variables=["contract","solidity_version"],
        template="""
            You are an expert auditor in blockchain, you need to find the vulnerabities in the following contract.
            ```{contract}```
            It was develop with the following solidity_version: {solidity_version}
            """,
    )
    llm_chain = LLMChain(llm=llm, prompt=prompt_template, output_key="vulnerabilities")
    return llm_chain({'contract': contract, 'solidity_version': solidity_version})["vulnerabilities"]

def load_llama_model(temperature=0):
    login(HUGGINGFACE_API_KEY)
    MODEL_NAME = "TheBloke/Llama-2-13b-Chat-GPTQ"
    tokenizer = AutoTokenizer.from_pretrained(MODEL_NAME, use_fast=True)
    model = AutoModelForCausalLM.from_pretrained(
        MODEL_NAME, torch_dtype=torch.float16, trust_remote_code=True, device_map="auto"
    )

    generation_config = GenerationConfig.from_pretrained(MODEL_NAME)
    generation_config.max_new_tokens = 1024
    generation_config.temperature = 0.0001
    generation_config.top_p = 0.95
    generation_config.do_sample = True
    generation_config.repetition_penalty = 1.15

    text_pipeline = pipeline(
        "text-generation",
        model=model,
        tokenizer=tokenizer,
        return_full_text=True,
        generation_config=generation_config
    )

    return HuggingFacePipeline(pipeline=text_pipeline, model_kwargs={"temperature": temperature})