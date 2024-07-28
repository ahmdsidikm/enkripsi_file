import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:encrypt/encrypt.dart' as encrypt;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'dart:convert';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp])
      .then((_) {
    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Numeric Password',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: const LoginPage(),
    );
  }
}

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  _LoginPageState createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final TextEditingController _passwordController = TextEditingController();
  final String correctPassword = '7290527';

  void _submitPassword() {
    String enteredPassword = _passwordController.text;
    if (enteredPassword == correctPassword) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => FileCryptoApp()),
      );
    } else {
      showDialog(
        context: context,
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Wrong Key'),
            content: const Text(
                'The key you entered is incorrect. Please try again.'),
            actions: <Widget>[
              TextButton(
                child: const Text('OK'),
                onPressed: () {
                  Navigator.of(context).pop();
                },
              ),
            ],
          );
        },
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              TextField(
                controller: _passwordController,
                obscureText: true,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  border: OutlineInputBorder(),
                  labelText: 'Key',
                ),
              ),
              const SizedBox(height: 20.0),
              ElevatedButton(
                onPressed: _submitPassword,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  padding: const EdgeInsets.symmetric(
                      vertical: 15.0, horizontal: 40.0),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10.0),
                  ),
                ),
                child: const Text(
                  'Login',
                  style: TextStyle(
                    fontSize: 18.0,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class FileCryptoApp extends StatelessWidget {
  final ValueNotifier<ThemeMode> _themeModeNotifier =
      ValueNotifier(ThemeMode.system);

  FileCryptoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: _themeModeNotifier,
      builder: (context, themeMode, _) {
        return MaterialApp(
          title: 'File Encrypted',
          themeMode: themeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primarySwatch: Colors.teal,
            visualDensity: VisualDensity.adaptivePlatformDensity,
          ),
          home: FileCryptoScreen(
            onThemeChanged: (newThemeMode) {
              _themeModeNotifier.value = newThemeMode;
            },
            currentThemeMode: themeMode,
          ),
        );
      },
    );
  }
}

class FileCryptoScreen extends StatefulWidget {
  final ValueChanged<ThemeMode> onThemeChanged;
  final ThemeMode currentThemeMode;

  FileCryptoScreen(
      {required this.onThemeChanged, required this.currentThemeMode});

  @override
  _FileCryptoScreenState createState() => _FileCryptoScreenState();
}

class _FileCryptoScreenState extends State<FileCryptoScreen> {
  File? _selectedFile;
  List<FileSystemEntity> _encryptedImages = [];
  List<FileSystemEntity> _encryptedDocuments = [];
  bool _isProcessing = false;
  final TextEditingController _passwordController = TextEditingController();
  PageController _pageController = PageController();

  @override
  void initState() {
    super.initState();
    _requestPermissions();
    _loadEncryptedFiles();
  }

  Future<void> _requestPermissions() async {
    if (Platform.isAndroid) {
      // Request permissions for Android
    } else if (Platform.isIOS) {
      // iOS doesn't need explicit permissions for accessing Downloads
    }
  }

