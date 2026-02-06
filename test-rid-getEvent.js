#!/usr/bin/env node

const eventkit = require('./dist/index.js');

console.log('\n=== Testing RID Handling in getEvent ===\n');

async function runTests() {
  try {
    // Step 1: Get recurring events with RID-suffixed IDs
    console.log('Step 1: Getting recurring events...');
    const predicate = eventkit.createEventPredicate(
      new Date('2026-02-01'),
      new Date('2026-02-28')
    );
    const events = eventkit.getEventsWithPredicate(predicate);

    console.log(`Found ${events.length} events total`);

    const recurringEvents = events.filter(e => e.id.includes('/RID='));
    console.log(`Found ${recurringEvents.length} recurring event occurrences with RID suffixes`);

    if (recurringEvents.length === 0) {
      console.log('\n⚠️  No recurring events found. Please create a recurring event in Calendar app first.');
      console.log('Example: Create an event that repeats daily from Feb 1-28, 2026');
      return;
    }

    // Use the first recurring event for testing
    const testEvent = recurringEvents[0];
    console.log('\nTest Event:', {
      id: testEvent.id,
      title: testEvent.title,
      startDate: testEvent.startDate,
      hasRecurrenceRules: testEvent.hasRecurrenceRules
    });

    // Test Case 1: Get Event with RID-Suffixed ID (NEW FEATURE)
    console.log('\n--- Test Case 1: getEvent with RID-suffixed ID ---');
    try {
      const retrieved = eventkit.getEvent(testEvent.id);

      if (retrieved) {
        console.log('✅ SUCCESS: Retrieved event using RID-suffixed ID');
        console.log('   Retrieved ID:', retrieved.id);
        console.log('   Original ID: ', testEvent.id);
        console.log('   IDs match:', retrieved.id === testEvent.id);
        console.log('   Title:', retrieved.title);
        console.log('   Start:', retrieved.startDate);
      } else {
        console.log('❌ FAILED: getEvent returned null');
      }
    } catch (error) {
      console.log('❌ ERROR:', error.message);
    }

    // Test Case 2: Backward Compatibility - Base ID + Explicit Date
    console.log('\n--- Test Case 2: Base ID with explicit occurrenceDate ---');
    const baseId = testEvent.id.split('/RID=')[0];
    const occurrenceDate = new Date(testEvent.startDate);

    try {
      const retrieved = eventkit.getEvent(baseId, occurrenceDate);

      if (retrieved) {
        console.log('✅ SUCCESS: Retrieved using base ID + explicit date');
        console.log('   Base ID used:', baseId);
        console.log('   Explicit date:', occurrenceDate.toISOString());
        console.log('   Retrieved event:', retrieved.title);
        console.log('   Start:', retrieved.startDate);
      } else {
        console.log('❌ FAILED: getEvent returned null');
      }
    } catch (error) {
      console.log('❌ ERROR:', error.message);
    }

    // Test Case 3: Master Event Retrieval
    console.log('\n--- Test Case 3: Get master event (no RID, no date) ---');
    try {
      const masterEvent = eventkit.getEvent(baseId);

      if (masterEvent) {
        console.log('✅ SUCCESS: Retrieved master event');
        console.log('   ID:', masterEvent.id);
        console.log('   Has RID suffix:', masterEvent.id.includes('/RID='));
        console.log('   Title:', masterEvent.title);
        console.log('   Has recurrence rules:', masterEvent.hasRecurrenceRules);
      } else {
        console.log('❌ FAILED: getEvent returned null');
      }
    } catch (error) {
      console.log('❌ ERROR:', error.message);
    }

    // Test Case 4: RID + Explicit Date (Explicit Should Take Priority)
    console.log('\n--- Test Case 4: RID-suffixed ID + explicit date (explicit wins) ---');

    // Find a different occurrence to use as explicit date
    const otherOccurrence = recurringEvents.find(e => e.id !== testEvent.id);

    if (otherOccurrence) {
      try {
        const explicitDate = new Date(otherOccurrence.startDate);
        const retrieved = eventkit.getEvent(testEvent.id, explicitDate);

        if (retrieved) {
          console.log('✅ SUCCESS: Explicit date overrode RID timestamp');
          console.log('   RID ID used:', testEvent.id);
          console.log('   RID start:', testEvent.startDate);
          console.log('   Explicit date:', explicitDate.toISOString());
          console.log('   Retrieved start:', retrieved.startDate);
          console.log('   Matches explicit date:',
            Math.abs(new Date(retrieved.startDate).getTime() - explicitDate.getTime()) < 60000);
        } else {
          console.log('❌ FAILED: getEvent returned null');
        }
      } catch (error) {
        console.log('❌ ERROR:', error.message);
      }
    } else {
      console.log('⚠️  SKIPPED: Need at least 2 recurring occurrences for this test');
    }

    // Test Case 5: Full Round Trip (Query → Retrieve → Update → Verify)
    console.log('\n--- Test Case 5: Full round trip workflow ---');
    try {
      // 1. Query events → Get RID-suffixed IDs
      console.log('1. Query: Found event with ID:', testEvent.id);

      // 2. Retrieve using RID-suffixed ID
      const retrieved = eventkit.getEvent(testEvent.id);
      console.log('2. Retrieve: Successfully got event:', retrieved ? '✓' : '✗');

      if (retrieved) {
        // 3. Update using RID-suffixed ID
        const originalTitle = retrieved.title;
        const testTitle = `[TEST ${Date.now()}] ${originalTitle}`;

        console.log('3. Update: Changing title to:', testTitle);
        const updateResult = eventkit.saveEvent({
          id: testEvent.id,
          title: testTitle,
          startDate: retrieved.startDate,
          endDate: retrieved.endDate,
          calendar: retrieved.calendar
        }, 'thisEvent');

        console.log('   Update result:', updateResult ? '✓' : '✗');

        // 4. Retrieve again to verify update
        const updated = eventkit.getEvent(testEvent.id);

        if (updated) {
          console.log('4. Verify: Retrieved updated event');
          console.log('   New title:', updated.title);
          console.log('   Title was updated:', updated.title === testTitle);

          // Clean up - restore original title
          eventkit.saveEvent({
            id: testEvent.id,
            title: originalTitle,
            startDate: updated.startDate,
            endDate: updated.endDate,
            calendar: updated.calendar
          }, 'thisEvent');
          console.log('   Restored original title');

          console.log('\n✅ FULL ROUND TRIP SUCCESS');
        } else {
          console.log('❌ Could not retrieve updated event');
        }
      }
    } catch (error) {
      console.log('❌ ERROR in round trip:', error.message);
    }

    console.log('\n=== Test Suite Complete ===\n');

  } catch (error) {
    console.error('Fatal error:', error);
  }
}

runTests();
