import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:store_management_system/Gpio/device_controller.dart';

class GpioScreen extends StatefulWidget {
  final DocumentSnapshot userDoc;

  const GpioScreen({Key? key, required this.userDoc}) : super(key: key);

  @override
  State<GpioScreen> createState() => _GpioScreenState();
}

class _GpioScreenState extends State<GpioScreen> {
  // GPIO
  late String token = ''; // 초기값 설정
  List<Map<String, dynamic>> devices = [];

  // Firestore DB
  CollectionReference gpioCollection =
      FirebaseFirestore.instance.collection('gpio');

  CollectionReference loginCollection =
      FirebaseFirestore.instance.collection('login');

  @override
  void initState() {
    super.initState();
    _initializeFirestore();

    // Firestore 리스너 추가
    FirebaseFirestore.instance
        .collection('login')
        .doc(widget.userDoc.id)
        .snapshots()
        .listen((DocumentSnapshot snapshot) {
      if (snapshot.exists) {
        setState(() {
          token = snapshot['token'];
        });
        _loadDevices(); // token이 업데이트된 후 디바이스 로드
      }
    });

    //connectMqtt();
  }

  Future<void> _initializeFirestore() async {
    try {
      // gpio 컬렉션의 모든 문서 가져오기
      final gpioDocs = await gpioCollection.get();

      // 문서가 있는지 확인
      if (gpioDocs.docs.isNotEmpty) {
        // 문서가 있으면 모든 문서 삭제
        for (var doc in gpioDocs.docs) {
          await gpioCollection.doc(doc.id).delete();
        }
        print("All documents in GPIO collection have been deleted.");
      } else {
        print("No documents found in GPIO collection.");
      }
    } catch (e) {
      print("Error initializing Firestore: $e");
    }
  }

  // 디바이스 로드
  void _loadDevices() async {
    print("Loading devices...");
    final loadedDevices = await getDevices(token); // 디바이스 목록 로드
    for (final device in loadedDevices) {
      print(device);
      final status = await getDeviceStatus(device['deviceId'], token);
      device['status'] = status;

      // gpio 컬렉션에 새 장치 추가
      await gpioCollection.add({
        'status': device['status'],
        'id': device['deviceId'],
        'name': device['name']
      });
    }
    setState(() {
      devices = loadedDevices;
      print("Devices updated in UI: $devices");
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Gpio'),
        actions: [
          IconButton(
            icon: Icon(Icons.settings), // 아이콘 설정
            onPressed: () async {
              //publishMessage('LED'); // 메시지 발행
            },
          ),
          IconButton(
            icon: Icon(Icons.info), // 새로운 아이콘 추가
            onPressed: _showTokenDialog, // 아이콘 클릭 시 다이얼로그 표시
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: gpioCollection.snapshots(),
                builder: (BuildContext context,
                    AsyncSnapshot<QuerySnapshot> streamSnapshot) {
                  if (streamSnapshot.hasData) {
                    return ListView.builder(
                      itemCount: streamSnapshot.data!.docs.length,
                      itemBuilder: (context, index) {
                        final DocumentSnapshot documentSnapshot =
                            streamSnapshot.data!.docs[index];

                        Map<String, dynamic> device =
                            documentSnapshot.data() as Map<String, dynamic>;

                        final isOn = device['status'] == 'on';

                        return Card(
                          shape: RoundedRectangleBorder(
                            side: BorderSide(
                              color: isOn ? Colors.green : Colors.grey,
                              width: 2,
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          margin: EdgeInsets.symmetric(vertical: 5),
                          child: ListTile(
                            title: Text(device['name']),
                            subtitle: Text('Status: ${device['status']}'),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                ElevatedButton(
                                  onPressed: () async {
                                    await controlDevice(
                                        device['id'], 'on', token);
                                    setState(() {
                                      device['status'] = 'on';
                                    });
                                  },
                                  child: Text(
                                    'On',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Color.fromARGB(255, 231, 109, 109),
                                  ),
                                ),
                                SizedBox(width: 5),
                                ElevatedButton(
                                  onPressed: () async {
                                    await controlDevice(
                                        device['id'], 'off', token);
                                    setState(() {
                                      device['status'] = 'off';
                                    });
                                  },
                                  child: Text(
                                    'Off',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor:
                                        Color.fromARGB(255, 47, 113, 77),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  }
                  return Center(child: CircularProgressIndicator());
                },
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showTokenInputDialog,
        child: Icon(Icons.edit),
      ),
    );
  }

// 토큰 입력 팝업
void _showTokenInputDialog() {
  final TextEditingController _controller = TextEditingController();
  const String correctValue = "ea53a9b6-eadc-48ba-9e79-a4fc7b04fa27"; // 비교할 값

  showDialog(
    context: context,
    builder: (context) {
      return AlertDialog(
        title: Text(
          'SmartThings Token',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: _controller,
          decoration: InputDecoration(
            labelText: 'Token',
            border: OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              // 입력된 값과 비교
              if (_controller.text.trim() == correctValue) {
                Navigator.pop(context);
                // Firestore의 userDoc 업데이트
                try {
                  // // gpio 컬렉션의 모든 문서 가져오기
                  // final gpioDocs = await gpioCollection.get();

                  // // 문서가 있는지 확인
                  // if (gpioDocs.docs.isNotEmpty) {
                  //   // 문서가 있으면 모든 문서 삭제
                  //   for (var doc in gpioDocs.docs) {
                  //     await gpioCollection.doc(doc.id).delete();
                  //   }
                  //   print("All documents in GPIO collection have been deleted.");
                  // } else {
                  //   print("No documents found in GPIO collection.");
                  // }

                  // Firestore의 userDoc 업데이트
                  await FirebaseFirestore.instance
                      .collection('login')
                      .doc(widget.userDoc.id) // userDoc의 ID를 사용
                      .update({'token': _controller.text.trim()}); // token 필드 업데이트

                  // 로컬 상태 업데이트
                  setState(() {
                    token = _controller.text.trim(); // 토큰 저장
                  });

                  //_loadDevices(); // 디바이스 로드
                } catch (e) {
                  print("Error updating token: $e");
                }
              } else {
                // 잘못된 토큰 입력 시 SnackBar 표시
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('유효하지 않은 토큰입니다.'),
                    duration: Duration(seconds: 2), 
                  ),
                );
              }
            },
            child: Text('Save'),
          ),
        ],
      );
    },
  );
}


  // 현재 토큰을 다이얼로그로 표시하는 메서드
  void _showTokenDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Current Token'),
          content: Text(token), // 현재 토큰 값을 표시
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text('Close'),
            ),
          ],
        );
      },
    );
  }
}
