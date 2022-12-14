Attribute VB_Name = "modPlayer"
Option Explicit

Sub HandleUseChar(ByVal Index As Long)
    If Not IsPlaying(Index) Then
        Call JoinGame(Index)
        Call AddLog(GetPlayerLogin(Index) & "/" & GetPlayerName(Index) & " has began playing " & Options.Game_Name & ".", PLAYER_LOG)
        Call TextAdd(GetPlayerLogin(Index) & "/" & GetPlayerName(Index) & " has began playing " & Options.Game_Name & ".")
        Call UpdateCaption
    End If
End Sub

Sub JoinGame(ByVal Index As Long)
    Dim i As Long
    
    ' Set the flag so we know the person is in the game
    TempPlayer(Index).InGame = True
    'Update the log
    frmServer.lvwInfo.ListItems(Index).SubItems(1) = GetPlayerIP(Index)
    frmServer.lvwInfo.ListItems(Index).SubItems(2) = GetPlayerLogin(Index)
    frmServer.lvwInfo.ListItems(Index).SubItems(3) = GetPlayerName(Index)
    
    ' send the login ok
    SendLoginOk Index
    
    TotalPlayersOnline = TotalPlayersOnline + 1
    
    ' Send some more little goodies, no need to explain these
    Call CheckEquippedItems(Index)
    Call SendClasses(Index)
    Call SendItems(Index)
    Call SendNpcs(Index)
    Call SendShops(Index)
    Call SendSpells(Index)
    Call SendResources(Index)
    Call SendInventory(Index)
    Call SendWornEquipment(Index)
    Call SendMapEquipment(Index)
    Call SendPlayerSpells(Index)
    Call SendHotbar(Index)
    Call SendMoney(Index)
    Call SendQuests(Index)
    Call SendPlayerQuests(Index)
    
    ' send vitals, exp + stats
    For i = 1 To Vitals.Vital_Count - 1
        Call SendVital(Index, i)
    Next
    SendEXP Index
    Call SendStats(Index)
    
    ' Warp the player to his saved location
    Call PlayerWarp(Index, GetPlayerMap(Index), GetPlayerX(Index), GetPlayerY(Index))
    
    ' Send a global message that he/she joined
    If GetPlayerAccess(Index) <= ADMIN_MONITOR Then
        Call GlobalMsg(GetPlayerName(Index) & " entrou no " & Options.Game_Name & "!", JoinLeftColor)
    Else
        Call GlobalMsg(GetPlayerName(Index) & " entrou no " & Options.Game_Name & "!", White)
    End If
    
    ' Send welcome messages
    Call SendWelcome(Index)

    ' Send Resource cache
    For i = 0 To ResourceCache(GetPlayerMap(Index)).Resource_Count
        SendResourceCacheTo Index, i
    Next
    
    ' Send the flag so they know they can start doing stuff
    SendInGame Index
End Sub

Sub LeftGame(ByVal Index As Long)
    Dim n As Long, i As Long
    Dim tradeTarget As Long
    
    If TempPlayer(Index).InGame Then
        TempPlayer(Index).InGame = False

        ' Check if player was the only player on the map and stop npc processing if so
        If GetTotalMapPlayers(GetPlayerMap(Index)) < 1 Then
            PlayersOnMap(GetPlayerMap(Index)) = NO
        End If
        
        ' cancel any trade they're in
        If TempPlayer(Index).InTrade > 0 Then
            tradeTarget = TempPlayer(Index).InTrade
            PlayerMsg tradeTarget, Trim$(GetPlayerName(Index)) & " recusou a negocia??o.", BrightRed
            ' clear out trade
            For i = 1 To MAX_INV
                TempPlayer(tradeTarget).TradeOffer(i).Num = 0
                TempPlayer(tradeTarget).TradeOffer(i).Value = 0
            Next
            TempPlayer(tradeTarget).InTrade = 0
            SendCloseTrade tradeTarget
        End If
        
        ' leave party.
        Party_PlayerLeave Index

        ' save and clear data.
        Call SavePlayer(Index)
        Call SaveBank(Index)
        Call ClearBank(Index)

        ' Send a global message that he/she left
        If GetPlayerAccess(Index) <= ADMIN_MONITOR Then
            Call GlobalMsg(GetPlayerName(Index) & " saiu do " & Options.Game_Name & "!", JoinLeftColor)
        Else
            Call GlobalMsg(GetPlayerName(Index) & " saiu do " & Options.Game_Name & "!", White)
        End If

        Call TextAdd(GetPlayerName(Index) & " foi desconectado do " & Options.Game_Name & ".")
        Call SendLeftGame(Index)
        TotalPlayersOnline = TotalPlayersOnline - 1
    End If

    Call ClearPlayer(Index)
End Sub

Function GetPlayerProtection(ByVal Index As Long) As Long
    Dim Armor As Long
    Dim Helm As Long
    GetPlayerProtection = 0

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or Index <= 0 Or Index > Player_HighIndex Then
        Exit Function
    End If

    Armor = GetPlayerEquipment(Index, Armor)
    Helm = GetPlayerEquipment(Index, Helmet)
    GetPlayerProtection = (GetPlayerStat(Index, Stats.Endurance) \ 5)

    If Armor > 0 Then
        GetPlayerProtection = GetPlayerProtection + Item(Armor).Data2
    End If

    If Helm > 0 Then
        GetPlayerProtection = GetPlayerProtection + Item(Helm).Data2
    End If

End Function

Function CanPlayerCriticalHit(ByVal Index As Long) As Boolean
    On Error Resume Next
    Dim i As Long
    Dim n As Long

    If GetPlayerEquipment(Index, Weapon) > 0 Then
        n = (Rnd) * 2

        If n = 1 Then
            i = (GetPlayerStat(Index, Stats.Strength) \ 2) + (GetPlayerLevel(Index) \ 2)
            n = Int(Rnd * 100) + 1

            If n <= i Then
                CanPlayerCriticalHit = True
            End If
        End If
    End If

End Function

Function CanPlayerBlockHit(ByVal Index As Long) As Boolean
    Dim i As Long
    Dim n As Long
    Dim ShieldSlot As Long
    ShieldSlot = GetPlayerEquipment(Index, Shield)

    If ShieldSlot > 0 Then
        n = Int(Rnd * 2)

        If n = 1 Then
            i = (GetPlayerStat(Index, Stats.Endurance) \ 2) + (GetPlayerLevel(Index) \ 2)
            n = Int(Rnd * 100) + 1

            If n <= i Then
                CanPlayerBlockHit = True
            End If
        End If
    End If

End Function

Sub PlayerWarp(ByVal Index As Integer, ByVal mapNum As Byte, ByVal X As Integer, ByVal Y As Integer)
    Dim shopNum As Byte
    Dim OldMap As Byte
    Dim i As Integer
    Dim Buffer As clsBuffer

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or mapNum <= 0 Or mapNum > MAX_MAPS Then
        Exit Sub
    End If

    ' Check if you are out of bounds
    If X > Map(mapNum).MaxX Then X = Map(mapNum).MaxX
    If Y > Map(mapNum).MaxY Then Y = Map(mapNum).MaxY
    If X < 0 Then X = 0
    If Y < 0 Then Y = 0
    
    ' if same map then just send their co-ordinates
    If mapNum = GetPlayerMap(Index) Then
        SendPlayerXYToMap Index
        Call CheckTasks(Index, QUEST_TYPE_GOREACH, mapNum)
    End If
    
    TempPlayer(Index).EventProcessingCount = 0
    TempPlayer(Index).EventMap.CurrentEvents = 0
    
    ' clear target
    TempPlayer(Index).target = 0
    TempPlayer(Index).targetType = TARGET_TYPE_NONE
    SendTarget Index

    ' Save old map to send erase player data to
    OldMap = GetPlayerMap(Index)

    If OldMap <> mapNum Then
        Call SendLeaveMap(Index, OldMap)
    End If
    
    UpdateMapBlock OldMap, GetPlayerX(Index), GetPlayerY(Index), False
    Call SetPlayerMap(Index, mapNum)
    Call SetPlayerX(Index, X)
    Call SetPlayerY(Index, Y)
    UpdateMapBlock mapNum, X, Y, True
    
    ' send player's equipment to new map
    SendMapEquipment Index
    
    ' send equipment of all people on new map
    If GetTotalMapPlayers(mapNum) > 0 Then
        For i = 1 To Player_HighIndex
            If IsPlaying(i) Then
                If GetPlayerMap(i) = mapNum Then
                    SendMapEquipmentTo i, Index
                End If
            End If
        Next
    End If

    ' Now we check if there were any players left on the map the player just left, and if not stop processing npcs
    If GetTotalMapPlayers(OldMap) = 0 Then
        PlayersOnMap(OldMap) = NO

        ' Regenerate all NPCs' health
        For i = 1 To MAX_MAP_NPCS

            If MapNpc(OldMap).NPC(i).Num > 0 Then
                MapNpc(OldMap).NPC(i).Vital(Vitals.HP) = GetNpcMaxVital(MapNpc(OldMap).NPC(i).Num, Vitals.HP)
            End If

        Next

    End If

    ' Sets it so we know to process npcs on the map
    PlayersOnMap(mapNum) = YES
    TempPlayer(Index).GettingMap = YES
    Set Buffer = New clsBuffer
    Buffer.WriteLong SCheckForMap
    Buffer.WriteLong mapNum
    Buffer.WriteLong Map(mapNum).Revision
    SendDataTo Index, Buffer.ToArray()
    Set Buffer = Nothing
    
    ' ALATAR
    Call CheckTasks(Index, QUEST_TYPE_GOREACH, mapNum)
