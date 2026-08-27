import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { StudySessionRecord } from '../main/ets/model/SubjectTagModel';

export default function continuationTest() {
  describe('ContinuationManager', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('record_defaultValues', 0, () => {
      const record = new StudySessionRecord();
      expect(record.id).assertEqual(0);
      expect(record.taskName).assertEqual('');
      expect(record.startTime).assertEqual(0);
      expect(record.endTime).assertEqual(0);
      expect(record.duration).assertEqual(0);
      expect(record.subjectTagId).assertEqual('');
      expect(record.isOffline).assertFalse();
      expect(record.isSynced).assertFalse();
    });

    it('record_fromRecord_shouldParseIntToBool', 0, () => {
      const data: Record<string, Object> = {
        'id': 5,
        'task_name': '高数学习',
        'start_time': 1000,
        'end_time': 2000,
        'duration': 25,
        'subject_tag_id': 'subject_1',
        'is_offline': 1,
        'is_synced': 0,
        'updated_at': 3000
      };
      const record = new StudySessionRecord(data);
      expect(record.id).assertEqual(5);
      expect(record.taskName).assertEqual('高数学习');
      expect(record.duration).assertEqual(25);
      expect(record.subjectTagId).assertEqual('subject_1');
      expect(record.isOffline).assertTrue();
      expect(record.isSynced).assertFalse();
      expect(record.updatedAt).assertEqual(3000);
    });

    it('record_toValues_shouldMapBoolToInt', 0, () => {
      const record = new StudySessionRecord();
      record.taskName = '英语学习';
      record.startTime = 100;
      record.endTime = 200;
      record.duration = 15;
      record.subjectTagId = 'subject_2';
      record.isOffline = true;
      record.isSynced = true;
      record.updatedAt = 4000;
      const values = record.toValues();
      expect(values.task_name).assertEqual('英语学习');
      expect(values.start_time).assertEqual(100);
      expect(values.duration).assertEqual(15);
      expect(values.subject_tag_id).assertEqual('subject_2');
      expect(values.is_offline).assertEqual(1);
      expect(values.is_synced).assertEqual(1);
      expect(values.updated_at).assertEqual(4000);
    });
  });
}
