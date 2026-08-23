#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成更新版作品介绍文档"""
import zipfile
import os
from xml.sax.saxutils import escape

OUTPUT = r"C:\Users\qq959\FocusTimer3\鸿蒙多端专注计时本_作品说明文档_更新版.docx"

def p(text, style=None, bold=False, size=None, align=None):
    style_xml = ''
    if style:
        style_xml = f'<w:pStyle w:val="{style}"/>'
    if align:
        style_xml += f'<w:jc w:val="{align}"/>'
    rpr = ''
    if bold or size:
        rpr = '<w:rPr>'
        if bold:
            rpr += '<w:b/>'
        if size:
            rpr += f'<w:sz w:val="{size}"/>'
        rpr += '</w:rPr>'
    parts = text.split('\n')
    runs = ''
    for i, part in enumerate(parts):
        if i > 0:
            runs += '<w:r><w:br/></w:r>'
        runs += f'<w:r>{rpr}<w:t xml:space="preserve">{escape(part)}</w:t></w:r>'
    return f'<w:p><w:pPr>{style_xml}</w:pPr>{runs}</w:p>'

def heading(text, level=1):
    sizes = {1: 36, 2: 28, 3: 24, 4: 20}
    return p(text, style=f'Heading{level}', bold=True, size=sizes.get(level, 20))

def code_block(text):
    lines = text.split('\n')
    result = ''
    for line in lines:
        result += f'<w:p><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/><w:ind w:left="200"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">{escape(line) if line else " "}</w:t></w:r></w:p>'
    return result

def bullet(text):
    return p('• ' + text)

def table(headers, rows):
    """生成简单表格"""
    xml = '<w:tbl><w:tblPr><w:tblW w:w="5000" w:type="pct"/><w:tblBorders><w:top w:val="single" w:sz="4"/><w:left w:val="single" w:sz="4"/><w:bottom w:val="single" w:sz="4"/><w:right w:val="single" w:sz="4"/><w:insideH w:val="single" w:sz="4"/><w:insideV w:val="single" w:sz="4"/></w:tblBorders></w:tblPr>'
    # 表头
    xml += '<w:tr>'
    for h in headers:
        xml += f'<w:tc><w:tcPr><w:shd w:val="clear" w:color="auto" w:fill="E8E8E8"/></w:tcPr>{p(h, bold=True)}</w:tc>'
    xml += '</w:tr>'
    # 数据行
    for row in rows:
        xml += '<w:tr>'
        for cell in row:
            xml += f'<w:tc>{p(cell)}</w:tc>'
        xml += '</w:tr>'
    xml += '</w:tbl>'
    return xml

body = ''

# ===== 封面信息 =====
body += heading('鸿蒙多端专注计时本', 1)
body += p('作者：中国地质大学（北京）  黎姿', align='center')
body += p('2026中国高校计算机大赛—人工智能创意赛', align='center')
body += p('鸿蒙赛道作品说明文档（初赛）', align='center')
body += p('')

# 参赛信息表
body += table(
    ['项目', '内容'],
    [
        ['参赛学校', '中国地质大学（北京）'],
        ['团队名称', '鸿端时计'],
        ['作品名称', '鸿蒙多端专注计时本'],
        ['赛题方向', '（✔）应用创新 （）Agent创新 （）用户体验创新 （）操作系统智能创新'],
        ['联系人（队长）', '黎姿'],
        ['联系电话（队长）', '18976738582'],
    ]
)
body += p('')

# 团队队员信息
body += heading('团队队员基本信息', 3)
body += table(
    ['姓名', '学校', '院系', '专业', '年级', '毕业时间', '联系电话', '邮箱', '分工'],
    [
        ['黎姿', '中国地质大学（北京）', '人工智能学院', '软件工程', '大一', '2029', '18976738582', '959843160@qq.com', '队长兼队员'],
    ]
)
body += p('')

# 指导教师
body += heading('团队指导教师信息', 3)
body += table(
    ['姓名', '院系', '职称', '研究方向', '联系电话', '联系邮箱'],
    [
        ['龙腾', '人工智能学院', '副教授', '智能化软件工程', '18010955906', 'longteng@cugb.edu.cn'],
    ]
)
body += p('')

