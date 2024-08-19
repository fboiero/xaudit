import markdown
from fpdf import FPDF, FontFace
from src.summarize_information import summarize_audit_information

def generate_tools_output(audit_information):
    output = ''
    for k, v in audit_information.items():
        output += f'\n###{k}\n'
        output += f'\n<code>{v}</code>\n'
    return output

def generate_markdown_text(audit_information, suggested_tests, config_module):
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
        summary_of_audit = summarize_audit_information(audit_information)
        text += "\n## Analysis Findings and Recommendations\n\n"
        text += summary_of_audit
        text += '\n'
    if config_module.include_unitary_test:
        text += "\n#### Suggested Unit Tests for Validation\n\n"
        text += suggested_tests
        text += '\n'
    if config_module.include_conclusion:
        pass
    appendix_text = ''
    if config_module.include_tools_output:
        f = open("docs/appendix_introduction.md", "r")
        appendix_text += f.read().replace('{tools}',f'{tools}')
        appendix_text += generate_tools_output(audit_information)
    
    return text, appendix_text

def generate_pdf_from_markdown(main_text, appendix_text, output_filename='output.pdf'):
    """
    pdf.write_html(
        <h1>Big title</h1>
        <section>
            <h2>Section title</h2>
            <p>Hello world!</p>
        </section>
        , tag_styles={
          #  "h1": FontFace(color=(0, 0, 0), size_pt=32),
         #   "h2": FontFace(color=(0, 0, 0), size_pt=24),
        #})
    """
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

def create_audit_in_pdf(audit_information, suggested_tests, config_module):
    main_text, appendix_text = generate_markdown_text(audit_information, suggested_tests, config_module)
    generate_pdf_from_markdown(main_text, appendix_text)
    return
    