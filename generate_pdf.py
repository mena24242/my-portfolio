#!/usr/bin/env python3
"""Generate a premium A4 PDF portfolio for Mena Medhat (Mechatronics Engineering)."""
from reportlab.lib.pagesizes import A4
from reportlab.lib.colors import HexColor, white
from reportlab.pdfbase import pdfmetrics
from reportlab.pdfbase.ttfonts import TTFont
from reportlab.platypus import (BaseDocTemplate, Frame, PageTemplate, Flowable,
                                Paragraph, Spacer, Table, TableStyle, KeepTogether)
from reportlab.lib.styles import ParagraphStyle
from reportlab.lib.enums import TA_LEFT, TA_CENTER
from reportlab.lib import colors

# ---------------------------------------------------------------- fonts
FONT_DIR = "/usr/share/fonts/truetype/dejavu"
pdfmetrics.registerFont(TTFont("Sans", f"{FONT_DIR}/DejaVuSans.ttf"))
pdfmetrics.registerFont(TTFont("Sans-Bold", f"{FONT_DIR}/DejaVuSans-Bold.ttf"))
pdfmetrics.registerFont(TTFont("Mono", f"{FONT_DIR}/DejaVuSansMono.ttf"))

SANS = "Sans"
BOLD = "Sans-Bold"
MONO = "Mono"

# ---------------------------------------------------------------- palette
NAVY   = HexColor("#0A1424")
NAVY2  = HexColor("#132338")
CYAN   = HexColor("#0FB5D9")
CYAN_L = HexColor("#5BC9E8")
VIOLET = HexColor("#8B7CE0")
INK    = HexColor("#16202C")
MUTED  = HexColor("#5B6B7E")
PANEL  = HexColor("#F5F9FD")
PANEL2 = HexColor("#EEF5FB")
LINE   = HexColor("#D7E4EF")
CHIP_BG  = HexColor("#EAF4FB")
CHIP_BD  = HexColor("#BFDEF0")
GREEN_BD = HexColor("#B7E6D3")
GREEN_BG = HexColor("#E7F7F0")
GREEN_TX = HexColor("#0E7C55")
WHITE   = white

W, H = A4
MARGIN = 46
CONTENT_W = W - 2 * MARGIN
TOP_MARGIN = 64
BOT_MARGIN = 58
HEADER_H = 150

# ---------------------------------------------------------------- styles
def S(name, **kw):
    base = dict(fontName=SANS, fontSize=9.5, leading=14, textColor=INK)
    base.update(kw)
    return ParagraphStyle(name, **base)

st_eyebrow   = S("eyebrow", fontName=MONO, fontSize=8, textColor=CYAN, leading=11)
st_body      = S("body", fontSize=9.8, leading=15.5, textColor=INK)
st_muted     = S("muted", fontSize=9.3, leading=14, textColor=MUTED)
st_title     = S("title", fontName=BOLD, fontSize=12.5, leading=16, textColor=NAVY)
st_subtitle  = S("subtitle", fontName=BOLD, fontSize=10, leading=13.5, textColor=CYAN)
st_role      = S("role", fontName=MONO, fontSize=8.3, leading=12, textColor=CYAN)
st_bullet    = S("bullet", fontSize=9.4, leading=14.2, textColor=MUTED, leftIndent=13, bulletIndent=0)
st_chip      = S("chip", fontName=BOLD, fontSize=8.4, leading=10, textColor=HexColor("#0B3B5C"),
                 alignment=TA_CENTER, backColor=CHIP_BG, borderColor=CHIP_BD,
                 borderWidth=0.9, borderRadius=9, borderPadding=(3.5, 2, 3.5, 2))
st_cert_name = S("cert_name", fontName=BOLD, fontSize=10.5, leading=13, textColor=NAVY)
st_cert_iss  = S("cert_iss", fontName=MONO, fontSize=7.6, leading=10, textColor=VIOLET)
st_cert_desc = S("cert_desc", fontSize=8, leading=11.5, textColor=MUTED)

# ---------------------------------------------------------------- custom flowables
class SectionHeader(Flowable):
    def __init__(self, title, accent=CYAN):
        Flowable.__init__(self)
        self.title = title
        self.accent = accent
        self.height = 36

    def wrap(self, aw, ah):
        self.width = aw
        return aw, self.height

    def draw(self):
        c = self.canv
        c.saveState()
        c.setFillColor(self.accent)
        c.rect(0, -self.height + 6, 4, 15, stroke=0, fill=1)   # left accent bar
        c.setFont(BOLD, 13)
        c.setFillColor(NAVY)
        c.drawString(13, -self.height + 11, self.title.upper())
        c.setStrokeColor(LINE)
        c.setLineWidth(0.8)
        c.line(0, -self.height + 2, self.width, -self.height + 2)
        c.restoreState()


