// services/rag/VectorRepository.ets
// 设备层：把向量块持久化到关系型数据库（复用项目统一的 DatabaseHelper / 同一个 db 文件），
// 实现「重启不丢」。表结构在 DatabaseHelper.createTables 中创建，并对 source_id 建索引。
//
// 纯逻辑的编解码放在 ChunkCodec（可单测），这里只负责和数据库打交道：
// 按来源原子重建（先删旧块再插块）、全量读出灌回内存向量库。

import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { DatabaseHelper } from '../../common/DatabaseHelper';
import { Constants } from '../../model/Constants';
import { ChunkCodec, RagChunkRecord } from './ChunkCodec';
import { EmbeddedChunk } from './RagTypes';

const DOMAIN = 0x0001;
const TAG = 'VectorRepository';

export class VectorRepository {
  private db: DatabaseHelper = DatabaseHelper.getInstance();

  /** 原子重建某来源：先删它的全部旧块，再逐条写入新块 */
  async replaceSource(sourceId: string, chunks: EmbeddedChunk[], model: string): Promise<number> {
    if (!sourceId) {
      return 0;
    }
    await this.db.delete(Constants.TABLE_RAG_CHUNK, 'source_id = ?', [sourceId]);
    const now: number = Date.now();
    let inserted: number = 0;
    for (let i = 0; i < chunks.length; i++) {
      const record: RagChunkRecord = ChunkCodec.encodeChunk(chunks[i], model, now);
      const values: relationalStore.ValuesBucket = {
        source_id: record.sourceId,
        source_type: record.sourceType,
        source_title: record.sourceTitle,
        source_time: record.sourceTime,
        chunk_index: record.chunkIndex,
        text: record.text,
        vector: record.vector,
        model: record.model,
        created_at: record.createdAt
      };
      const rowId: number = await this.db.insert(Constants.TABLE_RAG_CHUNK, values);
      if (rowId >= 0) {
        inserted++;
      }
    }
    hilog.info(DOMAIN, TAG, '重建来源 %{public}s 索引，写入 %{public}d 块', sourceId, inserted);
    return inserted;
  }

  /** 删除某来源的全部块 */
  async deleteSource(sourceId: string): Promise<void> {
    await this.db.delete(Constants.TABLE_RAG_CHUNK, 'source_id = ?', [sourceId]);
  }

  /** 清空整个向量表 */
  async clearAll(): Promise<void> {
    await this.db.executeSql(`DELETE FROM ${Constants.TABLE_RAG_CHUNK}`);
  }

  /** 全量读出，按来源、块序号升序；坏行（向量无法解析）自动跳过 */
  async loadAll(): Promise<EmbeddedChunk[]> {
    const store: relationalStore.RdbStore | null = this.db.getRdbStore();
    if (!store) {
      return [];
    }
    const result: EmbeddedChunk[] = [];
    let rs: relationalStore.ResultSet | null = null;
    try {
      rs = await store.querySql(
        `SELECT * FROM ${Constants.TABLE_RAG_CHUNK} ORDER BY source_id ASC, chunk_index ASC`);
      while (rs.goToNextRow()) {
        const record: RagChunkRecord = {
          sourceId: rs.getString(rs.getColumnIndex('source_id')),
          sourceType: rs.getString(rs.getColumnIndex('source_type')),
          sourceTitle: rs.getString(rs.getColumnIndex('source_title')),
          sourceTime: rs.getLong(rs.getColumnIndex('source_time')),
          chunkIndex: rs.getLong(rs.getColumnIndex('chunk_index')),
          text: rs.getString(rs.getColumnIndex('text')),
          vector: rs.getString(rs.getColumnIndex('vector')),
          model: rs.getString(rs.getColumnIndex('model')),
          createdAt: rs.getLong(rs.getColumnIndex('created_at'))
        };
        const chunk: EmbeddedChunk | null = ChunkCodec.decodeRecord(record);
        if (chunk !== null) {
          result.push(chunk);
        }
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '加载向量块失败: %{public}s', JSON.stringify(err));
    } finally {
      if (rs !== null) {
        rs.close();
      }
    }
    return result;
  }

  /** 已索引的块总数 */
  async count(): Promise<number> {
    const store: relationalStore.RdbStore | null = this.db.getRdbStore();
    if (!store) {
      return 0;
    }
    let rs: relationalStore.ResultSet | null = null;
    try {
      rs = await store.querySql(`SELECT COUNT(*) AS cnt FROM ${Constants.TABLE_RAG_CHUNK}`);
      if (rs.goToNextRow()) {
        return rs.getLong(rs.getColumnIndex('cnt'));
      }
    } catch (err) {
      hilog.error(DOMAIN, TAG, '统计向量块失败: %{public}s', JSON.stringify(err));
    } finally {
      if (rs !== null) {
        rs.close();
      }
    }
    return 0;
  }
}
