import { describe, beforeAll, beforeEach, afterEach, afterAll, it, expect } from '@ohos/hypium';
import { SubjectTagManager } from '../main/ets/common/SubjectTagManager';
import { SubjectTagModel } from '../main/ets/model/SubjectTagModel';

export default function subjectTagTest() {
  describe('SubjectTagManager', () => {
    beforeAll(() => {
    });
    beforeEach(() => {
    });
    afterEach(() => {
    });
    afterAll(() => {
    });

    it('isValidName_shouldRejectEmptyAndWhitespace', 0, () => {
      expect(SubjectTagManager.isValidName('')).assertFalse();
      expect(SubjectTagManager.isValidName('   ')).assertFalse();
    });

    it('isValidName_shouldAcceptNormalName', 0, () => {
      expect(SubjectTagManager.isValidName('高数')).assertTrue();
      expect(SubjectTagManager.isValidName(' 英语 ')).assertTrue();
    });

    it('model_defaultValues', 0, () => {
      const tag = new SubjectTagModel();
      expect(tag.id).assertEqual('');
      expect(tag.name).assertEqual('');
      expect(tag.color).assertEqual('#4A90D9');
      expect(tag.icon).assertEqual('📚');
      expect(tag.createdAt).assertEqual(0);
    });

    it('model_toValues_shouldMapAllFields', 0, () => {
      const tag = new SubjectTagModel();
      tag.id = 'subject_1';
      tag.name = '高数';
      tag.color = '#4A90D9';
      tag.icon = '📐';
      tag.createdAt = 123456789;
      const values = tag.toValues();
      expect(values.id).assertEqual('subject_1');
      expect(values.name).assertEqual('高数');
      expect(values.color).assertEqual('#4A90D9');
      expect(values.created_at).assertEqual(123456789);
    });

    it('model_fromRecord_shouldPopulate', 0, () => {
      const data: Record<string, Object> = {
        'id': 'subject_2',
        'name': '英语',
        'color': '#00B894',
        'icon': '📝',
        'created_at': 999
      };
      const tag = new SubjectTagModel(data);
      expect(tag.id).assertEqual('subject_2');
      expect(tag.name).assertEqual('英语');
      expect(tag.color).assertEqual('#00B894');
      expect(tag.icon).assertEqual('📝');
      expect(tag.createdAt).assertEqual(999);
    });
  });
}