class Card(Flowable):
    def __init__(self, items, bg=PANEL, border=LINE, radius=10, pad=15, gap=7):
        Flowable.__init__(self)
        self.items = items
        self.bg = bg
        self.border = border
        self.radius = radius
        self.pad = pad
        self.gap = gap

    def wrap(self, aw, ah):
        self.width = aw
        inner_w = aw - 2 * self.pad
        h = 2 * self.pad
        n = len(self.items)
        for i, it in enumerate(self.items):
            w, ih = it.wrap(inner_w, ah)
            h += ih
            if i < n - 1:
                h += self.gap
        self.height = h
        return aw, h

    def draw(self):
        c = self.canv
        c.saveState()
        c.setFillColor(self.bg)
        c.setStrokeColor(self.border)
        c.setLineWidth(0.9)
        c.roundRect(0, -self.height, self.width, self.height, self.radius, stroke=1, fill=1)
        c.restoreState()
        inner_w = self.width - 2 * self.pad
        y = -self.pad
        n = len(self.items)
        for i, it in enumerate(self.items):
            w, ih = it.wrap(inner_w, self.height)
            y -= ih
            it.drawOn(c, self.pad, y)
            if i < n - 1:
                y -= self.gap


def chips_table(items, inner_w, cols):
    """Grid of chip paragraphs."""
    colw = inner_w / cols
    rows = []
    for i in range(0, len(items), cols):
        cells = items[i:i + cols]
        while len(cells) < cols:
            cells.append("")
        rows.append([Paragraph(t, st_chip) for t in cells])
    t = Table(rows, colWidths=[colw] * cols)
    t.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "MIDDLE"),
        ("LEFTPADDING", (0, 0), (-1, -1), 2.5),
        ("RIGHTPADDING", (0, 0), (-1, -1), 2.5),
        ("TOPPADDING", (0, 0), (-1, -1), 2.2),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 2.2),
    ]))
    return t


def two_col_card(left_items, right_para, inner_w):
    left = Table([[left_items]], colWidths=[inner_w - 118])
    right = Table([[right_para]], colWidths=[118])
    right.setStyle(TableStyle([("VALIGN", (0, 0), (-1, -1), "TOP"),
                               ("ALIGN", (0, 0), (-1, -1), "RIGHT")]))
    outer = Table([[left, right]], colWidths=[inner_w - 118, 118])
    outer.setStyle(TableStyle([
        ("VALIGN", (0, 0), (-1, -1), "TOP"),
        ("LEFTPADDING", (0, 0), (-1, -1), 0),
        ("RIGHTPADDING", (0, 0), (-1, -1), 0),
        ("TOPPADDING", (0, 0), (-1, -1), 0),
        ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ]))
    return outer


def when_chip(text):
    return Paragraph(text, S("when", fontName=MONO, fontSize=8, textColor=CYAN,
                             alignment=TA_CENTER, backColor=PANEL2,
                             borderColor=CHIP_BD, borderWidth=0.9, borderRadius=9,
                             borderPadding=(3.5, 8, 3.5, 8)))


def bullets(lines):
    return [Paragraph(l, st_bullet, bulletText="\u2022") for l in lines]


# ---------------------------------------------------------------- document
doc = BaseDocTemplate(
    "/home/user/portfolio/Mena-Medhat-Portfolio.pdf",
    pagesize=A4,
    leftMargin=MARGIN, rightMargin=MARGIN,
    topMargin=TOP_MARGIN, bottomMargin=BOT_MARGIN,
    title="Mena Medhat — Portfolio",
    author="Mena Medhat",
)

frame = Frame(MARGIN, BOT_MARGIN, CONTENT_W, H - TOP_MARGIN - BOT_MARGIN, id="main")


