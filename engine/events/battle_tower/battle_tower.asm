Special_BattleTower_Battle:
	xor a
	ld [wBattleTowerBattleEnded], a
.loop
	call RunBattleTowerTrainer
	call DelayFrame
	ld a, [wBattleTowerBattleEnded]
	and a
	ret nz
	jr .loop

RunBattleTowerTrainer:
	ld a, [wOptions2]
	push af
	; force Set mode
	ld hl, wOptions2
	res BATTLE_SWITCH, [hl]
	res BATTLE_PREDICT, [hl]

	ld a, [wInBattleTowerBattle]
	push af
	or $1
	ld [wInBattleTowerBattle], a

	xor a
	ld [wLinkMode], a
	farcall HealPartyEvenForNuzlocke
	farcall PopulateBattleTowerTeam

	predef StartBattle

	farcall LoadPokemonData
	farcall HealPartyEvenForNuzlocke
	ld a, [wBattleResult]
	and a
	ld b, BTCHALLENGE_LOST
	jr nz, .got_result

	; Display awarded BP for the battle (saved after conclusion)
	call BT_GetCurTrainer
	farcall BT_GetPointsForTrainer
	add "0"
	ld hl, wStringBuffer1
	ld [hli], a
	ld [hl], "@"
	call BT_IncrementCurTrainer
	cp BATTLETOWER_STREAK_LENGTH
	ld b, BTCHALLENGE_WON
	jr z, .got_result

	; Convert total winstreak to determine next battle number
	inc a
	push af
	call BT_GetCurStreakAddr
	pop af
	inc hl
	add [hl]
	ld [wStringBuffer3 + 1], a
	dec hl
	ld a, [hl]
	adc 0
	ld [wStringBuffer3], a

	; Check if we're battling the Tycoon. If so, give a special msg.
	call BT_GetCurTrainerIndex
	cp BATTLETOWER_TYCOON
	ld b, BTCHALLENGE_TYCOON
	jr z, .got_result
	ld b, BTCHALLENGE_NEXT

.got_result
	ld a, b
	ldh [hScriptVar], a
	pop af
	ld [wInBattleTowerBattle], a
	pop af
	ld [wOptions2], a
	ld a, $1
	ld [wBattleTowerBattleEnded], a
	ret

Special_BattleTower_CommitChallengeResult:
; Commits battle result to game data, giving BP and updating streak data.
; Does not reset the challenge state, that is done by saving the game.
; This ensures that resetting the game doesn't annul this action.
; Returns true script-wise if we beat the Tycoon.
	; Award BP depending on how many trainers we defeated.

	; First byte is always zero (GiveBP wants a 2-byte parameter as input)
	xor a
	ld [wStringBuffer3], a

	call BT_GetCurTrainer