End Sub

Sub PlayerMove(ByVal Index As Long, ByVal Dir As Long, ByVal movement As Long, Optional ByVal sendToSelf As Boolean = False)
    Dim Buffer As clsBuffer, mapNum As Long, i As Long
    Dim X As Long, Y As Long
    Dim Moved As Byte, MovedSoFar As Boolean
    Dim NewMapX As Byte, NewMapY As Byte
    Dim TileType As Long, VitalType As Long, Colour As Long, Amount As Long, begineventprocessing As Boolean

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or Dir < DIR_UP Or Dir > DIR_RIGHT Or movement < 1 Or movement > 2 Then
        Exit Sub
    End If

    Call SetPlayerDir(Index, Dir)
    Moved = NO
    mapNum = GetPlayerMap(Index)
    
    Select Case Dir
        Case DIR_UP

            ' Check to make sure not outside of boundries
            If GetPlayerY(Index) > 0 Then

                ' Check to make sure that the tile is walkable
                If Not isDirBlocked(Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index)).DirBlock, DIR_UP + 1) Then
                    If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) - 1).Type <> TILE_TYPE_BLOCKED Then
                        If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) - 1).Type <> TILE_TYPE_RESOURCE Then
    
                            ' Check to see if the tile is a key and if it is check if its opened
                            If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) - 1).Type <> TILE_TYPE_KEY Or (Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) - 1).Type = TILE_TYPE_KEY And temptile(GetPlayerMap(Index)).DoorOpen(GetPlayerX(Index), GetPlayerY(Index) - 1) = YES) Then
                                Call SetPlayerY(Index, GetPlayerY(Index) - 1)
                                SendPlayerMove Index, movement, sendToSelf
                                Moved = YES
                            End If
                        End If
                    End If
                End If

            Else

                ' Check to see if we can move them to the another map
                If Map(GetPlayerMap(Index)).Up > 0 Then
                    NewMapY = Map(Map(GetPlayerMap(Index)).Up).MaxY
                    Call PlayerWarp(Index, Map(GetPlayerMap(Index)).Up, GetPlayerX(Index), NewMapY)
                    Moved = YES
                    ' clear their target
                    TempPlayer(Index).target = 0
                    TempPlayer(Index).targetType = TARGET_TYPE_NONE
                    SendTarget Index
                End If
            End If

        Case DIR_DOWN

            ' Check to make sure not outside of boundries
            If GetPlayerY(Index) < Map(mapNum).MaxY Then

                ' Check to make sure that the tile is walkable
                If Not isDirBlocked(Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index)).DirBlock, DIR_DOWN + 1) Then
                    If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) + 1).Type <> TILE_TYPE_BLOCKED Then
                        If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) + 1).Type <> TILE_TYPE_RESOURCE Then
    
                            ' Check to see if the tile is a key and if it is check if its opened
                            If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) + 1).Type <> TILE_TYPE_KEY Or (Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index) + 1).Type = TILE_TYPE_KEY And temptile(GetPlayerMap(Index)).DoorOpen(GetPlayerX(Index), GetPlayerY(Index) + 1) = YES) Then
                                Call SetPlayerY(Index, GetPlayerY(Index) + 1)
                                SendPlayerMove Index, movement, sendToSelf
                                Moved = YES
                            End If
                        End If
                    End If
                End If

            Else

                ' Check to see if we can move them to the another map
                If Map(GetPlayerMap(Index)).Down > 0 Then
                    Call PlayerWarp(Index, Map(GetPlayerMap(Index)).Down, GetPlayerX(Index), 0)
                    Moved = YES
                    ' clear their target
                    TempPlayer(Index).target = 0
                    TempPlayer(Index).targetType = TARGET_TYPE_NONE
                    SendTarget Index
                End If
            End If

        Case DIR_LEFT

            ' Check to make sure not outside of boundries
            If GetPlayerX(Index) > 0 Then

                ' Check to make sure that the tile is walkable
                If Not isDirBlocked(Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index)).DirBlock, DIR_LEFT + 1) Then
                    If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) - 1, GetPlayerY(Index)).Type <> TILE_TYPE_BLOCKED Then
                        If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) - 1, GetPlayerY(Index)).Type <> TILE_TYPE_RESOURCE Then
    
                            ' Check to see if the tile is a key and if it is check if its opened
                            If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) - 1, GetPlayerY(Index)).Type <> TILE_TYPE_KEY Or (Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) - 1, GetPlayerY(Index)).Type = TILE_TYPE_KEY And temptile(GetPlayerMap(Index)).DoorOpen(GetPlayerX(Index) - 1, GetPlayerY(Index)) = YES) Then
                                Call SetPlayerX(Index, GetPlayerX(Index) - 1)
                                SendPlayerMove Index, movement, sendToSelf
                                Moved = YES
                            End If
                        End If
                    End If
                End If

            Else

                ' Check to see if we can move them to the another map
                If Map(GetPlayerMap(Index)).Left > 0 Then
                    NewMapX = Map(Map(GetPlayerMap(Index)).Left).MaxX
                    Call PlayerWarp(Index, Map(GetPlayerMap(Index)).Left, NewMapX, GetPlayerY(Index))
                    Moved = YES
                    ' clear their target
                    TempPlayer(Index).target = 0
                    TempPlayer(Index).targetType = TARGET_TYPE_NONE
                    SendTarget Index
                End If
            End If

        Case DIR_RIGHT

            ' Check to make sure not outside of boundries
            If GetPlayerX(Index) < Map(mapNum).MaxX Then

                ' Check to make sure that the tile is walkable
                If Not isDirBlocked(Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index)).DirBlock, DIR_RIGHT + 1) Then
                    If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) + 1, GetPlayerY(Index)).Type <> TILE_TYPE_BLOCKED Then
                        If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) + 1, GetPlayerY(Index)).Type <> TILE_TYPE_RESOURCE Then
    
                            ' Check to see if the tile is a key and if it is check if its opened
                            If Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) + 1, GetPlayerY(Index)).Type <> TILE_TYPE_KEY Or (Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index) + 1, GetPlayerY(Index)).Type = TILE_TYPE_KEY And temptile(GetPlayerMap(Index)).DoorOpen(GetPlayerX(Index) + 1, GetPlayerY(Index)) = YES) Then
                                Call SetPlayerX(Index, GetPlayerX(Index) + 1)
                                SendPlayerMove Index, movement, sendToSelf
                                Moved = YES
                            End If
                        End If
                    End If
                End If
            Else
                ' Check to see if we can move them to the another map
                If Map(GetPlayerMap(Index)).Right > 0 Then
                    Call PlayerWarp(Index, Map(GetPlayerMap(Index)).Right, 0, GetPlayerY(Index))
                    Moved = YES
                    ' clear their target
                    TempPlayer(Index).target = 0
                    TempPlayer(Index).targetType = TARGET_TYPE_NONE
                    SendTarget Index
                End If
            End If
    End Select
    
    With Map(GetPlayerMap(Index)).Tile(GetPlayerX(Index), GetPlayerY(Index))
        ' Check to see if the tile is a warp tile, and if so warp them
        If .Type = TILE_TYPE_WARP Then
            mapNum = .Data1
            X = .Data2
            Y = .Data3
            Call PlayerWarp(Index, mapNum, X, Y)
            Moved = YES
        End If
    
        ' Check to see if the tile is a door tile, and if so warp them
        If .Type = TILE_TYPE_DOOR Then
            mapNum = .Data1
            X = .Data2
            Y = .Data3
            ' send the animation to the map
            SendDoorAnimation GetPlayerMap(Index), GetPlayerX(Index), GetPlayerY(Index)
            Call PlayerWarp(Index, mapNum, X, Y)
            Moved = YES
        End If
    
        ' Check for key trigger open
        If .Type = TILE_TYPE_KEYOPEN Then
            X = .Data1
            Y = .Data2
    
            If Map(GetPlayerMap(Index)).Tile(X, Y).Type = TILE_TYPE_KEY And temptile(GetPlayerMap(Index)).DoorOpen(X, Y) = NO Then
                temptile(GetPlayerMap(Index)).DoorOpen(X, Y) = YES
                temptile(GetPlayerMap(Index)).DoorTimer = GetTickCount
                SendMapKey Index, X, Y, 1
                Call MapMsg(GetPlayerMap(Index), "Essa porta est? fechada!", White)
            End If
        End If
        
        ' Check for a shop, and if so open it
        If .Type = TILE_TYPE_SHOP Then
            X = .Data1
            If X > 0 Then ' shop exists?
                If Len(Trim$(Shop(X).Name)) > 0 Then ' name exists?
                    SendOpenShop Index, X
                    TempPlayer(Index).InShop = X ' stops movement and the like
                End If
            End If
        End If
        
        ' Check to see if the tile is a bank, and if so send bank
        If .Type = TILE_TYPE_BANK Then
            SendBank Index
            TempPlayer(Index).InBank = True
            Moved = YES
        End If
        
        ' Check if it's a heal tile
        If .Type = TILE_TYPE_HEAL Then
            VitalType = .Data1
            Amount = .Data2
            If Not GetPlayerVital(Index, VitalType) = GetPlayerMaxVital(Index, VitalType) Then
                If VitalType = Vitals.HP Then
                    Colour = BrightGreen
                Else
                    Colour = BrightBlue
                End If
                SendActionMsg GetPlayerMap(Index), "+" & Amount, Colour, ACTIONMSG_SCROLL, GetPlayerX(Index) * 32, GetPlayerY(Index) * 32, 1
                SetPlayerVital Index, VitalType, GetPlayerVital(Index, VitalType) + Amount
                PlayerMsg Index, "Voc? sente for?as rejuvantes que fluem atrav?s de seu corpo.", BrightGreen
                Call SendVital(Index, VitalType)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
            End If
            Moved = YES
        End If
        
        ' Check if it's a trap tile
        If .Type = TILE_TYPE_TRAP Then
            Amount = .Data1
            SendActionMsg GetPlayerMap(Index), "-" & Amount, BrightRed, ACTIONMSG_SCROLL, GetPlayerX(Index) * 32, GetPlayerY(Index) * 32, 1
            If GetPlayerVital(Index, HP) - Amount <= 0 Then
                KillPlayer Index
                PlayerMsg Index, "Voc? foi morto por uma armadilha!", BrightRed
            Else
                SetPlayerVital Index, HP, GetPlayerVital(Index, HP) - Amount
                PlayerMsg Index, "Voc? est? ferido por uma armadilha.", BrightRed
                Call SendVital(Index, HP)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
            End If
            Moved = YES
        End If
        
                ' Slide
        If .Type = TILE_TYPE_SLIDE Then
            ForcePlayerMove Index, MOVING_WALKING, .Data1
            Moved = YES
        End If
    End With

    ' They tried to hack
    If Moved = NO Then
        PlayerWarp Index, GetPlayerMap(Index), GetPlayerX(Index), GetPlayerY(Index)
    End If
    
    X = GetPlayerX(Index)
    Y = GetPlayerY(Index)
    
    If Moved = YES Then
        If TempPlayer(Index).EventMap.CurrentEvents > 0 Then
            For i = 1 To TempPlayer(Index).EventMap.CurrentEvents
                If Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Global = 1 Then
                    If Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).X = X And Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Y = Y And Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Pages(TempPlayer(Index).EventMap.EventPages(i).pageID).Trigger = 1 And TempPlayer(Index).EventMap.EventPages(i).Visible = 1 Then begineventprocessing = True
                Else
                    If TempPlayer(Index).EventMap.EventPages(i).X = X And TempPlayer(Index).EventMap.EventPages(i).Y = Y And Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Pages(TempPlayer(Index).EventMap.EventPages(i).pageID).Trigger = 1 And TempPlayer(Index).EventMap.EventPages(i).Visible = 1 Then begineventprocessing = True
                End If
                If begineventprocessing = True Then
                    'Process this event, it is on-touch and everything checks out.
                    If Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Pages(TempPlayer(Index).EventMap.EventPages(i).pageID).CommandListCount > 0 Then
                        TempPlayer(Index).EventProcessingCount = TempPlayer(Index).EventProcessingCount + 1
                        ReDim Preserve TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount)
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).ActionTimer = GetTickCount
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).CurList = 1
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).CurSlot = 1
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).eventID = TempPlayer(Index).EventMap.EventPages(i).eventID
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).pageID = TempPlayer(Index).EventMap.EventPages(i).pageID
                        TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).WaitingForResponse = 0
                        ReDim TempPlayer(Index).EventProcessing(TempPlayer(Index).EventProcessingCount).ListLeftOff(0 To Map(GetPlayerMap(Index)).Events(TempPlayer(Index).EventMap.EventPages(i).eventID).Pages(TempPlayer(Index).EventMap.EventPages(i).pageID).CommandListCount)
                    End If
                    begineventprocessing = False
                End If
            Next
        End If
    End If

