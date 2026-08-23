import { relationalStore } from '@kit.ArkData';
import { userAuth } from '@kit.UserAuthenticationKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';
import { DatabaseHelper } from './DatabaseHelper';

const DOMAIN = 0x0001;
const TAG = "SecurityManager";

/** 加密文件夹信息接口 */
interface EncryptedFolderInfo {
  id: string;
  folderName: string;
  noteIds: string;
  createdAt: number;
}

/**
 * 安全与隐私管理器
 * 包含生物识别加密文件夹
 */
export class SecurityManager {
  private static instance: SecurityManager | null = null;

  private constructor() {
  }

  public static getInstance(): SecurityManager {
    if (SecurityManager.instance === null) {
      SecurityManager.instance = new SecurityManager();
    }
    return SecurityManager.instance;
  }

  /**
   * 检查生物识别是否可用
   */
  public async checkBiometricSupport(): Promise<boolean> {
    try {
      const authParam: userAuth.AuthParam = {
        challenge: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]),
        authType: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = {
        title: '验证身份',
        navigationButtonText: '取消'
      };
      const instance = await userAuth.getUserAuthInstance(authParam, widgetParam);
      return instance !== null;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '检查生物识别失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 执行生物识别验证
   */
  public async authenticateWithBiometric(): Promise<boolean> {
    try {
      const authParam: userAuth.AuthParam = {
        challenge: new Uint8Array([1, 2, 3, 4, 5, 6, 7, 8]),
        authType: [userAuth.UserAuthType.FACE, userAuth.UserAuthType.FINGERPRINT],
        authTrustLevel: userAuth.AuthTrustLevel.ATL1
      };
      const widgetParam: userAuth.WidgetParam = {
        title: '解锁加密文件夹',
        navigationButtonText: '取消'
      };
      const instance = await userAuth.getUserAuthInstance(authParam, widgetParam);
      const token = await instance.start();
      return token !== null && token !== undefined;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '生物识别验证失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 创建加密文件夹
   */
  public async createEncryptedFolder(folderName: string): Promise<boolean> {
    try {
      if (!folderName || folderName.trim().length === 0) {
        return false;
      }
      const db = DatabaseHelper.getInstance();
      const folderId = `folder_${Date.now()}`;
      const values: relationalStore.ValuesBucket = {
        id: folderId,
        folder_name: folderName.trim(),
        note_ids: '[]',
        created_at: Date.now()
      };
      const result = await db.insert(Constants.TABLE_ENCRYPTED_FOLDER, values);
      hilog.info(DOMAIN, TAG, '创建加密文件夹: %{public}s', folderName);
      return result > 0;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '创建加密文件夹失败: %{public}s', JSON.stringify(err));
      return false;
    }
  }

  /**
   * 获取所有加密文件夹
   */
  public async getEncryptedFolders(): Promise<EncryptedFolderInfo[]> {
    try {
      const db = DatabaseHelper.getInstance();
      const resultSet = await db.query(Constants.TABLE_ENCRYPTED_FOLDER, '', [], 'created_at');
      const folders: EncryptedFolderInfo[] = [];
      if (resultSet) {
        while (resultSet.goToNextRow()) {
          const folder: EncryptedFolderInfo = {
            id: resultSet.getString(resultSet.getColumnIndex('id')),
            folderName: resultSet.getString(resultSet.getColumnIndex('folder_name')),
            noteIds: resultSet.getString(resultSet.getColumnIndex('note_ids')),
            createdAt: resultSet.getLong(resultSet.getColumnIndex('created_at'))
          };
          folders.push(folder);
        }
        resultSet.close();
      }
      return folders;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '获取加密文件夹失败: %{public}s', JSON.stringify(err));
      return [];
    }
  }
}