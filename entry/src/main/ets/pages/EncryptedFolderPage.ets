import { Constants } from '../model/Constants';
import { router } from '@kit.ArkUI';
import { promptAction } from '@kit.ArkUI';
import { SecurityManager } from '../common/SecurityManager';

/** 加密文件夹信息接口 */
interface EncryptedFolderInfo {
  id: string;
  folderName: string;
  noteIds: string;
  createdAt: number;
}

/**
 * 加密文件夹页面
 * 需要生物识别验证后访问
 */
@Entry
@Component
struct EncryptedFolderPage {
  @State isAuthenticated: boolean = false;
  @State folders: EncryptedFolderInfo[] = [];
  @State folderNameInput: string = '';
  @State isCreatingFolder: boolean = false;
  private securityManager = SecurityManager.getInstance();

  async aboutToAppear(): Promise<void> {
    await this.authenticate();
  }

  async authenticate(): Promise<void> {
    try {
      const supported = await this.securityManager.checkBiometricSupport();
      if (!supported) {
        this.showToast('设备不支持生物识别');
        return;
      }

      const authenticated = await this.securityManager.authenticateWithBiometric();
      this.isAuthenticated = authenticated;

      if (authenticated) {
        await this.loadFolders();
      }
    } catch (err) {
      console.error('authenticate failed: ' + JSON.stringify(err));
      this.showToast('验证失败，请重试');
    }
  }

  async loadFolders(): Promise<void> {
    try {
      this.folders = await this.securityManager.getEncryptedFolders();
    } catch (err) {
      console.error('loadFolders failed: ' + JSON.stringify(err));
      this.folders = [];
    }
  }

  private showToast(message: string): void {
    try {
      promptAction.showToast({ message: message });
    } catch (err) {
      console.error('showToast failed: ' + JSON.stringify(err));
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

        Text('🔒 加密文件夹')
          .fontSize(18)
          .fontWeight(FontWeight.Bold)
          .fontColor(Constants.COLOR_TEXT)
          .margin({ left: 12 })

        Blank()
      }
      .width('100%')
      .padding({ left: 16, right: 16, top: 12, bottom: 10 })

      if (!this.isAuthenticated) {
        Column() {
          Text('🔐')
            .fontSize(48)
          Text('需要身份验证')
            .fontSize(16)
            .fontWeight(FontWeight.Bold)
            .fontColor(Constants.COLOR_TEXT)
            .margin({ top: 12 })
          Text('请使用指纹或人脸识别验证身份')
            .fontSize(13)
            .fontColor(Constants.COLOR_TEXT_SUB)
            .margin({ top: 4 })

          Button('重新验证')
            .width('60%')
            .height(40)
            .fontSize(14)
            .backgroundColor(Constants.COLOR_PRIMARY)
            .fontColor(Color.White)
            .borderRadius(20)
            .margin({ top: 20 })
            .onClick(async () => {
              await this.authenticate();
            })
        }
        .layoutWeight(1)
        .justifyContent(FlexAlign.Center)
      } else {
        Column() {
          // 创建文件夹
          if (this.isCreatingFolder) {
            Row({ space: 8 }) {
              TextInput({ placeholder: '文件夹名称', text: this.folderNameInput })
                .layoutWeight(1)
                .height(40)
                .fontSize(14)
                .onChange((value: string) => {
                  this.folderNameInput = value;
                })

              Button('创建')
                .height(40)
                .fontSize(13)
                .backgroundColor(Constants.COLOR_PRIMARY)
                .fontColor(Color.White)
                .borderRadius(20)
                .onClick(async () => {
                  if (this.folderNameInput.trim()) {
                    try {
                      const success = await this.securityManager.createEncryptedFolder(this.folderNameInput);
                      if (success) {
                        await this.loadFolders();
                        this.folderNameInput = '';
                        this.isCreatingFolder = false;
                        this.showToast('创建成功');
                      } else {
                        this.showToast('创建失败，请重试');
                      }
                    } catch (err) {
                      console.error('createEncryptedFolder failed: ' + JSON.stringify(err));
                      this.showToast('创建失败，请重试');
                    }
                  }
                })
            }
            .width('90%')
            .margin({ top: 12 })
          }

          // 文件夹列表
          if (this.folders.length === 0) {
            Column() {
              Text('📁')
                .fontSize(48)
              Text('暂无加密文件夹')
                .fontSize(14)
                .fontColor(Constants.COLOR_TEXT_SUB)
                .margin({ top: 8 })
            }
            .layoutWeight(1)
            .justifyContent(FlexAlign.Center)
          } else {
            List() {
              ForEach(this.folders, (folder: EncryptedFolderInfo) => {
                ListItem() {
                  Row() {
                    Text('🔒')
                      .fontSize(20)
                    Text(folder.folderName)
                      .fontSize(15)
                      .fontWeight(FontWeight.Medium)
                      .fontColor(Constants.COLOR_TEXT)
                      .margin({ left: 10 })
                      .layoutWeight(1)
                    Text(this.formatDate(folder.createdAt))
                      .fontSize(11)
                      .fontColor('#CCCCCC')
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

          // 新建按钮
          if (!this.isCreatingFolder) {
            Button('+ 新建加密文件夹')
              .width(180)
              .height(42)
              .fontSize(14)
              .backgroundColor(Constants.COLOR_PRIMARY)
              .fontColor(Color.White)
              .borderRadius(21)
              .margin({ bottom: 16 })
              .onClick(() => {
                this.isCreatingFolder = true;
              })
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Constants.COLOR_BG)
  }

  private formatDate(timestamp: number): string {
    const date = new Date(timestamp);
    return `${date.getMonth() + 1}/${date.getDate()}`;
  }
}