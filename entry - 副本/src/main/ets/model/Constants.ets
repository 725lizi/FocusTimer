/** 全局常量定义 */
export class Constants {
  // 预设时长选项（秒）
  static readonly PRESET_DURATIONS: number[] = [300, 900, 1500, 2700, 3600];
  // 预设时长显示名
  static readonly PRESET_LABELS: string[] = ['5分钟', '15分钟', '25分钟', '45分钟', '60分钟'];
  // 默认选中索引（25分钟）
  static readonly DEFAULT_INDEX: number = 2;

  // ====== 当前主题配色（经典蓝） ======
  static readonly COLOR_PRIMARY: string = '#4A90D9';
  static readonly COLOR_ACCENT: string = '#FF6B6B';
  static readonly COLOR_SUCCESS: string = '#4CAF50';
  static readonly COLOR_WARNING: string = '#FF9800';
  static readonly COLOR_BG: string = '#F5F7FA';
  static readonly COLOR_CARD: string = '#FFFFFF';
  static readonly COLOR_TEXT: string = '#2C3E50';
  static readonly COLOR_TEXT_SUB: string = '#7F8C8D';

  // ====== 5套主题的主色 ======
  static readonly THEME_0_PRIMARY: string = '#4A90D9';
  static readonly THEME_0_NAME: string = '经典蓝';
  static readonly THEME_1_PRIMARY: string = '#00B894';
  static readonly THEME_1_NAME: string = '薄荷绿';
  static readonly THEME_2_PRIMARY: string = '#FD79A8';
  static readonly THEME_2_NAME: string = '樱花粉';
  static readonly THEME_3_PRIMARY: string = '#6C5CE7';
  static readonly THEME_3_NAME: string = '深空紫';
  static readonly THEME_4_PRIMARY: string = '#F39C12';
  static readonly THEME_4_NAME: string = '暖阳橙';
  static readonly THEME_NAMES: string[] = ['经典蓝', '薄荷绿', '樱花粉', '深空紫', '暖阳橙'];

  // ====== 页面路由 ======
  static readonly PAGE_INDEX: string = 'pages/Index';
  static readonly PAGE_NOTES: string = 'pages/Notes';
  static readonly PAGE_STATS: string = 'pages/Statistics';
  static readonly PAGE_REPORT: string = 'pages/Report';
  static readonly PAGE_DEVICE_WHITELIST: string = 'pages/DeviceWhitelistPage';
  static readonly PAGE_ENCRYPTED_FOLDER: string = 'pages/EncryptedFolderPage';

  // ====== 传感器 ======
  static readonly DARK_LIGHT_THRESHOLD: number = 50;

  // ====== 数据库 ======
  static readonly DB_NAME: string = 'HongDuanShiJi.db';
  static readonly DB_VERSION: number = 1;

  // 数据表名
  static readonly TABLE_STUDY_SESSION: string = 'study_session';
  static readonly TABLE_NOTE: string = 'note';
  static readonly TABLE_SUBJECT_TAG: string = 'subject_tag';
  static readonly TABLE_DEVICE_WHITELIST: string = 'device_whitelist';
  static readonly TABLE_ENCRYPTED_FOLDER: string = 'encrypted_folder';
  static readonly TABLE_PENDING_SYNC: string = 'pending_sync';

  // ====== 分布式 ======
  static readonly KVSTORE_ID: string = 'hongduan_kvstore';
  static readonly SESSION_KEY: string = 'current_session';
  static readonly OFFLINE_FLAG: string = 'offline_mode';

  // ====== 专注模式 ======
  static readonly FOCUS_MODE_DURATION: number = 45;
  static readonly SEDENTARY_THRESHOLD: number = 45; // 分钟

  // ====== 科目标签默认颜色 ======
  static readonly SUBJECT_COLORS: string[] = [
    '#4A90D9', '#00B894', '#FD79A8', '#6C5CE7', '#F39C12', '#E74C3C', '#2ECC71', '#E67E22'
  ];
  static readonly SUBJECT_ICONS: string[] = ['??', '??', '??', '??', '??', '??', '??', '??'];
}