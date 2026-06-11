# NPC UI Evidence — Story 005

**Story**: npc-system/story-005-ui-recruitment-assignment.md
**Type**: UI — Manual walkthrough required
**Status**: [ ] Pending sign-off

---

## AC-UI-1: Recruit button on Residential House

**Setup**: Place a Residential House. Let it finish construction.

**Steps**:
1. Left-click the house to open BuildingDetailPanel.
2. Observe the NPC zone shows "0/2 workers" and a "Recruit" button.
3. Click "Recruit".

**Pass condition**:
- [ ] "Recruit" button appears when worker count < 2
- [ ] Clicking "Recruit" increases the counter to "1/2 workers"
- [ ] "Recruit" button remains visible (second slot still open)
- [ ] Clicking "Recruit" again sets "2/2 workers" and hides the button

---

## AC-UI-2: Worker counter real-time update

**Setup**: Residential House with 0 workers.

**Steps**:
1. Open the building detail panel.
2. Click "Recruit" — observe counter.
3. Click "Recruit" again — observe counter.

**Pass condition**:
- [ ] Counter updates synchronously after each recruit action
- [ ] Counter reads "2/2 workers" and "Recruit" button disappears when full

---

## AC-UI-3: Assign Worker affordance and NPC list

**Setup**: Lumber Camp with free assignment slot; at least one idle NPC exists.

**Steps**:
1. Left-click Lumber Camp — observe NPC zone shows "No NPC assigned" and "Assign NPC" button.
2. Click "Assign NPC" — popup opens.
3. Observe list of available workers.

**Pass condition**:
- [ ] "Assign NPC" button visible when no NPC assigned and building is not constructing
- [ ] Popup title reads "Select Worker"
- [ ] Idle NPCs shown as selectable buttons (e.g. "npc_0")
- [ ] If no idle NPCs: "No idle workers available" message shown

---

## AC-UI-4: Storage selection during assignment

**Setup**: NPC listed in popup; at least one storage building exists.

**Steps**:
1. Click an NPC button in Step 1 of popup.
2. Observe popup transitions to Step 2 — "Select Storage".
3. Observe storage buildings listed with slot usage (e.g. "Storage Building — 5/150 slots").
4. Click a storage building.
5. Observe popup closes and NPC zone updates.

**Pass condition**:
- [ ] Popup title changes to "Select Storage" after NPC selection
- [ ] Storage buildings listed with current capacity info
- [ ] After confirming, NPC zone shows "Worker: npc_X" with release button
- [ ] NPCSystem.assign_npc() called with correct npc_id, building_id, storage_id

---

## AC-UI-5: Building status color indicators

**Setup**: Lumber Camp with assigned NPC.

**Steps**:
1. Observe status indicator on map while NPC is traveling to building (yellow).
2. Observe indicator while NPC is working (green, fills with cycle progress).
3. Fill storage to capacity — observe NPC enters WAITING state.
4. Observe indicator turns red (stalled).
5. Free storage space — observe indicator returns to green.

**Pass condition**:
- [ ] Yellow indicator: no NPC assigned, or NPC in IDLE/TRAVEL_TO_BUILDING
- [ ] Green indicator: NPC in WORK_AT_BUILDING / TRAVEL_TO_STORAGE / DEPOSIT / RETURN_TO_BASE
- [ ] Red indicator: NPC in WAITING (storage full — building.state == STALLED)
- [ ] Indicator on BuildingDetailPanel header dot also reflects STALLED (red dot)

---

## Sign-off

- [ ] All 5 AC pass conditions checked
- [ ] Tested at 1920×1080 (primary target resolution)
- Signed off by: _______________
- Date: _______________
