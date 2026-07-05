import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';

class FirebaseScreenAdd extends StatefulWidget {
  const FirebaseScreenAdd({super.key});

  @override
  State<FirebaseScreenAdd> createState() => _FirebaseScreenAddState();
}

class _FirebaseScreenAddState extends State<FirebaseScreenAdd> {
  final TextEditingController _field1Controller = TextEditingController();
  final TextEditingController _field2Controller = TextEditingController();
  bool _isLoading = false;

  @override
  void dispose() {
    _field1Controller.dispose();
    _field2Controller.dispose();
    super.dispose();
  }

  Future<void> _addDataToFirestore() async {
    setState(() {
      _isLoading = true;
    });

    final String field1Value = _field1Controller.text.trim();
    final String field2Value = _field2Controller.text.trim();

    if (field1Value.isEmpty || field2Value.isEmpty) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Both fields are required')),
      );
      return;
    }

    // Capture the messenger before the async gap so we don't use context after await.
    final messenger = ScaffoldMessenger.of(context);
    try {
      debugPrint('Apps count: ${Firebase.apps.length}');
      debugPrint('App name: ${Firebase.app().name}');

      // Set these datas to Firestore
      await FirebaseFirestore.instance.collection('test').add({
        'field1': field1Value,
        'field2': field2Value,
        'createdAt': FieldValue.serverTimestamp(),
      });

      debugPrint('Write success');
      messenger.showSnackBar(
        const SnackBar(content: Text('Firestore write succeeded')),
      );

      // Optionally clear fields after successful write
      _field1Controller.clear();
      _field2Controller.clear();
    } catch (e, s) {
      debugPrint('Firestore error: $e');
      debugPrint('$s');
      messenger.showSnackBar(
        SnackBar(content: Text('Firestore write failed: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add to Firebase Firestore')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            TextField(
              controller: _field1Controller,
              decoration: const InputDecoration(
                labelText: 'Field 1',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 18),
            TextField(
              controller: _field2Controller,
              decoration: const InputDecoration(
                labelText: 'Field 2',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _addDataToFirestore,
                child: _isLoading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Add Data'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
