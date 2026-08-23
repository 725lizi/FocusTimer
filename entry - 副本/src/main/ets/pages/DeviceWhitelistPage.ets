import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { DeviceWhitelistManager } from '../common/DeviceWhitelistManager';

/** 设备信息接口 */
interface DeviceInfo {
  deviceId: string;
  deviceName: string;
  deviceType: string;
  isTrusted: boolean;
  firstConnectedAt: number;
  lastConnectedAt: number;
}

/**
 * 设备白名单管理页面
 */
@Entry
@Component
struct DeviceWhitelistPage {
  @State devices: DeviceInfo[] = [];
  @State isLoading: boolean = false;
  private deviceManager = DeviceWhitelistManager.getInstance();

  async aboutToAppear(): Promise<void> {
    await this.loadDevices();
  }

  async loadDevices(): Promise<void> {
    try {
      this.isLoading = true;
      this.devices = await this.deviceManager.getWhitelistDevices();
      this.isLoading = false;
    } catch (err) {
      console.error('loadDevices failed: ' + JSON.stringify(err));
      this.isLoading = false;
      this.devices = [];
    }
  }

  private navigateBack(): void {
    try {
      router.back();
    } catch (err) {
      console.error('back failed: ' + JSON.stringify(err));
    }
  }

  build() {
    Column() {
      // 顶部栏
      Row() {
        Text('←')
          .fontSize(22)
          .fontColor(Constants.COLOR_TEXT)
          .onClick(() => {
            this.navigateBack();
          })

        Text('设备白名单管理')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      if (this.isLoading) {
        Column() {
          LoadingProgress()
            .width(40)
            .height(40)
            .color(Constants.COLOR_PRIMARY)
          Text('加载中...')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 8 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else if (this.devices.length === 0) {
        Column() {
          Text('📱')
            .fontSize(48)
          Text('暂无信任设备')
            .fontSize(14)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 8 })
          Text('连接其他鸿蒙设备后会自动添加到白名单')
            .fontSize(12)
            .fontColor('#CCCCCC')
            .margin({ top: 4 })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        List() {
          ForEach(this.devices, (device: DeviceInfo) => {
            ListItem() {
              Row() {
                Text('📱')
                  .fontSize(24)

                Column() {
                  Text(device.deviceName)
                    .fontSize(15)
                    .fontWeight(FontWeight.Medium)
                    .fontColor(Constants.COLOR_TEXT)
                  Text(`类型：${device.deviceType}`)
                    .fontSize(12)
                    .fontColor(Constants.COLOR_TEXT_SUB)
                    .margin({ top: 2 })
                  Text(`首次连接：${this.formatTime(device.firstConnectedAt)}`)
                    .fontSize(11)
                    .fontColor('#CCCCCC')
                    .margin({ top: 2 })
                }
                .layoutWeight(1)
                .alignItems(HorizontalAlign.Start)
                .margin({ left: 10 })

                Text(device.isTrusted ? '✅ 信任' : '❌ 未信任')
                  .fontSize(12)
                  .fontColor(device.isTrusted ? Constants.COLOR_SUCCESS : '#F44336')

                Button('移除')
                  .height(30)
                  .fontSize(12)
                  .backgroundColor('#F44336')
                  .fontColor(Color.White)
                  .borderRadius(15)
                  .margin({ left: 8 })
                  .onClick(async () => {
                    try {
                      await this.deviceManager.removeDevice(device.deviceId);
                      await this.loadDevices();
                    } catch (err) {
                      console.error('removeDevice failed: ' + JSON.stringify(err));
                    }
                  })
              }
              .width('100%')
              .padding(14)
              .backgroundColor(Color.White)
              .borderRadius(12)
            }
            .margin({ bottom: 8 })
          })
        }
        .layoutWeight(1)
        .width('90%')
        .margin({ top: 10 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
  }

  private formatTime(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}-${String(date.getDate()).padStart(2, '0')}`;
  }
}