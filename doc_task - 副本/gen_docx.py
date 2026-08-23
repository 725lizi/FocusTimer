#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""生成 FocusTimer3 报错踩坑文档 docx"""
import zipfile
import os
from xml.sax.saxutils import escape

OUTPUT = r"C:\Users\qq959\FocusTimer3\FocusTimer3高频报错踩坑全文档.docx"

def p(text, style=None, bold=False, size=None):
    """生成段落 XML"""
    style_xml = ''
    if style:
        style_xml = f'<w:pStyle w:val="{style}"/>'
    rpr = ''
    if bold or size:
        rpr = '<w:rPr>'
        if bold:
            rpr += '<w:b/>'
        if size:
            rpr += f'<w:sz w:val="{size}"/>'
        rpr += '</w:rPr>'
    # 处理换行
    parts = text.split('\n')
    runs = ''
    for i, part in enumerate(parts):
        if i > 0:
            runs += '<w:r><w:br/></w:r>'
        runs += f'<w:r>{rpr}<w:t xml:space="preserve">{escape(part)}</w:t></w:r>'
    return f'<w:p><w:pPr>{style_xml}</w:pPr>{runs}</w:p>'

def heading(text, level=1):
    """生成标题"""
    sizes = {1: 36, 2: 28, 3: 24, 4: 20}
    return p(text, style=f'Heading{level}', bold=True, size=sizes.get(level, 20))

def code_block(text):
    """生成代码块（等宽字体，灰色背景模拟）"""
    lines = text.split('\n')
    result = ''
    for line in lines:
        result += f'<w:p><w:pPr><w:shd w:val="clear" w:color="auto" w:fill="F5F5F5"/><w:ind w:left="200"/></w:pPr><w:r><w:rPr><w:rFonts w:ascii="Consolas" w:hAnsi="Consolas"/><w:sz w:val="18"/></w:rPr><w:t xml:space="preserve">{escape(line) if line else " "}</w:t></w:r></w:p>'
    return result

def bullet(text):
    """生成列表项"""
    return p('• ' + text)

# 构建文档内容
body = ''

# ===== 文档头 =====
body += heading('FocusTimer3 鸿蒙应用高频报错踩坑全文档', 1)
body += p('文档定位：汇总 FocusTimer3 鸿蒙应用开发中遇到的 6 类高频疑难报错（ArkTS 编译约束、模块导入、桌面服务卡片、分布式数据与偏好存储、运行时 UI 渲染、数据持久化与业务逻辑），统一采用「报错现象 → 根因分析 → 代码复现 → 解决方案 → 面试核心考点」结构，为鸿蒙项目复盘、Bug 排查、面试口述提供标准化素材。')
body += p('适用场景：HarmonyOS NEXT 应用开发、ArkTS/Stage 模型项目、桌面服务卡片（FormKit）、分布式数据对象（distributedDataObject）、偏好存储（preferences）、关系型数据库（relationalStore）、异步初始化时序、数据持久化测试。')
body += p('')

# ===== 一、ArkTS 编译约束报错 =====
body += heading('一、ArkTS 编译约束报错（语法与类型系统高频）', 2)

body += heading('1. 报错现象', 3)
body += p('编译阶段抛出大量类型检查错误，常见报错：')
body += bullet('Object literal must correspond to some explicitly declared class or interface (arkts-no-untyped-obj-literals)')
body += bullet('Use explicit types instead of "any", "unknown" (arkts-no-any-unknown)')
body += bullet('Indexed signatures are not supported (arkts-no-indexed-signatures)')
body += bullet("Argument of type 'xxxValues' is not assignable to parameter of type 'Record'")
body += bullet('Invalid regular expression: Range out of order in character class')
body += bullet("'@Entry' should have a parameter 或 Unable to resolve signature of class decorator")
body += bullet('Module \'"@kit.ArkUI"\' has no exported member \'DrawingRenderingContext\'')
body += p('多出现于：数据模型定义、分布式数据对象操作、工具类封装、UI 组件装饰器使用、正则表达式解析等场景。')

