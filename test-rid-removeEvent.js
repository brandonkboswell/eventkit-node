#!/usr/bin/env node

const eventkit = require('./dist/index.js');

console.log('\n=== Testing RID Handling in removeEvent ===\n');

async function runTests() {
  try {
    // Step 1: Create a test recurring event that we can delete
    console.log('Step 1: Creating a test recurring event...');

    const testCalendars = eventkit.getCalendars('event');
    const writableCalendar = testCalendars.find(cal =>
      !cal.immutable &&
      cal.allowsContentModifications &&
      !cal.title.toLowerCase().includes('holiday') &&
      !cal.title.toLowerCase().includes('birthday')
    );

    if (!writableCalendar) {
      console.log('❌ No writable calendar found. Please ensure you have a writable calendar.');
      console.log('\nAvailable calendars:');
      testCalendars.forEach(cal => {
        console.log(`  - ${cal.title} (immutable: ${cal.immutable}, allowsContentMods: ${cal.allowsContentModifications})`);
      });
      return;
    }

    console.log(`Using calendar: ${writableCalendar.title} (ID: ${writableCalendar.id})`);

    // Create a recurring event (daily for 5 days)
    const now = new Date();
    const startDate = new Date(now.getTime() + 3600000); // 1 hour from now
    const endDate = new Date(startDate.getTime() + 3600000); // 1 hour duration

    const eventData = {
      title: '[TEST RID DELETE] Recurring Event',
      startDate: startDate,
      endDate: endDate,
      calendarId: writableCalendar.id,
      recurrenceRule: {
        frequency: 'daily',
        interval: 1,
        occurrenceCount: 5  // 5 occurrences total
      }
    };

    const createResult = await eventkit.saveEvent(eventData, 'thisEvent', true);

    if (!createResult) {
      console.log('❌ Failed to create test event');
      console.log('createResult:', createResult);
      return;
    }

    const masterEventId = typeof createResult === 'string' ? createResult : createResult.calendarItemIdentifier;
    console.log(`✅ Created recurring event: ${masterEventId}\n`);

    // Wait a moment for EventKit to process
    await new Promise(resolve => setTimeout(resolve, 500));

    // Step 2: Get all occurrences of the recurring event
    console.log('Step 2: Fetching all occurrences...');

    const predicate = eventkit.createEventPredicate(
      startDate,
      new Date(startDate.getTime() + 7 * 24 * 3600000) // 7 days from start
    );

    const allEvents = eventkit.getEventsWithPredicate(predicate);
    const testOccurrences = allEvents.filter(e =>
      e.title === '[TEST RID DELETE] Recurring Event'
    );

    console.log(`Found ${testOccurrences.length} occurrences of test event\n`);

    if (testOccurrences.length === 0) {
      console.log('❌ Could not find test event occurrences');
      return;
    }

    testOccurrences.forEach((occ, i) => {
      console.log(`  Occurrence ${i + 1}:`);
      console.log(`    ID: ${occ.id}`);
      console.log(`    Has RID: ${occ.id.includes('/RID=')}`);
      console.log(`    Start: ${occ.startDate}`);
    });

    console.log('');

    // Test Case 1: Delete specific occurrence using RID-suffixed ID
    if (testOccurrences.length >= 2) {
      console.log('--- Test Case 1: Delete specific occurrence with RID-suffixed ID ---');

      const secondOccurrence = testOccurrences[1];
      console.log(`Deleting occurrence: ${secondOccurrence.id}`);
      console.log(`Start date: ${secondOccurrence.startDate}`);

      const deleteResult = eventkit.removeEvent(secondOccurrence.id, 'thisEvent', true);

      console.log(`Delete result: ${deleteResult ? '✅ SUCCESS' : '❌ FAILED'}\n`);

      if (deleteResult) {
        // Verify deletion
        await new Promise(resolve => setTimeout(resolve, 500));

        const verifyEvents = eventkit.getEventsWithPredicate(predicate);
        const remainingOccurrences = verifyEvents.filter(e =>
          e.title === '[TEST RID DELETE] Recurring Event'
        );

        console.log(`Verification: ${remainingOccurrences.length} occurrences remain`);
        console.log(`Expected: ${testOccurrences.length - 1}`);
        console.log(`Match: ${remainingOccurrences.length === testOccurrences.length - 1 ? '✅' : '❌'}\n`);
      }
    }

    // Test Case 2: Delete using base ID (should delete master event)
    console.log('--- Test Case 2: Delete master event using base ID ---');

    const baseId = masterEventId;
    console.log(`Deleting master event: ${baseId}`);
    console.log(`Span: thisEvent (should delete just the master, but all occurrences will be gone)`);

    const deleteMasterResult = eventkit.removeEvent(baseId, 'thisEvent', true);

    console.log(`Delete result: ${deleteMasterResult ? '✅ SUCCESS' : '❌ FAILED'}\n`);

    if (deleteMasterResult) {
      // Verify all occurrences are gone
      await new Promise(resolve => setTimeout(resolve, 500));

      const verifyEvents = eventkit.getEventsWithPredicate(predicate);
      const remainingOccurrences = verifyEvents.filter(e =>
        e.title === '[TEST RID DELETE] Recurring Event'
      );

      console.log(`Verification: ${remainingOccurrences.length} occurrences remain`);
      console.log(`Expected: 0 (deleting master removes all occurrences)`);
      console.log(`All cleaned up: ${remainingOccurrences.length === 0 ? '✅' : '❌'}\n`);
    }

    console.log('=== Test Suite Complete ===\n');

  } catch (error) {
    console.error('Fatal error:', error);
  }
}

runTests();