# 团队成员优势
body += heading('团队成员优势描述', 3)
body += p('专业基础与项目经历：本人为软件工程专业大一学生，系统学习 Java、ArkTS 开发语言，熟练掌握鸿蒙应用开发 DevEco Studio 工具链；独立完成《鸿蒙多端专注计时本》从需求分析、架构设计到编码实现的全流程开发，累计完成 28 个核心模块，涵盖专注计时、笔记流转、AI 分析、数据统计、桌面卡片、安全加密等完整功能链路。')
body += p('能力分工与优势互补：单人完整覆盖产品全链路工作，兼具前端界面设计、交互逻辑梳理、赛事文档撰写能力；深耕学生自习真实使用场景，精准挖掘多设备学习工具痛点，熟悉鸿蒙分布式流转、关系型数据库、偏好存储、服务卡片（FormKit）、分布式数据对象等核心技术特性。')
body += p('赛事适配优势：充分研读赛事评审标准，作品围绕「鸿蒙技术创新性」展开设计，完整覆盖多端协同、AI 智能分析、数据安全防护、桌面元服务触达等差异化亮点，配套交互流程图、产品效果图、完整可运行 Demo、赛事说明文档全量材料，落地可行性强。')
body += p('')

# 原创性声明
body += heading('作品原创性声明', 3)
body += p('郑重声明：承诺本参赛队伍报名信息真实有效；呈交的参赛作品相关资料以及所完成的作品实物等相关成果，是本团队独立进行研究工作所取得的成果，除文中已经注明引用的内容外，本作品说明文档不包含任何其他个人或集体已经发表或撰写过的作品成果，不侵犯任何第三方的知识产权或其他权利。本声明的法律结果由本参赛队承担。')
body += p('参赛队员签名（团队全部成员）：')
body += p('日期：2026 年 8 月 22 日')
body += p('指导老师审核签名：')
body += p('日期：2026 年 8 月 22 日')
body += p('')

# ===== 正文 =====
body += heading('一、创意描述部分', 2)
body += p('依托鸿蒙分布式能力，实现手机平板笔记无缝流转 + 桌面元服务卡片实时触达 + AI 智能学习分析，打造一体化轻量化多端专注学习工具。')
body += p('')

body += heading('二、设计稿（交互流程图＋海报）部分', 2)
body += p('图表 1：产品整体架构图')
body += p('图表 2：核心页面交互流程图')
body += p('')

body += heading('三、作品介绍部分', 2)

body += heading('1. 创意背景', 3)
body += p('大学生多设备学习存在三大痛点：数据割裂，换设备后计时笔记不同步；提醒失效，手机静音易错过节点；功能分散，多软件切换打断专注。此外，现有学习工具普遍缺乏智能化数据分析能力，用户无法直观了解自身学习习惯与效率趋势。本项目依托鸿蒙全场景能力，打造一体化轻量化学习工具，解决多端学习割裂问题，并通过 AI 分析为用户提供个性化学习建议。')
body += p('')

body += heading('2. 核心创新点', 3)
body += bullet('分布式协同：突破单设备局限，手机平板双向同步，应用流转无缝接续，支持跨设备笔记迁移与编辑状态保留。')
body += bullet('AI 智能分析：基于学习记录自动生成智能周报，分析科目时长分布、专注趋势、效率变化，提供个性化学习建议。')
body += bullet('元服务实时触达：桌面服务卡片实时显示计时状态与今日统计，计时完成自动刷新，无需打开 App 即可掌握学习动态。')
body += bullet('异常中断接续：计时过程中 App 异常退出或被强杀，重启后自动检测未完成任务并弹出接续对话框，保障学习连续性。')
body += bullet('数据安全防护：笔记加密文件夹、设备白名单流转控制、分布式数据加密传输，全方位保障学习隐私安全。')
body += bullet('穿戴无感交互：手表震动替代弹窗，不打断专注，支持久坐提醒与实时进度查看（增强功能）。')
body += p('')

body += heading('3. 核心功能与交互', 3)

body += p('（1）专注计时', bold=True)
body += p('一键启停，支持 5/15/25/45/60 分钟五档时长预设，滑动切换；内置专注免打扰模式，计时期间自动屏蔽通知干扰；支持自定义科目标签（高等数学、英语、编程等），每次计时关联具体科目，便于后续分类统计；计时完成自动保存学习记录到关系型数据库，并实时更新桌面卡片。异常中断时自动保存会话状态，重启后弹出接续对话框，可选择继续学习或取消。')
body += p('图表 3：专注计时页面效果图')
body += p('')