End Sub

Sub ForcePlayerMove(ByVal Index As Long, ByVal movement As Long, ByVal Direction As Long)
    If Direction < DIR_UP Or Direction > DIR_RIGHT Then Exit Sub
    If movement < 1 Or movement > 2 Then Exit Sub
    
    Select Case Direction
        Case DIR_UP
            If GetPlayerY(Index) = 0 Then Exit Sub
        Case DIR_LEFT
            If GetPlayerX(Index) = 0 Then Exit Sub
        Case DIR_DOWN
            If GetPlayerY(Index) = Map(GetPlayerMap(Index)).MaxY Then Exit Sub
        Case DIR_RIGHT
            If GetPlayerX(Index) = Map(GetPlayerMap(Index)).MaxX Then Exit Sub
    End Select
    
    PlayerMove Index, Direction, movement, True
End Sub

Sub CheckEquippedItems(ByVal Index As Long)
    Dim Slot As Long
    Dim itemnum As Long
    Dim i As Long

    ' We want to check incase an admin takes away an object but they had it equipped
    For i = 1 To Equipment.Equipment_Count - 1
        itemnum = GetPlayerEquipment(Index, i)

        If itemnum > 0 Then

            Select Case i
                Case Equipment.Weapon

                    If Item(itemnum).Type <> ITEM_TYPE_WEAPON Then SetPlayerEquipment Index, 0, i
                Case Equipment.Armor

                    If Item(itemnum).Type <> ITEM_TYPE_ARMOR Then SetPlayerEquipment Index, 0, i
                Case Equipment.Helmet

                    If Item(itemnum).Type <> ITEM_TYPE_HELMET Then SetPlayerEquipment Index, 0, i
                Case Equipment.Shield

                    If Item(itemnum).Type <> ITEM_TYPE_SHIELD Then SetPlayerEquipment Index, 0, i
            End Select

        Else
            SetPlayerEquipment Index, 0, i
        End If

    Next

End Sub

Function FindOpenInvSlot(ByVal Index As Long, ByVal itemnum As Long) As Long
    Dim i As Long

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or itemnum <= 0 Or itemnum > MAX_ITEMS Then
        Exit Function
    End If

    If Item(itemnum).Type = ITEM_TYPE_CURRENCY Then

        ' If currency then check to see if they already have an instance of the item and add it to that
        For i = 1 To MAX_INV

            If GetPlayerInvItemNum(Index, i) = itemnum Then
                FindOpenInvSlot = i
                Exit Function
            End If

        Next

    End If

    For i = 1 To MAX_INV

        ' Try to find an open free slot
        If GetPlayerInvItemNum(Index, i) = 0 Then
            FindOpenInvSlot = i
            Exit Function
        End If

    Next

End Function

Function FindOpenBankSlot(ByVal Index As Long, ByVal itemnum As Long) As Long
    Dim i As Long

    If Not IsPlaying(Index) Then Exit Function
    If itemnum <= 0 Or itemnum > MAX_ITEMS Then Exit Function

        For i = 1 To MAX_BANK
            If GetPlayerBankItemNum(Index, i) = itemnum Then
                FindOpenBankSlot = i
                Exit Function
            End If
        Next i

    For i = 1 To MAX_BANK
        If GetPlayerBankItemNum(Index, i) = 0 Then
            FindOpenBankSlot = i
            Exit Function
        End If
    Next i

End Function

Function HasItem(ByVal Index As Long, ByVal itemnum As Long) As Long
    Dim i As Long

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or itemnum <= 0 Or itemnum > MAX_ITEMS Then
        Exit Function
    End If

    For i = 1 To MAX_INV

        ' Check to see if the player has the item
        If GetPlayerInvItemNum(Index, i) = itemnum Then
            If Item(itemnum).Type = ITEM_TYPE_CURRENCY Then
                HasItem = GetPlayerInvItemValue(Index, i)
            Else
                HasItem = 1
            End If

            Exit Function
        End If

    Next

End Function

Function FindItem(ByVal Index As Long, ByVal itemnum As Long) As Long
    Dim i As Long

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or itemnum <= 0 Or itemnum > MAX_ITEMS Then
        Exit Function
    End If

    For i = 1 To MAX_INV

        ' Check to see if the player has the item
        If GetPlayerInvItemNum(Index, i) = itemnum Then
            FindItem = i
            Exit Function
        End If

    Next

