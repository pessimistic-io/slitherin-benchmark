pragma solidity ^0.8.4;

import "./console.sol";

// CLASSES

// 0:"Wizard",
// 1:"Mage",
// 2:"Priest",
// 3:"Warlock",
// 4:"Mentah",
// 5:"Sorcerer",
// 6:"Druid",
// 7:"Enchanter",
// 8:"Astronomer",
// 9:"Elementalist",
// 10:"Shadowcaster"

// DAMAGE TYPES:

// 0:"Arcane",
// 1:"Shadow",
// 2:"Divine",
// 3:"Elemental",
// 4:"Voodoo",
// 5:"Wild"
// 6:"Melee"

interface IArcane{
    function getWizardInfosIds(uint256 _wizId) external returns (uint256[5] memory);
}

interface IItems{
    function getWizardStats(uint256 _wizId) external returns (uint256[5] memory);
}

interface IBattle {
    function getAOETiles(uint256[][] memory _shape, uint256 _mapId, uint256 _originX, uint256 _originY,uint256 _gameId) external returns(uint256[2] memory);
    function createSpellAction(uint256 _wizId, uint256 _originX, uint256 _originY, uint256 _spellId,uint256 _power)external;
    function validTile(uint256 _mapId,int _x,int _y) external view returns(bool);
}

interface IGames{
    function getGame(uint256 _wizId) external view returns (Game memory);
    function getWizPlayerId(uint256 _wizId) external returns(uint256);
    function getPlayerPosition(uint256 _wizId)
        external
        view
        returns (uint256, uint256);
    function setPosition(uint256 _wizId, uint256 _x, uint256 _y) external;
    function editHP(uint256 _wizId, int _delta) external;
    function getPlayerCurrAP(uint256 _wizId) external returns(uint256);
    function editPlayerAP(uint256 _wizId, int _apDelta) external;

}

interface IRandomizer{
    function getRandoms(string memory _seed, uint256 _size) external view returns (uint256[] memory);
}

