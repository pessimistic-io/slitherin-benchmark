pragma solidity ^0.8.4;

import "./console.sol";


interface IGames{
    function getGame(uint256 _wizId) external returns(Game memory);
    function getPlayerPosition(uint256 _wizId) external view returns(uint256, uint256);
    function getPlayersPositions(uint256 _gameId) external returns(uint256[2] memory, uint256[2] memory, uint256[2] memory);
    function getPlayerCurrMP(uint256 _wizId) external returns(uint256);
    function editPlayerMP(uint256 _wizId, int _apDelta) external;
    function setPosition(uint256 _wizId, uint256 _x, uint256 _y) external;

}

interface IArcane{
    function ownerOf(uint256 tokenId) external view returns (address);
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

// 0 is move 1 is spell
struct Action{
    uint8 actionType;
    uint8 startX;
    uint8 startY;
    uint8 endX;
    uint8 endY;
    uint8 spellId;
    uint8 power;
}

struct ActionList{
    Action[] actions;
}

contract Battle {

    IGames GAMES;
    IArcane ARCANE;

    uint256 mapSize=5;

    // maps
    mapping (uint256 => uint256[][]) private maps;
    mapping (uint256 => mapping (uint256 => uint256)) private startTilesX;
    mapping (uint256 => mapping (uint256 => uint256)) private startTilesY;

    // players
    mapping(uint256 => ActionList) private playerActionLists;
    mapping(uint256 => uint256) private actionCounter;

    
    // user

    function moveTo(uint256 _wizId, uint256[] memory _movesX, uint256[] memory _movesY) external {
        // TODO: check game id
        // TODO: check that game has started and its your turn !!
        Game memory currGame = GAMES.getGame(_wizId);
        require(currGame.winner==9,"Game finished");
        require(ARCANE.ownerOf(_wizId)==msg.sender, "You don't own this wizard");
        require(currGame.wizIds[currGame.currTurn]==_wizId, "It's not your turn");
        require(_movesX.length==_movesY.length, "invalid move");
        require(GAMES.getPlayerCurrMP(_wizId)>=_movesX.length, "Not enough MP to move");
        Game memory game = GAMES.getGame(_wizId);
        uint256 currX;
        uint256 currY;
        (currX,currY) = GAMES.getPlayerPosition(_wizId);
        validatePath(_wizId, game.gameId, game.map, currX, currY, _movesX, _movesY);
        GAMES.editPlayerMP(_wizId, -int(_movesX.length));

        // action
        Action memory moveAction = Action(0,uint8(_movesX[0]),uint8(_movesY[0]),uint8(_movesX[_movesX.length-1]),uint8(_movesY[_movesY.length-1]),0,0);
        ActionList storage actionList = playerActionLists[_wizId];
        actionList.actions.push(moveAction);
    } 

    // called from CombatSpell.sol to register action
    function createSpellAction(uint256 _wizId, uint256 _originX, uint256 _originY, uint256 _spellId,uint256 _power)public {
         // action
        Action memory moveAction = Action(1,uint8(_originX),uint8(_originY),uint8(_originX),uint8(_originY),uint8(_spellId),uint8(_power));
        ActionList storage actionList = playerActionLists[_wizId];
        actionList.actions.push(moveAction);
    }

    // system

    // helpers


    function validatePath(uint256 _wizId, uint256 _gameId, uint256 _mapId, uint256 _startX,uint256 _startY, uint256[] memory _movesX, uint256[] memory _movesY) public{
 
        uint256 lastCheckedX = _startX;
        uint256 lastCheckedY = _startY;
        for( uint move =0;move<_movesX.length;move++){
            // check distance
            int xDelta = int(lastCheckedX) - int(_movesX[move]);
            int yDelta = int(lastCheckedY) - int(_movesY[move]);
            
            if(yDelta==0){
                require(xDelta!=0, "You are currently on that tile!");
            }
            require(abs(xDelta) <=1 && abs(yDelta) <=1, "You cannot move that far!");
            lastCheckedX = _movesX[move];
            lastCheckedY = _movesY[move]; 

            // check for 0 tile
            require(maps[_mapId][_movesX[move]][_movesY[move]]!=0, "Cannot walk here");

            // check for enemy player
            uint256[2] memory playersId;
            uint256[2] memory playersX;
            uint256[2] memory playersY;
            (playersId,playersX,playersY) = GAMES.getPlayersPositions(_gameId);
            for(uint i=0;i<2;i++){
                if(playersId[i]!=_wizId){
                    if(_movesY[move]==playersY[i]){
                        require(_movesX[move]!=playersX[i], "Enemy standing on that tile");
                    }
                }
            }
        }

        GAMES.setPosition(_wizId, _movesX[_movesX.length-1], _movesY[_movesY.length-1]);
        
    }


    // !!! DOESNT CHECK VALIDITY OF ORIGIN
    function getAOETiles(uint256[][] memory _shape, uint256 _mapId, uint256 _originX, uint256 _originY,uint256 _gameId) public returns(uint256[2] memory){
         uint256[2] memory wizIds;
         uint256[2] memory playersX;
         uint256[2] memory playersY;
        (wizIds,playersX,playersY) = GAMES.getPlayersPositions(_gameId);

        uint256[2] memory touchedPlayerIds;
        touchedPlayerIds[0]=9;
        touchedPlayerIds[1]=9;
        
        uint256 counter=0;
         for(uint x = 0;x<mapSize-1;x++){
            for(uint y = 0;y<mapSize-1;y++){
                if(_shape[x][y]<1){
                    int offsetX = int(x+_originX)-2; // 8
                    int offsetY = int(y+_originY)-2; // 8
                    if(validTile(_mapId,offsetX,offsetY)){
                        for(uint p=0;p<wizIds.length;p++){
                            if(playersX[p]==uint256(offsetX) && playersY[p]==uint256(offsetY)){
                                touchedPlayerIds[counter] = p;
                                console.log("touched: ",p);
                                counter++;
                            }
                        }
                       
                    }
                }
            }
        }
        return(touchedPlayerIds);
    }

    function validTile(uint256 _mapId,int _x,int _y) public view returns(bool){
        if(_x < 0 || _x > int(mapSize-1) || _y < 0 || _y > int(mapSize-1)) return false;
        if(maps[_mapId][uint256(_x)][uint256(_y)]==0) return false;
        return true;
    }


    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    function getStartPosition(uint256 _mapId, uint256 _index) public view returns(uint256,uint256){
        return(startTilesX[_mapId][_index],startTilesY[_mapId][_index]);
    }

    function resetActions(uint256 _wizId) public {
        ActionList storage actionList = playerActionLists[_wizId];
        delete actionList.actions;
    }

    function getPlayerActions(uint256 _wizId) public view returns(Action[] memory){
        Action[] memory recentActions=new Action[](actionCounter[_wizId]);
        ActionList storage actionList = playerActionLists[_wizId];
        for(uint i=0;i<recentActions.length;i++){
            recentActions[i] = actionList.actions[i];
        }
        return actionList.actions;
    }

    // owner
    
    function setMap(uint256 _mapId, uint256 _mapSize, uint256[] memory _tileValues, uint256[] memory _startTiles) external {
        uint256 counter=0;
        uint256 startTileCounter=0;
    
        uint256[5][5] memory temp;
        for(uint x = 0;x<_mapSize;x++){
            for(uint y = 0;y<_mapSize;y++){
                temp[x][y]= _tileValues[counter];
                if(_startTiles[counter]==1){
                    startTilesX[_mapId][startTileCounter]=x;
                    startTilesY[_mapId][startTileCounter]=y;
                    startTileCounter++;
                }
                counter++;
            }
        }
        maps[_mapId] = temp;

    }

    function setGames(address _games) external {
        GAMES = IGames(_games);
    }

    function setArcane(address _arcane) external {
        ARCANE = IArcane(_arcane);
    }

    // safety
    function unlockGame() external {

    }

}