End Function

Function TakeInvItem(ByVal Index As Long, ByVal itemnum As Long, ByVal ItemVal As Long) As Boolean
    Dim i As Long
    Dim n As Long
    
    TakeInvItem = False

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or itemnum <= 0 Or itemnum > MAX_ITEMS Then
        Exit Function
    End If

    For i = 1 To MAX_INV

        ' Check to see if the player has the item
        If GetPlayerInvItemNum(Index, i) = itemnum Then
            If Item(itemnum).Type = ITEM_TYPE_CURRENCY Then

                ' Is what we are trying to take away more then what they have?  If so just set it to zero
                If ItemVal >= GetPlayerInvItemValue(Index, i) Then
                    TakeInvItem = True
                Else
                    Call SetPlayerInvItemValue(Index, i, GetPlayerInvItemValue(Index, i) - ItemVal)
                    Call SendInventoryUpdate(Index, i)
                End If
            Else
                TakeInvItem = True
            End If

            If TakeInvItem Then
                Call SetPlayerInvItemNum(Index, i, 0)
                Call SetPlayerInvItemValue(Index, i, 0)
                ' Send the inventory update
                Call SendInventoryUpdate(Index, i)
                Exit Function
            End If
        End If

    Next

End Function

Function TakeInvSlot(ByVal Index As Long, ByVal invSlot As Long, ByVal ItemVal As Long) As Boolean
    Dim i As Long
    Dim n As Long
    Dim itemnum
    
    TakeInvSlot = False

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or invSlot <= 0 Or invSlot > MAX_ITEMS Then
        Exit Function
    End If
    
    itemnum = GetPlayerInvItemNum(Index, invSlot)

    If Item(itemnum).Type = ITEM_TYPE_CURRENCY Then

        ' Is what we are trying to take away more then what they have?  If so just set it to zero
        If ItemVal >= GetPlayerInvItemValue(Index, invSlot) Then
            TakeInvSlot = True
        Else
            Call SetPlayerInvItemValue(Index, invSlot, GetPlayerInvItemValue(Index, invSlot) - ItemVal)
        End If
    Else
        TakeInvSlot = True
    End If

    If TakeInvSlot Then
        Call SetPlayerInvItemNum(Index, invSlot, 0)
        Call SetPlayerInvItemValue(Index, invSlot, 0)
        Exit Function
    End If

End Function

Function GiveInvItem(ByVal Index As Long, ByVal itemnum As Long, ByVal ItemVal As Long, Optional ByVal sendupdate As Boolean = True) As Boolean
    Dim i As Long

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or itemnum <= 0 Or itemnum > MAX_ITEMS Then
        GiveInvItem = False
        Exit Function
    End If

    i = FindOpenInvSlot(Index, itemnum)

    ' Check to see if inventory is full
    If i <> 0 Then
        Call SetPlayerInvItemNum(Index, i, itemnum)
        Call SetPlayerInvItemValue(Index, i, GetPlayerInvItemValue(Index, i) + ItemVal)
        If sendupdate Then Call SendInventoryUpdate(Index, i)
        GiveInvItem = True
    Else
        Call PlayerMsg(Index, "Your inventory is full.", BrightRed)
        GiveInvItem = False
    End If

End Function

Function HasSpell(ByVal Index As Long, ByVal spellNum As Long) As Boolean
    Dim i As Long

    For i = 1 To MAX_PLAYER_SPELLS

        If GetPlayerSpell(Index, i) = spellNum Then
            HasSpell = True
            Exit Function
        End If

    Next

End Function

Function FindOpenSpellSlot(ByVal Index As Long) As Long
    Dim i As Long

    For i = 1 To MAX_PLAYER_SPELLS

        If GetPlayerSpell(Index, i) = 0 Then
            FindOpenSpellSlot = i
            Exit Function
        End If

    Next

End Function

Sub PlayerMapGetItem(ByVal Index As Long)
    Dim i As Long
    Dim n As Long
    Dim mapNum As Long
    Dim Msg As String

    If Not IsPlaying(Index) Then Exit Sub
    mapNum = GetPlayerMap(Index)

    For i = 1 To MAX_MAP_ITEMS
        ' See if theres even an item here
        If (MapItem(mapNum, i).Num > 0) And (MapItem(mapNum, i).Num <= MAX_ITEMS) Then
            ' our drop?
            If CanPlayerPickupItem(Index, i) Then
                ' Check if item is at the same location as the player
                If (MapItem(mapNum, i).X = GetPlayerX(Index)) Then
                    If (MapItem(mapNum, i).Y = GetPlayerY(Index)) Then
                        ' Find open slot
                        n = FindOpenInvSlot(Index, MapItem(mapNum, i).Num)
    
                        ' Open slot available?
                        If n <> 0 Then
                            ' Set item in players inventor
                            Call SetPlayerInvItemNum(Index, n, MapItem(mapNum, i).Num)
    
                            If Item(GetPlayerInvItemNum(Index, n)).Type = ITEM_TYPE_CURRENCY Then
                                Call SetPlayerInvItemValue(Index, n, GetPlayerInvItemValue(Index, n) + MapItem(mapNum, i).Value)
                                Msg = MapItem(mapNum, i).Value & " " & Trim$(Item(GetPlayerInvItemNum(Index, n)).Name)
                            Else
                                Call SetPlayerInvItemValue(Index, n, 0)
                                Msg = Trim$(Item(GetPlayerInvItemNum(Index, n)).Name)
                            End If
    
                            ' Erase item from the map
                            ClearMapItem i, mapNum
                            
                            Call SendInventoryUpdate(Index, n)
                            Call SpawnItemSlot(i, 0, 0, GetPlayerMap(Index), 0, 0)
                            SendActionMsg GetPlayerMap(Index), Msg, White, 1, (GetPlayerX(Index) * 32), (GetPlayerY(Index) * 32)
                            ' ALATAR
                            Call CheckTasks(Index, QUEST_TYPE_GOGATHER, GetItemNum(Trim$(Item(GetPlayerInvItemNum(Index, n)).Name)))
                            Exit For
                        Else
                            Call PlayerMsg(Index, "Your inventory is full.", BrightRed)
                            Exit For
                        End If
                    End If
                End If
            End If
        End If
    Next
End Sub

Function CanPlayerPickupItem(ByVal Index As Long, ByVal mapItemNum As Long)
Dim mapNum As Long

    mapNum = GetPlayerMap(Index)
    
    ' no lock or locked to player?
    If MapItem(mapNum, mapItemNum).playerName = vbNullString Or MapItem(mapNum, mapItemNum).playerName = Trim$(GetPlayerName(Index)) Then
        CanPlayerPickupItem = True
        Exit Function
    End If
    
    CanPlayerPickupItem = False
End Function

Sub PlayerMapDropItem(ByVal Index As Long, ByVal invNum As Long, ByVal Amount As Long)
    Dim i As Long

    ' Check for subscript out of range
    If IsPlaying(Index) = False Or invNum <= 0 Or invNum > MAX_INV Then
        Exit Sub
    End If
    
    ' check the player isn't doing something
    If TempPlayer(Index).InBank Or TempPlayer(Index).InShop Or TempPlayer(Index).InTrade > 0 Then Exit Sub

    If (GetPlayerInvItemNum(Index, invNum) > 0) Then
        If (GetPlayerInvItemNum(Index, invNum) <= MAX_ITEMS) Then
            i = FindOpenMapItemSlot(GetPlayerMap(Index))

            If i <> 0 Then
                MapItem(GetPlayerMap(Index), i).Num = GetPlayerInvItemNum(Index, invNum)
                MapItem(GetPlayerMap(Index), i).X = GetPlayerX(Index)
                MapItem(GetPlayerMap(Index), i).Y = GetPlayerY(Index)
                MapItem(GetPlayerMap(Index), i).playerName = Trim$(GetPlayerName(Index))
                MapItem(GetPlayerMap(Index), i).playerTimer = GetTickCount + ITEM_SPAWN_TIME
                MapItem(GetPlayerMap(Index), i).canDespawn = True
                MapItem(GetPlayerMap(Index), i).despawnTimer = GetTickCount + ITEM_DESPAWN_TIME

                If Item(GetPlayerInvItemNum(Index, invNum)).Type = ITEM_TYPE_CURRENCY Then

                    ' Check if its more then they have and if so drop it all
                    If Amount >= GetPlayerInvItemValue(Index, invNum) Then
                        MapItem(GetPlayerMap(Index), i).Value = GetPlayerInvItemValue(Index, invNum)
                        Call MapMsg(GetPlayerMap(Index), GetPlayerName(Index) & " drops " & GetPlayerInvItemValue(Index, invNum) & " " & Trim$(Item(GetPlayerInvItemNum(Index, invNum)).Name) & ".", Yellow)
                        Call SetPlayerInvItemNum(Index, invNum, 0)
                        Call SetPlayerInvItemValue(Index, invNum, 0)
                    Else
                        MapItem(GetPlayerMap(Index), i).Value = Amount
                        Call MapMsg(GetPlayerMap(Index), GetPlayerName(Index) & " drops " & Amount & " " & Trim$(Item(GetPlayerInvItemNum(Index, invNum)).Name) & ".", Yellow)
                        Call SetPlayerInvItemValue(Index, invNum, GetPlayerInvItemValue(Index, invNum) - Amount)
                    End If

                Else
                    ' Its not a currency object so this is easy
                    MapItem(GetPlayerMap(Index), i).Value = 0
                    ' send message
                    Call MapMsg(GetPlayerMap(Index), GetPlayerName(Index) & " drops " & CheckGrammar(Trim$(Item(GetPlayerInvItemNum(Index, invNum)).Name)) & ".", Yellow)
                    Call SetPlayerInvItemNum(Index, invNum, 0)
                    Call SetPlayerInvItemValue(Index, invNum, 0)
                End If

                ' Send inventory update
                Call SendInventoryUpdate(Index, invNum)
                ' Spawn the item before we set the num or we'll get a different free map item slot
                Call SpawnItemSlot(i, MapItem(GetPlayerMap(Index), i).Num, Amount, GetPlayerMap(Index), GetPlayerX(Index), GetPlayerY(Index), Trim$(GetPlayerName(Index)), MapItem(GetPlayerMap(Index), i).canDespawn)
            Else
                Call PlayerMsg(Index, "Too many items already on the ground.", BrightRed)
            End If
        End If
    End If