.bp_loop
	sub 1 ; no-optimize a++|a-- (dec a can't set carry)
	jr c, .bp_done
	push af
	farcall BT_GetPointsForTrainer
	ld bc, wStringBuffer3 + 1
	ld [bc], a
	dec bc
	farcall GiveBP
	pop af
	jr .bp_loop

.bp_done
	; Now, handle streak. Append defeated trainers to current winstreak.
	call BT_GetBothStreakAddr
	inc hl
	call BT_GetCurTrainer
	add [hl]
	ld [hld], a
	ld a, [hl]
	adc 0
	ld [hl], a

	; If this is a new record, update it.
	ld a, [de]
	cp [hl]
	ld a, [hli]
	jr nc, .no_new_hibyte_record
	ld [de], a
	inc de
	ld a, [hl]
	ld [de], a
	jr .record_done

.no_new_hibyte_record
	inc de
	ld a, [de]
	cp [hl]
	ld a, [hli]
	jr nc, .record_done
	ld [de], a

.record_done
	; Reset winstreak if we lost
	call BT_GetChallengeState
	cp BATTLETOWER_WON_CHALLENGE
	jr nz, .reset_streak

	; Figure out if we beat the Tycoon
	call BT_GetCurTrainer
	dec a
	call BT_GetTrainerIndex
	cp BATTLETOWER_TYCOON
	ld a, 0
	ldh [hScriptVar], a
	ret nz
	inc a
	ldh [hScriptVar], a
	ret

.reset_streak
	call BT_GetCurStreakAddr
	xor a
	ld [hli], a
	ld [hl], a
	ldh [hScriptVar], a
	ret

Special_BattleTower_GetChallengeState:
	call BT_GetChallengeState
	and a
	ldh [hScriptVar], a
	ret

BT_GetChallengeState:
; Returns the current challenge state for Battle Tower, or zero if none.
	call BT_GetTowerStatus
	ret c
	and BATTLETOWER_CHALLENGEMASK
	ret

BT_GetBattleMode:
	call BT_GetTowerStatus
	ret c
	and BATTLETOWER_MODEMASK
	ret

BT_GetTowerStatus:
; Check tower status (challenge state + battle mode). Returns:
; z|c: The save isn't ours (a=0)
; z|nc: No ongoing challenge (a=0)
; nz|nc: Challenge ongoing, with status in a (a=1+)
	call BT_CheckSaveOwnership
	scf
	ret z

	ld hl, sBattleTowerChallengeState
	ld a, BANK(sBattleTowerChallengeState)
	call GetSRAMBank
	ld a, [hl]
	and a
	jp CloseSRAM

Special_BattleTower_SetChallengeState:
	; Don't mess with BT state on a previously existing save.
	; The game should never try this, so crash if it does.
	call BT_GetTowerStatus
	ld a, ERR_BT_STATE
	jp c, Crash

	; Otherwise, go ahead and write the challenge state
	ldh a, [hScriptVar]
	; fallthrough
BT_SetChallengeState:
	and BATTLETOWER_CHALLENGEMASK
	ld c, a
	call BT_GetTowerStatus
	and ~BATTLETOWER_CHALLENGEMASK
	or c
	; fallthrough
BT_SetTowerStatus:
	ld c, a
	ld a, BANK(sBattleTowerChallengeState)
	call GetSRAMBank
	ld a, c
	ld [sBattleTowerChallengeState], a
	jp CloseSRAM

BT_SetBattleMode:
	and BATTLETOWER_MODEMASK
	ld c, a
	push bc
	call BT_GetTowerStatus
	pop bc
	and ~BATTLETOWER_MODEMASK
	or c
	jr BT_SetTowerStatus

Special_BattleTower_SetupRentalMode:
	ld a, BATTLETOWER_RENTALMODE
	call BT_SetBattleMode

	; Reset amount of battled trainers. Done in case we abort the initial
	; selection, which should reset our winstreak and not award any BP.
	ld a, BANK(sBT_CurTrainer)
	call GetSRAMBank
	xor a
	ld [sBT_CurTrainer], a
	jp CloseSRAM

Special_BattleTower_GenerateNextOpponent:
; Generates opponent team and, if this is the first battle, rental picks.
	; If this is the first battle, generate a new rental team.
	call BT_GetCurTrainer
	and a
	jr nz, .not_first_battle
	farcall NewRentalTeam
	jr .got_player_selections

.not_first_battle
	; Otherwise, copy last trainer into secondary party...
	ld a, BANK(sBT_OTMonParties)
	call GetSRAMBank

	ld hl, sBT_OTMonParty3
	ld de, wBT_SecondaryMonParty
	ld bc, BATTLETOWER_PARTYDATA_SIZE
	push bc
	rst CopyBytes

	; ...and copy current party stored in sram into player party.
	ld hl, sBT_MonParty
	ld de, sBT_MonParty
	pop bc
	rst CopyBytes
	call CloseSRAM

.got_player_selections
	; Now, generate a new opponent party.
	farjp GenerateOpponentTrainer

Special_BattleTower_NextRentalBattle:
	; Copy move name of first mon's first move, in case we want to reveal it.
	ld a, [wOTPartyMon1Moves]
	ld [wNamedObjectIndexBuffer], a
	call GetMoveName

	; Figure out how many details we want to reveal.
	ld a, [wBattleFactoryCurStreak]
	and a
	jr nz, .most_common_type
	ld a, [wBattleFactoryCurStreak + 1]
	ld b, 7
	sub b
	ld hl, .ExpectThese3
	jr c, .print
	sub b
	ld hl, .ExpectThese2
	jr c, .print
	sub b
	ld hl, .ExactMonUsingMove
	jr c, .print
	sub b
	ld hl, .SomeMonUsingMove
	jr c, .print

.most_common_type
	; TODO: figure out most common type.
	ld hl, .SomeMonUsingMove
.print
	call PrintText

	ld hl, .NewRentalsText
	call PrintText
	jp Special_BattleTower_SelectParticipants

.NewRentalsText:
	text "We'll hold your"
	line "#mon safe and"
	cont "offer you 6 rental"
	cont "#mon."

	para "Choose #mon"
	line "to enter."
	prompt

.ExpectThese3:
	text "You can expect to"
	line "see "
	text_ram wOTPartyMonNicknames
	text ","
	cont ""
	text_ram wOTPartyMonNicknames + MON_NAME_LENGTH
	text " and"
	cont ""
	text_ram wOTPartyMonNicknames + MON_NAME_LENGTH * 2
	text "."
	prompt

.ExpectThese2:
	text "You can expect to"
	line "see "
	text_ram wOTPartyMonNicknames
	text " and"
	cont ""
	text_ram wOTPartyMonNicknames + MON_NAME_LENGTH
	text "."
	prompt

.ExactMonUsingMove:
	text "You can expect to"
	line "see a "
	text_ram wOTPartyMonNicknames
	cont "with "
	text_ram wStringBuffer1
	text "."
	prompt

.SomeMonUsingMove:
	text "You can expect to"
	line "see a #mon"
	cont "with "
	text_ram wStringBuffer1
	text "."
	prompt

Special_BattleTower_SelectParticipants:
	; Clear old BT participants selection
	xor a
	ld [wBT_PartySelectCounter], a

	; Select 3 mons to enter
	farcall BT_PartySelect

	; Update script var so the scripting engine can make sense of the result
	ld hl, hScriptVar
	ld [hl], 0
	ret c
	inc [hl]
	ret

BT_CheckSaveOwnership:
; Returns z if the save isn't ours.
	ld a, [wSaveFileExists]
	and a
	ret z

	farcall CompareLoadedAndSavedPlayerID
	jr z, .yes
	xor a
	ret
.yes
	or 1
	ret

Special_BattleTower_MaxVolume:
	xor a
	ld [wMusicFade], a
	jp MaxVolume

Special_BattleTower_BeginChallenge:
; Initializes Battle Tower challenge data.
; possible future idea: occasional special trainers (leaders/etc) after tycoon?
	call BT_GetBattleMode
	push af

	; Commit party selection to SRAM in regular mode. Blank it in rental mode.
	ld a, BANK(sBT_PartySelections)
	call GetSRAMBank
	pop af
	cp BATTLETOWER_RENTALMODE
	ld hl, wBT_PartySelections
	ld de, sBT_PartySelections
	ld bc, PARTY_LENGTH
	push af
	call nz, CopyBytes
	ld bc, BATTLETOWER_PARTYDATA_SIZE
	ld h, d
	ld l, e
	pop af
	ld a, -1
	call z, ByteFill

	; Reset amount of battled trainers
	xor a
	ld [sBT_CurTrainer], a

	; Blank previously used opponent Pokémon
	ld a, -1
	ld hl, sBT_OTMonParties
	ld bc, BATTLETOWER_PARTYDATA_SIZE * BATTLETOWER_SAVEDPARTIES
	rst ByteFill

	; Generates a list of Trainers for the player to battle.
	ld b, 0
	ld de, sBTTrainers
.outer_loop
	; Generate a trainer
	ld a, BATTLETOWER_NUM_TRAINERS
	call RandomRange
	ld [de], a

	; Now iterate through what we already have to verify uniqueness.
	ld hl, sBTTrainers
	ld c, b
	inc c
.inner_loop
	dec c
	jr z, .next
	cp [hl]
	jr z, .outer_loop
	inc hl
	jr .inner_loop
.next
	inc de
	inc b
	ld a, b
	cp BATTLETOWER_STREAK_LENGTH
	jr nz, .outer_loop

	; Replace the 7th trainer with Tycoon every 3rd run
	push de
	call BT_GetCurStreakAddr
	ld a, [hli]
	ldh [hDividend], a
	ld a, [hl]
	ldh [hDividend + 1], a
	ld a, BATTLETOWER_STREAK_LENGTH * 3
	ldh [hDivisor], a
	ld b, 2
	call Divide

	; GetCurStreakAddr closes SRAM, so reopen it.
	ld a, BANK(sBTTrainers)
	call GetSRAMBank
	pop de
	ldh a, [hRemainder]
	cp BATTLETOWER_STREAK_LENGTH * 2
	jr nz, .close_sram
	dec de
	ld a, BATTLETOWER_TYCOON
	ld [de], a
.close_sram
	jp CloseSRAM

BT_GetBothStreakAddr:
; Sets hl to the streak address for the current battle mode and de to the top.
; Closes SRAM.
	call BT_GetCurStreakAddr
	call BT_GetBattleMode
	cp BATTLETOWER_RENTALMODE
	ld de, wBattleFactoryTopStreak
	ret z
	ld de, wBattleTowerTopStreak
	ret

BT_GetCurStreakAddr:
; Sets hl to the streak address for the current battle mode.
; Closes SRAM.
	call BT_GetBattleMode
	cp BATTLETOWER_RENTALMODE
	ld hl, wBattleFactoryCurStreak
	ret z
	ld hl, wBattleTowerCurStreak
	ret

BT_LoadPartySelections:
; Loads party selections from SRAM
	; Set amount of mons for battle
	ld a, 3
	ld [wBT_PartySelectCounter], a
	ld a, BANK(sBT_PartySelections)
	call GetSRAMBank
	ld hl, sBT_PartySelections
	ld de, wBT_PartySelections
	ld bc, PARTY_LENGTH
	rst CopyBytes
	jp CloseSRAM

BT_GetCurTrainer:
; Returns beaten trainers so far in a.
	ld a, BANK(sBT_CurTrainer)
	call GetSRAMBank
	ld a, [sBT_CurTrainer]
	jp CloseSRAM

BT_IncrementCurTrainer:
; Increments amount of beaten trainers so far and returns result in a.
	ld a, BANK(sBT_CurTrainer)
	call GetSRAMBank
	ld a, [sBT_CurTrainer]
	inc a
	ld [sBT_CurTrainer], a
	jp CloseSRAM

BT_GetCurTrainerIndex:
; Get trainer index for current trainer
	call BT_GetCurTrainer
	; fallthrough
BT_GetTrainerIndex:
	ld c, a
	ld a, BANK(sBTTrainers)
	call GetSRAMBank
	ld b, 0
	ld hl, sBTTrainers
	add hl, bc
	ld a, [hl]
	jp CloseSRAM

Special_BattleTower_LoadOpponentTrainerAndPokemonsWithOTSprite:
	call BT_GetCurTrainerIndex
	ld c, a
	ld b, 0

	push bc
	farcall WriteBattleTowerTrainerName
	pop bc
	ld c, a
	dec c
	ld hl, BTTrainerClassSprites
	add hl, bc
	ld a, [hl]
	ld [wBTTempOTSprite], a

	; Load sprite of the opponent trainer
	; because s/he is chosen randomly and appears out of nowhere
	ld [wMap1ObjectSprite], a
	ldh [hUsedSpriteIndex], a
	ld a, 24
	ldh [hUsedSpriteTile], a
	farjp GetUsedSprite

INCLUDE "data/trainers/sprites.asm"

BT_SetPlayerOT:
; Interprets the selected party mons for entering and populates wOTParty
; with the chosen Pokémon from the player. Used for 2 things: legality
; checking and to fix the party order according to player choices.
	; Number of party mons
	ld a, [wBT_PartySelectCounter]
	ld [wOTPartyCount], a

	; The rest is iterated
	ld bc, 0
	ld d, a
.loop
	; Party species array
	push de
	ld hl, wPartySpecies
	ld de, wOTPartySpecies
	ld a, 1 ; just a single byte to copy each iteration
	call .CopyPartyData

	; Main party struct
	ld hl, wPartyMons
	ld de, wOTPartyMons
	ld a, PARTYMON_STRUCT_LENGTH
	call .CopyPartyData

	; Nickname struct
	ld hl, wPartyMonNicknames
	ld de, wOTPartyMonNicknames
	ld a, MON_NAME_LENGTH
	call .CopyPartyData

	; OT name struct
	ld hl, wPartyMonOTs
	ld de, wOTPartyMonOTs
	ld a, NAME_LENGTH
	call .CopyPartyData

	; In rental mode, also copy party selection to SRAM
	push bc
	call BT_GetBattleMode
	pop bc
	cp BATTLETOWER_RENTALMODE
	jr nz, .not_rental
	ld a, BANK(sBT_MonParty)
	call GetSRAMBank
	ld hl, wBT_MonParty
	ld de, sBT_MonParty
	ld a, 2
	call .CopyPartyData
	call CloseSRAM
.not_rental
	pop de

	inc c
	ld a, c
	cp d
	jr nz, .loop

	; Add party species terminator, then we're done
	ld hl, wOTPartySpecies
	add hl, bc
	ld [hl], -1
	ret

.CopyPartyData:
; Copy a bytes from hl to de, with relative addresses depending on
; which mon we're currently working on. Preserves bc.
	; First, correct de to the current mon target index we're adding.
	; Just add a*bc (struct length * loop iterator)
	push hl
	ld h, d
	ld l, e
	push af
	rst AddNTimes
	pop af
	ld d, h
	ld e, l
	pop hl

	; Now, correct hl to the current mon source index.
	; Get the source index from party selection
	push bc
	push hl
	ld hl, wBT_PartySelections
	add hl, bc
	ld c, [hl] ; b always remains zero, no need to mess with it
	pop hl

	; Now bc holds party index, so we can AddNTimes like with de earlier
	push af
	rst AddNTimes
	pop af

	; Now copy the data
	ld c, a
	rst CopyBytes
	pop bc
	ret

BT_LegalityCheck:
; Check OT party for violations of Species or Item Clause. Used to verify
; both the player team when entering after copying to OT data, and the
; generated AI team. Returns z if the team is legal, otherwise nz and the error
; in e (1: 2+ share species, 2: 2+ share item)
; Species Clause: more than 1 Pokémon are the same species
; Item Clause: more than 1 Pokémon holds the same item
	ld a, [wOTPartyCount]
	ld e, a

	; Do nothing if we have no mons at all
	and a
	ret z

	; Nor if we have a single mon (since we have nothing to compare with)
	dec e
	ret z

	ld hl, wOTPartyMon1
.outer_loop
	push de
	ld c, [hl]
	ld a, MON_FORM
	call .GetPartyValue
	ld b, a
	ld a, MON_ITEM
	call .GetPartyValue
	ld d, a
	push hl
	call .NextPartyMon
.inner_loop
	; Compare species
	ld a, [hl]
	cp c
	jr nz, .species_not_identical

	; Compare extspecies
	ld a, MON_FORM
	call .GetPartyValue
	xor b
	and EXTSPECIES_MASK
	ld a, 1
	jr z, .identical

.species_not_identical
	ld a, MON_ITEM
	call .GetPartyValue

	; Allow several mons with no item
	and a
	jr z, .item_not_identical
	cp d
	ld a, 2
	jr z, .identical

.item_not_identical
	call .NextPartyMon
	dec e
	jr nz, .inner_loop
	pop hl
	call .NextPartyMon
	pop de
	dec e
	jr nz, .outer_loop
	ret

.identical
	pop hl
	pop de
	ld e, a
	and a
	ret

.NextPartyMon:
; Advance to next party mon.
	push bc
	ld bc, PARTYMON_STRUCT_LENGTH
	add hl, bc
	pop bc
	ret

.GetPartyValue:
; From party field in a, get value for current partymon in hl.
; Preserves hl.
	push hl
	add l
	ld l, a
	adc h
	sub l
	ld h, a
	ld a, [hl]
	pop hl
	ret