body += heading('2. 核心报错原因', 3)
body += bullet('对象字面量无类型：ArkTS 强制所有对象字面量必须明确实现接口或类，不允许无类型对象。')
body += bullet('any/unknown 滥用：ArkTS 不允许使用 any/unknown，需显式声明具体类型或联合类型。')
body += bullet('索引签名被禁用：[key: string]: any 等索引签名语法不被支持，需改用具体字段或 Map 类型。')
body += bullet('类型不匹配：自定义类型与系统 API 期望类型不兼容。')
body += bullet('正则表达式转义错误：反斜杠层级在 ArkTS 中需特殊处理，字符类范围错误。（项目 AIAnalysisService 中实际踩坑）')
body += bullet('装饰器参数缺失：@Entry 使用规则误用导致编译失败。')
body += bullet('未导出或未提供类型：某些 Kit 模块内部类型未开放，直接导入报错。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：无类型对象字面量（项目 Constants.ets 中已修正）
let subject = { id: 1, name: '数学' }; // 报错：需对应接口

// 错误2：使用 any
let data: any = fetchData(); // 报错：禁止 any

// 错误3：索引签名（项目离线缓存中需避免）
interface CacheMap {
  [key: string]: string; // 报错：索引签名不支持
}

// 错误4：正则过度转义（AIAnalysisService.ets 中实际出现）
// 项目原代码：
const formulaPattern = /(\\\\$[^$]+\\\\$)|(\\\\\\[a-zA-Z]+...)/g;
// 修正后：
const formulaPattern = /(\\$[^$]+\\$)|(\\\\[a-zA-Z]+(\\{[^}]*\\})*)/g;

// 错误5：字符串中换行符过度转义（AIAnalysisService.ets 中实际出现）
// 项目原代码：
suggestion += '\\\\n💡 近期专注力呈下降趋势'; // 渲染显示字面 \\n
// 修正后：
suggestion += '\\n💡 近期专注力呈下降趋势'; // 正确换行

// 错误6：@Entry 误用
@Entry('widget') // 参数错误
struct FocusTimerCard { ... }

// 错误7：导入未导出类型
import { DrawingRenderingContext } from '@kit.ArkUI'; // 无此导出""")

body += heading('4. 完整解决方案', 3)
body += bullet('为对象定义 interface：所有对象字面量显式声明类型，如 SubjectTagValues、NoteValues、OfflineQueueItem 等。')
body += bullet('显式类型替代 any：使用具体类型、联合类型或 Object | undefined。')
body += bullet('移除索引签名：改用具名字段；如需动态键值，使用 Map<string, number> 替代。')
body += bullet('修正正则转义：ArkTS 中正则表达式的反斜杠转义规则与标准 TypeScript 一致，不需要多重转义。')
body += bullet('字符串中的换行符：使用 \\n 而非 \\\\n，同时确保 Text 组件设置 .multiLine(true)。')
body += bullet('@Entry 参数规则：卡片页面使用 @Entry 不带参数，普通页面可带参数但需符合规范。')
body += bullet('移除不可用类型：若 Kit 未导出某类型，则改用替代方案或自定义绘制。')

body += heading('5. 面试核心考点', 3)
body += p('Q：ArkTS 为什么禁止 any/unknown？和 TypeScript 有什么区别？')
body += p('A：ArkTS 是 TypeScript 的静态类型子集，为了保证运行时性能和跨设备一致性，强制要求全量类型标注，禁止动态类型。any/unknown 会绕过类型检查，导致运行时类型不确定，在鸿蒙分布式场景下可能引发跨设备数据同步异常。')
body += p('Q：正则表达式在 ArkTS 中转义有什么坑？')
body += p('A：ArkTS 正则转义规则与标准 TS 一致，但在字符串拼接和模板字符串中容易出现多重转义。建议直接使用正则字面量 /pattern/，避免 new RegExp("\\\\d") 这类字符串构造。项目中实际踩坑是将 \\$ 写成了 \\\\$，导致匹配失败。')
body += p('')

# ===== 二、模块导入与路径错误 =====
body += heading('二、模块导入与路径错误（工程结构高频）', 2)

body += heading('1. 报错现象', 3)
body += p('编译报错：')
body += bullet("Cannot find module '../common/ContinuationManager'")
body += bullet('Module \'"../common/OfflineCacheManager"\' has no exported member \'OfflineCacheManager\'')
body += bullet("Cannot find module './DatabaseHelper'")
body += p('多出现在：重构目录结构、文件名大小写变更、导出遗漏、相对路径错误。')

