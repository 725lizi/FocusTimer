import localUnitTest from './LocalUnit.test';
import timerEngineTest from './TimerEngine.test';
import subjectTagTest from './SubjectTag.test';
import continuationTest from './Continuation.test';
import aiAnalysisTest from './AIAnalysisService.test';
import focusAndSedentaryTest from './FocusModeAndSedentary.test';
import securityAndWhitelistTest from './SecurityAndWhitelist.test';
import offlineAndCardTest from './OfflineCacheAndCard.test';

export default function testsuite() {
  localUnitTest();
  timerEngineTest();
  subjectTagTest();
  continuationTest();
  aiAnalysisTest();
  focusAndSedentaryTest();
  securityAndWhitelistTest();
  offlineAndCardTest();
}
