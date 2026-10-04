import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:frontend/features/admin/services/admin_service.dart';
import 'package:frontend/core/api_client.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';

class QRScannerScreen extends StatefulWidget {
  final String eventId;

  const QRScannerScreen({super.key, required this.eventId});

  @override
  State<QRScannerScreen> createState() => _QRScannerScreenState();
}

class _QRScannerScreenState extends State<QRScannerScreen> {
  final MobileScannerController _scannerController = MobileScannerController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _scannerController.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;
    
    final List<Barcode> barcodes = capture.barcodes;
    for (final barcode in barcodes) {
      if (barcode.rawValue != null) {
        await _processCheckin(barcode.rawValue!);
        break;
      }
    }
  }

  Future<void> _processCheckin(String ticketPayload) async {
    if (_isProcessing) return;
    setState(() {
      _isProcessing = true;
    });

    try {
      final apiClient = ApiClient();
      final adminService = AdminService(apiClient.dio);
      await adminService.checkinAttendee(widget.eventId, ticketPayload);
      
      if (!mounted) return;
      AnimatedToast.show(context, message: 'Check-in successful!', isError: false);
      // Let the user scan another ticket or close manually
      Future.delayed(const Duration(seconds: 2), () {
        if (mounted) {
          setState(() {
            _isProcessing = false;
          });
        }
      });
    } catch (e) {
      if (!mounted) return;
      String errorMsg = 'Failed to check-in';
      if (e is ApiException) {
        errorMsg = e.message;
      }
      AnimatedToast.show(context, message: errorMsg, isError: true);
      setState(() {
        _isProcessing = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Ticket'),
        actions: [
          IconButton(
            icon: const Icon(Icons.flash_on),
            onPressed: () => _scannerController.toggleTorch(),
          ),
          IconButton(
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _scannerController.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerController,
            onDetect: _onDetect,
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: CircularProgressIndicator(),
              ),
            ),
          Positioned(
            bottom: 30,
            left: 24,
            right: 24,
            child: Card(
              color: Colors.black87,
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Text(
                  'Scan the complete EventSphere QR ticket. Registration IDs alone are not accepted.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
