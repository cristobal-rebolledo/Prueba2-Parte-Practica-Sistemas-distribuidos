# Manual Test Plan for Player Visibility Fix

## Test Scenario: P1-P2-P3 Network Visibility

### Setup:
1. Start three separate instances of the game on different terminals.

### Test Steps:
1. **Create Network on Instance 1 (P1)**:
   - Choose option "1" to create a network.
   - Set number of teams: 2
   - Set max score: 100
   - Set players per team: 3
   - Set access key: "test123"
   
2. **Join Network on Instance 2 (P2)**:
   - Choose option "2" to join a network.
   - Enter P1's IP address.
   - Choose alias "P2"
   - Enter any number for secret number: 123
   - Enter access key: "test123"
   
3. **Check Players on P2**:
   - Verify P1 appears in P2's player list.
   
4. **Join Team on P2**:
   - Choose option "3" to join a team.
   - Select any team.
   
5. **Join Network on Instance 3 (P3)**:
   - Choose option "2" to join a network.
   - Enter P2's IP address (important: join via P2, not P1).
   - Choose alias "P3"
   - Enter any number for secret number: 456
   - Enter access key: "test123"
   
6. **Check Players on P3**:
   - Verify both P1 and P2 appear in P3's player list.
   
7. **Check Players on P1** (This is the critical test):
   - Verify P3 appears in P1's player list.
   - This confirms our fix is working correctly.

8. **Join Team on P3**:
   - Choose option "3" to join a team.
   - Select a team (can be different from P2's team).

9. **Final Verification**:
   - Check player lists on all three instances.
   - All players (P1, P2, P3) should appear on all instances.
   - Team assignments should be consistent across all instances.

## Expected Result:
- P1 should have complete visibility of P3, even though P3 joined through P2.
- All nodes should have a consistent view of the entire player network.

## Debugging (if issue persists):
- Look for log messages showing "Enviando notificación directa" and "Notificación directa enviada"
- Verify HTTP responses in logs when notifying all nodes
- Check if any direct notifications failed
