import localUnitTest from './LocalUnit.test';
import timerEngineTest from './TimerEngine.test';
import subjectTagTest from './SubjectTag.test';
import continuationTest from './Continuation.test';
import learningAnalysisTest from './LearningAnalysisService.test';
import focusAndSedentaryTest from './FocusModeAndSedentary.test';
import securityAndWhitelistTest from './SecurityAndWhitelist.test';
import offlineAndCardTest from './OfflineCacheAndCard.test';
import aiReportLogicTest from './AiReportLogic.test';
import aiNetworkLogicTest from './AiNetworkLogic.test';
import markdownLiteTest from './MarkdownLite.test';

export default function testsuite() {
  localUnitTest();
  timerEngineTest();
  subjectTagTest();
  continuationTest();
  learningAnalysisTest();
  focusAndSedentaryTest();
  securityAndWhitelistTest();
  offlineAndCardTest();
  aiReportLogicTest();
  aiNetworkLogicTest();
  markdownLiteTest();
}
