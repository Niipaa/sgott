///
/// メインスクリプト2（各種モードへ分岐するまでを担当）
///
/// $HeadURL: https://svnrepos.sandlot.jp/svn/repos/AZUCHI/branches/international/Data/MainScript/MAINSCRIPT.AS $
/// $Id: MAINSCRIPT.AS 11132 2018-06-18 10:11:10Z prg_m_shimazaki $
///

/// @attension ゲームショウ用の処理は IsTGSMode でのみ分岐しています

#include "CommonTypes.h"
#include "CommonTypes.inner.h"
#include "ui_common_const.h"
#include "utility.h"
#include "locale.h"

BG					g_bg = BG();
BG					g_main_frame = BG();
Fade				g_fade = Fade();
Resource			g_resource = Resource();
Chat				g_chat = Chat();
UiObject			@g_prev_object = UiObject();
bool g_is_mission_clear = false; // 直前のミッションをクリアしたか？
SaveDataObject		@g_sys_cfg_object = SaveDataObject();	//システムコンフィグのセーブデータ用オブジェクト

// モードセレクト後のデータロード処理
bool	LoadSaveData_ModeSelect()
{
	WaitSaveLoad();
	ModeSelectLoadSaveData();
	WaitSaveLoad();
	return IsCompleteSaveLoad();
}

// タイトルに戻る際のセーブ
void	SaveAllData_ReturnTitle(bool is_focus)
{
	WaitSaveLoad();
	Save(is_focus, "Contents_AutoSaveRetry_ReturnTitle",true);
}

void CheckUnlockArmorWeaponLimit()
{
	int clear_ratio = GetAchivementValue_Int("AllClearRatio");
	if( clear_ratio >= 7000 ) {
		if( UnlockArmorWeaponLimit() ) {
			Dialog_Message( "Sys_UnlockArmorWeaponLimit" );
		}
	}
}

//-- ----------------------------------------------------------------------------------------------
int main()
{
	SetMemoryType(1);

	string current_routine = "Boot"; // 最初にコルーチン呼び出しを行う関数を登録しておく

	DeleteAllMenuUi();

	if( GetStartupRoutine().length() > 0 ) {
		print( "[" + GetStartupRoutine() + "] changed" );
		current_routine = GetStartupRoutine();
	}

	while( true ) {
		// 正式な呼び出し型情報を作成する
		string exec = "string " + current_routine + "()";
		print(exec);
		// コルーチン呼び出し
		coRoutine routine = createCoRoutine(exec);
		// コルーチンが完了するまで待つ
		routine.wait();
		// コルーチンから戻り値を取り出す
		current_routine = routine.resultString();

		// exitであれば抜ける
		if( "exit" == current_routine ) {
			break;
		}
	}

	InitializeAll();

	print("MainScript2 end");
	return 0;
}

//===============================================================================
// 起動
string Boot()
{
	Network_SetLocation(BOOTING);

	WaitJob();
	Reset( RESET_FLAG_ALL );

/////// _STEAM_VER_ ///////
	g_resource.CreateMousePointing();
///////////////////////////

	if( INVITATION_TYPE_NONE != GetInvitationType() ){
		return "Invite";
	}

	return "StartToTitle";
}

//===============================================================================
// 再起動
string ReBoot()
{
	Network_SetLocation(BOOTING);

	g_music.Stop( 1 );
	// ジョブのコールバック等が仕掛けられている可能性があるので、ジョブの終了を待つ
	WaitJob();

	g_music.WaitStop();

	// 完全リセット
	// マップ、UI、リソースの解放、サウンドの停止、ネットワークの停止等、システム系のリセットが行われる
	// ゲームの進行状況は別途 Reset を呼び出す
	SystemReset();
	
	return "Boot";
}

void InitializeAll()
{
	// リソース開放
	g_resource.FreeGroup(RESOURCE_GROUP_SCENE);
	g_resource.FreeGroup(RESOURCE_GROUP_MODE);

	// ネットワークコード終了
	Network_End();

	// 戻ってきた時のセーブロード待ち
	WaitSaveLoad();

	// UIを全部掃除
	DeleteAllMenuUi();

	//
	Reset( RESET_FLAG_ALL );
	
	//
	ResetControllerAssign();	// プレイヤーを一人に設定

	//フェード用のUI作成
	g_fade.Create();

	// スクリプト起動時のリソース常駐を行う
	g_resource.Entry("app:/UI/UiResourceGroup_BootScript.sgo", SYSTEM_GROUP_TITLE, 0);
	g_resource.Wait();

}

