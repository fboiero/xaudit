import openai
import os   
import json
from dotenv import load_dotenv
from src.GPTLens_prompts import (auditor_prompt, auditor_format_constrain, topk_prompt1, topk_prompt2,
                             critic_zero_shot_prompt, critic_few_shot_prompt, critic_format_constrain)
from src.utils import remove_spaces

load_dotenv()
openai.api_key = os.getenv('OPENAI_API_KEY')

def call_gpt(prompt, model='gpt-4o-mini', temperature=0.0, max_tokens=4000, n=1, stop=None) -> list:
    messages = [{"role": "user", "content": prompt}]
    if model == "gpt-4":
        pass
        time.sleep(30) # to prevent speed limitation exception
    return chatgpt(messages, model=model, temperature=temperature, max_tokens=max_tokens, n=n, stop=stop)


def chatgpt(messages, model, temperature, max_tokens, n, stop) -> list:
    outputs = []
    while n > 0:
        cnt = min(n, 20)
        n -= cnt
        res = openai.ChatCompletion.create(model=model, messages=messages, temperature=temperature, max_tokens=max_tokens,
                                           n=cnt, stop=stop)
        outputs.extend([choice["message"]["content"] for choice in res["choices"]])
    return outputs[0]

def get_response_auditor(contract, solidity_version):
    template = (auditor_prompt 
        + contract
        + auditor_format_constrain 
        + topk_prompt1.format(topk=5)
        + topk_prompt2)#.replace('{', '{{').replace('}', '}}')
    return call_gpt(template).replace('```json','').replace('```','')
    
def get_response_critic(audit):
    auditor_outputs = json.loads(audit)
    vul_info_str = ''
    for auditor_output in auditor_outputs['output_list']:
        function_name = auditor_output["function_name"]
        function_code = auditor_output["code"]
        vulnerability = auditor_output["vulnerability"]
        reason = auditor_output["reason"]
        vul_info_str += "function_name: " + function_name + "\n" + "code: " + function_code + "\n" + "vulnerability" + ": " + vulnerability + "\n" + "reason: " + reason + "\n------------------\n"
    critic_input = critic_few_shot_prompt + vul_info_str + critic_format_constrain
    return call_gpt(critic_input)#.replace('{', '{{').replace('}', '}}'))

def rank_by_score(json_list):
    return sorted(json_list, key=lambda x: x["final_score"], reverse=True)

def response_to_json(response_critic):
    critic_output_list = json.loads(response_critic)['output_list']
    for bug_info in critic_output_list:
        correctness = float(bug_info["correctness"])
        severity = float(bug_info["severity"])
        profitability = float(bug_info["profitability"])
        final_score = 0.5 * correctness + 0.25 * severity + 0.25 * profitability
        bug_info.update({"final_score": final_score})
    
    # Rank based on scores
    ranker_output_list = rank_by_score(critic_output_list)
    return ranker_output_list

def audit_contract(contract : str, solidity_version : str) -> str:
    contract = remove_spaces(contract)
    response_auditor = get_response_auditor(contract, solidity_version)
    response_critic = get_response_critic(response_auditor)
    return str(response_to_json(response_critic))
    