struct WizData{
    uint256 race;
    uint256 class;
    uint256 affinity;
    bool set;
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

contract BattleSpells {

    IArcane ARCANE;
    IBattle BATTLE;
    IGames GAMES;
    IRandomizer RANDOMIZER;
    IItems ITEMS;

    uint256 private centerX;
    uint256 private centerY;

    // spells
    mapping (uint256 => uint256[][]) public spellShapes;
    mapping (uint256 => uint256[][]) public spellRange;
    mapping (uint256 => uint256) public spellAPcost;

    // class default spellIds
    mapping (uint256 => uint256) classToBaseSpell1;
    mapping (uint256 => uint256) classToBaseSpell2;
    mapping(uint256 => mapping (uint256 => bool)) spellsKnown;

    mapping (uint256 => WizData) wizData;

    // user

    function useSpell(uint256 _wizId, uint256 _spellId,uint256 _originX, uint256 _originY) external {
        
        // check if data is set
        if(!wizData[_wizId].set){
            setWizardData(_wizId);
        }
        if(_spellId!=0){
        // check base spells
            // require(spellsKnown[_wizId][_spellId], "You don't know this spell");
        }
        require(GAMES.getPlayerCurrAP(_wizId)>=spellAPcost[_spellId], "Not enough AP for this spell");
        GAMES.editPlayerAP(_wizId, int256(spellAPcost[_spellId]));
        // get game Id
        Game memory currGame = GAMES.getGame(_wizId);
        // checks: game is ongoing, 
        require(currGame.winner==9,"Game finished");

        // TODO: add learned spells

        _validateSpellOrigin(_wizId, _spellId, _originX, _originY);

        // Get All touched tiles
        uint256[2] memory touchedPlayers = BATTLE.getAOETiles(spellShapes[_spellId], currGame.map, _originX, _originY, currGame.gameId);
        //Apply damage or heals
        uint256 power = _triggerSpell(_wizId, _spellId,_originX,_originY, touchedPlayers);

        // Action
        BATTLE.createSpellAction(_wizId, _originX, _originY, _spellId, power);
    }
      
    // spell mechanisms, apply effects
    function _triggerSpell(uint256 _wizId, uint256 _spellId,uint256 _Ox, uint256 _Oy,uint256[2] memory _touchedPlayers) private returns(uint256) {
        uint256[] memory rands = RANDOMIZER.getRandoms(string(abi.encodePacked(_wizId,_spellId)), 6);
        uint256[5] memory stats = ITEMS.getWizardStats(_wizId);
        uint256 power;
         // critical strike
        // TODO: scale with level
        uint256 critical=1;
        uint256 pass = 90;
        if(rands[0]>pass){ 
            critical = 2;
        }

        uint256 userPlayerId = GAMES.getWizPlayerId(_wizId);
        // apply
        if(_spellId==0){
            // melee
            // strength and 1D3 
            power = (1+ stats[1] + rands[1]%2) * critical;

            for(uint i=0;i<_touchedPlayers.length;i++){
                if(_touchedPlayers[i]!=9 && _touchedPlayers[i]!=userPlayerId){
                    _damagePlayer(GAMES.getGame(_wizId).wizIds[_touchedPlayers[i]], power, 6);
                }
            }

        }else if(_spellId==1){
            // Arcane Lance
            power = (4+ stats[3]+rands[1]%10) * critical;
            // TODO: affinity
            
             for(uint i=0;i<_touchedPlayers.length;i++){
                if(_touchedPlayers[i]!=9 && _touchedPlayers[i]!=userPlayerId){
                    _damagePlayer(GAMES.getGame(_wizId).wizIds[_touchedPlayers[i]], power, 0);
                }
            }
        }else if(_spellId==2){
            // teleport
            // TODO: affinity
            GAMES.setPosition(_wizId, _Ox,_Oy);
        }else if(_spellId==3){
            // Onyx Blast
            power = (2 + stats[3] + rands[1]%4 + rands[2]%3) * critical;
            // TODO: affinity
             for(uint i=0;i<_touchedPlayers.length;i++){
                if(_touchedPlayers[i]!=9 && _touchedPlayers[i]!=userPlayerId){
                    _damagePlayer(GAMES.getGame(_wizId).wizIds[_touchedPlayers[i]], power, 0);
                }
            }

        } else if(_spellId==4){
            // Mending Pit
            // self targeting
            power = (2 + stats[3] + rands[1]%4 + rands[2]%3) * critical;
            // TODO: affinity
             for(uint i=0;i<_touchedPlayers.length;i++){
                if(_touchedPlayers[i]!=9 && _touchedPlayers[i]==userPlayerId){
                    _healPlayer(GAMES.getGame(_wizId).wizIds[_touchedPlayers[i]], power, 0);
                }
            }
        }
       return power;
        
    }

    // helper
    function _damagePlayer(uint256 _targetWiz, uint256 _damageAmount, uint256 _type) internal {
        // TODO: check resistance & affinity

        // edit
        console.log("targetWiz",_targetWiz);
        console.log("did damage: ",_damageAmount);
        GAMES.editHP(_targetWiz, -int(_damageAmount));
    }

    function _healPlayer(uint256 _targetWiz, uint256 _healAmount, uint256 _type) internal {
        // TODO: check affinity

        // edit
        GAMES.editHP(_targetWiz, int(_healAmount));
        console.log("did heal: ",_healAmount);

    }

    function _validateSpellOrigin(uint256 _wizId, uint256 _spellId, uint256 _originX,uint256 _originY) public view {
        require(BATTLE.validTile(GAMES.getGame(_wizId).map, int(_originX), int(_originY)), "Can't invoke spell here");

        uint256 playerX;
        uint256 playerY;
        (playerX,playerY) = GAMES.getPlayerPosition(_wizId); // 3-1

        // -x = pX - (boardSize/2-1) - Ox
        // int spellRangeX = -1*(int(playerX) - 2 - int(_originX)); // 8   // 3-2-2 = 1
        // int spellRangeY = -1*(int(playerY) - 2 - int(_originY)); // 8   // 1-2-1 = 2

        // delta = Ox - Px, toCheck = center + delta
        int deltaX = int(_originX) - int(playerX);
        int deltaY = int(_originY) - int(playerY);
        int toCheckX = int(centerX) + deltaX;
        int toCheckY = int(centerY) + deltaY;

        require(toCheckX>=0 && toCheckY >=0 
        && toCheckY < 5 
        && toCheckX < 5 
        && spellRange[_spellId][uint256(toCheckX)][uint256(toCheckY)]<1, "Out of range");
    }
  

    function setWizardData(uint256 _wizId) public {
        uint256[5] memory pulledData = ARCANE.getWizardInfosIds(_wizId);
        WizData memory data = WizData(pulledData[0],pulledData[1],pulledData[2], true);
        wizData[_wizId]=data;
        //set base spells
        spellsKnown[_wizId][classToBaseSpell1[data.class]]=true;
        spellsKnown[_wizId][classToBaseSpell2[data.class]]=true;

    }

    // owner
    // [0,0,1,1,2,2] [0,1,0,1,0,1] [0,3,1,2,1,6]
    function setClassesToBases( uint256[] memory _class,uint256[] memory _baseId, uint256[] memory _spellId) external {
        for(uint i =0;i<_class.length;i++){
                if(_baseId[i]==0){
                    classToBaseSpell1[_class[i]] = _spellId[i];
                }else{
                    classToBaseSpell2[_class[i]] = _spellId[i];
                }
        }
       
    }

    function setArcane(address _arcane) external {
        ARCANE = IArcane(_arcane);
    }

     function setBattle(address _battle) external {
        BATTLE = IBattle(_battle);
    }

    function setRandomizer(address _randomizer) external {
        RANDOMIZER = IRandomizer(_randomizer);
    }

    function setGames(address _games) external { 
        GAMES = IGames(_games);
    }

     function setItems(address _items) external { 
        ITEMS = IItems(_items);
    }

    function setSpellShape(uint256 _spellId, uint256[] memory _spellShapeValues, uint256[] memory _spellRangeValues, uint256 _apCost) external {
        uint256 counter=0;
    
        uint256[5][5] memory tempShape;
        uint256[5][5] memory tempRange;
        for(uint x = 0;x<5;x++){
            for(uint y = 0;y<5;y++){
                tempShape[x][y]= _spellShapeValues[counter];
                tempRange[x][y]= _spellRangeValues[counter];
                counter++;
            }
        }
        spellShapes[_spellId] = tempShape;
        spellRange[_spellId] = tempRange;
        spellAPcost[_spellId] = _apCost;
    }

    function setCenterCoords(uint256 _center) external {
        centerX = _center;
        centerY = _center;
    }
}