//===============================================================================
// 招待処理
//  とりあえず失敗したらTitleに戻している
string Invite()
{
	g_music.Stop(g_music_fadetime);

	g_fade.Wait(); // 事前にFadeout呼び出しがあれば同期、なければ何もしない

	g_music.WaitStop();

	//初期化
	InitializeAll();

//// LOGO_LOAD_SAVEDATA ////
	// ロゴ前ロード
	LogoLoadSaveData();
	WaitSaveLoad();
////////////////////////////

	// 企業ロゴ表示
	CompanyLogo();
	Network_SetLocation(BOOT_COMPLETE);

	// PlayGoチェック
	if( false == IsDownloadComplete() ) {
		g_fade.Wait();
		g_fade.Transparency();
		Dialog_Message( "PlayGoDownload_Invitation" );
		return "StartToTitle";
	}

	g_music.Play( "BGM_E5S01_Title" );

	g_fade.Wait();
	g_fade.Transparency();
	titleSaveDataLoad();

	WaitSearchUpdateAddon();	//追加コンテンツの更新終了を待つ
	WaitSaveLoad();

	if( IsCompleteSaveLoad() == false ) {
		Dialog_Message( "Sys_LoadFailed_ToTitle" );
		return "StartToTitle";
	}

	g_fade.Black(); // 画面は黒で開始

	g_bg.Play("app:/ui/lyt_SlotSelect_BG.sgo");
	g_main_frame.Play("app:/ui/lyt_SlotFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	// スロット選択
	UiObject @object = _CreateSlotSelect();
	g_fade.In();

	object.WaitCloseRequest();

	string ret_string;
	if( GetUiExitCode() == Hui_ReturnOK) {
		int invitation_type = GetInvitationType();

		int mode;
		if( INVITATION_TYPE_INVITE == invitation_type ) {
			// 招待された側のみパッケージチェックを行う
			mode = GetInvitationMode();
			// パッケージを持っているかチェック
			if( mode < 0 ) {
				// Sys_InviteCancel
				Dialog_Message( "Sys_JoinGameCancel" );

				return "StartToTitle";
			}
		} else if( INVITATION_TYPE_PLAYTOGETHER_HOST == invitation_type ) {
			// とりあえずオンラインモードが選択されたことにする
			mode = GetModeNo(GAME_ONLINE_SCENARIO,0);
		} else {
			// テスト用経路、boot経由での本番では利用されない
			mode = GetModeNo(GAME_ONLINE_SCENARIO,0);
		}
		WaitSaveLoad();
		
		// 招待状に設定されているモードに設定
		FreeResourceGroup( RESOURCE_GROUP_MODE );
		if( !SetMode(mode) ) {
			Dialog_Message( "Lobby_NotHaveContents" );
			return "StartToTitle";
		}

		// モード、ゲームデータ読み込み
		if( LoadSaveData_ModeSelect() == false ){
			// エラーがあったのでスロットセレクトに
			Dialog_Message( "Sys_LoadFailed_ToTitle" );
			return "StartToTitle";
		}
		UnlockDownloadContents();

		UpdateAchievementCounter( false, false );
		AchievementAddCount("PlayCount");

		DeleteAllMenuUi();

		return "OnlineMode";
	}

	return "StartToTitle";
}

//===============================================================================
//タイトル開始まで
string StartToTitle()
{
	g_music.Stop(g_music_fadetime);

	g_fade.Wait(); // 事前にFadeout呼び出しがあれば同期、なければ何もしない
	g_fade.Black(); // 画面は黒で開始

	// タイトルに戻った段階で招待情報はクリアされる
	ClearInvitation();
	ClearPlayTogether();
	
	g_music.WaitStop();

	//初期化
	InitializeAll();

//// LOGO_LOAD_SAVEDATA ////
	// ロゴ前ロード
	LogoLoadSaveData();
	WaitSaveLoad();
////////////////////////////

	// 企業ロゴ表示
	CompanyLogo();

	g_fade.Wait();
	g_fade.Transparency();
	Network_SetLocation(BOOT_COMPLETE);
	WaitSaveLoad();
	CheckInvitation();
	g_fade.Black();
	
	// タイトル表示
	Title();

	if( IsTGSMode() ) {
		return "HQMain";
	}
	return "SlotSelect";
}



class Logo {
	UiObject@ m_handle = UiObject();
	string m_current;

	int play(string file,bool is_button_skipable) {
		m_current = file;

		if( false == IsLogoDisplayable(m_current) ) {
			return 0;
		}

		bool is_movie = (-1 != file.findLast(".MP4") );

		if( false == is_movie ) {
			string arg = "[tex_path|";
			arg += file;
			arg += "]";
			arg += "[skippable|";
			if ( is_button_skipable==true)
			{	arg += "true";		}
			else
			{	arg += "false";		}
			arg += "]";
			@m_handle = CreateUiFileOpt("app:/ui/lyt_Logo_sandlot.sgo",arg);
			g_fade.In();
		} else {
			@m_handle = UiObject(PlayLogoMovie("APP:/UI/"+file,is_button_skipable));
		}

		return 1;
	}
	void wait(){
		m_handle.WaitClose();
		g_fade.Wait();

		SetLogoDisplayed(m_current);
		m_current = "";
	}
};

//-----------------------------
// 企業ロゴ
void CompanyLogo()
{
	g_resource.Entry("app:/UI/UiResourceGroup_CompanyLogo.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Wait();

	Logo logo = Logo();

	logo.play("D3LOGO.MP4",true);
	logo.wait();

	logo.play("LOGO_CRIWARE.DDS",true);
	logo.wait();

	logo.play("LOGO_HAVOK.DDS",false);
	logo.wait();
	
	logo.play("LOGO_SANDLOT.DDS",true);
	logo.wait();

	g_fade.Out();
	g_fade.Wait();

	// ロゴ表示で使用されたリソースを開放
	g_resource.FreeGroup(SYSTEM_GROUP_SCENE);
}

void titleSaveDataLoad()
{
	WaitSaveLoad();	// 戻ってくる際のセーブ処理待機

	SearchUpdateAddon();	//追加コンテンツの更新開始

	// tgsモードはロードは行わない
	if( false == IsTGSMode() ) {
		TitleLoadSaveData();	// システムコンフィグとスロット選択用データロード開始
	}
}

//-----------------------------
// タイトル画面
void Title()
{
	//リソース読み込み
	g_resource.Entry("app:/UI/UiResourceGroup_Title.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Wait();

	g_bg.Play("app:/ui/lyt_TitleBg.sgo");
	g_music.Play( "BGM_E5S01_Title" );			// BGM:タイトル画面

	g_fade.In();

	UiObject@ ui_title = CreateUiFile("app:/ui/lyt_Title.sgo");

	//次の画面のリソース読み込み開始
	g_resource.Entry("app:/UI/UiResourceGroup_SlotSel.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Entry("app:/UI/UiResourceGroup_ModeSel.sgo", SYSTEM_GROUP_SCENE, 0);

	titleSaveDataLoad();

	g_fade.Wait();

	ui_title.WaitClose();
	WaitSearchUpdateAddon();	//追加コンテンツの更新終了を待つ
	
	
	g_resource.Wait();
	// ロード終了待機
	WaitSaveLoad();
	g_sys_cfg_object.WaitComplete();
	if( IsCompleteSaveLoad() == false )
	{
		// ここでのロードは停止しない(エラーはロード処理中で表示)
	}

	// 次の画面へ
	g_fade.Out();
	g_fade.Wait();
	g_bg.Stop();
}

//===============================================================================
// ゲームショウのゲーム終了後画面
string TSGEnding()
{
	g_resource.Entry("app:/UI/UiResourceGroup_TGSEnding.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Wait();
	g_bg.Play("app:/ui/lyt_TGS2016_END.sgo");
	
	//Dialog_Message("Sys_PressButton");
	UiObject@ tgs = CreateUiFile("app:/ui/lyt_TgsEnd.sgo");
	g_fade.In();
	tgs.WaitClose();	//uiが
	
	g_fade.Out();
	g_fade.Wait();
	
	g_bg.Stop();
	
	return "Boot";
}

UiObject@	_CreateSlotSelect()
{
	int slot_select_mode = UISLOTSELECT_NORMAL;
	if( INVITATION_TYPE_NONE != GetInvitationType() ){
		slot_select_mode = UISLOTSELECT_INVITATION;
	}
	int ui_handle = CreateSlotSelectUi2(slot_select_mode);
	UiObject @object = UiObject(ui_handle);

	return object;
}

//===============================================================================
// スロット選択
string SlotSelect()
{
	Reset( RESET_FLAG_SLOT_RESET );
	g_bg.Play("app:/ui/lyt_SlotSelect_BG.sgo");
	g_main_frame.Play("app:/ui/lyt_SlotFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	//UiObject @object = CreateUiFileOpt("app:/ui/lyt_ModeSelect.sgo","[UISLOTSELECT|"+UISLOTSELECT_NORMAL+"]");
	UiObject @object = _CreateSlotSelect();
	object.SetDrawOrder(@g_prev_object);
	g_fade.In();

	object.WaitCloseRequest();

	string ret_string;
	if( GetUiExitCode() == Hui_ReturnOK)
	{
		ret_string = "ModeSelect";
	}
	else
	{
		g_fade.Out();
		ret_string = "StartToTitle";
	}
	return ret_string;
}


//===============================================================================
// モード選択
string ModeSelect()
{
	Reset( RESET_FLAG_MODE_RESET );

	g_fade.In();

	g_bg.Play("app:/ui/lyt_SlotSelect_BG.sgo");
	g_main_frame.Play("app:/ui/lyt_SlotFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	UiObject@ ui_handle = CreateUiFile("app:/ui/lyt_ModeSelect.sgo");
	@g_prev_object = ui_handle;
	ui_handle.WaitCloseRequest();

	//キャンセルならもどる
	if( GetUiExitCode() ==  Hui_ReturnCancel)
	{
		return "SlotSelect";	//戻る
	}

	g_resource.FreeGroup(RESOURCE_GROUP_MODE);

	// 返値によりモードを切り替え
	int ret = GetUiExitCode();
	int mode_id = ((ret & 0xff00) >> 8);	// GameModeID
	int mode_no = ( ret & 0x00ff); 			// pkgの順

	if( mode_id == UIMODESELECT_RESULT_CANCEL ) {
		return "SlotSelect";
	}

	// モード設定

	string return_jmp = "StartToTitle";

	if( UIMODEINDEX_ERROR != mode_no ) {
		switch( mode_id ) {
		case GAME_OFFLINE_SCENARIO:
			return_jmp = "HQMain";
			break;
		case GAME_ONLINE_SCENARIO:
			return_jmp = "OnlineMode";
			break;
		}

		SetMode(mode_no);

		// モード、ゲームデータ読み込み
		if( LoadSaveData_ModeSelect() == false ){
			// エラーがあったのでスロットセレクトに
			Dialog_Message( "Sys_LoadFailed_ToSlotSelect" );
			
			@g_prev_object = UiObject();
			return "SlotSelect";
		}
		UnlockDownloadContents();
		UpdateAchievementCounter( false, false );
		AchievementAddCount("PlayCount");
	}

	g_music.Stop(g_music_fadetime);

	g_fade.Out();
	g_fade.Wait();

	DeleteAllMenuUi();
	g_fade.Black();

	return return_jmp;
}

//===============================================================================
// 作戦司令本部画面
string HQMain()
{
	g_resource.Entry("app:/ui/UiResourceGroup_HQ.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.EntryModeImage(0);
	g_resource.Wait();

	g_fade.Wait();

	g_bg.Play("app:/ui/lyt_bg.sgo");
	g_main_frame.Play("app:/ui/lyt_MainFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	g_music.Play( GetMainMenuBgm() );	// BGM:メニュー画面

	UiObject@ ui_handle3D = CreateUiFile("app:/ui/lyt_HUiHQ3DModel.sgo");

	UiObject@ ui_handle = CreateUiFile("app:/ui/lyt_HUiHQMain.sgo");

	//-- フェードイン
	g_fade.In();
	g_fade.Wait();

	//-- UI操作終了 --
	ui_handle.WaitCloseRequest();
	g_music.Stop( g_music_fadetime );
	//
	if( GetUiExitCode() ==  Hui_ReturnOK)
	{
		//ミッションへ
		g_fade.Out();
		g_fade.Wait();

		return "PlayMission_Offline";
	}

	//タイトルに戻るに設定された
	if( false == IsTGSMode() && GetUiExitCode() ==  Hui_HQMain_Return_GotoTitle)
	{
		SaveAllData_ReturnTitle(true);
	}

	//タイトルに戻る
	g_fade.Out();
	g_fade.Wait();

	ui_handle3D.Close();

	g_music.WaitStop();

	return "StartToTitle";	//todo:
}

//===============================================================================
// ミッション共通処理
int PlayMission_Common()
{
	g_fade.Out();
	g_fade.Wait();
	DeleteAllMenuUi();

	g_resource.FreeGroup(RESOURCE_GROUP_SCENE);

	g_resource.Entry("app:/ui/UiResourceGroup_InMission.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.EntryLoadinImage(0);

	SoldierTypeSortieAddCount();	// 兵科ごとの出撃回数カウントアップ

	// ネットワークの現在位置を更新する(エラー表示用)
	Network_SetLocation(GAME_LOADING);

	// ホスト側のモード番号をチェックして正しいモードでなれけばモード切替を行う

	int new_mode_index = 0;
	if( MISSIONSYNC_ERROR == Network_Wait_MissionPreSync(new_mode_index) ) {
		Dialog_Message("Online_Game_Disconnect");

		g_fade.Black();
		/// 通信に失敗したので、ロビーへ戻されます
		/// 切断済みになっていますが、GAME_LOADINGなのでメッセージの表示が必要です。
		return MISSION_RESULT_LOBBY;
	}

	if( false == ApplyModeNo(new_mode_index) ) {
		return MISSION_RESULT_RETURNTITLE;
	}

	if( false == Network_Wait_MissionSync() ) {
		Dialog_Message("Online_Game_Disconnect");

		g_fade.Black();
		/// 通信に失敗したので、ロビーへ戻されます
		/// 切断済みになっていますが、GAME_LOADINGなのでメッセージの表示が必要です。
		return MISSION_RESULT_LOBBY;
	}

	// ホスト側のモード番号をチェックして正しいモードでなれけばモード切替を行う
	

	SetUsedWeapon();
	ResetResult();				// アイテムの取得状態を完全にリセット
	
	int result;

	g_resource.Wait();

	SetMemoryType(2);
	for(;;){
		// ネットワークのゲームセッションをリセットする(ローカルの状態をリセットする)
		Network_Session_Reset();

		result = Mission();
		if( result != MISSION_RESULT_RETRY) break;
	}
	// ゲームシーン開放
	g_resource.FreeGroup(RESOURCE_GROUP_SCENE);

	MemoryDump();
	SetMemoryType(1);

	//フェード用のUI再作成
	g_fade.Black();

	switch( result ) {
	case MISSION_RESULT_ABORT:
	case MISSION_RESULT_CLEAR:
		Network_Wait_ResultSync();
		break;
	}

	// ネットワークのゲームセッションを終了する
	Network_Session_End();

	// ネットワークの現在位置を更新する(エラー表示用)
	Network_SetLocation(MENU_ROOM);

	return result;
}

// オフラインミッションを実行する
string PlayMission_Offline()
{
	AchievementAddCount("OfflinePlayCount");	// オフラインミッション開始回数

	// デモの再生
	g_resource.FreeGroup(RESOURCE_GROUP_SCENE);
	Before();
	g_resource.FreeGroup(RESOURCE_GROUP_SCENE);
	
	if( false == IsTGSMode() ) {
		g_chat.Rebuild();
	}
	int result = PlayMission_Common();
	g_chat.Release();

	if( MISSION_RESULT_RETURNTITLE == result ) {
		return "StartToTitle";
	}
	if( result == MISSION_RESULT_CLEAR )
	{
		g_is_mission_clear = true;
		
		if( IsTGSMode() ) {
			return "TSGEnding";
		} else {
			return "Result_Offline";
		}
	}else{
		g_is_mission_clear = false;

		if( IsTGSMode() ) {
			return "TSGEnding";
		} else {
			return "Result_Offline";
			// return "HQMain";
		}
	}
}

//===============================================================================
// オンラインミッション
string PlayMission_Online()
{
	AchievementAddCount("OnlinePlayCount");	// オンラインミッション開始回数	
	
	int result = PlayMission_Common();

	g_is_mission_clear = false;

	if( MISSION_RESULT_RETURNTITLE == result ) {
		return "StartToTitle";
	}

	// ルームとの通信が出来ている場合のみルームに戻す
	if( Network_IsRoomConnected() ) {
		if( result == MISSION_RESULT_CLEAR ){
			g_is_mission_clear = true;
			return "Result_Online";
		}else{
			return "Result_Online";
		}
	} else {
		if( result != MISSION_RESULT_LOBBY ) {
			g_fade.Wait();
			g_fade.Transparency();

			Dialog_Message("Online_Game_Disconnect");
			
			g_fade.Black();
		}
	}

	g_chat.Release();
	Network_LeaveRoom();

	return "Lobby";
}


void PlayEnding(string lyt_sgo,string bgm)
{
	int ui_handle_end = Ending(lyt_sgo);
	if (ui_handle_end != -1)
	{
		g_music.Play(bgm);
		UiObject @object = UiObject(ui_handle_end);
		object.WaitClose();
	}
}

//DLCは共通のエンディング
void DLCEnding()
{
	PlayEnding("app:/ui/lyt_EndingDLC.sgo","BGM_E5S08_EndingTelopOnline");
}

// BGMの言語切替がある場合の付加文字を取得する
string GetBGMLangString()
{
	int lang = GetLanguage();
	if( lang == EN )
	{
		return "_en";
	}
	else if ( lang == CN )
	{
		return "_cn";
	}
	else if ( lang == KR )
	{
		return "_kr";
	}
	else
	{
		return "";
	}
}

//===============================================================================
// オフライン用ミッションリザルト
string Result_Offline()
{
	if(  g_is_mission_clear == true ){
		if( IsLastMission() ) {
			g_fade.In();
			g_music.Stop( g_music_fadetime );
			g_music.WaitStop();
			
			if( GetContentID() == 0 ) {
				//エンディング
				PlayEnding("app:/ui/lyt_Ending.sgo","BGM_E5S07_EndingTelop");
				
				//エンドクレジット
				string end_staff_bgm = "BGM_E5S05_Staffroll" + GetBGMLangString();
				PlayEnding("app:/ui/lyt_EndCredit.sgo",end_staff_bgm);
			} else {
				DLCEnding();
			}
			
			g_fade.Out();
		}
	}

	//
	Result_Common( g_is_mission_clear );

	return "HQMain";
}

string EndingTest()
{
	//エンディング
	g_fade.In();
	g_music.Stop( g_music_fadetime );
	g_music.WaitStop();
	
	//エンディング
	PlayEnding("app:/ui/lyt_Ending.sgo","BGM_E5S07_EndingTelop");
	
	//エンドクレジット
	string end_staff_bgm = "BGM_E5S05_Staffroll" + GetBGMLangString();
	PlayEnding("app:/ui/lyt_EndCredit.sgo",end_staff_bgm);
	
	return "";
}

//===============================================================================
// オンライン用ミッションリザルト
string Result_Online()
{
	if(  g_is_mission_clear == true ){
		if( IsLastMission() ) {
			//通常のパッケージの時のみエンディングを呼び出す
			g_fade.In();
			g_music.Stop( g_music_fadetime );
			g_music.WaitStop();
			
			if( GetContentID() == 0 ) {
				//エンディング
				PlayEnding("app:/ui/lyt_EndingOnline.sgo","BGM_E5S08_EndingTelopOnline");
			}
			else
			{
				DLCEnding();
			}
			g_fade.Out();
		}
	}

	Result_Common( g_is_mission_clear );

	return "Room";
}

//===============================================================================
// ミッションリザルト画面
void Result_Common(bool is_mission_clear )
{
	DeleteAllMenuUi();	// 念のためUIを掃除
	g_fade.Black();

	g_resource.Entry("app:/ui/UiResourceGroup_Result.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Wait();

	g_bg.Play("app:/ui/lyt_bg.sgo");
	g_main_frame.Play("app:/ui/lyt_ResultFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	ResolveResult();	// ドロップアイテムを確定
	UiObject@ ui_handle = CreateUiFile("app:/ui/lyt_HUiResult.sgo");
	g_music.Play( GetMainMenuBgm() );

	g_fade.In();

	bool is_all_clear = ApplyResult(is_mission_clear );	// ミッション結果を反映
	UpdateAchievementCounter( true, is_mission_clear );

	// 武器制限アンロックチェック
	CheckUnlockArmorWeaponLimit();

/////// _STEAM_VER_ ///////
	// セーブデータのバックアップ
	BackupSaveData();
///////////////////////////

	Save(false, "Contents_AutoSaveRetry",true);	// セーブ開始

	// 次の画面用のプリロード開始
	g_resource.SetSilent(true);
	g_resource.EntryModeImage(0);
	g_resource.SetSilent(false);
	
/////// _STEAM_VER_ ///////
	//（オンラインモードのみ）リザルトからルームに戻るときもルームUIのプリロードを行う
	if( Network_IsRoomConnected() ) {
		g_resource.Entry("app:/ui/UiResourceGroup_OnlineRoom.sgo", SYSTEM_GROUP_SCENE, 0);
	}
///////////////////////////

	g_fade.Wait();

	// 初めてラストミッションをクリアしたら、全難易度が解放されたことを通知する。
	if (is_all_clear == true)
	{
		Dialog_Message( "NotifyAllMissionClear" );
	}
	ui_handle.WaitCloseRequest();

	// ClearResult();		// ドロップアイテムをクリア
	ResetResult();

	g_fade.Out();
	g_fade.Wait();

	DeleteAllMenuUi();
	g_fade.Black();
}

enum OnlineInitializeResult {
	TO_LOBBY,
	TO_ROOM,
	TO_CREATEROOM,
	TO_TITLE,
};

/// メモ：UI処理内から直に呼び出すように仕様修正するので、All系の命令は使えない
OnlineInitializeResult _OnlineMode()
{
	int invitation_type = GetInvitationType();
	int result_code;

	Network_SignIn();

	int extra_error_code = 0;
	result_code = Network_PreCheck(extra_error_code);
	if( 0 == extra_error_code && NETWORKBEGINRESULT_NO_PLUS == result_code ) {
		UiObject @object = CreateUiFileOpt("app:/ui/lyt_HUiPsPlus.sgo","");
		object.WaitClose();

		if( 0 == GetUiExitCode() ) {
			// エラーの場合はオンラインモードから抜ける
			return TO_TITLE;
		} else {
			// PLUS:成功
			result_code = NETWORKBEGINRESULT_SUCCESS;
		}
	}

	// 接続中待機ウインドウ作成
	int wait_ui_handle = CreateWaitUi("Online_NameVerify");

	// 接続処理呼び出し
	if( NETWORKBEGINRESULT_SUCCESS == result_code ) {
		result_code = Network_Begin();
	}

	// 名前チェック
	if( NETWORKBEGINRESULT_SUCCESS == result_code ) {
		result_code = Network_NameCheck();
	}

	// エラー判定
	if( NETWORKBEGINRESULT_SUCCESS != result_code ) {
		// 待機ウインドウを消す
		CloseUi(wait_ui_handle);
		WaitUiClose(wait_ui_handle);

		switch( result_code ) {
		case NETWORKBEGINRESULT_NO_SIGNIN:
			Dialog_Message( "GameMode_NoSignin" );
			break;
		case NETWORKBEGINRESULT_FAILED:
			{
				int handle = CreateErrorDialog("GameMode_OnlineFailed",extra_error_code);
				WaitUiClose(handle);
			}
			break;
		case NETWORKBEGINRESULT_PARENTAL:
			Dialog_Message( "GameMode_OnlineCantUse" );
			break;
		case NETWORKBEGINRESULT_IRRELEVANT_NAME:
			Dialog_Message( "Online_NameVerifyError" );
			// 名前がダメなので、必ずタイトルに戻る
			break;
		}

		// エラーの場合はオンラインモードから抜ける
		return TO_TITLE;
	}

	// 一定時間は待ってからダイアログを消す
	//Wait( 60 );

	g_resource.Wait();
	// 待機ウインドウを消す
	CloseUi(wait_ui_handle);

	// ミッション画像だけ先に読ませておく
	g_resource.EntryModeImage(0);

	// 年齢チェックを行い、必要であればチャット禁止などの警告を出す必要がある。
	if( false == Network_IsCommunications() ) {
		int chat_restriction = Network_GetChatRestrictType();
		if( RESTRICT_CHAT == (chat_restriction & RESTRICT_CHAT) ) {
			// チャット禁止
			int ui = CreateChatRestrictUI( 0 );
			WaitUiClose(ui);
		}
		if( RESTRICT_UGC == (chat_restriction & RESTRICT_UGC) ) {
			// UGC禁止
			int ui = CreateChatRestrictUI( 1 );
			WaitUiClose(ui);
		}
	}

	if( INVITATION_TYPE_NONE != invitation_type ) {
		// 招待処理
		int wait_ui_handle = CreateWaitUi("RoomCreate_Join");

		int ret = NETWORKJOINRESULT_FAILED;

		// 接続開始
		bool is_continue = true;
		while( is_continue ) {
			if( INVITATION_TYPE_INVITE == invitation_type ) {
				InvitationJoin join;
				ret = join.wait();
			} else if( INVITATION_TYPE_PLAYTOGETHER_HOST == invitation_type ) {
				ret = NETWORKJOINRESULT_SUCCESS;
			}

			// パスコード再入力
			is_continue = false;
			switch( ret ) {
			case NETWORKJOINRESULT_PASSCODE:
				if( DIALOG_YES == Dialog_YesNo( "OnlineError_RoomPassFailed" ) ) {
					is_continue = true;
				}
				break;
			}
		}
		bool is_room_entry = false;

		// 参加チェック
		switch( ret ) {
		case NETWORKJOINRESULT_SUCCESS:
			is_room_entry = true;
			break;
		case NETWORKJOINRESULT_CHAT_RESTRICTION:
			Dialog_Message( "Lobby_Chat_NotInvite" );
			break;
		case NETWORKJOINRESULT_UGC_RESTRICTION:
			Dialog_Message( "Lobby_UGC_NotInvite" );
			break;
		case NETWORKJOINRESULT_PASSCODE:
		case NETWORKJOINRESULT_FAILED:
			Dialog_Message( "OnlineError_RoomError" );
			break;
		case NETWORKJOINRESULT_FILLED:
			Dialog_Message( "OnlineError_RoomFull" );
			break;
		}

		OnlineInitializeResult return_function = TO_TITLE;

		if( is_room_entry ) {
			g_resource.Entry("app:/ui/UiResourceGroup_OnlineRoom.sgo", SYSTEM_GROUP_SCENE, 0);
			g_resource.EntryModeImage(0);

			if( INVITATION_TYPE_PLAYTOGETHER_HOST == invitation_type ) {
				return_function = TO_CREATEROOM;
			} else {
				return_function = TO_ROOM;
			}
		}

		CloseUi(wait_ui_handle);
		WaitUiClose(wait_ui_handle);

		if( INVITATION_TYPE_PLAYTOGETHER_HOST != invitation_type ) {
			// 招待情報をクリア
			ClearInvitation();
		}

		/// 
		return return_function;
	}
	WaitUiClose(wait_ui_handle);

	return TO_LOBBY;
}

//===============================================================================
// サーバ選択画面
// オンラインモード
string OnlineMode()
{
	g_fade.Black();
	DeleteAllMenuUi();

	g_fade.In();

	// この関数以降基本的に強制的にタイトルに戻される全体リセットが発生します。管理されていないメモリとかないようにしてください。
	g_music.Play( "BGM_E5S04_OnlineLobby" );	// BGM:メニュー画面
	g_resource.Entry("app:/ui/UiResourceGroup_Online.sgo", SYSTEM_GROUP_SCENE, 0);

	OnlineInitializeResult next = _OnlineMode();

	g_fade.Black();

	switch( next ) {
	case TO_LOBBY:
		return "Lobby";
	case TO_ROOM:
		return "Room";
	case TO_CREATEROOM:
		return "CreateRoom";
	default:
		break;
	}

	g_music.Stop( 0 );
	return "StartToTitle";
}



//===============================================================================
// ロビーから開始
string StartLobby()
{
	g_music.Stop(g_music_fadetime);
	g_music.WaitStop();
	
	//初期化
	InitializeAll();
	Network_SetLocation(BOOT_COMPLETE);

	//タイトル
	titleSaveDataLoad();

	WaitSearchUpdateAddon();	//追加コンテンツの更新終了を待つ
	WaitSaveLoad();

	SetMode(GetModeNo(GAME_ONLINE_SCENARIO,0));

	// モード、ゲームデータ読み込み
	if( LoadSaveData_ModeSelect() == false ){
		Dialog_Message( "Sys_LoadFailed_ToTitle" );

		return "StartToTitle";
	}
	UnlockDownloadContents();

	g_resource.Entry("app:/UI/UiResourceGroup_BootScript.sgo", SYSTEM_GROUP_TITLE, 0);
	g_resource.Entry("app:/ui/UiResourceGroup_Online.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Entry("app:/ui/UiResourceGroup_OnlineRoom.sgo", SYSTEM_GROUP_SCENE, 0);

	OnlineInitializeResult next = _OnlineMode();
	switch( next ) {
	case TO_LOBBY:
		return "Lobby";
	case TO_ROOM:
		return "Room";
	case TO_CREATEROOM:
		return "CreateRoom";
	default:
		break;
	}

	return "StartToTitle";
}

bool ApplyModeNo(int mode_index)
{
	if (mode_index == GetCurrentModeNo()) {
		RestoreMissionSelect();
		// 既にロード済みなのでなにもしないようにする
	} else {
		g_resource.FreeGroup(RESOURCE_GROUP_MODE);

		Storage	gamemode("store_gamemode");
		if (SetMode(mode_index)) {

			g_resource.SetSilent(true);
			g_resource.EntryModeImage(0);
			g_resource.SetSilent(false);

			// モード、ゲーム、実績データ読み込み
			if (LoadSaveData_ModeSelect()) {
				UpdateAchievementCounter(false, false);
				UnlockDownloadContents();

				gamemode.Restore();
			} else {
				gamemode.Release();
				// セーブデータのロードに失敗したのでタイトルに戻ります
				Dialog_Message("Sys_LoadFailed_ToTitle");
				return false;
			}
		} else {
			gamemode.Release();
			// コンテンツを所有していないのでタイトルに戻ります
			Dialog_Message("Lobby_NotHaveContents");

			return false;
		}
	}
	return true;
}

void _lobby_SetModeHandler(UiObject @window, string message_id, string wparam)
{
	if ("SetModeRequest" == message_id) {
		// HUiLobbyからのコールバック、DLCモードとセーブデータのロードを行うために呼び出される

		// モード番号そのものがくるので、そのまま使用する
		int mode_no = parseInt(wparam);

		if (false == ApplyModeNo(mode_no)) {
			window.PostMessage("ModeRequestDone", "[result|false]");
		} else {
			window.PostMessage("ModeRequestDone", "[result|true]");
		}
	}
}

//===============================================================================
// ロビー画面
string Lobby()
{
	g_chat.Release();

	// ロビーに戻った段階で不用になっているネットワーク通知処理を掃除する（累積分の切断通知等）
	Network_ClearMessage();

	g_resource.Entry("app:/ui/UiResourceGroup_Online.sgo", SYSTEM_GROUP_SCENE, 0);
	g_resource.Wait();

	g_bg.Play("app:/ui/lyt_bg.sgo");
	g_music.Play( "BGM_E5S04_OnlineLobby" );	// BGM:メニュー画面

	g_main_frame.Play("app:/ui/lyt_MainFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	// ロビー画面のＵＩ表示

	Network_SetLocation(MENU_LOBBY);
	
	string result = "";
	
	UiObject@ window = CreateUiFile("app:/ui/lyt_HUiOnlineLobby.sgo");
	window.SetDrawOrder(@g_prev_object);
	g_fade.In();

	// 次の画面は同じリソースなのでプリロードを開始しておく
	g_resource.Entry("app:/ui/UiResourceGroup_OnlineRoom.sgo", SYSTEM_GROUP_SCENE, 0);

	string message_id;
	string wparam;
	while( window.GetMessage(message_id,wparam) ) {
		_lobby_SetModeHandler(window, message_id, wparam);
	}

	window.WaitCloseRequest();
	int exit_code = GetUiExitCode();

	switch( (exit_code&0xf) ){
	case NETWORKLOBBYMENU_CREATEROOM:
		result = "CreateRoom";
		break;

	case NETWORKLOBBYMENU_JOINROOM:
		g_music.Stop( g_music_fadetime );
		result = "Room";
		break;

	case NETWORKLOBBYMENU_RETURN_TITLE:
		g_music.Stop( g_music_fadetime );
		g_fade.Out();
		g_resource.Wait();
		g_music.WaitStop();
		result = "StartToTitle";
		break;

	default:
		result = "exit";
		break;
	}

	// プレイヤーの選択で少なくとも以下に分岐する
	return result;
}

string CreateRoom()
{
	int invitation_type = GetInvitationType();

	g_resource.Wait();

	g_bg.Play("app:/ui/lyt_bg.sgo");

	g_main_frame.Play("app:/ui/lyt_MainFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	g_music.Play( "BGM_E5S04_OnlineLobby" );

	UiObject@ main_object = CreateUiFile("app:/ui/lyt_HUiOnline_RoomCreate.sgo");
	@g_prev_object = main_object;
	g_fade.In();

	string message_id;
	string wparam;
	while (main_object.GetMessage(message_id, wparam))
	{
		_lobby_SetModeHandler(main_object, message_id, wparam);
	}

	main_object.WaitCloseRequest();

	int exit_code = GetUiExitCode();

	string result = "Lobby";
	switch( exit_code ){
	case Hui_ROOMCREATE_MENU_CREATEROOM:
		Network_SetLocation(MENU_ROOM);
		if( INVITATION_TYPE_PLAYTOGETHER_HOST == invitation_type ) {
			// ここで再度PlayTogetherのシグナルを行うことで招待状を自動送信する
			PlayTogether_Signal();
			// 招待情報をクリア
			ClearInvitation();
		}
		g_music.Stop( g_music_fadetime );
		result = "Room";
		break;
		
	case Hui_ROOMCREATE_MENU_RETURN_LOBBY:
		result = "Lobby";
		break;
	case Hui_ROOMCREATE_MENU_RETURN_TITLE:
		g_music.Stop( g_music_fadetime );
		g_fade.Out();
		g_resource.Wait();
		g_music.WaitStop();
		result = "StartToTitle";
		break;
	}

	return result;
}

string Room()
{
	g_resource.Wait();

	g_fade.Wait();

	g_chat.Build();
	Network_SetLocation(MENU_ROOM);

	g_bg.Play("app:/ui/lyt_bg.sgo");
	g_music.Play( GetMainMenuBgm() );

	g_main_frame.Play("app:/ui/lyt_MainFrame.sgo");
	g_main_frame.GetObject().SetDrawOrder(g_fade.GetObject());

	UiObject@ ui_handle3D = CreateUiFile("app:/ui/lyt_HUiHQ3DModel.sgo");

	UiObject@ main_object = CreateUiFile("app:/ui/lyt_HUiOnlineRoom.sgo");
	@g_prev_object = main_object;

	g_fade.In();

	string message_id;
	string wparam;
	while (main_object.GetMessage(message_id, wparam)) {
		_lobby_SetModeHandler(main_object, message_id, wparam);
	}

	main_object.WaitCloseRequest();
	int exit_code = GetUiExitCode();

	g_music.Stop( g_music_fadetime );

	print("ui_online_room exit code["+exit_code+"]");
	switch( exit_code ){
	case UIONLINE_GOTO_MISSION:
		g_fade.Out();
		g_fade.Wait();
		g_bg.Stop();

		ui_handle3D.Close();

		return "PlayMission_Online";
	case UIONLINE_GOTO_LOBBY:
		SaveAllData_ReturnTitle(false);
		break;
	case UIONLINE_GOTO_RETURNTITLE:
		ui_handle3D.Close();
		g_chat.Release();
		Network_LeaveRoom();
		
		g_music.Stop( g_music_fadetime );
		g_fade.Out();
		g_resource.Wait();
		g_music.WaitStop();
		return "StartToTitle";
	default:
		print("ハンドルされていないリザルトコードが返ってきています ["+exit_code+"]");
		break;
	}

	ui_handle3D.Close();

	// ロビーに戻す
	g_chat.Release();
	Network_LeaveRoom();

	// セーブ
	return "Lobby";
}

