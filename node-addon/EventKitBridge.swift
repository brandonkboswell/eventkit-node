//
//  EventKitBridge.swift
//  eventkit-addon
//
//  Created by Deniz Acay on 8.03.2025.
//

import EventKit
import Foundation

@objc public class EventKitBridge: NSObject {
    private let eventStore = EKEventStore()

    @objc public func requestCalendarAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToEvents { granted, error in
                completion(granted)
            }
        } else {
            // Fall back to the older API for macOS 10.15-13.x
            eventStore.requestAccess(to: .event) { granted, error in
                completion(granted)
            }
        }
    }
    
    @objc public func requestWriteOnlyAccessToEvents(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestWriteOnlyAccessToEvents { granted, error in
                completion(granted)
            }
        } else {
            // Fall back to the older API for macOS 10.15-13.x
            // Write-only access is not available in older versions, so we use regular access
            eventStore.requestAccess(to: .event) { granted, error in
                completion(granted)
            }
        }
    }
    
    @objc public func requestRemindersAccess(completion: @escaping (Bool) -> Void) {
        if #available(macOS 14.0, *) {
            eventStore.requestFullAccessToReminders { granted, error in
                completion(granted)
            }
        } else {
            // Fall back to the older API for macOS 10.15-13.x
            eventStore.requestAccess(to: .reminder) { granted, error in
                completion(granted)
            }
        }
    }

    // Calendar object for JSON serialization
    @objc public class Calendar: NSObject {
        @objc public let id: String
        @objc public let title: String
        @objc public let allowsContentModifications: Bool
        @objc public let type: String
        @objc public let colorHex: String
        @objc public let colorComponents: String
        @objc public let colorSpace: String
        @objc public let source: String
        @objc public let allowedEntityTypes: [String]
        
        init(from ekCalendar: EKCalendar) {
            self.id = ekCalendar.calendarIdentifier
            self.title = ekCalendar.title
            self.allowsContentModifications = ekCalendar.allowsContentModifications
            self.type = ekCalendar.type == .local ? "local" : 
                        ekCalendar.type == .calDAV ? "calDAV" : 
                        ekCalendar.type == .exchange ? "exchange" : 
                        ekCalendar.type == .subscription ? "subscription" : 
                        ekCalendar.type == .birthday ? "birthday" : "unknown"
            
            // Determine allowed entity types
            var entityTypes: [String] = []
            if ekCalendar.allowedEntityTypes.contains(.event) {
                entityTypes.append("event")
            }
            if ekCalendar.allowedEntityTypes.contains(.reminder) {
                entityTypes.append("reminder")
            }
            self.allowedEntityTypes = entityTypes
            
            // Store color space information
            if let colorSpace = ekCalendar.cgColor.colorSpace {
                switch colorSpace.model {
                case .rgb: self.colorSpace = "rgb"
                case .monochrome: self.colorSpace = "monochrome"
                case .cmyk: self.colorSpace = "cmyk"
                case .lab: self.colorSpace = "lab"
                case .deviceN: self.colorSpace = "deviceN"
                case .indexed: self.colorSpace = "indexed"
                case .pattern: self.colorSpace = "pattern"
                case .XYZ: self.colorSpace = "xyz"
                case .unknown: self.colorSpace = "unknown"
                @unknown default: self.colorSpace = "unknown"
                }
            } else {
                self.colorSpace = "unknown"
            }
            
            // Store raw color components as a string
            if let components = ekCalendar.cgColor.components {
                let componentStrings = components.map { String(format: "%.6f", $0) }
                self.colorComponents = componentStrings.joined(separator: ",")
            } else {
                self.colorComponents = ""
            }
            
            // Convert to hex for convenience (RGB approximation)
            if let components = ekCalendar.cgColor.components, ekCalendar.cgColor.numberOfComponents >= 4 {
                let r = Int(components[0] * 255.0)
                let g = Int(components[1] * 255.0)
                let b = Int(components[2] * 255.0)
                let a = Int(components[3] * 255.0)
                self.colorHex = String(format: "#%02X%02X%02X%02X", r, g, b, a)
            } else if let components = ekCalendar.cgColor.components, ekCalendar.cgColor.numberOfComponents >= 1 {
                // Handle grayscale
                let gray = Int(components[0] * 255.0)
                let a = ekCalendar.cgColor.numberOfComponents >= 2 ? Int(components[1] * 255.0) : 255
                self.colorHex = String(format: "#%02X%02X%02X%02X", gray, gray, gray, a)
            } else {
                self.colorHex = "#00000000" // Transparent black as fallback
            }
            
            self.source = ekCalendar.source.title
        }
    }

    // Source object for JSON serialization
    @objc public class Source: NSObject {
        @objc public let id: String
        @objc public let title: String
        @objc public let sourceType: String
        
        init(ekSource: EKSource) {
            self.id = ekSource.sourceIdentifier
            self.title = ekSource.title
            
            // Convert EKSourceType to string
            switch ekSource.sourceType {
            case .local:
                self.sourceType = "local"
            case .exchange:
                self.sourceType = "exchange"
            case .calDAV:
                self.sourceType = "calDAV"
            case .mobileMe:
                self.sourceType = "mobileMe"
            case .subscribed:
                self.sourceType = "subscribed"
            case .birthdays:
                self.sourceType = "birthdays"
            @unknown default:
                self.sourceType = "unknown"
            }
            
            super.init()
        }
    }

    @objc public func getCalendars(entityTypeString: String = "event") -> [Calendar] {
        let entityType: EKEntityType = entityTypeString.lowercased() == "reminder" ? .reminder : .event
        let ekCalendars = eventStore.calendars(for: entityType)
        return ekCalendars.map { Calendar(from: $0) }
    }
    
    @objc public func getCalendar(identifier: String) -> Calendar? {
        guard let ekCalendar = eventStore.calendar(withIdentifier: identifier) else {
            return nil
        }
        return Calendar(from: ekCalendar)
    }
    
    @objc public func saveCalendar(calendarData: NSDictionary, commit: Bool) -> [String: Any]? {
        // Get the calendar ID if it exists (for updating an existing calendar)
        let calendarId = calendarData["id"] as? String
        
        // Get the entity type (default to event if not specified)
        let entityTypeString = (calendarData["entityType"] as? String)?.lowercased() ?? "event"
        let entityType: EKEntityType = entityTypeString == "reminder" ? .reminder : .event
        
        // Create a new calendar or get an existing one
        let calendar: EKCalendar
        if let calendarId = calendarId, let existingCalendar = eventStore.calendar(withIdentifier: calendarId) {
            // Update existing calendar
            calendar = existingCalendar
            
            // Check if the calendar supports the specified entity type
            if !existingCalendar.allowedEntityTypes.contains(entityType == .event ? .event : .reminder) {
                return ["success": false, "error": "This calendar does not support the specified entity type"]
            }
        } else {
            // Create a new calendar
            calendar = EKCalendar(for: entityType, eventStore: eventStore)
            
            // For new calendars, we need to set a source
            if let sourceId = calendarData["sourceId"] as? String, 
               let source = eventStore.source(withIdentifier: sourceId) {
                calendar.source = source
            } else {
                // No valid source ID provided
                return ["success": false, "error": "A valid sourceId is required for new calendars"]
            }
        }
        
        // Update calendar properties
        if let title = calendarData["title"] as? String {
            calendar.title = title
        }
        
        // Update color if provided
        if let colorHex = calendarData["colorHex"] as? String, colorHex.hasPrefix("#") {
            let hexString = colorHex.dropFirst() // Remove the # prefix
            
            // Parse the hex color
            var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 1.0
            
            if hexString.count == 8 {
                // #RRGGBBAA format
                let scanner = Scanner(string: String(hexString))
                var hexValue: UInt64 = 0
                
                if scanner.scanHexInt64(&hexValue) {
                    r = CGFloat((hexValue & 0xFF000000) >> 24) / 255.0
                    g = CGFloat((hexValue & 0x00FF0000) >> 16) / 255.0
                    b = CGFloat((hexValue & 0x0000FF00) >> 8) / 255.0
                    a = CGFloat(hexValue & 0x000000FF) / 255.0
                }
            } else if hexString.count == 6 {
                // #RRGGBB format
                let scanner = Scanner(string: String(hexString))
                var hexValue: UInt64 = 0
                
                if scanner.scanHexInt64(&hexValue) {
                    r = CGFloat((hexValue & 0xFF0000) >> 16) / 255.0
                    g = CGFloat((hexValue & 0x00FF00) >> 8) / 255.0
                    b = CGFloat(hexValue & 0x0000FF) / 255.0
                }
            }
            
            // Create a CGColor from the components
            if let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) {
                let components: [CGFloat] = [r, g, b, a]
                if let cgColor = CGColor(colorSpace: colorSpace, components: components) {
                    calendar.cgColor = cgColor
                }
            }
        }
        
        // Save the calendar
        do {
            try eventStore.saveCalendar(calendar, commit: commit)
            return ["success": true, "id": calendar.calendarIdentifier]
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }

    @objc public func getEvents(startDate: Date, endDate: Date) -> [String] {
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
        let events = eventStore.events(matching: predicate)
        return events.map { $0.title ?? "Untitled Event" }
    }

    @objc public func getSources() -> NSArray {
        let sources = eventStore.sources
        let result = NSMutableArray()
        
        for source in sources {
            result.add(Source(ekSource: source))
        }
        
        return result
    }
    
    @objc public func getDelegateSources() -> NSArray {
        if #available(macOS 12.0, *) {
            let sources = eventStore.delegateSources
            let result = NSMutableArray()
            
            for source in sources {
                result.add(Source(ekSource: source))
            }
            
            return result
        } else {
            // For older macOS versions, return an empty array
            return NSArray()
        }
    }
    
    @objc public func getSource(sourceId: String) -> Source? {
        if let source = eventStore.source(withIdentifier: sourceId) {
            return Source(ekSource: source)
        }
        return nil
    }

    @objc public func commit(completion: @escaping (Bool, String?) -> Void) {
        do {
            try eventStore.commit()
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    @objc public func reset() {
        eventStore.reset()
    }
    
    @objc public func refreshSourcesIfNecessary() {
        eventStore.refreshSourcesIfNecessary()
    }
    
    @objc public func removeCalendar(identifier: String, commit: Bool, completion: @escaping (Bool, String?) -> Void) {
        // Get the calendar by identifier
        guard let calendar = eventStore.calendar(withIdentifier: identifier) else {
            completion(false, "Calendar not found")
            return
        }
        
        // Try to remove the calendar
        do {
            try eventStore.removeCalendar(calendar, commit: commit)
            completion(true, nil)
        } catch {
            completion(false, error.localizedDescription)
        }
    }
    
    @objc public func getDefaultCalendarForNewEvents() -> Calendar? {
        if let defaultCalendar = eventStore.defaultCalendarForNewEvents {
            return Calendar(from: defaultCalendar)
        }
        return nil
    }
    
    @objc public func getDefaultCalendarForNewReminders() -> Calendar? {
        if let defaultCalendar = eventStore.defaultCalendarForNewReminders() {
            return Calendar(from: defaultCalendar)
        }
        return nil
    }

    @objc public func getAuthorizationStatus(entityTypeString: String) -> String {
        let entityType: EKEntityType = entityTypeString.lowercased() == "reminder" ? .reminder : .event
        let status = EKEventStore.authorizationStatus(for: entityType)
        
        switch status {
        case .notDetermined:
            return "notDetermined"
        case .restricted:
            return "restricted"
        case .denied:
            return "denied"
        case .authorized:
            return "authorized"
        case .fullAccess:
            return "fullAccess"
        case .writeOnly:
            return "writeOnly"
        @unknown default:
            return "unknown"
        }
    }

    // Event object for JSON serialization
    @objc public class Event: NSObject {
        @objc public let id: String
        @objc public let title: String
        @objc public let notes: String?
        @objc public let startDate: Date
        @objc public let endDate: Date
        @objc public let isAllDay: Bool
        @objc public let calendarId: String
        @objc public let calendarTitle: String
        @objc public let location: String?
        @objc public let url: String?
        @objc public let hasAlarms: Bool
        @objc public let availability: String
        @objc public let externalIdentifier: String?
        
        init(from ekEvent: EKEvent) {
            // Get base identifier
            let baseIdentifier = ekEvent.eventIdentifier ?? ""

            // For recurring events, add RID suffix if not already present
            let identifier: String
            if ekEvent.hasRecurrenceRules && !baseIdentifier.contains("/RID=") {
                // Calculate RID from occurrence start date
                let timestamp = Int(ekEvent.startDate.timeIntervalSinceReferenceDate)
                identifier = "\(baseIdentifier)/RID=\(timestamp)"
            } else {
                identifier = baseIdentifier
            }

            self.id = identifier
            self.title = ekEvent.title ?? "Untitled Event"
            self.notes = ekEvent.notes
            self.startDate = ekEvent.startDate
            self.endDate = ekEvent.endDate
            self.isAllDay = ekEvent.isAllDay
            self.calendarId = ekEvent.calendar.calendarIdentifier
            self.calendarTitle = ekEvent.calendar.title
            self.location = ekEvent.location
            self.url = ekEvent.url?.absoluteString
            self.hasAlarms = ekEvent.hasAlarms
            self.externalIdentifier = ekEvent.calendarItemExternalIdentifier

            // Convert availability to string
            switch ekEvent.availability {
            case .free:
                self.availability = "free"
            case .busy:
                self.availability = "busy"
            case .tentative:
                self.availability = "tentative"
            case .unavailable:
                self.availability = "unavailable"
            default:
                self.availability = "unknown"
            }

            super.init()
        }
    }
    
    // Reminder object for JSON serialization
    @objc public class Reminder: NSObject {
        @objc public let id: String
        @objc public let title: String
        @objc public let notes: String?
        @objc public let calendarId: String
        @objc public let calendarTitle: String
        @objc public let completed: Bool
        @objc public let completionDate: Date?
        @objc public let dueDate: Date?
        @objc public let startDate: Date?
        @objc public let priority: Int
        @objc public let hasAlarms: Bool
        @objc public let externalIdentifier: String?
        
        init(from ekReminder: EKReminder) {
            self.id = ekReminder.calendarItemIdentifier
            self.title = ekReminder.title ?? "Untitled Reminder"
            self.notes = ekReminder.notes
            self.calendarId = ekReminder.calendar.calendarIdentifier
            self.calendarTitle = ekReminder.calendar.title
            self.completed = ekReminder.isCompleted
            self.completionDate = ekReminder.completionDate
            self.externalIdentifier = ekReminder.calendarItemExternalIdentifier
            
            // Convert date components to Date objects if available
            if let dueDateComponents = ekReminder.dueDateComponents {
                self.dueDate = Foundation.Calendar.current.date(from: dueDateComponents)
            } else {
                self.dueDate = nil
            }
            
            if let startDateComponents = ekReminder.startDateComponents {
                self.startDate = Foundation.Calendar.current.date(from: startDateComponents)
            } else {
                self.startDate = nil
            }
            
            self.priority = ekReminder.priority
            self.hasAlarms = ekReminder.hasAlarms
            
            super.init()
        }
    }
    
    // Predicate wrapper for serialization
    @objc public class Predicate: NSObject {
        @objc public let predicateType: String
        @objc public let predicate: NSPredicate
        
        init(type: String, predicate: NSPredicate) {
            self.predicateType = type
            self.predicate = predicate
            super.init()
        }
    }
    
    // MARK: - Predicate Methods
    
    @objc public func createEventPredicate(startDate: Date, endDate: Date, calendarIds: [String]?) -> Predicate {
        // Convert calendar IDs to EKCalendar objects if provided
        var calendars: [EKCalendar]? = nil
        if let calendarIds = calendarIds, !calendarIds.isEmpty {
            calendars = calendarIds.compactMap { eventStore.calendar(withIdentifier: $0) }
        }
        
        // Create the predicate
        let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: calendars)
        
        return Predicate(type: "event", predicate: predicate)
    }
    
    @objc public func createReminderPredicate(calendarIds: [String]?) -> Predicate {
        // Convert calendar IDs to EKCalendar objects if provided
        var calendars: [EKCalendar]? = nil
        if let calendarIds = calendarIds, !calendarIds.isEmpty {
            calendars = calendarIds.compactMap { eventStore.calendar(withIdentifier: $0) }
        }
        
        // Create the predicate
        let predicate = eventStore.predicateForReminders(in: calendars)
        
        return Predicate(type: "reminder", predicate: predicate)
    }
    
    @objc public func createIncompleteReminderPredicate(startDate: Date?, endDate: Date?, calendarIds: [String]?) -> Predicate {
        // Convert calendar IDs to EKCalendar objects if provided
        var calendars: [EKCalendar]? = nil
        if let calendarIds = calendarIds, !calendarIds.isEmpty {
            calendars = calendarIds.compactMap { eventStore.calendar(withIdentifier: $0) }
        }
        
        // Create the predicate
        let predicate = eventStore.predicateForIncompleteReminders(withDueDateStarting: startDate, ending: endDate, calendars: calendars)
        
        return Predicate(type: "incompleteReminder", predicate: predicate)
    }
    
    @objc public func createCompletedReminderPredicate(startDate: Date?, endDate: Date?, calendarIds: [String]?) -> Predicate {
        // Convert calendar IDs to EKCalendar objects if provided
        var calendars: [EKCalendar]? = nil
        if let calendarIds = calendarIds, !calendarIds.isEmpty {
            calendars = calendarIds.compactMap { eventStore.calendar(withIdentifier: $0) }
        }
        
        // Create the predicate
        let predicate = eventStore.predicateForCompletedReminders(withCompletionDateStarting: startDate, ending: endDate, calendars: calendars)
        
        return Predicate(type: "completedReminder", predicate: predicate)
    }
    
    // MARK: - Query Methods
    
    @objc public func getEvent(identifier: String, occurrenceDate: Date?) -> Event? {
        // Parse RID suffix if present in identifier (similar to saveEvent)
        var baseIdentifier = identifier
        var derivedOccurrenceDate = occurrenceDate

        print("[EventKit getEvent] identifier: \(identifier)")
        print("[EventKit getEvent] occurrenceDate: \(occurrenceDate?.description ?? "nil")")

        if identifier.contains("/RID=") {
            let components = identifier.split(separator: "/", maxSplits: 1)
            baseIdentifier = String(components[0])

            print("[EventKit getEvent] RID suffix detected")
            print("[EventKit getEvent] Base ID: \(baseIdentifier)")

            // Extract RID timestamp if we don't already have an explicit occurrence date
            if derivedOccurrenceDate == nil, components.count > 1 {
                let ridPart = String(components[1])
                if ridPart.hasPrefix("RID=") {
                    let timestampString = ridPart.replacingOccurrences(of: "RID=", with: "")
                    if let timestamp = Double(timestampString) {
                        derivedOccurrenceDate = Date(timeIntervalSinceReferenceDate: timestamp)
                        print("[EventKit getEvent] Derived occurrence date from RID: \(derivedOccurrenceDate!)")
                    }
                }
            } else if derivedOccurrenceDate != nil {
                print("[EventKit getEvent] Using explicit occurrenceDate, ignoring RID")
            }
        }

        // If an occurrence date is available (explicit or derived from RID), fetch specific occurrence
        if let occurrenceDate = derivedOccurrenceDate {
            print("[EventKit getEvent] Fetching specific occurrence at: \(occurrenceDate)")

            let startDate = occurrenceDate.addingTimeInterval(-1)
            let endDate = occurrenceDate.addingTimeInterval(86400)

            let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let events = eventStore.events(matching: predicate)

            print("[EventKit getEvent] Predicate returned \(events.count) events")

            // Match by base ID AND start date (same logic as saveEvent)
            // IMPORTANT: After first modification, detached occurrences get /RID suffix in their eventIdentifier
            // So we need to check for both exact match AND prefix match
            if let foundEvent = events.first(where: {
                let eventId = $0.eventIdentifier ?? ""
                let matchesId = (eventId == baseIdentifier || eventId.hasPrefix(baseIdentifier + "/RID="))
                let matchesTime = abs($0.startDate.timeIntervalSince(occurrenceDate)) < 60
                return matchesId && matchesTime
            }) {
                print("[EventKit getEvent] ✓ Found specific occurrence")
                print("[EventKit getEvent]   Time difference: \(abs(foundEvent.startDate.timeIntervalSince(occurrenceDate))) seconds")
                return Event(from: foundEvent)
            } else {
                print("[EventKit getEvent] ✗ Specific occurrence not found in predicate results")
            }
        }

        // Fallback: No occurrence date, or occurrence not found - get master event
        print("[EventKit getEvent] Fetching master event with base ID: \(baseIdentifier)")
        guard let ekEvent = eventStore.event(withIdentifier: baseIdentifier) else {
            print("[EventKit getEvent] ✗ Master event not found")
            return nil
        }

        print("[EventKit getEvent] ✓ Found master event")
        return Event(from: ekEvent)
    }
    
    @objc public func getCalendarItem(identifier: String) -> [String: Any]? {
        // Try to get the calendar item using calendarItem(withIdentifier:)
        guard let ekCalendarItem = eventStore.calendarItem(withIdentifier: identifier) else {
            // If the calendar item doesn't exist, return nil
            return nil
        }
        
        // Determine type and create appropriate wrapper
        if let ekEvent = ekCalendarItem as? EKEvent {
            let event = Event(from: ekEvent)
            return [
                "type": "event",
                "item": event
            ]
        } else if let ekReminder = ekCalendarItem as? EKReminder {
            let reminder = Reminder(from: ekReminder)
            return [
                "type": "reminder",
                "item": reminder
            ]
        }
        
        // Unknown item type
        return nil
    }
    
    @objc public func getCalendarItemsWithExternalIdentifier(_ externalIdentifier: String) -> NSArray? {
        // Try to retrieve calendar items with the external identifier
        let items = eventStore.calendarItems(withExternalIdentifier: externalIdentifier)
        
        // If no items found, return nil
        if items.isEmpty {
            return nil
        }
        
        // Convert the found items to dictionary representations
        let result = NSMutableArray()
        
        for item in items {
            if let ekEvent = item as? EKEvent {
                let event = Event(from: ekEvent)
                result.add([
                    "type": "event",
                    "item": event
                ])
            } else if let ekReminder = item as? EKReminder {
                let reminder = Reminder(from: ekReminder)
                result.add([
                    "type": "reminder",
                    "item": reminder
                ])
            }
        }
        
        return result.count > 0 ? result : nil
    }
    
    @objc public func getEventsWithPredicate(predicate: Predicate) -> NSArray {
        guard predicate.predicateType == "event" else {
            return NSArray() // Return empty array if predicate type doesn't match
        }

        let events = eventStore.events(matching: predicate.predicate)
        let result = NSMutableArray()

        for event in events {
            result.add(Event(from: event))
        }

        return result
    }
    
    @objc public func getRemindersWithPredicate(_ predicate: Predicate, completion: @escaping ([Reminder]?) -> Void) {
        // Validate that this is a reminder predicate
        guard predicate.predicateType.lowercased().contains("reminder") else {
            print("Error: Predicate type does not contain 'reminder': \(predicate.predicateType)")
            completion([])
            return
        }
        
        // Create a strong reference to the predicate to prevent it from being deallocated
        let strongPredicate = predicate
        
        // Fetch reminders using EventKit's asynchronous API
        eventStore.fetchReminders(matching: strongPredicate.predicate) { [weak self] ekReminders in
            // Check if self is still alive
            guard self != nil else {
                completion([])
                return
            }
            
            if let ekReminders = ekReminders {
                // Create a strong reference to the reminders to prevent them from being deallocated
                let strongReminders = ekReminders
                
                // Map EKReminder objects to our Reminder objects
                let reminders = strongReminders.map { Reminder(from: $0) }
                
                // Call the completion handler with the reminders
                completion(reminders)
            } else {
                // If nil is returned, return an empty array
                completion([])
            }
        }
    }

    // MARK: - Removal Methods
    
    @objc public func removeEvent(withIdentifier identifier: String, span: String, commit: Bool) -> Bool {
        // Parse RID suffix if present in identifier (same logic as getEvent/saveEvent)
        var baseIdentifier = identifier
        var derivedOccurrenceDate: Date? = nil

        print("[EventKit removeEvent] identifier: \(identifier)")
        print("[EventKit removeEvent] span: \(span)")

        if identifier.contains("/RID=") {
            let components = identifier.split(separator: "/", maxSplits: 1)
            baseIdentifier = String(components[0])

            print("[EventKit removeEvent] RID suffix detected")
            print("[EventKit removeEvent] Base ID: \(baseIdentifier)")

            // Extract RID timestamp to get the specific occurrence
            if components.count > 1 {
                let ridPart = String(components[1])
                if ridPart.hasPrefix("RID=") {
                    let timestampString = ridPart.replacingOccurrences(of: "RID=", with: "")
                    if let timestamp = Double(timestampString) {
                        derivedOccurrenceDate = Date(timeIntervalSinceReferenceDate: timestamp)
                        print("[EventKit removeEvent] Derived occurrence date from RID: \(derivedOccurrenceDate!)")
                    }
                }
            }
        }

        // Fetch the event - use predicate if we have occurrence date from RID
        var event: EKEvent?

        if let occurrenceDate = derivedOccurrenceDate {
            print("[EventKit removeEvent] Fetching specific occurrence at: \(occurrenceDate)")

            let startDate = occurrenceDate.addingTimeInterval(-1)
            let endDate = occurrenceDate.addingTimeInterval(86400)

            let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
            let events = eventStore.events(matching: predicate)

            print("[EventKit removeEvent] Predicate returned \(events.count) events")

            // Match by base ID AND start date (same logic as getEvent/saveEvent)
            event = events.first(where: {
                $0.eventIdentifier == baseIdentifier &&
                abs($0.startDate.timeIntervalSince(occurrenceDate)) < 60
            })

            if event != nil {
                print("[EventKit removeEvent] ✓ Found specific occurrence")
            } else {
                print("[EventKit removeEvent] ✗ Specific occurrence not found")
            }
        } else {
            // No RID suffix - fetch master event
            print("[EventKit removeEvent] Fetching master event with base ID: \(baseIdentifier)")
            event = eventStore.event(withIdentifier: baseIdentifier)

            if event != nil {
                print("[EventKit removeEvent] ✓ Found master event")
            } else {
                print("[EventKit removeEvent] ✗ Master event not found")
            }
        }

        guard let event = event else {
            return false
        }

        // Convert string span to EKSpan
        var ekSpan: EKSpan
        switch span {
        case "thisEvent":
            ekSpan = .thisEvent
        case "futureEvents":
            ekSpan = .futureEvents
        default:
            ekSpan = .thisEvent
        }

        print("[EventKit removeEvent] Attempting to remove event: \(event.title ?? "Untitled")")
        print("[EventKit removeEvent] Span: \(span)")

        do {
            // Remove the event
            try eventStore.remove(event, span: ekSpan, commit: commit)
            print("[EventKit removeEvent] ✓ Event removed successfully")
            return true
        } catch {
            print("[EventKit removeEvent] ✗ Remove failed: \(error.localizedDescription)")
            return false
        }
    }
    
    @objc public func removeReminder(withIdentifier identifier: String, commit: Bool) -> Bool {
        // Try to get the reminder
        guard let calendarItem = eventStore.calendarItem(withIdentifier: identifier),
              let reminder = calendarItem as? EKReminder else {
            return false
        }
        
        do {
            // Remove the reminder
            try eventStore.remove(reminder, commit: commit)
            return true
        } catch {
            // If there was an error removing the reminder, return false
            return false
        }
    }
    
    // MARK: - Save Methods
    
    @objc public func saveEvent(eventData: NSDictionary, span: String, commit: Bool, originalOccurrenceDate: Date?) -> [String: Any]? {
        // Get the event ID if it exists (for updating an existing event)
        let eventId = eventData["id"] as? String

        // DEBUG: Log parameters to verify new code is running
        print("========================================")
        print("[EventKit saveEvent] UPDATED VERSION WITH FULL LOGGING")
        print("[EventKit saveEvent] eventId: \(eventId ?? "nil")")
        print("[EventKit saveEvent] span: \(span)")
        print("[EventKit saveEvent] commit: \(commit)")
        print("[EventKit saveEvent] originalOccurrenceDate: \(originalOccurrenceDate?.description ?? "nil")")
        print("[EventKit saveEvent] eventData keys: \(eventData.allKeys)")
        if let title = eventData["title"] as? String {
            print("[EventKit saveEvent] eventData.title: \(title)")
        }
        if let startDate = eventData["startDate"] as? Date {
            print("[EventKit saveEvent] eventData.startDate: \(startDate)")
        }
        if let endDate = eventData["endDate"] as? Date {
            print("[EventKit saveEvent] eventData.endDate: \(endDate)")
        }
        print("========================================")

        // Parse RID suffix if present in event ID
        var baseEventId = eventId
        var derivedOccurrenceDate = originalOccurrenceDate

        if let eventId = eventId, eventId.contains("/RID=") {
            let components = eventId.split(separator: "/", maxSplits: 1)
            baseEventId = String(components[0])

            print("[EventKit saveEvent] RID suffix detected in event ID")
            print("[EventKit saveEvent] Base ID: \(baseEventId ?? "nil")")

            // Extract RID timestamp if we don't already have an explicit occurrence date
            if derivedOccurrenceDate == nil, components.count > 1 {
                let ridPart = String(components[1])
                if ridPart.hasPrefix("RID=") {
                    let timestampString = ridPart.replacingOccurrences(of: "RID=", with: "")
                    if let timestamp = Double(timestampString) {
                        derivedOccurrenceDate = Date(timeIntervalSinceReferenceDate: timestamp)
                        print("[EventKit saveEvent] Derived occurrence date from RID: \(derivedOccurrenceDate?.description ?? "nil")")
                    } else {
                        print("[EventKit saveEvent] WARNING: Failed to parse RID timestamp: \(timestampString)")
                    }
                }
            } else if derivedOccurrenceDate != nil {
                print("[EventKit saveEvent] Using explicit originalOccurrenceDate, ignoring RID timestamp")
            }
        }

        // Create a new event or get an existing one
        let event: EKEvent
        if let baseId = baseEventId {
            // IMPORTANT: For recurring events, if we have an occurrence date (explicit or derived from RID),
            // we need to fetch the SPECIFIC occurrence at that date, not the master event.
            // This ensures we modify only that instance (creating an exception/detachment)
            // instead of modifying the entire recurring series.
            if let occurrenceDate = derivedOccurrenceDate {
                // Use a predicate to fetch events in a small window around the occurrence date
                // This will return the specific occurrence, not the master event
                let startDate = occurrenceDate.addingTimeInterval(-1) // 1 second before
                let endDate = occurrenceDate.addingTimeInterval(86400) // 1 day after (to catch all-day events)

                let predicate = eventStore.predicateForEvents(withStart: startDate, end: endDate, calendars: nil)
                let events = eventStore.events(matching: predicate)

                // Debug: Log all events returned by predicate
                print("[EventKit] Predicate query returned \(events.count) events")
                for (index, evt) in events.enumerated() {
                    print("[EventKit]   Event[\(index)]: id=\(evt.eventIdentifier ?? "nil"), title=\(evt.title ?? "nil"), startDate=\(evt.startDate!)")
                }
                print("[EventKit] Looking for baseId: \(baseId)")
                print("[EventKit] Target occurrenceDate: \(occurrenceDate)")

                // Find the event with matching base identifier AND start date
                // We need to match both because multiple occurrences share the same eventIdentifier
                // IMPORTANT: After first modification, detached occurrences get /RID suffix in their eventIdentifier
                // So we need to check for both exact match AND prefix match
                if let foundEvent = events.first(where: {
                    let eventId = $0.eventIdentifier ?? ""
                    let matchesId = (eventId == baseId || eventId.hasPrefix(baseId + "/RID="))
                    let matchesTime = abs($0.startDate.timeIntervalSince(occurrenceDate)) < 60
                    return matchesId && matchesTime
                }) {
                    print("[EventKit] MATCH FOUND!")
                    print("[EventKit]   Matched event startDate: \(foundEvent.startDate!)")
                    print("[EventKit]   Time difference from target: \(foundEvent.startDate.timeIntervalSince(occurrenceDate)) seconds")
                    event = foundEvent
                } else {
                    // Fallback to master event if specific occurrence not found
                    print("[EventKit] NO MATCH FOUND in predicate results")
                    print("[EventKit] Attempting fallback to master event with ID: \(baseId)")
                    if let existingEvent = eventStore.event(withIdentifier: baseId) {
                        print("[EventKit] ✓ Fallback successful - found master event")
                        print("[EventKit]   Master event title: \(existingEvent.title ?? "nil")")
                        print("[EventKit]   Master event startDate: \(existingEvent.startDate!)")
                        event = existingEvent
                    } else {
                        print("[EventKit] ✗ Fallback FAILED - master event not found")
                        print("[EventKit] ERROR: Event not found with identifier: \(baseId)")
                        return ["success": false, "error": "Event not found with identifier: \(baseId)"]
                    }
                }
            } else if let existingEvent = eventStore.event(withIdentifier: baseId) {
                // No occurrence date provided, use master event
                print("[EventKit] Fetched master event (no occurrence date)")
                print("[EventKit]   Event title: \(existingEvent.title ?? "nil")")
                print("[EventKit]   Event startDate: \(existingEvent.startDate!)")
                event = existingEvent
            } else {
                print("[EventKit] ERROR: Event not found with identifier: \(baseId)")
                print("[EventKit]   Tried to fetch event but eventStore returned nil")
                return ["success": false, "error": "Event not found with identifier: \(baseId)"]
            }
        } else {
            // Create a new event
            print("[EventKit] Creating NEW event (no ID provided)")
            event = EKEvent(eventStore: eventStore)

            // For new events, we need to set a calendar
            if let calendarId = eventData["calendarId"] as? String,
               let calendar = eventStore.calendar(withIdentifier: calendarId) {
                print("[EventKit] Setting calendar: \(calendar.title) (\(calendarId))")
                event.calendar = calendar
            } else {
                print("[EventKit] ERROR: No valid calendarId provided for new event")
                return ["success": false, "error": "A valid calendarId is required for new events"]
            }
        }

        print("[EventKit] Updating event properties...")

        // Update event properties
        if let title = eventData["title"] as? String {
            print("[EventKit]   Setting title: \(title)")
            event.title = title
        }
        
        if let notes = eventData["notes"] as? String {
            print("[EventKit]   Setting notes: \(notes.prefix(50))...")
            event.notes = notes
        }

        // isAllDay must be set BEFORE startDate/endDate so that EventKit does not normalize
        // the times to midnight/23:59:59 (which it does automatically for all-day events).
        // Setting isAllDay first lets EventKit treat subsequent date assignments as timed.
        if let isAllDay = eventData["isAllDay"] as? Bool {
            print("[EventKit]   Setting isAllDay: \(isAllDay)")
            event.isAllDay = isAllDay
        }

        if let startDate = eventData["startDate"] as? Date {
            print("[EventKit]   Setting startDate: \(startDate)")
            event.startDate = startDate
        }

        if let endDate = eventData["endDate"] as? Date {
            print("[EventKit]   Setting endDate: \(endDate)")
            event.endDate = endDate
        }

        if let location = eventData["location"] as? String {
            print("[EventKit]   Setting location: \(location)")
            event.location = location
        }
        
        if let urlString = eventData["url"] as? String, let url = URL(string: urlString) {
            event.url = url
        }
        
        if let availabilityString = eventData["availability"] as? String {
            switch availabilityString.lowercased() {
            case "free":
                event.availability = .free
            case "busy":
                event.availability = .busy
            case "tentative":
                event.availability = .tentative
            case "unavailable":
                event.availability = .unavailable
            default:
                break
            }
        }
        
        // Convert string span to EKSpan
        var ekSpan: EKSpan
        switch span {
        case "thisEvent":
            ekSpan = .thisEvent
        case "futureEvents":
            ekSpan = .futureEvents
        default:
            ekSpan = .thisEvent
        }

        print("[EventKit] Preparing to save event...")
        print("[EventKit]   Event ID: \(event.eventIdentifier ?? "new event")")
        print("[EventKit]   Event title: \(event.title ?? "nil")")
        print("[EventKit]   Event calendar: \(event.calendar?.title ?? "nil")")
        print("[EventKit]   Event calendar writable: \(event.calendar?.allowsContentModifications ?? false)")
        print("[EventKit]   Span: \(span) (ekSpan: \(ekSpan == .thisEvent ? "thisEvent" : "futureEvents"))")
        print("[EventKit]   Commit: \(commit)")

        // Save the event
        do {
            print("[EventKit] Calling eventStore.save()...")
            try eventStore.save(event, span: ekSpan, commit: commit)
            print("[EventKit] ✓ Save successful!")
            print("[EventKit]   Saved event ID: \(event.eventIdentifier!)")

            // Create Event object to return full event data
            let savedEvent = Event(from: event)

            return [
                "success": true,
                "id": event.eventIdentifier!,
                "event": savedEvent
            ]
        } catch {
            print("[EventKit] ✗ Save FAILED with error:")
            print("[EventKit]   Error: \(error.localizedDescription)")
            print("[EventKit]   Error details: \(error)")
            return ["success": false, "error": error.localizedDescription]
        }
    }
    
    @objc public func saveReminder(reminderData: NSDictionary, commit: Bool) -> [String: Any]? {
        // Get the reminder ID if it exists (for updating an existing reminder)
        let reminderId = reminderData["id"] as? String
        
        // Create a new reminder or get an existing one
        let reminder: EKReminder
        if let reminderId = reminderId, 
           let calendarItem = eventStore.calendarItem(withIdentifier: reminderId),
           let existingReminder = calendarItem as? EKReminder {
            // Update existing reminder
            reminder = existingReminder
        } else {
            // Create a new reminder
            reminder = EKReminder(eventStore: eventStore)
            
            // For new reminders, we need to set a calendar
            if let calendarId = reminderData["calendarId"] as? String, 
               let calendar = eventStore.calendar(withIdentifier: calendarId) {
                reminder.calendar = calendar
            } else {
                // No valid calendar ID provided
                return ["success": false, "error": "A valid calendarId is required for new reminders"]
            }
        }
        
        // Update reminder properties
        if let title = reminderData["title"] as? String {
            reminder.title = title
        }
        
        if let notes = reminderData["notes"] as? String {
            reminder.notes = notes
        }
        
        if let completed = reminderData["completed"] as? Bool {
            reminder.isCompleted = completed
            
            if completed {
                reminder.completionDate = Date()
            } else {
                reminder.completionDate = nil
            }
        }
        
        if let priority = reminderData["priority"] as? Int {
            reminder.priority = priority
        }
        
        // Handle due date if provided
        if let dueDate = reminderData["dueDate"] as? Date {
            let dateComponents = Foundation.Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: dueDate)
            reminder.dueDateComponents = dateComponents
        }
        
        // Handle start date if provided
        if let startDate = reminderData["startDate"] as? Date {
            let dateComponents = Foundation.Calendar.current.dateComponents([.year, .month, .day, .hour, .minute], from: startDate)
            reminder.startDateComponents = dateComponents
        }
        
        // Save the reminder
        do {
            try eventStore.save(reminder, commit: commit)
            return ["success": true, "id": reminder.calendarItemIdentifier]
        } catch {
            return ["success": false, "error": error.localizedDescription]
        }
    }
} 