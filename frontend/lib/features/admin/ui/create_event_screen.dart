import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/admin/providers/admin_provider.dart';
import 'package:frontend/core/validators.dart';
import 'package:flutter/services.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';

class CreateEventScreen extends StatefulWidget {
  const CreateEventScreen({super.key});

  @override
  State<CreateEventScreen> createState() => _CreateEventScreenState();
}

class _CreateEventScreenState extends State<CreateEventScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _descController = TextEditingController();
  final _categoryController = TextEditingController(text: 'conference');
  final _locationController = TextEditingController();
  final _capacityController = TextEditingController();
  
  DateTime? _eventDate;
  DateTime? _eventEndDate;
  DateTime? _registrationDeadline;
  bool _isPrivate = false;
  bool _allowWaitlist = true;

  @override
  void dispose() {
    _nameController.dispose();
    _descController.dispose();
    _categoryController.dispose();
    _locationController.dispose();
    _capacityController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate() || _eventDate == null || _eventEndDate == null || _registrationDeadline == null) {
      AnimatedToast.show(context, message: 'Please fill all fields and select event times.', isError: true);
      return;
    }

    if (_registrationDeadline!.isAfter(_eventDate!)) {
      AnimatedToast.show(context, message: 'Registration deadline cannot be after the event date.', isError: true);
      return;
    }
    if (!_eventEndDate!.isAfter(_eventDate!)) {
      AnimatedToast.show(context, message: 'Event end time must be after the start time.', isError: true);
      return;
    }

    final data = {
      "name": _nameController.text.trim(),
      "description": _descController.text.trim(),
      "category": _categoryController.text.trim(),
      "location": _locationController.text.trim(),
      "eventDate": _eventDate!.toUtc().toIso8601String(),
      "eventEndDate": _eventEndDate!.toUtc().toIso8601String(),
      "registrationDeadline": _registrationDeadline!.toUtc().toIso8601String(),
      "capacity": int.tryParse(_capacityController.text.trim()) ?? 0,
      "isPrivate": _isPrivate,
      "allowWaitlist": _allowWaitlist,
    };

    final success = await context.read<AdminProvider>().createEvent(data);
    
    if (!mounted) return;
    
    if (success) {
      context.pop();
    } else {
      final err = context.read<AdminProvider>().error ?? 'Failed to create event.';
      AnimatedToast.show(context, message: err, isError: true);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now().add(const Duration(days: 1)),
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return null;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(current ?? DateTime.now()),
    );
    if (time == null) return null;
    return DateTime(date.year, date.month, date.day, time.hour, time.minute);
  }

  String _dateLabel(String label, DateTime? value) => value == null
      ? label
      : '$label: ${value.day}/${value.month}/${value.year} ${TimeOfDay.fromDateTime(value).format(context)}';

  @override
  Widget build(BuildContext context) {
    final adminProvider = context.watch<AdminProvider>();

    return Scaffold(
      appBar: AppBar(title: const Text('Create Event')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Event Name'),
                validator: Validators.requiredField,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _descController,
                decoration: const InputDecoration(labelText: 'Description'),
                maxLines: 3,
                validator: Validators.requiredField,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _categoryController,
                decoration: const InputDecoration(labelText: 'Category'),
                validator: Validators.requiredField,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _locationController,
                decoration: const InputDecoration(labelText: 'Location'),
                validator: Validators.requiredField,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _capacityController,
                decoration: const InputDecoration(labelText: 'Capacity'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                validator: Validators.positiveInteger,
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton(
                    onPressed: () async {
                      final value = await _pickDateTime(_eventDate);
                      if (value != null) setState(() => _eventDate = value);
                    },
                    child: Text(_dateLabel('Start', _eventDate)),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final value = await _pickDateTime(_eventEndDate ?? _eventDate?.add(const Duration(hours: 1)));
                      if (value != null) setState(() => _eventEndDate = value);
                    },
                    child: Text(_dateLabel('End', _eventEndDate)),
                  ),
                  OutlinedButton(
                    onPressed: () async {
                      final value = await _pickDateTime(_registrationDeadline);
                      if (value != null) setState(() => _registrationDeadline = value);
                    },
                    child: Text(_dateLabel('Deadline', _registrationDeadline)),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              SwitchListTile(
                title: const Text('Private Event (Invite Only)'),
                subtitle: const Text('Private events do not appear on the public discover page.'),
                value: _isPrivate,
                onChanged: (val) => setState(() => _isPrivate = val),
              ),
              SwitchListTile(
                title: const Text('Enable waitlist'),
                subtitle: const Text('Automatically promotes the earliest eligible attendee when a seat is released.'),
                value: _allowWaitlist,
                onChanged: (value) => setState(() => _allowWaitlist = value),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: adminProvider.isLoading ? null : _submit,
                child: adminProvider.isLoading
                    ? const CircularProgressIndicator()
                    : const Text('CREATE EVENT'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