  Future<void> _loadEncryptedFiles() async {
    final directory = await getApplicationDocumentsDirectory();
    setState(() {
      _encryptedImages = directory
          .listSync()
          .where((file) =>
              file.path.contains('encrypted_') &&
              (file.path.endsWith('.png') ||
                  file.path.endsWith('.jpg') ||
                  file.path.endsWith('.jpeg')))
          .toList();
      _encryptedDocuments = directory
          .listSync()
          .where((file) =>
              file.path.contains('encrypted_') &&
              !(file.path.endsWith('.png') ||
                  file.path.endsWith('.jpg') ||
                  file.path.endsWith('.jpeg')))
          .toList();
    });
  }

  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles();
      if (result != null) {
        setState(() {
          _selectedFile = File(result.files.single.path!);
        });
      }
    } catch (e) {
      _showErrorDialog('Error picking file: $e');
    }
  }

  Future<String?> _pickDirectory() async {
    String? selectedDirectory = await FilePicker.platform.getDirectoryPath();
    return selectedDirectory;
  }

  Future<void> _encryptFile() async {
    if (_selectedFile == null) {
      _showErrorDialog('Please select a file first');
      return;
    }
    if (_passwordController.text.isEmpty) {
      _showErrorDialog('Please enter a password');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final key = _generateKey(_passwordController.text);
      final iv = encrypt.IV.fromSecureRandom(16);
      final encrypter = encrypt.Encrypter(encrypt.AES(key));

      final fileBytes = await _selectedFile!.readAsBytes();
      final encrypted = encrypter.encryptBytes(fileBytes, iv: iv);

      final directory = await getApplicationDocumentsDirectory();
      final fileName =
          'encrypted_${DateTime.now().millisecondsSinceEpoch}_${_selectedFile!.path.split('/').last}';
      final encryptedFile = File('${directory.path}/$fileName');

      List<int> encryptedBytes = iv.bytes + encrypted.bytes;
      await encryptedFile.writeAsBytes(encryptedBytes);

      await _loadEncryptedFiles();
      _showSuccessDialog('File encrypted successfully');

      setState(() {
        _selectedFile = null;
      });
    } catch (e) {
      print('Error encrypting file: $e');
      _showErrorDialog('Error encrypting file: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _decryptFile(File file) async {
    if (_passwordController.text.isEmpty) {
      _showErrorDialog('Please enter a password');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      final key = _generateKey(_passwordController.text);
      final fileBytes = await file.readAsBytes();

      final iv = encrypt.IV(fileBytes.sublist(0, 16));
      final encryptedBytes = fileBytes.sublist(16);

      final encrypter = encrypt.Encrypter(encrypt.AES(key));
      final decrypted =
          encrypter.decryptBytes(encrypt.Encrypted(encryptedBytes), iv: iv);

      String? selectedDirectory = await _pickDirectory();
      if (selectedDirectory == null) {
        setState(() {
          _isProcessing = false;
        });
        return;
      }

      final fileName =
          'decrypted_${DateTime.now().millisecondsSinceEpoch}_${file.path.split('/').last.replaceFirst('encrypted_', '')}';
      final decryptedFile = File('$selectedDirectory/$fileName');

      await decryptedFile.writeAsBytes(decrypted);

      _showSuccessDialog(
          'File decrypted successfully and saved to: ${decryptedFile.path}');
    } catch (e) {
      print('Error decrypting file: $e');
      _showErrorDialog('Error decrypting file: ${e.toString()}');
    } finally {
      setState(() {
        _isProcessing = false;
      });
    }
  }

  Future<void> _deleteFile(File file) async {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Confirm Deletion'),
          content: const Text('Are you sure you want to delete this file?'),
          actions: [
            TextButton(
              onPressed: () async {
                await file.delete();
                await _loadEncryptedFiles();
                Navigator.of(context).pop();
                _showSuccessDialog('File deleted successfully');
              },
              child: const Text('Delete'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Error'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSuccessDialog(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Success'),
          content: Text(message),
          actions: <Widget>[
            TextButton(
              child: const Text('OK'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  encrypt.Key _generateKey(String password) {
    final keyBytes = utf8.encode(password);
    final hashBytes = sha256.convert(keyBytes).bytes;
    return encrypt.Key(Uint8List.fromList(hashBytes));
  }

  @override
  Widget build(BuildContext context) {
    final isDarkMode = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('File Encrypted'),
        backgroundColor: Colors.black12,
        actions: [],
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            ElevatedButton(
              onPressed: _pickFile,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: Colors.blueAccent,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(150, 50),
              ),
              child: const Text('Pick a file'),
            ),
            const SizedBox(height: 10),
            if (_selectedFile != null)
              Text('Selected file: ${_selectedFile!.path}'),
            const SizedBox(height: 10),
            TextField(
              controller: _passwordController,
              decoration: InputDecoration(
                labelText: 'Password',
                border: const OutlineInputBorder(),
                filled: true,
                fillColor: isDarkMode
                    ? const Color.fromARGB(164, 50, 48, 48)
                    : Colors.white,
              ),
              style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
              obscureText: true,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _isProcessing ? null : _encryptFile,
              style: ElevatedButton.styleFrom(
                foregroundColor: Colors.white,
                backgroundColor: _isProcessing ? Colors.grey : Colors.teal,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                minimumSize: const Size(150, 50),
              ),
              child: _isProcessing
                  ? const CircularProgressIndicator()
                  : const Text('Encrypt file'),
            ),
            const SizedBox(height: 20),
            Expanded(
              child: PageView(
                controller: _pageController,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Encrypted Documents:',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _encryptedDocuments.length,
                          itemBuilder: (context, index) {
                            final file = _encryptedDocuments[index];
                            return ListTile(
                              title: Text(file.path.split('/').last),
                              subtitle: Text(_getFileSize(file)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.lock_open,
                                        color: isDarkMode
                                            ? Colors.tealAccent
                                            : Colors.teal),
                                    onPressed: () => _decryptFile(file as File),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteFile(file as File),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Encrypted Images:',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      Expanded(
                        child: ListView.builder(
                          itemCount: _encryptedImages.length,
                          itemBuilder: (context, index) {
                            final file = _encryptedImages[index];
                            return ListTile(
                              title: Text(file.path.split('/').last),
                              subtitle: Text(_getFileSize(file)),
                              trailing: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  IconButton(
                                    icon: Icon(Icons.lock_open,
                                        color: isDarkMode
                                            ? Colors.tealAccent
                                            : Colors.teal),
                                    onPressed: () => _decryptFile(file as File),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.delete,
                                        color: Colors.redAccent),
                                    onPressed: () => _deleteFile(file as File),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _getFileSize(FileSystemEntity file) {
    if (file is File) {
      final bytes = file.lengthSync();
      final kilobytes = bytes / 1024;
      final megabytes = kilobytes / 1024;
      return '${megabytes.toStringAsFixed(2)} MB';
    }
    return '0 MB';
  }
}