End Sub

Sub CheckPlayerLevelUp(ByVal Index As Long)
    Dim i As Long
    Dim expRollover As Long
    Dim level_count As Long
    
    level_count = 0
    
    Do While GetPlayerExp(Index) >= GetPlayerNextLevel(Index)
        expRollover = GetPlayerExp(Index) - GetPlayerNextLevel(Index)
        
        ' can level up?
        If Not SetPlayerLevel(Index, GetPlayerLevel(Index) + 1) Then
            Exit Sub
        End If
        
        Call SetPlayerPOINTS(Index, GetPlayerPOINTS(Index) + 3)
        Call SetPlayerExp(Index, expRollover)
        level_count = level_count + 1
    Loop
    
    If level_count > 0 Then
        If level_count = 1 Then
            'singular
            GlobalMsg GetPlayerName(Index) & " has gained " & level_count & " level!", Brown
        Else
            'plural
            GlobalMsg GetPlayerName(Index) & " has gained " & level_count & " levels!", Brown
        End If
        SendEXP Index
        SendPlayerData Index
    End If
End Sub

' //////////////////////
' // PLAYER FUNCTIONS //
' //////////////////////
Function GetPlayerLogin(ByVal Index As Long) As String
    GetPlayerLogin = Trim$(Player(Index).Login)
End Function

Sub SetPlayerLogin(ByVal Index As Long, ByVal Login As String)
    Player(Index).Login = Login
End Sub

Function GetPlayerPassword(ByVal Index As Long) As String
    GetPlayerPassword = Trim$(Player(Index).Password)
End Function

Sub SetPlayerPassword(ByVal Index As Integer, ByVal Password As String)
    Player(Index).Password = Password
End Sub

Function GetPlayerName(ByVal Index As Integer) As String

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerName = Trim$(Player(Index).Name)
End Function

Sub SetPlayerName(ByVal Index As Integer, ByVal Name As String)
    Player(Index).Name = Name
End Sub

Function GetPlayerClass(ByVal Index As Integer) As Long
    GetPlayerClass = Player(Index).Class
End Function

Sub SetPlayerClass(ByVal Index As Integer, ByVal ClassNum As Byte)
    Player(Index).Class = ClassNum
End Sub

Function GetPlayerSprite(ByVal Index As Integer) As Integer

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerSprite = Player(Index).Sprite
End Function

Sub SetPlayerSprite(ByVal Index As Integer, ByVal Sprite As Integer)
    Player(Index).Sprite = Sprite
End Sub

Function GetPlayerMoney(ByVal Index As Integer) As Long
    If Index > MAX_PLAYERS Then Exit Function
    
    GetPlayerMoney = Player(Index).Money
End Function

Sub SetPlayerMoney(ByVal Index As Integer, ByVal Money As Long)
    Player(Index).Money = Money
End Sub

Function GetPlayerLevel(ByVal Index As Long) As Long

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerLevel = Player(Index).Level
End Function

Function SetPlayerLevel(ByVal Index As Integer, ByVal Level As Long) As Boolean
    SetPlayerLevel = False
    If Level > MAX_LEVELS Then Exit Function
    Player(Index).Level = Level
    SetPlayerLevel = True
End Function

Function GetPlayerNextLevel(ByVal Index As Integer) As Long
    GetPlayerNextLevel = (50 / 3) * ((GetPlayerLevel(Index) + 1) ^ 3 - (6 * (GetPlayerLevel(Index) + 1) ^ 2) + 17 * (GetPlayerLevel(Index) + 1) - 12)
End Function

Function GetPlayerExp(ByVal Index As Long) As Long
    GetPlayerExp = Player(Index).Exp
End Function

Sub SetPlayerExp(ByVal Index As Integer, ByVal Exp As Long)
    Player(Index).Exp = Exp
    If GetPlayerLevel(Index) = MAX_LEVELS And Player(Index).Exp > GetPlayerNextLevel(Index) Then
        Player(Index).Exp = GetPlayerNextLevel(Index)
    End If
End Sub

Function GetPlayerAccess(ByVal Index As Integer) As Byte
    If Index > MAX_PLAYERS Then Exit Function
    
    GetPlayerAccess = Player(Index).Access
End Function

Sub SetPlayerAccess(ByVal Index As Integer, ByVal Access As Byte)
    Player(Index).Access = Access
End Sub

Function GetPlayerPK(ByVal Index As Long) As Byte

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerPK = Player(Index).PK
End Function

Sub SetPlayerPK(ByVal Index As Integer, ByVal PK As Byte)
    Player(Index).PK = PK
End Sub

Function GetPlayerVital(ByVal Index As Integer, ByVal Vital As Vitals) As Long
    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerVital = Player(Index).Vital(Vital)
End Function

Sub SetPlayerVital(ByVal Index As Integer, ByVal Vital As Vitals, ByVal Value As Long)
    Player(Index).Vital(Vital) = Value

    If GetPlayerVital(Index, Vital) > GetPlayerMaxVital(Index, Vital) Then
        Player(Index).Vital(Vital) = GetPlayerMaxVital(Index, Vital)
    End If

    If GetPlayerVital(Index, Vital) < 0 Then
        Player(Index).Vital(Vital) = 0
    End If

End Sub

Public Function GetPlayerStat(ByVal Index As Integer, ByVal Stat As Stats) As Integer
    Dim X As Long, i As Long
    If Index > MAX_PLAYERS Then Exit Function
    
    X = Player(Index).Stat(Stat)
    
    For i = 1 To Equipment.Equipment_Count - 1
        If GetPlayerEquipment(Index, i) > 0 Then
            If Item(GetPlayerEquipment(Index, i)).Add_Stat(Stat) > 0 Then
                X = X + Item(GetPlayerEquipment(Index, i)).Add_Stat(Stat)
            End If
        End If
    Next
    
    GetPlayerStat = X
End Function

Public Function GetPlayerRawStat(ByVal Index As Integer, ByVal Stat As Stats) As Integer
    If Index > MAX_PLAYERS Then Exit Function
    
    GetPlayerRawStat = Player(Index).Stat(Stat)
End Function

Public Sub SetPlayerStat(ByVal Index As Integer, ByVal Stat As Stats, ByVal Value As Integer)
    Player(Index).Stat(Stat) = Value
End Sub

Function GetPlayerPOINTS(ByVal Index As Integer) As Integer

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerPOINTS = Player(Index).POINTS
End Function

Sub SetPlayerPOINTS(ByVal Index As Integer, ByVal POINTS As Integer)
    If POINTS <= 0 Then POINTS = 0
    Player(Index).POINTS = POINTS
End Sub

Function GetPlayerMap(ByVal Index As Integer) As Integer

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerMap = Player(Index).Map
End Function

Sub SetPlayerMap(ByVal Index As Integer, ByVal mapNum As Integer)

    If mapNum > 0 And mapNum <= MAX_MAPS Then
        Player(Index).Map = mapNum
    End If

End Sub

Function GetPlayerX(ByVal Index As Long) As Long

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerX = Player(Index).X
End Function

Sub SetPlayerX(ByVal Index As Long, ByVal X As Long)
    Player(Index).X = X
End Sub

Function GetPlayerY(ByVal Index As Long) As Long

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerY = Player(Index).Y
End Function

