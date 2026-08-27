import localUnitTest from './LocalUnit.test';
import timerEngineTest from './TimerEngine.test';

export default function testsuite() {
  localUnitTest();
  timerEngineTest();
}
