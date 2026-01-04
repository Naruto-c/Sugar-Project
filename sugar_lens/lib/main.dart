import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'package:image_picker/image_picker.dart';

void main() => runApp(const SugarApp());

class SugarApp extends StatelessWidget {
  const SugarApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(primarySwatch: Colors.green),
      home: const SugarScanner(),
    );
  }
}

class SugarScanner extends StatefulWidget {
  const SugarScanner({super.key});

  @override
  _SugarScannerState createState() => _SugarScannerState();
}

class _SugarScannerState extends State<SugarScanner> {
  String result = "Search or Scan a food";
  List<dynamic> suggestions = [];
  TextEditingController controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  // --- NEW HELPERS FOR BUSINESS LOGIC ---

  // Traffic Light System: Green (Low), Orange (Moderate), Red (High)
  Color getSugarColor(dynamic sugarValue) {
    double sugar = double.tryParse(sugarValue.toString()) ?? 0.0;
    if (sugar <= 5) return Colors.green.shade100;
    if (sugar <= 15) return Colors.orange.shade100;
    return Colors.red.shade100;
  }

  // Visualization: 1 teaspoon/cube of sugar is roughly 4 grams
  String getCubes(dynamic sugarValue) {
    double sugar = double.tryParse(sugarValue.toString()) ?? 0.0;
    double cubes = sugar / 4.0;
    return cubes.toStringAsFixed(1);
  }

  // --- FUNCTION 1: TEXT SEARCH ---
  Future<void> checkSugar(String food) async {
    if (food.isEmpty) return;
    setState(() {
      result = "Searching...";
      suggestions = [];
    });

    final url = Uri.parse('http://localhost:8000/analyze/$food');

    try {
      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        setState(() {
          result = "${data['product_name']}\nSugar: ${data['sugar_100g']}g\n(~${getCubes(data['sugar_100g'])} cubes)";
        });
      } else {
        setState(() => result = "Food not found.");
      }
    } catch (e) {
      setState(() => result = "Connection error. Is main.py running?");
    }
  }

  // --- FUNCTION 2: IMAGE SCAN ---
  Future<void> pickAndUploadImage() async {
    final XFile? image = await _picker.pickImage(source: ImageSource.gallery);

    if (image != null) {
      setState(() {
        result = "Analyzing image...";
        suggestions = [];
      });

      var request = http.MultipartRequest('POST', Uri.parse('http://localhost:8000/upload'));

      request.files.add(http.MultipartFile.fromBytes(
        'file',
        await image.readAsBytes(),
        filename: image.name,
      ));

      try {
        var streamedResponse = await request.send();
        var response = await http.Response.fromStream(streamedResponse);

        if (response.statusCode == 200) {
          var data = jsonDecode(response.body);
          setState(() {
            suggestions = data['suggestions'];
            result = "We found 3 possibilities:";
          });
        } else {
          setState(() => result = "Server error during scan.");
        }
      } catch (e) {
        setState(() => result = "Error uploading image: $e");
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Sugar Lens AI")),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: "Enter Food Name",
                suffixIcon: IconButton(
                  icon: const Icon(Icons.clear),
                  onPressed: () => controller.clear(),
                ),
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () => checkSugar(controller.text),
                    icon: const Icon(Icons.search),
                    label: const Text("Search"),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: pickAndUploadImage,
                    icon: const Icon(Icons.camera_alt),
                    label: const Text("Scan"),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 30),
            
            // Result Text Area
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(result, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold), textAlign: TextAlign.center),
            ),

            const SizedBox(height: 20),

           // --- SUGGESTIONS LIST (Updated for 2025 AI Backend) ---
          if (suggestions.isNotEmpty)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(left: 8.0, bottom: 8.0, top: 16.0),
                  child: Text(
                    "AI IDENTIFIED POSSIBILITIES:", 
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)
                  ),
                ),
                ...suggestions.map((sug) {
                  return Card(
                    elevation: 3,
                    color: getSugarColor(sug['sugar']),
                    margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                    child: ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Colors.white,
                        // Show a "Sparkle" icon to indicate it was generated by AI
                        child: Icon(Icons.auto_awesome, size: 20, color: Colors.blue),
                      ),
                      title: Text(
                        sug['label'].toString().toUpperCase(), 
                        style: const TextStyle(fontWeight: FontWeight.bold)
                      ),
                      subtitle: Text("Sugar Content: ${sug['sugar']}g"),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        setState(() {
                          // Set the final result and clear suggestions
                          result = "Item: ${sug['label']}\nSugar: ${sug['sugar']}g\n(~${getCubes(sug['sugar'])} cubes)";
                          suggestions = []; 
                        });
                      },
                    ),
                  );
                }).toList(),
              ],
            ),
          ],
        ),
      ),
    );
  }
}