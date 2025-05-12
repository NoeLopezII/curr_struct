import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
// No http import needed here directly if all calls are in services
import 'package:http/http.dart' as http;
// No path_provider needed here directly
import 'package:path_provider/path_provider.dart';
import 'dart:async';
// No dart:io needed here directly
import 'dart:io';
// No dart:convert needed here directly
import 'dart:convert';
import 'services/ocr_service.dart';
import 'services/openai_service.dart';
import 'services/claude_service.dart';
import 'services/deepseek_service.dart';
import 'models/explanation.dart'; // Includes Explanation and Description
import 'utils/logger.dart';
// Config might not be needed directly if only used in services
import 'utils/config.dart';
import 'dart:core'; // Usually implicitly imported
import 'package:flutter/foundation.dart'; // Added for debugPrint

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'STEM Analyzer',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
      ),
      home: MainScreen(),
    );
  }
}

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  CameraController? _controller;
  String? _imagePath;
  String _extractedText = '';
  // Subject Classification State
  List<Explanation> _explanations = [];
  String _subjectResult = ''; // Renamed from _result for clarity
  bool _isAnalyzingSubject = false; // Renamed from _isProcessing

  // Teaching Feature State
  List<Description> _teachings = [];
  Description? _winningTeaching;
  bool _isGeneratingTeaching = false; // New state for teaching feature

  final Logger _logger = Logger();

  final List<String> semester_subjects = [
    'Algorithms Design and Analysis', 'Advanced Algorithms', 'Game Theory',
    'Calculus I (Differential)', 'Calculus II (Integral)', 'Vector Calculus',
    'Computer Organization and Assembly Language', 'Digital Logic Design', 'Embedded Systems Design',
    'Linear Algebra', 'Discrete Mathematics', 'Machine Learning', 'Cryptography',
    'General Physics', 'Rocket Science', 'Thermodynamics',
    'Probability', 'Statistical Inference', 'Accounting I',
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initializeCamera();
  }

