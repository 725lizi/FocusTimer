import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Constants } from '../model/Constants';

const DOMAIN = 0x0001;
const TAG = "DatabaseHelper";

export class DatabaseHelper {
  private static instance: DatabaseHelper | null = null;
  private rdbStore: relationalStore.RdbStore | null = null;

  private constructor() {
  }

  public static getInstance(): DatabaseHelper {
    if (DatabaseHelper.instance === null) {
      DatabaseHelper.instance = new DatabaseHelper();
    }
    return DatabaseHelper.instance;
  }

  public async init(context: common.Context): Promise<void> {
    if (this.rdbStore) {
      return;
    }

    const config: relationalStore.StoreConfig = {
      name: Constants.DB_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };

    try {
      this.rdbStore = await relationalStore.getRdbStore(context, config);
      await this.createTables();
      hilog.info(DOMAIN, TAG, '数据库初始化成功');
    } catch (err) {
      hilog.error(DOMAIN, TAG, '数据库初始化失败: %{public}s', JSON.stringify(err));
    }
  }

  private async createTables(): Promise<void> {
    if (!this.rdbStore) {
      return;
    }

    try {
      const createSessionTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_STUDY_SESSION} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        task_name TEXT NOT NULL,
        start_time INTEGER NOT NULL,
        end_time INTEGER,
        duration INTEGER DEFAULT 0,
        subject_tag_id TEXT DEFAULT '',
        is_offline INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        updated_at INTEGER NOT NULL
      )`;

      const createNoteTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_NOTE} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        title TEXT NOT NULL,
        content TEXT DEFAULT '',
        subject_tag_id TEXT DEFAULT '',
        is_encrypted INTEGER DEFAULT 0,
        is_offline INTEGER DEFAULT 0,
        is_synced INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL,
        updated_at INTEGER NOT NULL
      )`;

      const createSubjectTagTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_SUBJECT_TAG} (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL,
        color TEXT DEFAULT '#4A90D9',
        icon TEXT DEFAULT '📚',
        created_at INTEGER NOT NULL
      )`;

      const createDeviceWhitelistTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_DEVICE_WHITELIST} (
        device_id TEXT PRIMARY KEY,
        device_name TEXT NOT NULL,
        device_type TEXT DEFAULT 'unknown',
        is_trusted INTEGER DEFAULT 1,
        first_connected_at INTEGER NOT NULL,
        last_connected_at INTEGER
      )`;

      const createEncryptedFolderTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_ENCRYPTED_FOLDER} (
        id TEXT PRIMARY KEY,
        folder_name TEXT NOT NULL,
        note_ids TEXT DEFAULT '[]',
        created_at INTEGER NOT NULL
      )`;

      const createPendingSyncTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_PENDING_SYNC} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        kv_key TEXT NOT NULL,
        kv_value TEXT NOT NULL,
        is_synced INTEGER DEFAULT 0,
        created_at INTEGER NOT NULL
      )`;

      const createRagChunkTable = `CREATE TABLE IF NOT EXISTS ${Constants.TABLE_RAG_CHUNK} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        source_id TEXT NOT NULL,
        source_type TEXT NOT NULL,
        source_title TEXT DEFAULT '',
        source_time INTEGER NOT NULL,
        chunk_index INTEGER NOT NULL,
        text TEXT DEFAULT '',
        vector TEXT NOT NULL,
        model TEXT DEFAULT '',
        created_at INTEGER NOT NULL
      )`;
      const createRagSourceIndex =
        `CREATE INDEX IF NOT EXISTS idx_rag_chunk_source ON ${Constants.TABLE_RAG_CHUNK}(source_id)`;

      await this.rdbStore.executeSql(createSessionTable);
      await this.rdbStore.executeSql(createNoteTable);
      await this.rdbStore.executeSql(createSubjectTagTable);
      await this.rdbStore.executeSql(createDeviceWhitelistTable);
      await this.rdbStore.executeSql(createEncryptedFolderTable);
      await this.rdbStore.executeSql(createPendingSyncTable);
      await this.rdbStore.executeSql(createRagChunkTable);
      await this.rdbStore.executeSql(createRagSourceIndex);

      hilog.info(DOMAIN, TAG, '所有数据表创建完成');
    } catch (err) {
      hilog.error(DOMAIN, TAG, '创建数据表失败: %{public}s', JSON.stringify(err));
    }
  }

  public getRdbStore(): relationalStore.RdbStore | null {
    return this.rdbStore;
  }

  public async insert(table: string, values: relationalStore.ValuesBucket): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    try {
      return await this.rdbStore.insert(table, values);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '插入失败: %{public}s', JSON.stringify(err));
      return -1;
    }
  }

  public async update(table: string, values: relationalStore.ValuesBucket, whereClause: string, whereArgs: string[]): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    try {
      const setClause = Object.keys(values).map(key => `${key} = ?`).join(', ');
      const updateValues = Object.values(values).map(v => String(v));
      const sql = `UPDATE ${table} SET ${setClause} WHERE ${whereClause}`;
      const args = [...updateValues, ...whereArgs];
      await this.rdbStore.executeSql(sql, args);
      return 1;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '更新失败: %{public}s', JSON.stringify(err));
      return -1;
    }
  }

  public async query(table: string, whereClause: string = '', whereArgs: string[] = [], orderBy: string = ''): Promise<relationalStore.ResultSet | null> {
    if (!this.rdbStore) {
      return null;
    }
    try {
      let sql = `SELECT * FROM ${table}`;
      if (whereClause) {
        sql += ` WHERE ${whereClause}`;
      }
      if (orderBy) {
        sql += ` ORDER BY ${orderBy} DESC`;
      }
      return await this.rdbStore.querySql(sql, whereArgs);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '查询失败: %{public}s', JSON.stringify(err));
      return null;
    }
  }

  public async delete(table: string, whereClause: string, whereArgs: string[]): Promise<number> {
    if (!this.rdbStore) {
      return -1;
    }
    try {
      const sql = `DELETE FROM ${table} WHERE ${whereClause}`;
      await this.rdbStore.executeSql(sql, whereArgs);
      return 1;
    } catch (err) {
      hilog.error(DOMAIN, TAG, '删除失败: %{public}s', JSON.stringify(err));
      return -1;
    }
  }

  public async executeSql(sql: string, args: relationalStore.ValueType[] = []): Promise<void> {
    if (!this.rdbStore) {
      return;
    }
    try {
      await this.rdbStore.executeSql(sql, args);
    } catch (err) {
      hilog.error(DOMAIN, TAG, '执行SQL失败: %{public}s', JSON.stringify(err));
    }
  }
}
