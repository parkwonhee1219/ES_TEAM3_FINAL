import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime, time
from pytz import timezone


# Firebase 초기화
cred = credentials.Certificate("C:/Users/User/Desktop/db/store-b179f-firebase-adminsdk-jxxp8-18b3d61eba.json")
firebase_admin.initialize_app(cred)
db = firestore.client()


def qr_check_update_attendance(qr_data, mode, scan_time):
    workers_ref = db.collection("login")
    worker_doc = workers_ref.document(qr_data).get()

    if not worker_doc.exists:
        print(f"QR 정보 '{qr_data}'와 일치하는 문서를 찾을 수 없습니다.")
        return {"status": "failed", "message": "일치하는 문서를 찾을 수 없습니다."}

    worker_name = worker_doc.to_dict().get("name")
    if not worker_name:
        print(f"login 문서 '{qr_data}'에 'name' 필드가 없습니다.")
        return {"status": "failed", "message": "'name' 필드를 찾을 수 없습니다."}

    # UTC+9 (KST) 시간대로 변환
    kst = timezone('Asia/Seoul')
    scan_time = scan_time.astimezone(kst)  # QR 스캔 시간을 KST로 변환
    scan_date = scan_time.date()  # 날짜만 추출

    # calendar_events에서 조건에 맞는 문서 찾기
    calendar_events_ref = db.collection("calendar_events")
    query = calendar_events_ref.where("name", "==", worker_name).get()

    target_doc = None
    for doc in query:
        event_data = doc.to_dict()

        # Firestore에서 받은 UTC 타임스탬프를 KST로 변환
        event_start_time = event_data.get("start_time")
        event_end_time = event_data.get("end_time")

        if event_start_time and event_end_time:
            event_start_time = event_start_time.astimezone(kst)
            event_end_time = event_end_time.astimezone(kst)

            # 날짜 비교
            if event_start_time.date() == scan_date and event_end_time.date() == scan_date:
                target_doc = doc
                break

    if not target_doc :
        print(f"조건에 맞는 이벤트를 찾을 수 없습니다. (name={worker_name}, date={scan_date})")
        
 # 새로운 문서 생성
        midnight = datetime.combine(scan_date, time(0, 0)).astimezone(kst)  # 해당 날짜 00시 00분

        if mode == "checkin":
            new_event_data = {
                "name": worker_name,
                "start_time": midnight,
                "end_time": midnight,
                "real_start": scan_time,  # 출근 시간
                "real_end": midnight
            }
            new_doc_ref = calendar_events_ref.document()  # 랜덤 문서 ID 생성
            new_doc_ref.set(new_event_data)
            print(f"새로운 이벤트 문서 생성 완료 (name={worker_name}, real_start={scan_time})")
            return {"status": "success", "message": "새로운 문서를 생성하고 출근 시간이 성공적으로 업데이트되었습니다."}

        elif mode == "checkout":
            new_event_data = {
                "name": worker_name,
                "start_time": midnight,
                "end_time": midnight,
                "real_start": midnight,
                "real_end": scan_time  # 퇴근 시간
            }
            new_doc_ref = calendar_events_ref.document()  # 랜덤 문서 ID 생성
            new_doc_ref.set(new_event_data)
            print(f"새로운 이벤트 문서 생성 완료 (name={worker_name}, real_end={scan_time})")
            return {"status": "success", "message": "새로운 문서를 생성하고 퇴근 시간이 성공적으로 업데이트되었습니다."}

        else:
            return {"status": "failed", "message": "조건에 맞는 이벤트가 없고, 잘못된 요청입니다."}
        
    # real_start 또는 real_end 업데이트
    if mode == "checkin":
        calendar_events_ref.document(target_doc.id).update({"real_start": scan_time})
        print(f"출근 시간 업데이트 완료 (real_start: {scan_time})")
    elif mode == "checkout":
        calendar_events_ref.document(target_doc.id).update({"real_end": scan_time})
        print(f"퇴근 시간 업데이트 완료 (real_end: {scan_time})")
    else:
        print(f"알 수 없는 모드: {mode}")
        return {"status": "failed", "message": "잘못된 요청입니다."}

    return {"status": "success", "message": f"{mode} 시간이 성공적으로 업데이트되었습니다."}

