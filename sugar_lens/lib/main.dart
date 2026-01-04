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
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
      ),
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
  String productName = "Sugar Lens AI";
  String sugarGrams = "0.0";
  String cubesCount = "0";
  bool isLoading = false;
  List<dynamic> suggestions = [];
  TextEditingController controller = TextEditingController();
  final ImagePicker _picker = ImagePicker();

  Color getSugarColor(dynamic val) {
    double s = double.tryParse(val.toString()) ?? 0.0;
    if (s <= 5) return Colors.green;
    if (s <= 15) return Colors.orange;
    return Colors.red;
  }

  // UPDATED: Now handles the 'source' from our Hybrid Backend
  Future<void> checkSugar(String food) async {
    if (food.isEmpty) return;
    setState(() => isLoading = true);

    try {
      final response = await http.get(Uri.parse('http://10.0.0.3:8000/analyze/$food'));
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        updateUI(
          data['product_name'], 
          data['sugar_100g'], 
          data['source'] ?? 'database'
        );
      }
    } catch (e) {
      showError("Connection Failed");
    } finally {
      setState(() => isLoading = false);
    }
  }

  // UPDATED: Added a visual sparkle ✨ if Gemini provided the data
  void updateUI(String name, dynamic sugar, String source) {
    double s = double.tryParse(sugar.toString()) ?? 0.0;
    setState(() {
      productName = source == "gemini_ai" ? "$name ✨" : name;
      sugarGrams = s.toStringAsFixed(1);
      cubesCount = (s / 4).toStringAsFixed(1);
      suggestions = [];
    });
  }

  void showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  void _showPicker(context) {
    showModalBottomSheet(
      context: context,
      builder: (bc) => SafeArea(
        child: Wrap(
          children: [
            ListTile(leading: const Icon(Icons.photo_library), title: const Text('Gallery'), onTap: () => _handleImage(ImageSource.gallery)),
            ListTile(leading: const Icon(Icons.camera_alt), title: const Text('Camera'), onTap: () => _handleImage(ImageSource.camera)),
          ],
        ),
      ),
    );
  }

  Future<void> _handleImage(ImageSource source) async {
    Navigator.pop(context);
    final XFile? image = await _picker.pickImage(source: source);
    if (image == null) return;
    setState(() => isLoading = true);
    
    var request = http.MultipartRequest('POST', Uri.parse('http://10.0.0.3:8000/upload'));
    request.files.add(http.MultipartFile.fromBytes('file', await image.readAsBytes(), filename: image.name));
    
    try {
      var res = await request.send();
      var data = jsonDecode(await res.stream.bytesToString());
      setState(() {
        suggestions = data['suggestions'];
        productName = "Identify Food";
      });
    } catch (e) {
      showError("Upload Error");
    } finally {
      setState(() => isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          const SliverAppBar.large(
            title: Text("Sugar Lens", style: TextStyle(fontWeight: FontWeight.bold)),
            centerTitle: true,
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  Container(
                    decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(30), boxShadow: [const BoxShadow(color: Colors.black12, blurRadius: 10)]),
                    child: TextField(
                      controller: controller,
                      onSubmitted: checkSugar,
                      decoration: InputDecoration(
                        hintText: "Search food item...",
                        prefixIcon: const Icon(Icons.search),
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(vertical: 15),
                        suffixIcon: IconButton(icon: const Icon(Icons.camera_alt), onPressed: () => _showPicker(context)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 30),

                  if (isLoading) const CircularProgressIndicator(),

                  if (!isLoading && suggestions.isEmpty)
                    Container(
                      padding: const EdgeInsets.all(25),
                      decoration: BoxDecoration(
                        gradient: LinearGradient(colors: [getSugarColor(sugarGrams).withOpacity(0.8), getSugarColor(sugarGrams)]),
                        borderRadius: BorderRadius.circular(30),
                        boxShadow: [BoxShadow(color: getSugarColor(sugarGrams).withOpacity(0.3), blurRadius: 20, offset: const Offset(0, 10))],
                      ),
                      child: Column(
                        children: [
                          Text(productName.toUpperCase(), 
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
                          const SizedBox(height: 15),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(sugarGrams, style: const TextStyle(color: Colors.white, fontSize: 64, fontWeight: FontWeight.w900)),
                              const Text(" g", style: TextStyle(color: Colors.white, fontSize: 24)),
                            ],
                          ),
                          const Text("Sugar per 100g", style: TextStyle(color: Colors.white70)),
                          const Divider(height: 40, color: Colors.white24),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                            children: [
                              _infoIcon(Icons.bubble_chart, "$cubesCount Cubes"),
                              _infoIcon(Icons.analytics_outlined, sugarGrams == "0.0" ? "Clear" : "Verified"),
                            ],
                          )
                        ],
                      ),
                    ),

                  if (suggestions.isNotEmpty)
                    ...suggestions.map((sug) => Card(
                      margin: const EdgeInsets.only(bottom: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                      child: ListTile(
                        leading: CircleAvatar(backgroundColor: getSugarColor(sug['sugar']).withOpacity(0.2), child: Icon(Icons.fastfood, color: getSugarColor(sug['sugar']))),
                        title: Text(sug['label']),
                        subtitle: Text("${sug['sugar']}g Sugar"),
                        // Updated to pass the AI confidence as the source
                        onTap: () => updateUI(sug['label'], sug['sugar'], "gemini_ai"),
                      ),
                    )).toList(),
                ],
              ),
            ),
          )
        ],
      ),
    );
  }

  Widget _infoIcon(IconData icon, String text) {
    return Column(children: [Icon(icon, color: Colors.white, size: 30), const SizedBox(height: 5), Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold))]);
  }
}