Sub SetPlayerY(ByVal Index As Long, ByVal Y As Long)
    Player(Index).Y = Y
End Sub

Function GetPlayerDir(ByVal Index As Long) As Long

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerDir = Player(Index).Dir
End Function

Sub SetPlayerDir(ByVal Index As Long, ByVal Dir As Long)
    Player(Index).Dir = Dir
End Sub

Function GetPlayerIP(ByVal Index As Long) As String

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerIP = frmServer.Socket(Index).RemoteHostIP
End Function

Function GetPlayerInvItemNum(ByVal Index As Long, ByVal invSlot As Long) As Long
    If Index > MAX_PLAYERS Then Exit Function
    If invSlot = 0 Then Exit Function
    
    GetPlayerInvItemNum = Player(Index).Inv(invSlot).Num
End Function

Sub SetPlayerInvItemNum(ByVal Index As Long, ByVal invSlot As Long, ByVal itemnum As Long)
    Player(Index).Inv(invSlot).Num = itemnum
End Sub

Function GetPlayerInvItemValue(ByVal Index As Long, ByVal invSlot As Long) As Long

    If Index > MAX_PLAYERS Then Exit Function
    GetPlayerInvItemValue = Player(Index).Inv(invSlot).Value
End Function

Sub SetPlayerInvItemValue(ByVal Index As Long, ByVal invSlot As Long, ByVal ItemValue As Long)
    Player(Index).Inv(invSlot).Value = ItemValue
End Sub

Function GetPlayerSpell(ByVal Index As Long, ByVal spellSlot As Byte) As Integer
    ' Prevenir Erros
    If Index <= 0 Or Index > MAX_PLAYERS Then Exit Function
    
    GetPlayerSpell = Player(Index).Spell(spellSlot).Num
End Function

Sub SetPlayerSpell(ByVal Index As Integer, ByVal spellSlot As Byte, ByVal spellNum As Integer)
    ' Prevenir Erros
    If Index <= 0 Or Index > MAX_PLAYERS Then Exit Sub
    
    Player(Index).Spell(spellSlot).Num = spellNum
End Sub

Function GetPlayerSpellLevel(ByVal Index As Integer, ByVal spellSlot As Byte) As Byte
    ' Prevenir Erros
    If Index <= 0 Or Index > MAX_PLAYERS Then Exit Function
    
    GetPlayerSpellLevel = Player(Index).Spell(spellSlot).Level
End Function

Sub SetPlayerSpellLevel(ByVal Index As Integer, ByVal spellSlot As Byte, ByVal LevelNum As Byte)
    ' Prevenir Erros
    If Index <= 0 Or Index > MAX_PLAYERS Then Exit Sub
    
    Player(Index).Spell(spellSlot).Level = LevelNum
End Sub

Function GetPlayerEquipment(ByVal Index As Integer, ByVal EquipmentSlot As Equipment) As Integer
    If Index > MAX_PLAYERS Then Exit Function
    
    If EquipmentSlot = 0 Then Exit Function
    
    GetPlayerEquipment = Player(Index).Equipment(EquipmentSlot).Num
End Function

Sub SetPlayerEquipment(ByVal Index As Integer, ByVal invNum As Integer, ByVal EquipmentSlot As Equipment)
    Player(Index).Equipment(EquipmentSlot).Num = invNum
End Sub

Function GetPlayerEquipmentEnhancement(ByVal Index As Integer, ByVal EquipmentSlot As Equipment) As Byte
    If Index > MAX_PLAYERS Then Exit Function
    
    If EquipmentSlot = 0 Then Exit Function
    
    GetPlayerEquipmentEnhancement = Player(Index).Equipment(EquipmentSlot).Enhancement
End Function

Sub SetPlayerEquipmentEnhancement(ByVal Index As Integer, ByVal numLevel As Byte, ByVal EquipmentSlot As Equipment)
    Player(Index).Equipment(EquipmentSlot).Enhancement = numLevel
End Sub

' ToDo
Sub OnDeath(ByVal Index As Integer)
    Dim i As Long
    
    ' Set HP to nothing
    Call SetPlayerVital(Index, Vitals.HP, 0)

    ' Drop all worn items
    For i = 1 To Equipment.Equipment_Count - 1
        If GetPlayerEquipment(Index, i) > 0 Then
            PlayerMapDropItem Index, GetPlayerEquipment(Index, i), 0
        End If
    Next

    ' Warp player away
    Call SetPlayerDir(Index, DIR_DOWN)
    
    With Map(GetPlayerMap(Index))
        ' to the bootmap if it is set
        If .BootMap > 0 Then
            PlayerWarp Index, .BootMap, .BootX, .BootY
        Else
            Call PlayerWarp(Index, START_MAP, START_X, START_Y)
        End If
    End With
    
    ' clear all DoTs and HoTs
    For i = 1 To MAX_DOTS
        With TempPlayer(Index).DoT(i)
            .Used = False
            .Spell = 0
            .Timer = 0
            .Caster = 0
            .StartTime = 0
        End With
        
        With TempPlayer(Index).HoT(i)
            .Used = False
            .Spell = 0
            .Timer = 0
            .Caster = 0
            .StartTime = 0
        End With
    Next
    
    ' Clear spell casting
    TempPlayer(Index).spellBuffer.Spell = 0
    TempPlayer(Index).spellBuffer.Timer = 0
    TempPlayer(Index).spellBuffer.target = 0
    TempPlayer(Index).spellBuffer.tType = 0
    Call SendClearSpellBuffer(Index)
    
    ' Restore vitals
    Call SetPlayerVital(Index, Vitals.HP, GetPlayerMaxVital(Index, Vitals.HP))
    Call SetPlayerVital(Index, Vitals.MP, GetPlayerMaxVital(Index, Vitals.MP))
    Call SendVital(Index, Vitals.HP)
    Call SendVital(Index, Vitals.MP)
    ' send vitals to party if in one
    If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index

    ' If the player the attacker killed was a pk then take it away
    If GetPlayerPK(Index) = YES Then
        Call SetPlayerPK(Index, NO)
        Call SendPlayerData(Index)
    End If

End Sub

Sub CheckResource(ByVal Index As Long, ByVal X As Long, ByVal Y As Long)
    Dim Resource_num As Long
    Dim Resource_index As Long
    Dim rX As Long, rY As Long
    Dim i As Long
    Dim Damage As Long
    
    If Map(GetPlayerMap(Index)).Tile(X, Y).Type = TILE_TYPE_RESOURCE Then
        Resource_num = 0
        Resource_index = Map(GetPlayerMap(Index)).Tile(X, Y).Data1

        ' Get the cache number
        For i = 0 To ResourceCache(GetPlayerMap(Index)).Resource_Count

            If ResourceCache(GetPlayerMap(Index)).ResourceData(i).X = X Then
                If ResourceCache(GetPlayerMap(Index)).ResourceData(i).Y = Y Then
                    Resource_num = i
                End If
            End If

        Next

        If Resource_num > 0 Then
            If GetPlayerEquipment(Index, Weapon) > 0 Then
                If Item(GetPlayerEquipment(Index, Weapon)).Data3 = Resource(Resource_index).ToolRequired Then

                    ' inv space?
                    If Resource(Resource_index).ItemReward > 0 Then
                        If FindOpenInvSlot(Index, Resource(Resource_index).ItemReward) = 0 Then
                            PlayerMsg Index, "You have no inventory space.", BrightRed
                            Exit Sub
                        End If
                    End If

                    ' check if already cut down
                    If ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).ResourceState = 0 Then
                    
                        rX = ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).X
                        rY = ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).Y
                        
                        Damage = Item(GetPlayerEquipment(Index, Weapon)).Data2
                    
                        ' check if damage is more than health
                        If Damage > 0 Then
                            ' cut it down!
                            If ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).cur_health - Damage <= 0 Then
                                SendActionMsg GetPlayerMap(Index), "-" & ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).cur_health, BrightRed, 1, (rX * 32), (rY * 32)
                                ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).ResourceState = 1 ' Cut
                                ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).ResourceTimer = GetTickCount
                                SendResourceCacheToMap GetPlayerMap(Index), Resource_num
                                ' send message if it exists
                                If Len(Trim$(Resource(Resource_index).SuccessMessage)) > 0 Then
                                    SendActionMsg GetPlayerMap(Index), Trim$(Resource(Resource_index).SuccessMessage), BrightGreen, 1, (GetPlayerX(Index) * 32), (GetPlayerY(Index) * 32)
                                End If
                                ' carry on
                                GiveInvItem Index, Resource(Resource_index).ItemReward, 1
                                SendAnimation GetPlayerMap(Index), Resource(Resource_index).Animation, rX, rY
                            Else
                                ' just do the damage
                                ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).cur_health = ResourceCache(GetPlayerMap(Index)).ResourceData(Resource_num).cur_health - Damage
                                SendActionMsg GetPlayerMap(Index), "-" & Damage, BrightRed, 1, (rX * 32), (rY * 32)
                                SendAnimation GetPlayerMap(Index), Resource(Resource_index).Animation, rX, rY
                            End If
                            ' send the sound
                            SendMapSound Index, rX, rY, SoundEntity.seResource, Resource_index
                            ' ALATAR
                            Call CheckTasks(Index, QUEST_TYPE_GOTRAIN, Resource_index)
                        Else
                            ' too weak
                            SendActionMsg GetPlayerMap(Index), "Miss!", BrightRed, 1, (rX * 32), (rY * 32)
                        End If
                    Else
                        ' send message if it exists
                        If Len(Trim$(Resource(Resource_index).EmptyMessage)) > 0 Then
                            SendActionMsg GetPlayerMap(Index), Trim$(Resource(Resource_index).EmptyMessage), BrightRed, 1, (GetPlayerX(Index) * 32), (GetPlayerY(Index) * 32)
                        End If
                    End If

                Else
                    PlayerMsg Index, "You have the wrong type of tool equiped.", BrightRed
                End If

            Else
                PlayerMsg Index, "You need a tool to interact with this resource.", BrightRed
            End If
        End If
    End If