def on_first_page(canvas, doc_):
    c = canvas
    c.saveState()
    # navy band
    c.setFillColor(NAVY)
    c.rect(0, H - HEADER_H, W, HEADER_H, stroke=0, fill=1)
    # cyan strip
    c.setFillColor(CYAN)
    c.rect(0, H - HEADER_H - 4, W, 4, stroke=0, fill=1)
    # watermark MM
    c.setFillColor(NAVY2)
    c.setFont(BOLD, 148)
    c.drawRightString(W - 44, H - HEADER_H / 2 - 58, "MM")
    # eyebrow
    c.setFillColor(CYAN_L)
    c.setFont(MONO, 8.5)
    c.drawString(MARGIN, H - 46, "P O R T F O L I O   /   M E C H A T R O N I C S   E N G I N E E R I N G")
    # name
    c.setFillColor(WHITE)
    c.setFont(BOLD, 33)
    c.drawString(MARGIN, H - 84, "MENA MEDHAT")
    # title
    c.setFillColor(CYAN_L)
    c.setFont(SANS, 13)
    c.drawString(MARGIN, H - 108, "Mechatronics Engineering Student")
    # contact
    c.setFillColor(HexColor("#AFC2D6"))
    c.setFont(SANS, 9)
    c.drawString(MARGIN, H - 124,
                 "Sohag, Egypt   |   +20 120 488 5035   |   menamedhat242006@gmail.com")
    c.setFillColor(HexColor("#7FB8D8"))
    c.drawString(MARGIN, H - 140,
                 "linkedin.com/in/mena-medhat-b38093370   |   github.com/mena24242")
    c.restoreState()


def on_later_pages(canvas, doc_):
    c = canvas
    c.saveState()
    c.setStrokeColor(LINE)
    c.setLineWidth(0.8)
    c.line(MARGIN, 40, W - MARGIN, 40)
    c.setFillColor(CYAN)
    c.setFont(BOLD, 8.5)
    c.drawString(MARGIN, 26, "MENA MEDHAT  \u00b7  PORTFOLIO")
    c.setFillColor(MUTED)
    c.setFont(SANS, 8.5)
    c.drawRightString(W - MARGIN, 26, "Page %d" % doc_.page)
    c.restoreState()


doc.addPageTemplates([PageTemplate(id="first", frames=[frame], onPage=on_first_page),
                      PageTemplate(id="later", frames=[frame], onPage=on_later_pages)])

# ---------------------------------------------------------------- story
story = []
from reportlab.platypus import NextPageTemplate
story.append(NextPageTemplate("later"))          # page 1 uses "first", then switch
story.append(Spacer(1, HEADER_H + 18))

# ---------- profile
story.append(SectionHeader("Profile"))
story.append(Card([
    Paragraph("Mechatronics Engineering student with a strong interest in electrical "
              "systems, circuit design, and the integration of mechanical and electronic "
              "technologies. I bring solid analytical and problem-solving skills backed by "
              "hands-on experience in electronics, CAD design, and technical project "
              "development — aiming at automation, intelligent systems, and innovative "
              "solutions that bridge mechanics, electronics, and control engineering.",
              st_body),
]))
story.append(Spacer(1, 14))

# ---------- quick stats
stats = [
    ("3.74 / 4.0", "CGPA — Excellent"),
    ("2", "Engineering Projects"),
    ("4", "SOLIDWORKS Certs"),
    ("9", "Software Tools"),
]
stat_cells = []
for val, lbl in stats:
    stat_cells.append(Card([
        Paragraph(val, S("sv", fontName=BOLD, fontSize=15, leading=17, textColor=CYAN)),
        Paragraph(lbl, S("sl", fontSize=8, leading=11, textColor=MUTED)),
    ], pad=12, radius=10))
