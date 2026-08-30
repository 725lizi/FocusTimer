import { formBindingData, formProvider, FormExtensionAbility, formInfo } from '@kit.FormKit';
import { Want } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { CardDataBuilder, CardData } from '../common/CardDataBuilder';

export default class EntryFormAbility extends FormExtensionAbility {
  // 内存缓存的 formId（App 运行期间用）
  private static latestFormId: string = '';
  // 持久化存储的 key
  private static readonly PREFS_NAME: string = 'focusUserPrefs';
  private static readonly FORM_ID_KEY: string = 'cardFormId';

  /**
   * 从 Preferences 读取持久化的 formId
   */
  private static async loadFormId(context: Context): Promise<string> {
    try {
      const prefs = await preferences.getPreferences(context, EntryFormAbility.PREFS_NAME);
      const savedId = await prefs.get(EntryFormAbility.FORM_ID_KEY, '') as string;
      if (savedId) {
        EntryFormAbility.latestFormId = savedId;
      }
      return savedId;
    } catch (err) {
      console.error('读取 formId 失败: ' + JSON.stringify(err));
      return '';
    }
  }

  /**
   * 保存 formId 到 Preferences（App 杀了也不丢）
   */
  private static async saveFormId(context: Context, formId: string): Promise<void> {
    try {
      const prefs = await preferences.getPreferences(context, EntryFormAbility.PREFS_NAME);
      await prefs.put(EntryFormAbility.FORM_ID_KEY, formId);
      await prefs.flush();
      EntryFormAbility.latestFormId = formId;
    } catch (err) {
      console.error('保存 formId 失败: ' + JSON.stringify(err));
    }
  }

  onAddForm(want: Want): formBindingData.FormBindingData {
    // 标准方式获取 formId
    const formId = want.parameters?.[formInfo.FormParam.IDENTITY_KEY] as string
      || want.parameters?.['ohos.extra.param.key.formIdentity'] as string
      || want.parameters?.['ohos.extra.form.id'] as string
      || '';

    if (formId) {
      EntryFormAbility.saveFormId(this.context, formId);
      this.loadAndUpdateCard(formId);
    }

    const cardData: CardData = {
      title: '专注计时',
      focusTime: '00:00',
      taskInfo: '今日待学：未选择',
      todayMinutes: '0分钟'
    };
    return formBindingData.createFormBindingData(cardData);
  }

  onUpdateForm(formId: string): void {
    EntryFormAbility.saveFormId(this.context, formId);
    this.loadAndUpdateCard(formId);
  }

  // 实例方法：加载真实数据并更新指定卡片
  private async loadAndUpdateCard(formId: string): Promise<void> {
    if (!formId) {
      console.error('formId 为空，跳过更新');
      return;
    }
    try {
      const cardData = await EntryFormAbility.loadCardData(this.context);
      const formData = formBindingData.createFormBindingData(cardData);
      await formProvider.updateForm(formId, formData);
    } catch (err) {
      console.error('更新卡片失败: ' + JSON.stringify(err));
    }
  }

  // 静态方法：从 preferences 读取真实卡片数据
  private static async loadCardData(context: Context): Promise<CardData> {
    try {
      const prefs = await preferences.getPreferences(context, EntryFormAbility.PREFS_NAME);
      const todayMinutes = await prefs.get('todayTotal', 0) as number;
      const lastDuration = await prefs.get('lastDuration', 0) as number;
      const lastSubject = await prefs.get('lastSubject', '') as string;

      return CardDataBuilder.build(todayMinutes, lastDuration, lastSubject);
    } catch (err) {
      console.error('加载卡片数据失败: ' + JSON.stringify(err));
      return CardDataBuilder.build(0, 0, '');
    }
  }

  // 主应用调用的静态方法：计时完成后主动刷新卡片
  static async requestUpdate(context: Context): Promise<void> {
    try {
      // 1. 优先用内存缓存
      let formId = EntryFormAbility.latestFormId;

      // 2. 内存没有，从 Preferences 读（App 重启后场景）
      if (!formId) {
        formId = await EntryFormAbility.loadFormId(context);
      }

      // 3. 还没有，尝试从系统获取所有卡片
      if (!formId) {
        const formsInfo = await formProvider.getFormsInfo();
        if (formsInfo && formsInfo.length > 0) {
          for (const item of formsInfo) {
            const id = (item as Object as Record<string, string>)['formId']
              || (item as Object as Record<string, string>)['id'];
            if (id) {
              formId = id;
              EntryFormAbility.saveFormId(context, formId);
              break;
            }
          }
        }
      }

      if (!formId) {
        console.error('没有可用的卡片 formId，请先添加桌面卡片');
        return;
      }

      const cardData = await EntryFormAbility.loadCardData(context);
      const formData = formBindingData.createFormBindingData(cardData);
      await formProvider.updateForm(formId, formData);
      console.info('卡片主动更新成功, formId=' + formId);
    } catch (err) {
      console.error('主动更新卡片失败: ' + JSON.stringify(err));
    }
  }

  onCastToNormalForm(formId: string): void {}
  onFormEvent(formId: string, message: string): void {}
  onRemoveForm(formId: string): void {}
  onAcquireFormState(want: Want): formInfo.FormState {
    return formInfo.FormState.READY;
  }
}