// ========== NEW DEBUG PRINTING METHODS ==========
  void _printFullOCR() {
    debugPrint('[OCR FULL TEXT]', wrapWidth: 1024);
    debugPrint(_extractedText, wrapWidth: 1024);
  }

  void _printFullTeaching(String teaching) {
    debugPrint('[TEACHING FULL CONTENT]', wrapWidth: 1024);
    // Split into chunks if needed for very long texts
    for (var i = 0; i < teaching.length; i += 1000) {
      final end = (i + 1000).clamp(0, teaching.length);
      debugPrint(teaching.substring(i, end), wrapWidth: 1024);
    }
  }

  Future<void> _saveTeachingToFile(String text) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/teaching_${DateTime.now().millisecondsSinceEpoch}.txt');
      await file.writeAsString(text);
      debugPrint('[FILE] Teaching saved to: ${file.path}');
    } catch (e) {
      debugPrint('[FILE ERROR] $e');
    }
  }
  // ===============================================
  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();
      _controller = CameraController(cameras[0], ResolutionPreset.high); // Use high for better OCR maybe
      await _controller!.initialize();
      if (mounted) setState(() {});
    } catch (e) {
      _logger.addLog('Camera Error: $e');
      _showSnackBar('Failed to initialize camera.');
    }
  }

  // Function to show snackbar messages
  void _showSnackBar(String message) {
    if (!mounted) return; // Check if the widget is still in the tree
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }


  Future<void> _takePhotoAndAnalyzeSubject() async {
    // Prevent concurrent operations
    if (_isAnalyzingSubject || _isGeneratingTeaching || _controller == null || !_controller!.value.isInitialized) return;

    setState(() {
      _isAnalyzingSubject = true;
      _subjectResult = ''; // Clear previous results
      _extractedText = '';
      _explanations = [];
      _winningTeaching = null; // Clear previous teaching result too
      _logger.addLog('Starting analysis...');
    });

    try {
      final image = await _controller!.takePicture();
      _logger.addLog('Photo captured: ${image.path}');
      // No need to set _imagePath state unless displaying the photo itself
      // setState(() => _imagePath = image.path);

      final ocrText = await OCRService.extractText(image.path);
      debugPrint('[CAMERA] Photo path: ${image.path}');
      _printFullOCR(); // New: Print full OCR text to console


      if (!mounted) return; // Check after async gap

      if (ocrText.isEmpty) {
        _logger.addLog('OCR Error: No text extracted.');
        _showSnackBar('Could not extract text from the image.');
        setState(() => _isAnalyzingSubject = false );
        return;
      }

      setState(() => _extractedText = ocrText);
      _logger.addLog('OCR Extracted (first 100 chars): ${ocrText.substring(0, ocrText.length > 100 ? 100 : ocrText.length)}...');

      // Fetch explanations concurrently
      final results = await Future.wait([
        OpenAIService.getExplanation(ocrText, semester_subjects),
        ClaudeService.getExplanation(ocrText, semester_subjects),
        DeepSeekService.getExplanation(ocrText, semester_subjects),
      ]);
      if (!mounted) return; // Check after async gap

      _explanations = results;
      _logger.addLog('Received all subject explanations.');
      _logger.addLog('OpenAI: ${_explanations[0]}');
      _logger.addLog('Claude: ${_explanations[1]}');
      _logger.addLog('DeepSeek: ${_explanations[2]}');


      debugPrint('[SUBJECT] All explanations received:');
      for (final e in _explanations) {
        debugPrint(' - ${e.subject}');
        debugPrint('   Reasoning: ${e.reasoning}', wrapWidth: 1024);
        print('**********************************');
      }


      // Check for consensus
      final consensus = await DeepSeekService.checkConsensus(
          _explanations.map((e) => e.subject).toList()
      ); // Assuming DeepSeek still hosts consensus logic
      if (!mounted) return; // Check after async gap

      if (consensus['agreed']) {



        setState(() => _subjectResult = consensus['subject']);
        _logger.addLog('Subject Consensus reached: ${consensus['subject']}');
      } else {
        _logger.addLog('No subject consensus. Starting scoring process...');
        await _scoreSubjectExplanations(ocrText);
        if (!mounted) return; // Check after async gap

        // Determine winner using DeepSeek (or another logic)
        final winnerSubject = await DeepSeekService.determineWinner(_explanations);
        if (!mounted) return; // Check after async gap

        setState(() => _subjectResult = winnerSubject.isNotEmpty ? winnerSubject : 'Undetermined Subject');
        _logger.addLog('Subject scoring complete. Winner: $_subjectResult');
      }
    } catch (e, stackTrace) {
      _logger.addLog('Subject Analysis Error: $e');
      _logger.addLog('Stack Trace: $stackTrace'); // Log stack trace for debugging
      _showSnackBar('An error occurred during analysis.');
      if (mounted) {
        setState(() => _subjectResult = 'Error during analysis');
      }
    } finally {
      if (mounted) {
        setState(() => _isAnalyzingSubject = false);
      }
    }
  }

  // Renamed scoring function for clarity
  Future<void> _scoreSubjectExplanations(String ocrText) async {
    for (int i = 0; i < _explanations.length; i++) {
      try {
        _logger.addLog('Scoring ${_explanations[i].subject} explanation...');
        final scores = await Future.wait([
          OpenAIService.scoreExplanation(ocrText, _explanations[i]),
          ClaudeService.scoreExplanation(ocrText, _explanations[i]),
          DeepSeekService.scoreExplanation(ocrText, _explanations[i]),
        ]);
        if (!mounted) return; // Check after async gap

        _explanations[i].scores = scores;
        _logger.addLog('${_explanations[i].subject} scores: $scores');
      } catch(e) {
        _logger.addLog('Error scoring explanation ${i+1}: $e');
        // Assign default scores or handle error appropriately
        _explanations[i].scores = [1, 1, 1]; // Example: assign lowest scores on error
      }
    }
  }

  // --- NEW FUNCTION FOR TEACHING FEATURE ---
  Future<void> _generateAndScoreTeaching() async {
    if (_extractedText.isEmpty || _isAnalyzingSubject || _isGeneratingTeaching) {
      _showSnackBar('Please analyze an image first, or wait for the current process to finish.');
      return;
    }

    setState(() {
      _isGeneratingTeaching = true;
      _winningTeaching = null; // Clear previous teaching
      _logger.addLog('\n--- Starting Teaching Generation ---');
    });

    try {
      // 1. Generate teachings concurrently
      _logger.addLog('Generating teachings from LLMs...');
      final teachingFutures = [
        OpenAIService.generateTeaching(_extractedText),
        DeepSeekService.generateTeaching(_extractedText),
        ClaudeService.generateTeaching(_extractedText),
      ];
      _teachings = await Future.wait(teachingFutures);


      debugPrint('[TEACHING] All teachings generated:');
      for (final t in _teachings) {
        debugPrint('--- ${t.modelName} ---');
        _printFullTeaching(t.teaching); // New: Full print with chunking
      }


      if (!mounted) return; // Check after async gap

      // Log generated teachings (as requested)
      _logger.addLog('--- Generated Teachings ---');
      for (var teaching in _teachings) {
        _logger.addLog('${teaching.modelName}: ${teaching.teaching}');
      }
      _logger.addLog('---------------------------');


      // 2. Score teachings - Each LLM scores the *other* two
      _logger.addLog('Starting teaching scoring process...');
      List<Future<void>> scoringTasks = [];

      for (int i = 0; i < _teachings.length; i++) {
        // For teaching 'i', get scores from LLMs 'j' and 'k'
        List<Future<int>> currentScoresFutures = [];
        Description teachingToScore = _teachings[i];

        currentScoresFutures.add(OpenAIService.scoreTeaching(_extractedText, teachingToScore));
        currentScoresFutures.add(DeepSeekService.scoreTeaching(_extractedText, teachingToScore));
        currentScoresFutures.add(ClaudeService.scoreTeaching(_extractedText, teachingToScore));

        // Add a task that waits for scores and assigns them
        scoringTasks.add(
            Future.wait(currentScoresFutures).then((scores) {
              if (mounted) { // Check if widget is still active before modifying state indirectly
                _teachings[i].scores = scores;
                _logger.addLog('${_teachings[i].modelName}\'s teaching scored by others: $scores');
              }
            }).catchError((e) {
              _logger.addLog('Error scoring teaching from ${_teachings[i].modelName}: $e');
              if (mounted) {
                _teachings[i].scores = [1, 1, 1]; // Assign default low scores on error
              }
            })
        );
      }///////////////////////////////////////////////////////////////////////

      // Wait for all scoring tasks to complete
      await Future.wait(scoringTasks);
      if (!mounted) return; // Check after async gap

      // 3. Determine the winner
      _logger.addLog('Determining winning teaching...');
      Description? bestTeaching;
      double highestAverageScore = -1.0;

      for (var teaching in _teachings) {
        _logger.addLog('${teaching.modelName} Teaching Average Score: ${teaching.averageScore.toStringAsFixed(2)}');
        if (teaching.averageScore > highestAverageScore) {
          highestAverageScore = teaching.averageScore;
          bestTeaching = teaching;
        }
      }

      if (bestTeaching != null) {
        /////////////////////
        debugPrint('[TEACHING WINNER] ${bestTeaching.modelName} (Score: ${bestTeaching.averageScore})');
        _printFullTeaching(bestTeaching.teaching);
        await _saveTeachingToFile(bestTeaching.teaching); // New: Save to file
        ///////////////////////
        _logger.addLog('Winning Teaching by: ${bestTeaching.modelName} (Score: ${bestTeaching.averageScore.toStringAsFixed(2)})');
        setState(() => _winningTeaching = bestTeaching);
      } else {
        _logger.addLog('Could not determine a winning teaching.');
        _showSnackBar('Could not determine the best teaching explanation.');
      }


    } catch (e, stackTrace) {
      _logger.addLog('Teaching Generation/Scoring Error: $e');
      _logger.addLog('Stack Trace: $stackTrace');
      _showSnackBar('An error occurred while generating the teaching.');
      if (mounted) {
        setState(() {
          // Optionally set winningTeaching to an error message Description
          _winningTeaching = Description(modelName: 'Error', teaching: 'Failed to generate/score teaching.');
        });
      }
    } finally {
      if (mounted) {
        setState(() => _isGeneratingTeaching = false);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('STEM Analyzer'),
        actions: [
          IconButton(
              icon: Icon(Icons.info_outline),
              onPressed: () {
                // Show info dialog or navigate to info screen
                showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text('How to Use'),
                    content: SingleChildScrollView( // Make dialog scrollable if content is long
                      child: Text(
                          '1. Point the camera at STEM-related text (equations, code, definitions).\n'
                              '2. Tap "Capture & Analyze Subject" to identify the subject.\n'
                              '3. If text is extracted, tap "Teach Me About This" to get an explanation of the extracted text content.\n\n'
                              'Logs below show the process.'
                      ),
                    ),
                    actions: [TextButton(onPressed: () => Navigator.pop(context), child: Text('OK'))],
                  ),
                );
              })
        ],
      ),
      body: Column(
        children: [
          // Camera Preview
          Expanded(
            flex: 3, // Adjusted flex for better balance
            child: (_controller != null && _controller!.value.isInitialized)
                ? CameraPreview(_controller!)
                : Container( // Use a container for background color and alignment
              color: Colors.grey[300],
              child: Center(child: Text('Initializing Camera...')),
            ),
          ),

          // Buttons Row
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 8.0),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                // Analyze Subject Button
                ElevatedButton.icon(
                  icon: Icon(Icons.camera_alt),
                  label: Text('Capture & Analyze Subject'),
                  onPressed: (_isAnalyzingSubject || _isGeneratingTeaching) ? null : _takePhotoAndAnalyzeSubject,
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
                // Teach Me Button
                ElevatedButton.icon(
                  icon: Icon(Icons.school),
                  label: Text('Teach Me About This'),
                  // Enable only if subject analysis is done, text exists, and not already processing
                  onPressed: (_extractedText.isNotEmpty && !_isAnalyzingSubject && !_isGeneratingTeaching)
                      ? _generateAndScoreTeaching
                      : null,
                  style: ElevatedButton.styleFrom(padding: EdgeInsets.symmetric(horizontal: 16, vertical: 12)),
                ),
              ],
            ),
          ),
          // Loading Indicators Row (Optional but good UX)
          if (_isAnalyzingSubject || _isGeneratingTeaching)
            Padding(
              padding: const EdgeInsets.only(bottom: 8.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(width: 10),
                  Text(_isAnalyzingSubject ? 'Analyzing Subject...' : 'Generating Teaching...'),
                ],
              ),
            ),


          // Results and Logs Area
          Expanded(
            flex: 4, // Adjusted flex
            child: Container(
              width: double.infinity, // Ensure it takes full width
              padding: EdgeInsets.all(12.0),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: Colors.blueGrey.shade100)),
                color: Colors.grey[50], // Slightly different background
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Subject Result
                  Text('Subject: $_subjectResult',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.blue[800])),
                  SizedBox(height: 8),

                  // Winning Teaching Display Area
                  if (_winningTeaching != null) ...[ // Use collection-if for cleaner conditional UI
                    Text('Explanation:', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                    SizedBox(height: 4),
                    Expanded( // Allow teaching text to take remaining space in this section
                      child: Container(
                        padding: EdgeInsets.all(8.0),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          border: Border.all(color: Colors.grey.shade300),
                          borderRadius: BorderRadius.circular(4.0),
                        ),
                        // Use SingleChildScrollView to prevent overflow
                        child: SingleChildScrollView(
                          child: Text(
                            _winningTeaching!.teaching,
                            style: TextStyle(fontSize: 14, height: 1.4), // Added line height
                          ),
                        ),
                      ),
                    ),
                    SizedBox(height: 8), // Space before logs
                  ] else if (_isGeneratingTeaching) ... [
                    // Placeholder while loading teaching
                    Center(child: Text('Generating explanation...')),
                    SizedBox(height: 8),
                  ],

                  // Log Area (only takes space if teaching is not displayed or is loading)
                  if (_winningTeaching == null && !_isGeneratingTeaching)
                    Divider(), // Show divider only when logs are the main content below subject

                  // Flexible makes the ListView take available space *within its parent Column*
                  // If _winningTeaching is displayed, Logs area shrinks. If not, it expands more.
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (_logger.logs.isNotEmpty) // Only show 'Logs' title if there are logs
                          Padding(
                            padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                            child: Text('Logs:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey[600])),
                          ),
                        Expanded( // Make ListView scrollable within its Flexible parent
                          child: ListView.builder(
                            itemCount: _logger.logs.length,
                            reverse: true, // Show newest logs first
                            itemBuilder: (ctx, i) => Padding(
                              padding: EdgeInsets.symmetric(vertical: 1.0),
                              child: Text('• ${_logger.logs[_logger.logs.length - 1 - i]}', // Access logs in reverse
                                  style: TextStyle(fontSize: 10, color: Colors.grey[700])),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose(); // Dispose camera controller
    //_logger.dispose(); // If your logger needs disposal
    super.dispose();
  }

  // Optional: Handle app lifecycle changes (pause/resume camera)
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final CameraController? cameraController = _controller;

    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }

    if (state == AppLifecycleState.inactive) {
      cameraController.dispose(); // Dispose on inactive
    } else if (state == AppLifecycleState.resumed) {
      _initializeCamera(); // Re-initialize on resume
    }
  }
}