stat_row = Table([stat_cells], colWidths=[(CONTENT_W - 3 * 10) / 4.0] * 4)
stat_row.setStyle(TableStyle([
    ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
story.append(stat_row)
story.append(Spacer(1, 20))
# ---------- education
story.append(SectionHeader("Education"))
edu_inner_w = CONTENT_W - 30
story.append(Card([
    two_col_card(
        [Paragraph("Assiut University — Faculty of Engineering", st_title),
         Paragraph("B.Sc. in Mechatronics Engineering", st_subtitle)],
        when_chip("2024 \u2013 2029"),
        edu_inner_w),
    Paragraph("CGPA 3.74 / 4.0   \u00b7   Grade: Excellent",
              S("grade", fontName=BOLD, fontSize=9, leading=13, textColor=GREEN_TX,
                backColor=GREEN_BG, borderColor=GREEN_BD, borderWidth=0.9,
                borderRadius=9, borderPadding=(4, 10, 4, 10))),
] + bullets([
    "Focused coursework in electrical systems, circuit design, mechanics, and control engineering.",
    "Hands-on labs in electronics, CAD modeling, and technical project development.",
])))
story.append(Spacer(1, 20))

# ---------- experience
story.append(SectionHeader("Experience"))
story.append(Card([
    two_col_card(
        [Paragraph("ASME Asyut Student Section", st_title),
         Paragraph("Mechanical Design & Technical Member", st_subtitle)],
        when_chip("2026 \u2013 Present"),
        edu_inner_w),
] + bullets([
    "Hands-on experience in mechanical design using SOLIDWORKS through practical modeling work.",
    "Studied core engineering topics — gears, materials, and fasteners — and produced technical reports that strengthened analytical and documentation skills.",
])))
story.append(Spacer(1, 20))

# ---------- projects
story.append(SectionHeader("Projects"))
proj1 = Card([
    Paragraph("Fire Fighting Car", st_title),
    Paragraph("Role: Electrical Wiring & Connections", st_role),
] + bullets([
    "Designed and executed the full electrical wiring and connection layout for a fire-fighting vehicle model.",
    "Ensured reliable power distribution and safe integration between motors, actuators, and control modules.",
    "Practiced circuit-level troubleshooting and disciplined cable-routing.",
]), pad=15)
proj2 = Card([
    Paragraph("Bus Management System", st_title),
    Paragraph("Role: Automation & Workflow Developer", st_role),
] + bullets([
    "Developed an automated bus-management workflow that streamlines routing and scheduling logic.",
    "Reduced manual coordination overhead by automating repetitive operational steps.",
    "Explored workflow-automation tools (n8n) and data-flow design.",
]), pad=15)
story.append(KeepTogether(proj1))
story.append(Spacer(1, 12))
story.append(KeepTogether(proj2))
story.append(Spacer(1, 20))

# ---------- skills
story.append(SectionHeader("Skills"))
skill_inner = (CONTENT_W - 12) / 2.0 - 30
def skill_group(title, items, cols):
    return Card([
        Paragraph(title, st_title),
        chips_table(items, skill_inner, cols),
    ], pad=14)

row1 = Table([[skill_group("Technical", ["Electrical Wiring", "Electronics", "Mechanical Design",
                                          "FEA", "Sheet Metal", "PCB Design", "AI Automation"], 2),
               skill_group("Software", ["SOLIDWORKS", "AutoCAD", "Ansys", "Arduino IDE", "MATLAB",
                                        "C++", "Python", "KiCad", "n8n"], 2)]],
              colWidths=[(CONTENT_W - 12) / 2.0] * 2)
row1.setStyle(TableStyle([
    ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
row2 = Table([[skill_group("Soft Skills", ["Problem Solving", "Analytical Thinking", "Teamwork",
                                           "Continuous Learning"], 2),
               skill_group("Languages", ["Arabic — Native", "English — Professional"], 1)]],
              colWidths=[(CONTENT_W - 12) / 2.0] * 2)
row2.setStyle(TableStyle([
    ("LEFTPADDING", (0, 0), (-1, -1), 0), ("RIGHTPADDING", (0, 0), (-1, -1), 6),
    ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
story.append(KeepTogether(row1))
story.append(Spacer(1, 12))
story.append(KeepTogether(row2))
story.append(Spacer(1, 20))

# ---------- certifications
story.append(SectionHeader("Certifications & Awards"))
certs = [
    ("CSWA", "Dassault Syst\u00e8mes", "3D modeling fundamentals."),
    ("CSWP", "Dassault Syst\u00e8mes", "Advanced part & assembly design."),
    ("CSWPA-SM", "Dassault Syst\u00e8mes", "Specialized sheet-metal design."),
    ("CSWA-S", "Dassault Syst\u00e8mes", "FEA & engineering analysis."),
]
cert_cells = []
for code, issuer, desc in certs:
    cert_cells.append(Card([
        Paragraph(code, S("cc", fontName=BOLD, fontSize=13, leading=16, textColor=CYAN)),
        Paragraph(issuer, st_cert_iss),
        Paragraph(desc, st_cert_desc),
    ], pad=12, radius=10, gap=5))
cert_row = Table([cert_cells], colWidths=[(CONTENT_W - 3 * 10) / 4.0] * 4)
cert_row.setStyle(TableStyle([
    ("LEFTPADDING", (0, 0), (-1, -1), 5), ("RIGHTPADDING", (0, 0), (-1, -1), 5),
    ("TOPPADDING", (0, 0), (-1, -1), 0), ("BOTTOMPADDING", (0, 0), (-1, -1), 0),
    ("VALIGN", (0, 0), (-1, -1), "TOP"),
]))
story.append(KeepTogether(cert_row))
story.append(Spacer(1, 8))

doc.build(story)
print("PDF built OK -> /home/user/portfolio/Mena-Medhat-Portfolio.pdf")
