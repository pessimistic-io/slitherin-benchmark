pragma solidity ^0.8.4;

import "./console.sol";

// TALENTS

// 0:"Focus",
// 1:"Strenght"
// 2:"Intellect",
// 3:"Spell",
// 4:"Endurance"

interface IBattle {
    function getStartPosition(uint256 _mapId, uint256 _index)
        external
        returns (uint256, uint256);
    function resetActions(uint256 _playerId) external;

}

interface IArcane{
    function ownerOf(uint256 tokenId) external view returns (address);
}

interface IItems{
    function getWizardStats(uint256 _wizId) external returns (uint256[5] memory);
}

struct Game {
    uint256 gameId;
    bool opened;
    bool started;
    uint8 playerAmount;
    uint16[2] wizIds;
    uint8 map;
    uint256 magicPrize;
    uint8 currTurn;
    int256[2] HP;
    int256[2] AP;
    int256[2] MP;
    uint8 winner;
}



contract Games {
    constructor() {
        slotId = 1;
    }

    IBattle BATTLE;
    IArcane ARCANE;
    IItems ITEMS;

    // games
    mapping(uint256 => Game) public games;
    uint256 private slotId;

    // player data
    mapping(uint256 => uint256) public playerToGameId;

    mapping(uint256 => uint256) public positionX;
    mapping(uint256 => uint256) public positionY;
    mapping(uint256 => uint256[5])public talentPoints;

    // user

    function createGame(uint256 _creatorId) external {
        require(playerToGameId[_creatorId] == 0, "Wizard already in game");
        require(ARCANE.ownerOf(_creatorId)==msg.sender, "You don't own this wizard");
        // TODO: check ownerOf, add player Amount
        uint16[2] memory players;
        players[0] = uint8(_creatorId);
        players[1] = 0;
        int256[2] memory hps;
        // hps[0] = 0;
        // hps[1] = 0;
        // TODO: we set the turn to length-1 so we can go to 0 when game starts, but needs to be dynamic
        Game memory newGame = Game(
            slotId,
            true,
            false,
            2,
            players,
            0,
            0,
            uint8(players.length - 1),
            hps,
            hps,
            hps,
            9
        );
        games[slotId] = newGame;
       _setupPlayer(_creatorId, 0, slotId, newGame.map);
        console.log("game created");
        slotId++;
    }

    function joinGame(uint256 _gameId, uint256 _wizId) external {
        require(ARCANE.ownerOf(_wizId)==msg.sender, "You don't own this wizard");
        require(playerToGameId[_wizId]==0, "You're already in a game");
        require(games[_gameId].opened, "Cannot join this game");
        // TODO: send startposition with join game

        // check amount in game
        uint256 playerAmount = 2;
        Game storage gameToJoin = games[_gameId];
        gameToJoin.wizIds[1] = uint16(_wizId);

        _setupPlayer(_wizId, 1, _gameId, gameToJoin.map);

        // check for ready game
        if (playerAmount == 2) {
            // player 1 start
            gameToJoin.started = true;
            nextTurn(_gameId);
        }
    }

    function endTurn(uint256 _wizId) external {
        // TODO: check that sender owns this playerId, but maybe 2nd line already does this, check
        require(playerToGameId[_wizId]>0, "You're not in a game");
        require(ARCANE.ownerOf(uint256(games[playerToGameId[_wizId]].wizIds[games[playerToGameId[_wizId]].currTurn]))==msg.sender, "It's not your turn");
        nextTurn(playerToGameId[_wizId]);
    }

    function exitGame(uint256 _wizId) external {
        require(playerToGameId[_wizId]>0, "You're not in a game");
        require(ARCANE.ownerOf(_wizId)==msg.sender, "You don't own this wizard");
        require(games[playerToGameId[_wizId]].winner!=9, "Battle is still going");
        playerToGameId[_wizId] = 0;
    }

    function abandonGame(uint256 _wizId) external{
          require(playerToGameId[_wizId]>0, "You're not in a game");
          require(ARCANE.ownerOf(_wizId)==msg.sender, "You don't own this wizard");
          uint256 winner = 1 - getWizPlayerId(_wizId);
          _endGame(playerToGameId[_wizId], winner);
          // exit
          playerToGameId[_wizId]=0;
    }

    // system

    function nextTurn(uint256 _gameId) public {
        // TODO: scale with player #
        Game memory game = games[_gameId];

        game.currTurn++;
        if (game.currTurn > 1) game.currTurn = 0;

        // reset actions
        BATTLE.resetActions(game.wizIds[game.currTurn]);
        
        // reset player stats
        games[_gameId] = game;
        editPlayerAP(
            game.wizIds[game.currTurn],
            getPlayerMaxAP(game.wizIds[game.currTurn])
        );
        editPlayerMP(
            game.wizIds[game.currTurn],
            getPlayerMaxMP(game.wizIds[game.currTurn])
        );
    }


    function editHP(uint256 _wizId, int _delta) public {
        // TODO: check authorized contract
        games[playerToGameId[_wizId]].HP[getWizPlayerId(_wizId)]+=_delta;
        if(games[playerToGameId[_wizId]].HP[getWizPlayerId(_wizId)]<0){
            // player dead
            _endGame(games[playerToGameId[_wizId]].gameId,1 - getWizPlayerId(_wizId)); 
        }
    }

    function setPosition(
        uint256 _wizId,
        uint256 _x,
        uint256 _y
    ) public {
        positionX[_wizId] = _x;
        positionY[_wizId] = _y;
    }

    function _setupPlayer(uint256 _wizId, uint256 _playerId, uint256 _gameId, uint256 _mapId) internal{
        playerToGameId[_wizId] = _gameId;
        // position
        uint256 startX;
        uint256 startY;
        (startX, startY) = BATTLE.getStartPosition(_mapId, _playerId);
        positionX[_wizId] = startX;
        positionY[_wizId] = startY;
        // Talent points
        talentPoints[_wizId]=ITEMS.getWizardStats(_wizId);
        // HP
        games[playerToGameId[_wizId]].HP[getWizPlayerId(_wizId)] = int256(talentPoints[_wizId][4])+5;
    }

    function _endGame(uint256 _gameId, uint256 _winnerPlayerId) internal {
        games[_gameId].winner = uint8(_winnerPlayerId);
        console.log("Game won by ",_winnerPlayerId," wizard #",games[_gameId].wizIds[_winnerPlayerId]);
        
    }
    

    // helpers

 

    function getPlayerMaxAP(uint256 _wizId) public pure returns (int256) {
        return 7;
    }

    function getPlayerCurrAP(uint256 _wizId) public view returns (uint256) {
        require(playerToGameId[_wizId] != 0, "Player not in a game");
        return uint256(games[playerToGameId[_wizId]].AP[getWizPlayerId(_wizId)]);
    }

    function editPlayerAP(uint256 _wizId, int256 _apDelta) public {
        if (games[playerToGameId[_wizId]].AP[getWizPlayerId(_wizId)] + _apDelta >= 0) {
            games[playerToGameId[_wizId]].AP[getWizPlayerId(_wizId)] += _apDelta;            
        } else {
            games[playerToGameId[_wizId]].AP[getWizPlayerId(_wizId)] = 0;
        }
    }

     function getPlayerMaxMP(uint256 _wizId) public pure returns (int256) {
        return 3;
    }

    function getPlayerCurrMP(uint256 _wizId) public view returns (uint256) {
        require(playerToGameId[_wizId] != 0, "Player not in a game");
        return uint256(games[playerToGameId[_wizId]].MP[getWizPlayerId(_wizId)]);
    }

    function editPlayerMP(uint256 _wizId, int256 _mpDelta) public {
        if (games[playerToGameId[_wizId]].MP[getWizPlayerId(_wizId)] + _mpDelta >= 0) {
            games[playerToGameId[_wizId]].MP[getWizPlayerId(_wizId)] += _mpDelta;            
        } else {
            games[playerToGameId[_wizId]].MP[getWizPlayerId(_wizId)] = 0;
        }
    }


    function getGame(uint256 _wizId) public view returns (Game memory) {
        require(playerToGameId[_wizId] != 0, "Player not in a game");
        return games[playerToGameId[_wizId]];
    }

    function getGameById(uint256 _gameId) public view returns (Game memory) {
        return games[playerToGameId[_gameId]];
    }

    // public

    function getPlayersPositions(uint256 _gameId)
        public
        view
        returns (
            uint256[2] memory,
            uint256[2] memory,
            uint256[2] memory
        )
    {
        // TODO: adjust for player size
        uint256[2] memory playersX;
        uint256[2] memory playersY;
        uint256[2] memory wizIds;
        for (uint256 i = 0; i < 2; i++) {
            wizIds[i] = games[_gameId].wizIds[i];
            playersX[i] = positionX[games[_gameId].wizIds[i]];
            playersY[i] = positionY[games[_gameId].wizIds[i]];
        }
        return (wizIds, playersX, playersY);
    }

    function getPlayerPosition(uint256 _wizId)
        public
        view
        returns (uint256, uint256)
    {
        return (positionX[_wizId], positionY[_wizId]);
    }

    function getWizPlayerId(uint256 _wizId) public view returns(uint256){
        require(playerToGameId[_wizId] != 0, "Player not in a game");
        for(uint i=0;i<games[playerToGameId[_wizId]].wizIds.length;i++){
            if(games[playerToGameId[_wizId]].wizIds[i]==_wizId){
                return i;
            }
        }
    }

    // owner

    function setBattle(address _battle) external {
        BATTLE = IBattle(_battle);
    }

    function setArcane(address _arcane) external {
        ARCANE = IArcane(_arcane);
    }

    function setItems(address _items) external {
        ITEMS = IItems(_items);
    }
}