body += p('（2）多端笔记流转', bold=True)
body += p('支持新建、编辑、删除笔记，笔记可关联科目标签；点击流转按钮自动搜索同账号设备，一键迁移并保留编辑状态，实时同步；内置 AI 笔记解析功能，可自动提取笔记要点、生成学习摘要；支持加密文件夹，敏感笔记需密码访问；数据加密传输存储，流转需二次确认并受设备白名单控制，保障隐私安全。')
body += p('图表 4：笔记流转页面效果图')
body += p('')

body += p('（3）数据统计与 AI 智能周报', bold=True)
body += p('多维度数据统计：今日/本周/本月专注时长趋势、科目学习时长分布饼图、完成次数统计；AI 智能周报基于历史学习数据自动生成，分析各科投入占比、专注效率变化趋势、学习习惯评估，并给出针对性改进建议；支持按科目筛选查看统计详情。')
body += p('图表 5：数据统计与 AI 周报页面效果图')
body += p('')

body += p('（4）桌面元服务卡片', bold=True)
body += p('桌面服务卡片实时显示当前计时状态、今日累计专注时长、今日待学科目；计时开始、暂停、完成各节点自动触发卡片更新，无需打开 App 即可掌握学习动态；卡片数据通过偏好存储（Preferences）持久化，App 被杀后卡片仍保持最新状态；支持点击卡片快速跳转至计时页面。')
body += p('图表 6：桌面卡片效果图')
body += p('')

body += p('（5）久坐提醒与穿戴联动', bold=True)
body += p('计时节点震动提醒，手表实时查看进度；久坐自动提醒，保障学习健康；手表为增强功能，未佩戴时自动切换手机提醒，全场景适配。')
body += p('图表 7：穿戴联动示意图')
body += p('')

body += p('（6）数据安全与备份', bold=True)
body += p('加密文件夹：敏感笔记独立加密存储，需密码解锁；设备白名单：仅允许白名单内设备接收流转数据，防止误流转到陌生设备；离线缓存：网络异常时学习数据本地缓存，恢复后自动同步；数据备份：支持学习记录与笔记的本地备份与恢复，防止数据丢失。')
body += p('')

body += heading('4. 多端互动场景', 3)
body += table(
    ['场景', '设备', '交互', '价值'],
    [
        ['图书馆自习', '手机+手表', '手机启动计时，手表震动提醒节点', '静音不扰人，专注不中断'],
        ['换设备学习', '手机+平板', '一键流转笔记，自动同步编辑状态', '大屏高效，进度无缝接续'],
        ['碎片化学习', '手机桌面', '元服务卡片一键启动，实时看进度', '无需开App，快速进入状态'],
        ['异常中断', '手机', '强杀App后重启自动弹出接续对话框', '学习不丢失，连续性有保障'],
        ['周复盘', '手机', 'AI智能周报自动生成，分析学习趋势', '数据驱动，针对性改进'],
    ]
)
body += p('')

body += heading('5. 竞品差异化对比', 3)
body += table(
    ['维度', '普通番茄APP', '传统笔记软件', '本作品'],
    [
        ['设备支持', '单手机端', '账号手动同步', '三端原生互联'],
        ['提醒方式', '仅手机弹窗', '无计时提醒', '弹窗+手表双提醒'],
        ['启动效率', '需打开App', '需打开App', '桌面卡片一键启动'],
        ['数据分析', '基础统计', '无', 'AI智能周报+多维度统计'],
        ['异常恢复', '无接续', '自动保存草稿', '会话状态持久化+接续对话框'],
        ['数据安全', '普通加密', '部分支持', '加密文件夹+设备白名单+流转确认'],
    ]
)
body += p('')

