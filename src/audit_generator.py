import markdown
from fpdf import FPDF, FontFace
from src.summarize_information import summarize_audit_information
import os

def generate_tools_output(audit_information):
    output = ''
    for k, v in audit_information.items():
        output += f'\n###{k}\n'
        output += f'\n<code>{v}</code>\n'
    return output

def generate_markdown_text(audit_information, suggested_tests, conclusion_text, summary_of_audit, config_module):
    # Generate your text here
    text = ''
    tools = tuple(audit_information.keys())
    if config_module.include_introduction:
        f = open("docs/introduction.md", "r")
        text += f.read()
        text += '\n'
        for tool in tools:
            f = open(f"docs/{tool}.md", "r")
            text += f.read()
            text += '\n'
    if config_module.include_summary:
        text += "\n## Analysis Findings and Recommendations\n\n"
        text += summary_of_audit
        text += '\n'
    if config_module.include_unitary_test:
        text += "\n#### Suggested Unit Tests for Validation\n\n"
        text += suggested_tests
        text += '\n'
    if config_module.include_conclusion:
        text += "\n## Conclusions\n\n"
        text += conclusion_text
    appendix_text = ''
    if config_module.include_tools_output:
        f = open("docs/appendix_introduction.md", "r")
        appendix_text += f.read().replace('{tools}',f'{tools}')
        appendix_text += generate_tools_output(audit_information)
    
    return text, appendix_text

def generate_pdf_from_markdown(main_text, appendix_text, output_filename='output/output.pdf'):
    pdf = FPDF()
    pdf.add_page()
    pdf.set_font("Arial", size=12)
    # Convert Markdown to HTML
    html = markdown.markdown(main_text)
    # Write HTML to PDF
    pdf.write_html(html)
    pdf.add_page()
    pdf.set_font("Arial", size=12)
    # Convert Markdown to HTML
    html = markdown.markdown(appendix_text)
    # Write HTML to PDF
    pdf.write_html(html)
    
    pdf.output(output_filename)

def generate_txt_from_markdown(audit_information, summary_of_audit, conclusion_text, output_filename='output/'):
    if not os.path.isdir(output_filename):
        os.makedirs(output_filename)
    print(output_filename)
    for keys, values in audit_information.items():
        f = open(output_filename+keys+'.txt', "w")
        f.write(values)
        f.close()
    f = open(output_filename+'summary.txt', "w")
    f.write(summary_of_audit)
    f.close()
    f = open(output_filename+'conclusion.txt', "w")
    f.write(conclusion_text)
    f.close()

def create_audit_in_pdf(audit_information, suggested_tests, conclusion_text, tag, config_module):
    summary_of_audit = ''
    if config_module.include_summary:
        summary_of_audit = summarize_audit_information(audit_information)
    main_text, appendix_text = generate_markdown_text(audit_information, suggested_tests, conclusion_text, summary_of_audit, config_module)
    #generate_pdf_from_markdown(main_text, appendix_text, summary_of_audit)
    generate_txt_from_markdown(audit_information, summary_of_audit, conclusion_text,  output_filename='output/'+tag+'/')
    