End Sub

Function GetPlayerBankItemNum(ByVal Index As Long, ByVal BankSlot As Long) As Long
    GetPlayerBankItemNum = Bank(Index).Item(BankSlot).Num
End Function

Sub SetPlayerBankItemNum(ByVal Index As Long, ByVal BankSlot As Long, ByVal itemnum As Long)
    Bank(Index).Item(BankSlot).Num = itemnum
End Sub

Function GetPlayerBankItemValue(ByVal Index As Long, ByVal BankSlot As Long) As Long
    GetPlayerBankItemValue = Bank(Index).Item(BankSlot).Value
End Function

Sub SetPlayerBankItemValue(ByVal Index As Long, ByVal BankSlot As Long, ByVal ItemValue As Long)
    Bank(Index).Item(BankSlot).Value = ItemValue
End Sub

Sub GiveBankItem(ByVal Index As Long, ByVal invSlot As Long, ByVal Amount As Long)
Dim BankSlot

    If invSlot < 0 Or invSlot > MAX_INV Then
        Exit Sub
    End If
    
    If Amount < 0 Or Amount > GetPlayerInvItemValue(Index, invSlot) Then
        Exit Sub
    End If
    
    BankSlot = FindOpenBankSlot(Index, GetPlayerInvItemNum(Index, invSlot))
        
    If BankSlot > 0 Then
        If Item(GetPlayerInvItemNum(Index, invSlot)).Type = ITEM_TYPE_CURRENCY Then
            If GetPlayerBankItemNum(Index, BankSlot) = GetPlayerInvItemNum(Index, invSlot) Then
                Call SetPlayerBankItemValue(Index, BankSlot, GetPlayerBankItemValue(Index, BankSlot) + Amount)
                Call TakeInvItem(Index, GetPlayerInvItemNum(Index, invSlot), Amount)
            Else
                Call SetPlayerBankItemNum(Index, BankSlot, GetPlayerInvItemNum(Index, invSlot))
                Call SetPlayerBankItemValue(Index, BankSlot, Amount)
                Call TakeInvItem(Index, GetPlayerInvItemNum(Index, invSlot), Amount)
            End If
        Else
            If GetPlayerBankItemNum(Index, BankSlot) = GetPlayerInvItemNum(Index, invSlot) Then
                Call SetPlayerBankItemValue(Index, BankSlot, GetPlayerBankItemValue(Index, BankSlot) + 1)
                Call TakeInvItem(Index, GetPlayerInvItemNum(Index, invSlot), 0)
            Else
                Call SetPlayerBankItemNum(Index, BankSlot, GetPlayerInvItemNum(Index, invSlot))
                Call SetPlayerBankItemValue(Index, BankSlot, 1)
                Call TakeInvItem(Index, GetPlayerInvItemNum(Index, invSlot), 0)
            End If
        End If
    End If
    
    SaveBank Index
    SavePlayer Index
    SendBank Index

End Sub

Sub TakeBankItem(ByVal Index As Long, ByVal BankSlot As Long, ByVal Amount As Long)
Dim invSlot

    If BankSlot < 0 Or BankSlot > MAX_BANK Then
        Exit Sub
    End If
    
    If Amount < 0 Or Amount > GetPlayerBankItemValue(Index, BankSlot) Then
        Exit Sub
    End If
    
    invSlot = FindOpenInvSlot(Index, GetPlayerBankItemNum(Index, BankSlot))
        
    If invSlot > 0 Then
        If Item(GetPlayerBankItemNum(Index, BankSlot)).Type = ITEM_TYPE_CURRENCY Then
            Call GiveInvItem(Index, GetPlayerBankItemNum(Index, BankSlot), Amount)
            Call SetPlayerBankItemValue(Index, BankSlot, GetPlayerBankItemValue(Index, BankSlot) - Amount)
            If GetPlayerBankItemValue(Index, BankSlot) <= 0 Then
                Call SetPlayerBankItemNum(Index, BankSlot, 0)
                Call SetPlayerBankItemValue(Index, BankSlot, 0)
            End If
        Else
            If GetPlayerBankItemValue(Index, BankSlot) > 1 Then
                Call GiveInvItem(Index, GetPlayerBankItemNum(Index, BankSlot), 0)
                Call SetPlayerBankItemValue(Index, BankSlot, GetPlayerBankItemValue(Index, BankSlot) - 1)
            Else
                Call GiveInvItem(Index, GetPlayerBankItemNum(Index, BankSlot), 0)
                Call SetPlayerBankItemNum(Index, BankSlot, 0)
                Call SetPlayerBankItemValue(Index, BankSlot, 0)
            End If
        End If
    End If
    
    SaveBank Index
    SavePlayer Index
    SendBank Index

End Sub

Public Sub KillPlayer(ByVal Index As Long)
Dim Exp As Long

    ' Calculate exp to give attacker
    Exp = GetPlayerExp(Index) \ 3

    ' Make sure we dont get less then 0
    If Exp < 0 Then Exp = 0
    If Exp = 0 Then
        Call PlayerMsg(Index, "You lost no exp.", BrightRed)
    Else
        Call SetPlayerExp(Index, GetPlayerExp(Index) - Exp)
        SendEXP Index
        Call PlayerMsg(Index, "You lost " & Exp & " exp.", BrightRed)
    End If
    
    Call OnDeath(Index)
End Sub