body += heading('6. 技术实现路径', 3)
body += p('本项目基于 HarmonyOS NEXT 平台，采用 ArkTS 语言与 Stage 模型开发，整体架构分为 UI 层、业务逻辑层、数据持久层三层：')
body += p('')
body += p('UI 层：使用 ArkUI 声明式开发，包含专注计时（Index）、笔记（Notes）、统计（Statistics）、AI 报告（Report）四大主页面，以及加密文件夹、设备白名单、接续对话框等功能页面。底部导航统一使用 Circle 组件实现选中指示器，避免 Unicode 字符兼容性问题。')
body += p('')
body += p('业务逻辑层：包含 20+ 功能管理器模块，核心包括：')
body += bullet('ContinuationManager：异常中断会话状态管理，基于 Preferences 持久化')
body += bullet('SubjectTagManager：科目标签增删改查，基于关系型数据库')
body += bullet('AIAnalysisService：AI 学习分析与周报生成')
body += bullet('FocusModeManager：专注免打扰模式控制')
body += bullet('SedentaryReminderManager：久坐提醒管理')
body += bullet('SecurityManager：数据加密与解密')
body += bullet('DeviceWhitelistManager：流转设备白名单管理')
body += bullet('OfflineCacheManager：离线数据缓存')
body += bullet('CalendarSyncManager：日历同步')
body += bullet('ShareManager：内容分享')
body += p('')
body += p('数据持久层：采用三级存储架构：')
body += bullet('关系型数据库（relationalStore）：存储学习记录、笔记、科目标签等结构化数据，支持 SQL 查询与事务')
body += bullet('偏好存储（Preferences）：存储用户配置、卡片数据、会话状态快照等轻量级键值对')
body += bullet('分布式数据对象（distributedDataObject）：实现跨设备实时数据同步')
body += p('')
body += p('桌面服务卡片：基于 FormKit 开发，EntryFormAbility 负责卡片生命周期管理，通过 formProvider.updateForm 实现主动更新，formId 持久化到 Preferences 确保 App 重启后仍能更新卡片。')
body += p('')
body += p('项目不依赖复杂后端服务，所有数据本地存储与处理，单人即可完成全链路开发与迭代。')
body += p('')

body += heading('7. 市场前景评估', 3)
body += p('全国高校在校生超 3000 万，备考群体庞大，学习工具需求旺盛。市面同类产品均为单端应用，缺乏鸿蒙原生多端协同能力。本作品填补鸿蒙轻量化学习工具空白，具备以下优势：')
body += bullet('鸿蒙原生：深度适配分布式能力、服务卡片、跨设备流转，体验优于第三方跨平台方案')
body += bullet('AI 赋能：智能周报与学习分析提升产品附加值，区别于传统计时工具')
body += bullet('轻量无后端：纯本地架构，无需服务器成本，易迭代易上架')
body += bullet('隐私安全：数据本地存储，加密保护，符合用户对学习隐私的诉求')
body += p('具备华为应用市场上架潜力，兼具社会价值（提升学习效率）与商业价值（付费高级功能、AI 分析订阅）。')
body += p('')
body += p('—— 文档结束 ——')

# 生成 document.xml
document_xml = f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:body>
{body}
<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1440" w:right="1440" w:bottom="1440" w:left="1440" w:header="708" w:footer="708" w:gutter="0"/></w:sectPr>
</w:body>
</w:document>'''

content_types = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
<Default Extension="xml" ContentType="application/xml"/>
<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>
</Types>'''

rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
</Relationships>'''

word_rels = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>
</Relationships>'''

styles = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<w:styles xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/><w:rPr><w:rFonts w:ascii="Calibri" w:hAnsi="Calibri" w:eastAsia="宋体"/><w:sz w:val="22"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:before="360" w:after="200"/></w:pPr><w:rPr><w:b/><w:sz w:val="36"/><w:rFonts w:eastAsia="黑体"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:before="280" w:after="160"/></w:pPr><w:rPr><w:b/><w:sz w:val="28"/><w:rFonts w:eastAsia="黑体"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading3"><w:name w:val="heading 3"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:before="200" w:after="120"/></w:pPr><w:rPr><w:b/><w:sz w:val="24"/><w:rFonts w:eastAsia="黑体"/></w:rPr></w:style>
<w:style w:type="paragraph" w:styleId="Heading4"><w:name w:val="heading 4"/><w:basedOn w:val="Normal"/><w:next w:val="Normal"/><w:pPr><w:spacing w:before="160" w:after="100"/></w:pPr><w:rPr><w:b/><w:sz w:val="20"/><w:rFonts w:eastAsia="黑体"/></w:rPr></w:style>
</w:styles>'''

with zipfile.ZipFile(OUTPUT, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', content_types)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/_rels/document.xml.rels', word_rels)
    z.writestr('word/styles.xml', styles)
    z.writestr('word/document.xml', document_xml)

print(f'Document generated: {OUTPUT}')
print(f'File size: {os.path.getsize(OUTPUT)} bytes')
