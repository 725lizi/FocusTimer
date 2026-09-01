import { describe, it, expect } from '@ohos/hypium';
import { VectorMath } from '../main/ets/services/rag/VectorMath';

export default function vectorMathTest() {
  describe('VectorMath', () => {

    it('vec_dotComputesInnerProduct', 0, () => {
      expect(VectorMath.dot([1, 2, 3], [4, 5, 6])).assertEqual(32); // 4+10+18
    });

    it('vec_dotMismatchedDimensionIsNaN', 0, () => {
      expect(Number.isNaN(VectorMath.dot([1, 2], [1, 2, 3]))).assertTrue();
    });

    it('vec_normIsL2Length', 0, () => {
      expect(VectorMath.norm([3, 4])).assertEqual(5); // 勾股数
      expect(VectorMath.norm([])).assertEqual(0);
    });

    it('vec_cosineSameVectorIsOne', 0, () => {
      expect(VectorMath.cosineSimilarity([2, 3, 4], [2, 3, 4])).assertEqual(1);
    });

    it('vec_cosineOrthogonalIsZero', 0, () => {
      expect(VectorMath.cosineSimilarity([1, 0], [0, 1])).assertEqual(0);
    });

    it('vec_cosineOppositeIsMinusOne', 0, () => {
      expect(VectorMath.cosineSimilarity([1, 0], [-1, 0])).assertEqual(-1);
    });

    it('vec_cosineKnownValue', 0, () => {
      // [1,1] 与 [1,0]：点积1 / (sqrt2 * 1) = 1/sqrt2 ≈ 0.7071
      const v: number = VectorMath.cosineSimilarity([1, 1], [1, 0]);
      expect(Math.abs(v - 1 / Math.sqrt(2)) < 1e-9).assertTrue();
    });

    it('vec_cosineZeroOrMismatchedIsZeroNotThrow', 0, () => {
      expect(VectorMath.cosineSimilarity([0, 0], [1, 1])).assertEqual(0);
      expect(VectorMath.cosineSimilarity([1, 2], [1])).assertEqual(0);
    });

    it('vec_normalizeMakesUnitLength', 0, () => {
      const n: number[] = VectorMath.normalize([3, 4]); // -> [0.6,0.8]
      expect(Math.abs(n[0] - 0.6) < 1e-9).assertTrue();
      expect(Math.abs(n[1] - 0.8) < 1e-9).assertTrue();
      expect(Math.abs(VectorMath.norm(n) - 1) < 1e-9).assertTrue();
    });

    it('vec_sameDimensionCheck', 0, () => {
      expect(VectorMath.sameDimension([1, 2], [3, 4])).assertTrue();
      expect(VectorMath.sameDimension([1], [1, 2])).assertFalse();
      expect(VectorMath.sameDimension([], [1])).assertFalse();
    });
  });
}