Public Sub UseItem(ByVal Index As Long, ByVal invNum As Long)
Dim n As Long, i As Long, tempItem As Long, X As Long, Y As Long, itemnum As Long

    ' Prevent hacking
    If invNum < 1 Or invNum > MAX_ITEMS Then
        Exit Sub
    End If

    If (GetPlayerInvItemNum(Index, invNum) > 0) And (GetPlayerInvItemNum(Index, invNum) <= MAX_ITEMS) Then
        n = Item(GetPlayerInvItemNum(Index, invNum)).Data2
        itemnum = GetPlayerInvItemNum(Index, invNum)
        
        ' Find out what kind of item it is
        Select Case Item(itemnum).Type
            Case ITEM_TYPE_ARMOR
            
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to equip this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to equip this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to equip this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to equip this item.", BrightRed
                    Exit Sub
                End If

                If GetPlayerEquipment(Index, Armor) > 0 Then
                    tempItem = GetPlayerEquipment(Index, Armor)
                End If

                SetPlayerEquipment Index, itemnum, Armor
                PlayerMsg Index, "Voc? equipou " & CheckGrammar(Item(itemnum).Name), Orange
                TakeInvItem Index, itemnum, 1

                If tempItem > 0 Then
                    GiveInvItem Index, tempItem, 0 ' give back the stored item
                    tempItem = 0
                End If

                Call SendWornEquipment(Index)
                Call SendMapEquipment(Index)
                Call SendStats(Index)
                
                ' send vitals
                Call SendVital(Index, Vitals.HP)
                Call SendVital(Index, Vitals.MP)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            Case ITEM_TYPE_WEAPON
            
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to equip this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to equip this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to equip this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to equip this item.", BrightRed
                    Exit Sub
                End If

                If GetPlayerEquipment(Index, Weapon) > 0 Then
                    tempItem = GetPlayerEquipment(Index, Weapon)
                End If

                SetPlayerEquipment Index, itemnum, Weapon
                PlayerMsg Index, "Voc? equipou " & CheckGrammar(Item(itemnum).Name), Orange
                TakeInvItem Index, itemnum, 1

                If tempItem > 0 Then
                    GiveInvItem Index, tempItem, 0 ' give back the stored item
                    tempItem = 0
                End If

                Call SendWornEquipment(Index)
                Call SendMapEquipment(Index)
                Call SendStats(Index)
                
                ' send vitals
                Call SendVital(Index, Vitals.HP)
                Call SendVital(Index, Vitals.MP)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            Case ITEM_TYPE_HELMET
            
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to equip this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to equip this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to equip this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to equip this item.", BrightRed
                    Exit Sub
                End If

                If GetPlayerEquipment(Index, Helmet) > 0 Then
                    tempItem = GetPlayerEquipment(Index, Helmet)
                End If

                SetPlayerEquipment Index, itemnum, Helmet
                PlayerMsg Index, "Voc? equipou " & CheckGrammar(Item(itemnum).Name), Orange
                TakeInvItem Index, itemnum, 1

                If tempItem > 0 Then
                    GiveInvItem Index, tempItem, 0 ' give back the stored item
                    tempItem = 0
                End If

                Call SendWornEquipment(Index)
                Call SendMapEquipment(Index)
                Call SendStats(Index)
                
                ' send vitals
                Call SendVital(Index, Vitals.HP)
                Call SendVital(Index, Vitals.MP)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            Case ITEM_TYPE_SHIELD
            
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to equip this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to equip this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to equip this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to equip this item.", BrightRed
                    Exit Sub
                End If

                If GetPlayerEquipment(Index, Shield) > 0 Then
                    tempItem = GetPlayerEquipment(Index, Shield)
                End If

                SetPlayerEquipment Index, itemnum, Shield
                PlayerMsg Index, "Voc? equipou " & CheckGrammar(Item(itemnum).Name), Orange
                TakeInvItem Index, itemnum, 1

                If tempItem > 0 Then
                    GiveInvItem Index, tempItem, 0 ' give back the stored item
                    tempItem = 0
                End If
                
                Call SendStats(Index)
                
                ' send vitals
                Call SendVital(Index, Vitals.HP)
                Call SendVital(Index, Vitals.MP)
                ' send vitals to party if in one
                If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index

                Call SendWornEquipment(Index)
                Call SendMapEquipment(Index)
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            ' consumable
            Case ITEM_TYPE_CONSUME
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to use this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to use this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to use this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to use this item.", BrightRed
                    Exit Sub
                End If
                
                ' add hp
                If Item(itemnum).AddHP > 0 Then
                    Player(Index).Vital(Vitals.HP) = Player(Index).Vital(Vitals.HP) + Item(itemnum).AddHP
                    SendActionMsg GetPlayerMap(Index), "+" & Item(itemnum).AddHP, BrightGreen, ACTIONMSG_SCROLL, GetPlayerX(Index) * 32, GetPlayerY(Index) * 32
                    SendVital Index, HP
                    ' send vitals to party if in one
                    If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
                End If
                ' add mp
                If Item(itemnum).AddMP > 0 Then
                    Player(Index).Vital(Vitals.MP) = Player(Index).Vital(Vitals.MP) + Item(itemnum).AddMP
                    SendActionMsg GetPlayerMap(Index), "+" & Item(itemnum).AddMP, BrightBlue, ACTIONMSG_SCROLL, GetPlayerX(Index) * 32, GetPlayerY(Index) * 32
                    SendVital Index, MP
                    ' send vitals to party if in one
                    If TempPlayer(Index).inParty > 0 Then SendPartyVitals TempPlayer(Index).inParty, Index
                End If
                ' add exp
                If Item(itemnum).AddEXP > 0 Then
                    SetPlayerExp Index, GetPlayerExp(Index) + Item(itemnum).AddEXP
                    CheckPlayerLevelUp Index
                    SendActionMsg GetPlayerMap(Index), "+" & Item(itemnum).AddEXP & " EXP", White, ACTIONMSG_SCROLL, GetPlayerX(Index) * 32, GetPlayerY(Index) * 32
                    SendEXP Index
                End If
                Call SendAnimation(GetPlayerMap(Index), Item(itemnum).Animation, 0, 0, TARGET_TYPE_PLAYER, Index)
                Call TakeInvItem(Index, Player(Index).Inv(invNum).Num, 0)
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            Case ITEM_TYPE_KEY
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to use this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to use this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to use this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to use this item.", BrightRed
                    Exit Sub
                End If

                Select Case GetPlayerDir(Index)
                    Case DIR_UP

                        If GetPlayerY(Index) > 0 Then
                            X = GetPlayerX(Index)
                            Y = GetPlayerY(Index) - 1
                        Else
                            Exit Sub
                        End If

                    Case DIR_DOWN

                        If GetPlayerY(Index) < Map(GetPlayerMap(Index)).MaxY Then
                            X = GetPlayerX(Index)
                            Y = GetPlayerY(Index) + 1
                        Else
                            Exit Sub
                        End If

                    Case DIR_LEFT

                        If GetPlayerX(Index) > 0 Then
                            X = GetPlayerX(Index) - 1
                            Y = GetPlayerY(Index)
                        Else
                            Exit Sub
                        End If

                    Case DIR_RIGHT

                        If GetPlayerX(Index) < Map(GetPlayerMap(Index)).MaxX Then
                            X = GetPlayerX(Index) + 1
                            Y = GetPlayerY(Index)
                        Else
                            Exit Sub
                        End If

                End Select

                ' Check if a key exists
                If Map(GetPlayerMap(Index)).Tile(X, Y).Type = TILE_TYPE_KEY Then

                    ' Check if the key they are using matches the map key
                    If itemnum = Map(GetPlayerMap(Index)).Tile(X, Y).Data1 Then
                        temptile(GetPlayerMap(Index)).DoorOpen(X, Y) = YES
                        temptile(GetPlayerMap(Index)).DoorTimer = GetTickCount
                        SendMapKey Index, X, Y, 1
                        Call MapMsg(GetPlayerMap(Index), "A door has been unlocked.", White)
                        
                        Call SendAnimation(GetPlayerMap(Index), Item(itemnum).Animation, X, Y)

                        ' Check if we are supposed to take away the item
                        If Map(GetPlayerMap(Index)).Tile(X, Y).Data2 = 1 Then
                            Call TakeInvItem(Index, itemnum, 0)
                            Call PlayerMsg(Index, "The key is destroyed in the lock.", Yellow)
                        End If
                    End If
                End If
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
            Case ITEM_TYPE_SPELL
            
                ' stat requirements
                For i = 1 To Stats.Stat_Count - 1
                    If GetPlayerRawStat(Index, i) < Item(itemnum).Stat_Req(i) Then
                        PlayerMsg Index, "You do not meet the stat requirements to use this item.", BrightRed
                        Exit Sub
                    End If
                Next
                
                ' level requirement
                If GetPlayerLevel(Index) < Item(itemnum).LevelReq Then
                    PlayerMsg Index, "You do not meet the level requirement to use this item.", BrightRed
                    Exit Sub
                End If
                
                ' class requirement
                If Item(itemnum).ClassReq > 0 Then
                    If Not GetPlayerClass(Index) = Item(itemnum).ClassReq Then
                        PlayerMsg Index, "You do not meet the class requirement to use this item.", BrightRed
                        Exit Sub
                    End If
                End If
                
                ' access requirement
                If Not GetPlayerAccess(Index) >= Item(itemnum).AccessReq Then
                    PlayerMsg Index, "You do not meet the access requirement to use this item.", BrightRed
                    Exit Sub
                End If
                
                ' Get the spell num
                n = Item(itemnum).Data1

                If n > 0 Then

                    ' Make sure they are the right class
                    If Spell(n).ClassReq = GetPlayerClass(Index) Or Spell(n).ClassReq = 0 Then
                        ' Make sure they are the right level
                        i = Spell(n).LevelReq

                        If i <= GetPlayerLevel(Index) Then
                            i = FindOpenSpellSlot(Index)

                            ' Make sure they have an open spell slot
                            If i > 0 Then

                                ' Make sure they dont already have the spell
                                If Not HasSpell(Index, n) Then
                                    Call SetPlayerSpell(Index, i, n)
                                    Call SendAnimation(GetPlayerMap(Index), Item(itemnum).Animation, 0, 0, TARGET_TYPE_PLAYER, Index)
                                    Call TakeInvItem(Index, itemnum, 0)
                                    Call PlayerMsg(Index, "You feel the rush of knowledge fill your mind. You can now use " & Trim$(Spell(n).Name) & ".", BrightGreen)
                                Else
                                    Call PlayerMsg(Index, "You already have knowledge of this skill.", BrightRed)
                                End If

                            Else
                                Call PlayerMsg(Index, "You cannot learn any more skills.", BrightRed)
                            End If

                        Else
                            Call PlayerMsg(Index, "You must be level " & i & " to learn this skill.", BrightRed)
                        End If

                    Else
                        Call PlayerMsg(Index, "This spell can only be learned by " & CheckGrammar(GetClassName(Spell(n).ClassReq)) & ".", BrightRed)
                    End If
                End If
                
                ' send the sound
                SendPlayerSound Index, GetPlayerX(Index), GetPlayerY(Index), SoundEntity.seItem, itemnum
        End Select
    End If
End Sub
