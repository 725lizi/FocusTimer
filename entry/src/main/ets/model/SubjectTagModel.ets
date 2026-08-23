/**
 * 科目标签数据模型
 */

export interface SubjectTagValues {

  id: string;
  name: string;
  color: string;
  icon: string;
  created_at: number;
}

export interface StudySessionValues {

  task_name: string;
  start_time: number;
  end_time: number;
  duration: number;
  subject_tag_id: string;
  is_offline: number;
  is_synced: number;
  updated_at: number;
}

export class SubjectTagModel {
  id: string = '';
  name: string = '';
  color: string = '#4A90D9';
  icon: string = '📚';
  createdAt: number = 0;

  constructor(data?: Record<string, Object>) {
    if (data) {
      this.id = data['id'] as string || '';
      this.name = data['name'] as string || '';
      this.color = data['color'] as string || '#4A90D9';
      this.icon = data['icon'] as string || '📚';
      this.createdAt = data['created_at'] as number || 0;
    }
  }

  public toValues(): SubjectTagValues {
    const values: SubjectTagValues = {
      id: this.id,
      name: this.name,
      color: this.color,
      icon: this.icon,
      created_at: this.createdAt
    };
    return values;
  }
}

/**
 * 学习会话数据模型（用于数据库存储）
 */
export class StudySessionRecord {
  id: number = 0;
  taskName: string = '';
  startTime: number = 0;
  endTime: number = 0;
  duration: number = 0; // 分钟
  subjectTagId: string = '';
  isOffline: boolean = false;
  isSynced: boolean = false;
  updatedAt: number = 0;

  constructor(data?: Record<string, Object>) {
    if (data) {
      this.id = data['id'] as number || 0;
      this.taskName = data['task_name'] as string || '';
      this.startTime = data['start_time'] as number || 0;
      this.endTime = data['end_time'] as number || 0;
      this.duration = data['duration'] as number || 0;
      this.subjectTagId = data['subject_tag_id'] as string || '';
      this.isOffline = (data['is_offline'] as number || 0) === 1;
      this.isSynced = (data['is_synced'] as number || 0) === 1;
      this.updatedAt = data['updated_at'] as number || 0;
    }
  }

  public toValues(): StudySessionValues {
    const values: StudySessionValues = {
      task_name: this.taskName,
      start_time: this.startTime,
      end_time: this.endTime,
      duration: this.duration,
      subject_tag_id: this.subjectTagId,
      is_offline: this.isOffline ? 1 : 0,
      is_synced: this.isSynced ? 1 : 0,
      updated_at: this.updatedAt
    };
    return values;
  }
}