body += heading('2. 核心报错原因', 3)
body += bullet('文件名大小写不一致：导入时写 ContinuationManager 但实际文件名大小写不同（HarmonyOS 文件系统大小写敏感）。')
body += bullet('导出缺失：类未正确使用 export class，或文件被覆盖后丢失导出。')
body += bullet('路径错误：项目重构后目录层级变化，相对路径失效。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：大小写不匹配
import { ContinuationManager } from '../common/ContinuationManager';
// 文件实际为 continuationManager.ets

// 错误2：模块无导出成员（项目重构后实际出现）
import { OfflineCacheManager } from '../common/OfflineCacheManager';
// 文件中实际导出的类名与导入名不一致

// 错误3：路径错误
import { DatabaseHelper } from './DatabaseHelper';
// 实际位置为 ../common/DatabaseHelper""")

body += heading('4. 完整解决方案', 3)
body += bullet('统一文件名大小写：使用 PascalCase，保持导入与文件名完全一致。')
body += bullet('检查导出语句：确保类前有 export，且导出名称与导入名称匹配。')
body += bullet('使用相对路径规范：项目重构后统一路径结构，pages/ 页面组件、common/ 工具类、model/ 数据模型与常量、entryability/ 入口 Ability。')
body += bullet('编辑器自动导入：利用 DevEco Studio 自动补全导入路径，减少手动书写错误。')

body += heading('5. 面试核心考点', 3)
body += p('Q：鸿蒙项目中模块导入报错最常见的三个原因是什么？')
body += p('A：①文件名大小写不匹配（鸿蒙构建系统大小写敏感）；②导出语句缺失或名称不一致；③重构后相对路径层级错误。排查顺序：先看文件名大小写，再看 export 语句，最后核对相对路径。')
body += p('')

# ===== 三、桌面服务卡片开发报错 =====
body += heading('三、桌面服务卡片开发报错（FormKit 高频）', 2)

body += heading('1. 报错现象', 3)
body += p('编译阶段报错：')
body += bullet('Use explicit types instead of "any", "unknown" (arkts-no-any-unknown)')
body += bullet("Property 'formId' does not exist on type 'FormInfo'")
body += bullet("Conversion of type 'FormInfo[]' to type 'FormInfoWithId[]' may be a mistake")
body += bullet('No overload matches this call / requestPublishForm 不存在')
body += p('运行时问题：')
body += bullet('卡片数据写死（永远显示 25:00、今日待学：高等数学），计时完成后不更新')
body += bullet('杀掉 App 后卡片变回初始状态，formId 丢失')
body += bullet('今日专注显示异常数值（如 300 分钟），单位错乱')
body += bullet('日志无 [Widget] 相关输出，requestUpdate 未执行或执行失败')

body += heading('2. 核心报错原因', 3)
body += bullet('ArkTS 类型约束：不能用 any/unknown 双重断言，FormInfo 类型定义中无 formId 字段但运行时实际有。')
body += bullet('API 误用：formProvider.getFormsInfo() 不接受 Context 参数；requestPublishForm 是 formHost 的方法而非 formProvider。')
body += bullet('数据写死：EntryFormAbility 的 onAddForm、updateCard、requestUpdate 三处直接写死 focusTime="25:00"、taskInfo="今日待学：高等数学"。')
body += bullet('formId 仅存内存：latestFormId 是静态变量，App 进程被杀后清空，重启后 requestUpdate 找不到目标卡片。')
body += bullet('单位不一致：旧代码 todayTotal 存的是单次计时秒数（this.totalSecond），新代码期望存今日累计分钟数，读取时直接当分钟用导致数值放大 60 倍。')
body += bullet('权限缺失：module.json5 未添加 ohos.permission.REQUIRE_FORM，主动更新卡片静默失败。')
body += bullet('调用时机错误：只在计时完成时更新卡片，且未 await 异步操作，可能被进程销毁中断。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：用 unknown 双重断言（ArkTS 禁止）
const formId = (info as unknown as FormInfoWithId).formId;

// 错误2：FormInfo 无 formId 字段，直接访问编译报错
const formInfos = await formProvider.getFormsInfo();
const formId = formInfos[0].formId; // 编译报错

// 错误3：getFormsInfo 传了 Context 参数
const formInfos = await formProvider.getFormsInfo(context); // 参数错误

// 错误4：卡片数据三处写死（EntryFormAbility.ets 实际出现）
onAddForm(want) {
  const cardData = {
    title: '专注计时',
    focusTime: '25:00',        // 写死
    taskInfo: '今日待学：高等数学', // 写死
    todayMinutes: '0分钟'
  };
}

// 错误5：formId 只存静态变量，杀 App 即丢
private static latestFormId: string = '';
// App 重启后 latestFormId = ''，requestUpdate 直接 return

// 错误6：todayTotal 存的是秒数但当分钟读（Index.ets 实际出现）
await prefs.put('todayTotal', this.totalSecond); // 存 1500（秒）
// 卡片读取：const todayMinutes = await prefs.get('todayTotal', 0);
// 直接显示 `${todayMinutes}分钟` → 显示 1500分钟""")

body += heading('4. 完整解决方案', 3)
body += p('（1）类型断言用 object 替代 unknown：')
body += code_block("""interface FormInfoWithId extends formInfo.FormInfo {
  formId: string;
}
const formId = (info as object as FormInfoWithId).formId;""")

body += p('（2）formId 持久化到 Preferences，App 重启不丢失：')
body += code_block("""private static readonly PREFS_NAME = 'focusUserPrefs';
private static readonly FORM_ID_KEY = 'cardFormId';

// 保存 formId
private static async saveFormId(context, formId) {
  const prefs = await preferences.getPreferences(context, EntryFormAbility.PREFS_NAME);
  await prefs.put(EntryFormAbility.FORM_ID_KEY, formId);
  await prefs.flush();
  EntryFormAbility.latestFormId = formId;
}

// requestUpdate 三级获取：内存 → Preferences → getFormsInfo()
static async requestUpdate(context) {
  let formId = EntryFormAbility.latestFormId;
  if (!formId) {
    const prefs = await preferences.getPreferences(context, 'focusUserPrefs');
    formId = await prefs.get('cardFormId', '') as string;
  }
  if (!formId) {
    const formsInfo = await formProvider.getFormsInfo();
    // 遍历获取 formId...
  }
  // ... 更新卡片
}""")

body += p('（3）卡片数据全部从 Preferences 动态读取，不写死：')
body += code_block("""private static async loadCardData(context) {
  const prefs = await preferences.getPreferences(context, 'focusUserPrefs');
  const todayMinutes = await prefs.get('todayTotal', 0) as number;
  const lastDuration = await prefs.get('lastDuration', 0) as number;
  const lastSubject = await prefs.get('lastSubject', '') as string;
  const min = Math.floor(lastDuration);
  return {
    title: '专注计时',
    focusTime: `${min < 10 ? '0' + min : min}:00`,
    taskInfo: lastSubject ? `今日待学：${lastSubject}` : '今日待学：未选择',
    todayMinutes: `${todayMinutes}分钟`
  };
}""")

body += p('（4）Index.ets 计时完成后存正确数据并 await 卡片更新：')
body += code_block("""// 存今日累计分钟数（不是秒数）
await prefs.put('todayTotal', dbMinutes);
await prefs.put('lastDuration', Math.floor(this.totalSecond / 60));
await prefs.put('lastSubject', tagName || '未分类');
await prefs.flush();
// 主动更新卡片，必须 await
await EntryFormAbility.requestUpdate(getContext(this));""")

body += p('（5）添加权限并重装：module.json5 的 requestPermissions 中添加 ohos.permission.REQUIRE_FORM，修改权限后必须卸载重装。')

body += heading('5. 面试核心考点', 3)
body += p('Q：鸿蒙桌面卡片主动更新的完整链路是什么？')
body += p('A：①主应用将最新数据写入 preferences；②调用 formProvider.updateForm(formId, formBindingData) 推送更新；③FormExtensionAbility 的 onUpdateForm 回调接收；④卡片 UI 通过 @LocalStorageProp 绑定数据自动刷新。关键是 formId 必须持久化，不能只存内存。')
body += p('Q：为什么卡片数据更新了但桌面没变化？')
body += p('A：常见原因：①formId 失效或为空（App 重启后丢失）；②REQUIRE_FORM 权限未授予；③getFormsInfo() 返回空（桌面没添加卡片）；④数据写入和卡片更新之间存在时序问题，未 await 异步操作。排查顺序：先看桌面是否添加了卡片，再查权限，最后打日志看 formId 和 updateForm 返回值。')
body += p('')

# ===== 四、分布式数据与偏好存储运行时错误 =====
body += heading('四、分布式数据与偏好存储运行时错误（初始化与时序高频）', 2)

body += heading('1. 报错现象', 3)
body += bullet('计时到一半强杀 App，重开后不弹出「发现未完成的学习任务」接续对话框')
body += bullet('接续对话框有延迟，需切换到统计页再切回计时页才弹出')
body += bullet('分布式数据对象 set() 操作无效果，远端设备未收到变更')
body += bullet('preferences.getPreferencesSync() 返回 null 或抛异常')
body += bullet('离线队列数据丢失，flush() 后数据未同步')
body += bullet('跨设备接续时，远程设备获取到旧数据快照')
body += p('多出现于：应用启动时分布式数据初始化、离线缓存同步、跨设备任务接续、异常中断恢复场景。')

body += heading('2. 核心报错原因', 3)
body += bullet('会话状态仅存内存：ContinuationManager.sessionState 是普通成员变量，saveSessionState() 只改内存，未写入任何持久化存储，App 被杀即丢失。')
body += bullet('init() 从未被调用：ContinuationManager.init(context) 在整个项目中没有任何调用点，context 始终为 null，分布式对象和 Preferences 都无法初始化。')
body += bullet('异步初始化时序错乱：EntryAbility.onCreate 是 async 但系统不等待其完成，页面 aboutToAppear 可能在 init 执行前触发；checkContinuation 读内存状态时，Preferences 加载尚未完成。')
body += bullet('分布式数据对象未初始化：调用 set() 前 distributedDataObject 未完成 create 和 setStorage。')
body += bullet('偏好存储上下文错误：preferences 操作需要有效 Context，在 Ability 外调用会失败。')
body += bullet('change 回调与 UI 更新不同步：分布式数据变更触发回调，但 AppStorage 快照更新与 UI 轮询存在时间差。')
body += bullet('离线队列序列化失败：对象中包含不可序列化属性（函数、undefined），JSON.stringify 丢失数据。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：sessionState 只存内存，未持久化（ContinuationManager.ets 实际出现）
private sessionState: SessionState = { active: false, ... };

public async saveSessionState(...) {
  this.sessionState.active = isActive; // 只改内存
  // 没有写入 preferences 或数据库
}
// App 被杀后 sessionState 重置为 active=false

// 错误2：init() 从未被调用（项目实际出现）
public init(context: Context): void {
  this.context = context;
  this.sessionObj = distributedDataObject.create(context, this.sessionState);
  this.loadSessionStateFromPrefs(); // 异步，没人 await
}
// EntryAbility.onCreate 中没有调用 ContinuationManager.getInstance().init()

// 错误3：checkContinuation 读内存，时序错乱（Index.ets 实际出现）
async aboutToAppear() {
  this.checkContinuation(); // 此时 init 可能还没完成
}
private async checkContinuation() {
  const sessionState = continuationManager.getSessionState(); // 读内存，可能还是默认值
  if (sessionState.active === true) { ... }
}

// 错误4：偏好存储在 Ability 外调用
const prefs = preferences.getPreferencesSync(null, { name: 'offlineCache' });
// context 为 null，抛异常""")

body += heading('4. 完整解决方案', 3)
body += p('（1）会话状态持久化到 Preferences：')
body += code_block("""private async saveSessionStateToPrefs() {
  const prefs = await preferences.getPreferences(this.context, 'continuation_session');
  await prefs.put('session_state', JSON.stringify(this.sessionState));
  await prefs.flush();
}

public async saveSessionState(...) {
  this.sessionState.active = isActive;
  // ... 更新其他字段
  await this.saveSessionStateToPrefs(); // 关键：持久化
}""")

body += p('（2）EntryAbility.onCreate 中调用 init()：')
body += code_block("""async onCreate(want, launchParam) {
  await DatabaseHelper.getInstance().init(this.context);
  ContinuationManager.getInstance().init(this.context); // 新增
  this.initDistributedFocus();
  this.initDistributedNote();
}""")

body += p('（3）checkContinuation 直接从 Preferences 读取，绕过时序问题：')
body += code_block("""private async checkContinuation() {
  // 直接读 Preferences，不依赖内存初始化时序
  const prefs = await preferences.getPreferences(getContext(this), 'continuation_session');
  const saved = await prefs.get('session_state', '') as string;
  if (!saved) return;
  const sessionState = JSON.parse(saved);
  if (sessionState.active === true) {
    this.showContinuationDialog = true;
  }
}""")

body += p('（4）Context 传递规范：偏好存储操作统一在 Ability 中初始化，通过构造参数传递给工具类，禁止在工具类中直接获取 Context。')
body += p('（5）离线队列序列化：入队前将 payload 通过 JSON.stringify 转为字符串存储，出队后 JSON.parse 恢复；禁止存储函数、Symbol 等不可序列化类型。')

body += heading('5. 面试核心考点', 3)
body += p('Q：鸿蒙应用中异步初始化时序问题怎么排查和解决？')
body += p('A：根本原因是 UIAbility.onCreate 声明为 async 但系统不等待其 Promise 完成，页面 aboutToAppear 可能先于初始化执行。解决方案：①关键状态直接从持久化存储读取，不依赖内存初始化；②用 initPromise 模式，暴露 ensureInitialized() 方法供页面等待；③在页面 aboutToAppear 中对依赖初始化的数据做空值兜底。')
body += p('Q：偏好存储 preferences 和关系型数据库 relationalStore 的使用场景区别？')
body += p('A：preferences 适合轻量级键值对（如用户配置、卡片数据、状态快照），读写快但不适合复杂查询；relationalStore 适合结构化数据（如学习记录、笔记列表），支持 SQL 查询和事务。接续状态这种单条 JSON 数据用 preferences 更合适。')
body += p('')

# ===== 五、运行时 UI 渲染异常 =====
body += heading('五、运行时 UI 渲染异常（空值与显示高频）', 2)

body += heading('1. 报错现象', 3)
body += bullet('底部导航图标显示 ? / ?? 问号，而非预期的圆点或图标')
body += bullet('页面加载失败，白屏或闪退，日志显示「页面加载失败」')
body += bullet('进度显示 undefined%，dailyGoalProgress 计算异常')
body += bullet('AI 周报内容显示 \\n 字符（字面换行符未解析）')
body += bullet('科目标签菜单不弹出或位置异常')
body += p('多出现于：数据加载时序、计算属性依赖、字符串处理、弹窗组件、Unicode 字符渲染。')

body += heading('2. 核心报错原因', 3)
body += bullet('Unicode 字符缺字形：Text(\'●\') 使用 U+25CF 黑圆点字符，部分设备/模拟器系统字体无对应字形，fallback 渲染为问号。（项目底部导航实际踩坑）')
body += bullet('Builder 未正确标记：弹窗 Builder 函数未加 @Builder 装饰，导致弹窗构建失败。')
body += bullet('布局溢出：页面内容超出屏幕高度，渲染引擎崩溃。')
body += bullet('计算属性返回 undefined/NaN：依赖数据未初始化，除法运算分母为零或空。')
body += bullet('字符串转义错误：生成文本中使用 \\\\n（双反斜杠），前端直接显示为字面 \\n。')
body += bullet('bindMenu 数据源为空：科目标签菜单的数据列表未在 onAppear 前赋值。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：Unicode 字符缺字形（Index.ets / Notes.ets 实际出现）
Column() {
  Text('●').fontSize(8).fontColor(Constants.COLOR_PRIMARY); // 部分设备显示 ?
  Text('计时');
}
// Report.ets 中甚至直接写死了问号
Text('?').fontSize(22);  // 源码就是问号
Text('??').fontSize(22);

// 错误2：缺失 @Builder
continuationDialogBuilder() {  // 未加 @Builder，弹窗构建失败
  Text('检测到未完成的任务');
}

// 错误3：计算属性未处理空值
get dailyGoalProgress() {
  return (this.completed / this.total) * 100;
  // total 为 0 时得到 NaN，显示 undefined%
}

// 错误4：AI 周报字符串包含字面 \\n（AIAnalysisService.ets 实际出现）
let report = '今日总结\\\\n\\\\n完成度80%'; // 渲染显示字面 \\n""")

body += heading('4. 完整解决方案', 3)
body += bullet('用图形组件替代 Unicode 字符：底部导航指示器改用 Circle({ width: 6, height: 6 }).fill(color)，所有设备都能正常渲染，不依赖系统字体。')
body += bullet('Builder 装饰器：确保所有 Builder 函数前有 @Builder，调用时使用 this.xxxBuilder()。')
body += bullet('使用 Scroll 组件：将页面根布局包裹在 Scroll 中，避免内容溢出。')
body += bullet('计算属性加 isNaN 检查：使用 @State 变量存储进度，数据变化时计算并更新，添加零值和 NaN 兜底。')
body += bullet('字符串换行修复：显示前执行 .replace(/\\\\n/g, \'\\n\')，同时 Text 组件加 .multiLine(true)。')
body += bullet('bindMenu 数据源初始化：在组件 aboutToAppear 中确保数据已加载，避免空菜单。')

body += heading('5. 面试核心考点', 3)
body += p('Q：为什么 Text 组件里的特殊字符会显示成问号？')
body += p('A：这是字体字形（glyph）缺失问题。Text 组件渲染依赖系统字体，当字符的 Unicode 码位在当前字体中没有对应字形时，系统会 fallback 到问号或豆腐块（□）。解决方案：①用图形组件（Circle、Image）替代文字字符；②使用 SymbolGlyph 系统符号组件；③嵌入自定义字体文件。')
body += p('Q：鸿蒙 UI 渲染中白屏/闪退的常见排查顺序？')
body += p('A：①看 HiLog 有无页面加载失败日志；②检查 @Builder 装饰器是否缺失；③检查布局是否溢出（内容超出屏幕高度）；④检查计算属性是否返回 NaN/undefined；⑤检查 @State 变量初始化是否为空导致渲染异常。')
body += p('')

# ===== 六、数据持久化与业务逻辑报错 =====
body += heading('六、数据持久化与业务逻辑报错（计时与统计高频）', 2)

body += heading('1. 报错现象', 3)
body += bullet('统计页「科目学习时长分布」显示「5分钟」「25分钟」，而非真实科目名（高数/英语）')
body += bullet('AI 智能周报「各科情况」显示「5分钟：5分钟」「25分钟：15分钟」，科目名和时长都是时长标签')
body += bullet('修改默认时长索引后，计时器仍跑旧时长（如默认改成10秒但实际跑25分钟）')
body += bullet('今日专注显示异常大数值（如300分钟），与实际不符')
body += bullet('异常中断后今日次数/时长错误增加（未完成也被计数）')
body += p('多出现于：计时完成保存逻辑、统计页数据聚合、默认值同步、数据持久化测试场景。')

body += heading('2. 核心报错原因', 3)
body += bullet('tags 字段存错数据：saveCurrentSession() 中 tags 存的是 Constants.PRESET_LABELS[labelIndex]（时长预设名如"5分钟"），而非用户选择的真实科目名。统计页拿 tags 当科目分组，自然全错。')
body += bullet('selectedSubjectTagId 未使用：Index.ets 有 @State selectedSubjectTagId 记录用户选的科目，但保存时完全没用到。')
body += bullet('初始值不同步：selectedDuration 默认值改成 Constants.DEFAULT_INDEX 后，totalSecond 和 currentSecond 仍写死 1500（25分钟），导致实际计时时长与显示的预设选项不一致。')
body += bullet('旧数据单位残留：旧版 todayTotal 存秒数，新版存分钟数，升级后旧数据被当分钟读取，数值放大。')
body += bullet('Math.max(1, ...) 保护：saveCurrentSession 中 durationMinutes = Math.max(1, Math.floor(totalSecond/60))，不足1分钟按1分钟算，导致超短测试时长与数据库记录不一致。')
body += bullet('保存路径分叉：学习记录同时存数据库（saveStudySessionToDb）和 preferences（saveSession），两处 duration 计算逻辑不同，导致统计页与首页数据不一致。')

body += heading('3. 错误代码复现', 3)
body += code_block("""// 错误1：tags 存时长预设名而非科目名（Index.ets 实际出现）
private async saveCurrentSession() {
  const durationMinutes = Math.max(1, Math.floor(this.totalSecond / 60));
  const labelIndex = this.selectedDuration;
  const tagLabel = Constants.PRESET_LABELS[labelIndex] || '📚 日常学习';
  // tagLabel = "5分钟"、"25分钟" 等，不是科目名！
  const session = {
    id: Date.now().toString(),
    duration: durationMinutes,
    tags: [tagLabel],  // 存的是时长标签
    // this.selectedSubjectTagId 完全没用到
  };
}
// 统计页按 tags 分组 → 显示"5分钟""25分钟"当科目

// 错误2：初始值不同步（Index.ets 实际出现）
@State selectedDuration: number = 0; // 改成默认第一个（10秒）
@State totalSecond: number = 1500;    // 还是25分钟！
@State currentSecond: number = 1500;  // 还是25分钟！
// 用户选了"10秒"但实际跑25分钟，10秒后不弹完成

// 错误3：两处保存 duration 不一致
// 数据库：Math.floor(this.totalSecond / 60) → 10秒=0分钟
await continuationManager.saveStudySessionToDb(
  ..., Math.floor(this.totalSecond / 60), ...
);
// Preferences：Math.max(1, Math.floor(this.totalSecond / 60)) → 10秒=1分钟
const durationMinutes = Math.max(1, Math.floor(this.totalSecond / 60));""")

body += heading('4. 完整解决方案', 3)
body += p('（1）tags 存真实科目名：')
body += code_block("""private async saveCurrentSession() {
  const durationMinutes = Math.max(1, Math.floor(this.totalSecond / 60));
  // 通过 selectedSubjectTagId 查真实科目名
  let subjectName = '未分类';
  if (this.selectedSubjectTagId) {
    const tagManager = SubjectTagManager.getInstance();
    const name = await tagManager.getTagName(this.selectedSubjectTagId);
    if (name) subjectName = name;
  }
  const session = {
    id: Date.now().toString(),
    duration: durationMinutes,
    tags: [subjectName],  // 存真实科目名
  };
}""")

body += p('（2）初始值动态引用常量，杜绝不同步：')
body += code_block("""@State selectedDuration: number = Constants.DEFAULT_INDEX;
@State totalSecond: number = Constants.PRESET_DURATIONS[Constants.DEFAULT_INDEX];
@State currentSecond: number = Constants.PRESET_DURATIONS[Constants.DEFAULT_INDEX];""")

body += p('（3）统一两处 duration 计算逻辑：数据库和 preferences 使用相同的 duration 值，避免统计不一致。')
body += p('（4）旧数据兼容清洗：统计页加载时，把形如「\\d+分钟」的错误标签归为「未分类」，避免历史错误数据污染统计。')
body += code_block("""sessions = sessions.map(s => {
  s.tags = s.tags.map(tag => {
    if (/^\\d+分钟$/.test(tag)) return '未分类'; // 旧的错误标签
    return tag;
  });
  return s;
});""")

body += heading('5. 面试核心考点', 3)
body += p('Q：数据持久化测试中，如何验证数据真的写入了磁盘而不是只在内存？')
body += p('A：标准验证流程：①完成操作后强杀 App（从后台划掉，不是按主页键）；②重新打开 App；③检查数据是否恢复。如果数据还在，说明持久化成功；如果数据丢失，说明只存了内存。进阶验证：用 hdc 命令导出 .db 文件或 preferences XML 文件，用 sqlite3 或文本编辑器直接查看存储内容。')
body += p('Q：业务逻辑中「默认值不同步」这类 bug 怎么预防？')
body += p('A：核心原则是「单一数据源」。所有派生值从同一个常量动态计算，不写死字面量。比如计时时长应该从 Constants.PRESET_DURATIONS[selectedDuration] 读取，而不是各自维护独立的初始值。代码审查时重点检查：修改了默认配置后，所有引用的地方是否同步更新。')
body += p('')

# ===== 七、面试通用总结 =====
body += heading('七、面试通用总结（必背）', 2)
body += p('1. 编译类报错：根源是 ArkTS 类型约束（禁止 any/索引签名/无类型对象字面量）、正则与字符串转义、装饰器使用规范。属于开发阶段显性 bug，可通过严格类型定义、代码格式化提前规避。')
body += p('2. 模块导入类报错：根源是文件名大小写敏感、导出语句缺失、重构后相对路径失效。排查顺序：文件名大小写 → export 语句 → 相对路径层级。')
body += p('3. 桌面卡片类报错：核心是 formId 持久化、数据不写死、权限配置、异步 await。卡片更新链路：preferences 存数据 → formProvider.updateForm 推送 → @LocalStorageProp 绑定刷新。formId 必须存 Preferences，不能只存静态变量。')
body += p('4. 持久化与时序类报错：核心是状态只存内存、init 未被调用、异步初始化时序错乱。解决方案：关键状态直接从 Preferences 读取，不依赖内存初始化；EntryAbility.onCreate 中显式调用所有管理器的 init()。')
body += p('5. UI 渲染类报错：核心是 Unicode 字符缺字形、@Builder 缺失、计算属性 NaN、字符串转义错误。用图形组件替代文字字符，所有计算加零值兜底。')
body += p('6. 业务逻辑类报错：核心是字段存错数据（tags 存时长而非科目）、默认值不同步、多处保存逻辑不一致。预防原则：单一数据源、保存前校验字段含义、统一计算逻辑。')
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

# 生成其他必要文件
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

# 写入 docx
with zipfile.ZipFile(OUTPUT, 'w', zipfile.ZIP_DEFLATED) as z:
    z.writestr('[Content_Types].xml', content_types)
    z.writestr('_rels/.rels', rels)
    z.writestr('word/_rels/document.xml.rels', word_rels)
    z.writestr('word/styles.xml', styles)
    z.writestr('word/document.xml', document_xml)

print(f'Document generated: {OUTPUT}')
print(f'File size: {os.path.getsize(OUTPUT)} bytes')
