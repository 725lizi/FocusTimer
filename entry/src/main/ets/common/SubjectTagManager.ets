import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';
import { SubjectTagModel } from '../model/SubjectTagModel';
import { DatabaseHelper } from './DatabaseHelper';

const DOMAIN = 0x0001;
const TAG = "SubjectTagManager";

/**
 * 科目标签管理器
 * 提供科目标签的增删改查
 */
export class SubjectTagManager {
  private static instance: SubjectTagManager | null = null;

  private constructor() {
  }

  public static getInstance(): SubjectTagManager {
    if (SubjectTagManager.instance === null) {
      SubjectTagManager.instance = new SubjectTagManager();
    }
    return SubjectTagManager.instance;
  }

  /**
   * 校验科目标签名是否合法（非空且去除首尾空格后仍有内容）
   * 对应 createTag 中的空名校验逻辑
   */
  public static isValidName(name: string): boolean {
    const trimmed: string = name ? name.trim() : '';
    return trimmed.length > 0;
  }

  /**
   * 获取所有科目标签
   */
  public async getAllTags(): Promise<SubjectTagModel[]> {
    try {
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_SUBJECT_TAG, '', [], 'created_at');

      const tags: SubjectTagModel[] = [];
      if (resultSet) {
        while (resultSet.goToNextRow()) {
          const tag = new SubjectTagModel();
          tag.id = resultSet.getString(resultSet.getColumnIndex('id'));
          tag.name = resultSet.getString(resultSet.getColumnIndex('name'));
          tag.color = resultSet.getString(resultSet.getColumnIndex('color'));
          tag.icon = resultSet.getString(resultSet.getColumnIndex('icon'));
          tag.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
          tags.push(tag);
        }
        resultSet.close();
      }
      return tags;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取所有科目标签失败');
      return [];
    }
  }

  /**
   * 创建新科目标签
   */
  public async createTag(name: string, color: string = '', icon: string = ''): Promise<boolean> {
    try {
      if (!SubjectTagManager.isValidName(name)) {
        return false;
      }

      const db = DatabaseHelper.getInstance();
      const tag = new SubjectTagModel();
      tag.id = `subject_${Date.now()}_${Math.floor(Math.random() * 1000)}`;
      tag.name = name.trim();
      tag.color = color || Constants.SUBJECT_COLORS[Math.floor(Math.random() * Constants.SUBJECT_COLORS.length)];
      tag.icon = icon || Constants.SUBJECT_ICONS[Math.floor(Math.random() * Constants.SUBJECT_ICONS.length)];
      tag.createdAt = Date.now();

      const values: relationalStore.ValuesBucket = {
        id: tag.id,
        name: tag.name,
        color: tag.color,
        icon: tag.icon,
        created_at: tag.createdAt
      };
      const result = await db.insert(Constants.TABLE_SUBJECT_TAG, values);
      hilog.info(DOMAIN, TAG, '创建科目标签: %{public}s, 结果: %{public}d', name, result);
      return result > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '创建科目标签失败');
      return false;
    }
  }

  /**
   * 删除科目标签
   */
  public async deleteTag(tagId: string): Promise<boolean> {
    try {
      if (!tagId) {
        return false;
      }
      const db = DatabaseHelper.getInstance();
      const result = await db.delete(Constants.TABLE_SUBJECT_TAG, 'id = ?', [tagId]);
      return result > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '删除科目标签失败');
      return false;
    }
  }

  /**
   * 根据 ID 获取标签名称
   */
  public async getTagName(tagId: string): Promise<string> {
    try {
      if (!tagId) {
        return '';
      }
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_SUBJECT_TAG, 'id = ?', [tagId]);
      if (resultSet && resultSet.goToNextRow()) {
        const name = resultSet.getString(resultSet.getColumnIndex('name'));
        resultSet.close();
        return name;
      }
      return '';
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取标签名称失败');
      return '';
    }
  }
}