import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:go_router/go_router.dart';
import 'package:frontend/features/admin/providers/admin_provider.dart';
import 'package:frontend/features/events/models/event.dart';
import 'package:frontend/core/validators.dart';
import 'package:frontend/shared/widgets/animated_toast.dart';
import 'package:flutter/services.dart';

class EditEventScreen extends StatefulWidget {
  final Event event;

  const EditEventScreen({super.key, required this.event});

  @override
  State<EditEventScreen> createState() => _EditEventScreenState();
}

class _EditEventScreenState extends State<EditEventScreen> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  late TextEditingController _descController;
  late TextEditingController _categoryController;
  late TextEditingController _locationController;
  late TextEditingController _capacityController;
  
  late DateTime? _eventDate;
  late DateTime? _eventEndDate;
  late DateTime? _registrationDeadline;
  late bool _isPrivate;
  late bool _allowWaitlist;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.event.name);
    _descController = TextEditingController(text: widget.event.description);
    _categoryController = TextEditingController(text: widget.event.category);
    _locationController = TextEditingController(text: widget.event.location);
    _capacityController = TextEditingController(text: widget.event.capacity.toString());
    _eventDate = widget.event.eventDate;
    _eventEndDate = widget.event.eventEndDate ?? widget.event.eventDate.add(const Duration(hours: 1));
    _registrationDeadline = widget.event.registrationDeadline;
    _isPrivate = widget.event.isPrivate;
    _allowWaitlist = widget.event.allowWaitlist;
  }

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

    final success = await context.read<AdminProvider>().updateEvent(widget.event.id, data);
    
    if (!mounted) return;
    
    if (success) {
      context.pop();
    } else {
      final err = context.read<AdminProvider>().error ?? 'Failed to update event.';
      AnimatedToast.show(context, message: err, isError: true);
    }
  }

  Future<DateTime?> _pickDateTime(DateTime? current) async {
    final date = await showDatePicker(
      context: context,
      initialDate: current ?? DateTime.now(),
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
      appBar: AppBar(title: const Text('Edit Event')),
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
                      final value = await _pickDateTime(_eventEndDate);
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
                subtitle: const Text('Promote attendees in waitlist order when seats are released.'),
                value: _allowWaitlist,
                onChanged: (value) => setState(() => _allowWaitlist = value),
              ),
              const SizedBox(height: 32),
              ElevatedButton(
                onPressed: adminProvider.isLoading ? null : _submit,
                child: adminProvider.isLoading
                    ? const CircularProgressIndicator()
                    : const Text('SAVE CHANGES'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
