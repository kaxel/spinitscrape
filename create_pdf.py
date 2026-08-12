#!/usr/bin/env python3
"""
Aggregate all TXT files into a single PDF with each file on a new page.
"""
import glob
from datetime import datetime
from reportlab.lib.pagesizes import letter
from reportlab.platypus import SimpleDocTemplate, Paragraph, PageBreak, Spacer
from reportlab.lib.styles import getSampleStyleSheet, ParagraphStyle
from reportlab.lib.units import inch
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.lib.enums import TA_LEFT

def create_pdf():
    # Get all txt files and sort them chronologically
    txt_files = sorted(glob.glob('*.txt'))

    # Filter out the file we're currently creating
    txt_files = [f for f in txt_files if f != 'create_pdf.txt']

    # Create PDF
    pdf_filename = 'aggregated_radio_plays.pdf'
    doc = SimpleDocTemplate(pdf_filename, pagesize=letter,
                           leftMargin=0.75*inch, rightMargin=0.75*inch,
                           topMargin=0.75*inch, bottomMargin=0.75*inch)

    # Container for the 'Flowable' objects
    elements = []

    # Get styles
    styles = getSampleStyleSheet()

    # Create custom styles
    title_style = ParagraphStyle(
        'CustomTitle',
        parent=styles['Heading1'],
        fontSize=16,
        spaceAfter=20,
        textColor='#000000'
    )

    content_style = ParagraphStyle(
        'CustomContent',
        parent=styles['Normal'],
        fontSize=10,
        leading=14,
        alignment=TA_LEFT,
        fontName='Courier'
    )

    # Process each file
    for txt_file in txt_files:
        print(f"Processing {txt_file}...")

        # Add title with filename
        title = Paragraph(f"<b>{txt_file}</b>", title_style)
        elements.append(title)
        elements.append(Spacer(1, 0.2*inch))

        # Read and add content
        try:
            with open(txt_file, 'r', encoding='utf-8') as f:
                content = f.read()

                # Split content into lines and create paragraphs
                lines = content.split('\n')
                for line in lines:
                    # Escape special characters for reportlab
                    line = line.replace('&', '&amp;')
                    line = line.replace('<', '&lt;')
                    line = line.replace('>', '&gt;')

                    if line.strip():
                        para = Paragraph(line, content_style)
                        elements.append(para)
                    else:
                        elements.append(Spacer(1, 0.1*inch))

        except Exception as e:
            error_text = f"Error reading file: {str(e)}"
            elements.append(Paragraph(error_text, styles['Normal']))

        # Add page break after each file (except the last one)
        if txt_file != txt_files[-1]:
            elements.append(PageBreak())

    # Build PDF
    print(f"Building PDF: {pdf_filename}")
    doc.build(elements)
    print(f"PDF created successfully: {pdf_filename}")

if __name__ == '__main__':
    create_pdf()
