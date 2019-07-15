

//! ミッション結果定数
enum MissionResult{
	MISSION_RESULT_UNKNOWN,
	MISSION_RESULT_CLEAR,
	MISSION_RESULT_ABORT,
	MISSION_RESULT_RETRY,
	MISSION_RESULT_LOBBY,
	MISSION_RESULT_RETURNTITLE,		// セーブデータ不良によりタイトルへ戻る
	MISSION_RESULT_MAX,
};

//! リソースグループ
enum ResouceSystemGroup{	//class ResourceManagerに定義されているenumと同じじゃないとダメ
	SYSTEM_GROUP_TITLE,		// タイトル起動から終了まで常駐し続けるリソース用
	SYSTEM_GROUP_MODE,		// ゲームモード単位で常駐するリソース用
	SYSTEM_GROUP_SCENE,		// シーン単位のリソース（進行画面毎やミッション毎等）
};

enum MODE_SELECT {
	MODE_UNSELECT,
	MODE_OFFLINE,
	MODE_ONLINE,
};

