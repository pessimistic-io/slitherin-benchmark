pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC721Receiver.sol";

interface ISkillbook {
    function useMana(uint8 _amount, uint256 _wizId) external returns(bool);
}

interface IItems {
    function mintItems(address _to, uint256[] memory _itemIds, uint256[] memory _amounts) external;
    function getWizardStats(uint256 _wizId) external returns (uint256[5] memory);
}

interface IArcane {
    function ownerOf(uint256 tokenId) external view returns (address);
    function setApprovalForAll(address operator, bool approved) external;
    function balanceOf(address owner) external view returns (uint256);
    function getWizardInfosIds(uint256 _wizId)
        external
        view
        returns (uint256[5] memory);

    function safeTransferFrom(
        address from,
        address to,
        uint256 tokenId
    ) external;
}

interface IEvents {
    function getEvents(uint256 _wizId, uint256 _tile) external returns (Event[] memory);
}

interface ILoot{
    function getLoot(uint256 _zoneId, uint256 _tile, uint256 _eventAmount, uint256 _wizId, bool passedSpecial) external returns(uint256[] memory lootIds, uint256[] memory lootAmounts);
}

interface IConsumable{
     function getBonus (uint256 _wizId, uint256 _bonusId) external returns(uint256);
}

interface ICoinReward {
    function tryReward(uint256 _wizId, uint256 _zoneId, bool _special) external;
}

struct Event {
    uint8 eventType;
    uint256 rand;
} 

 struct State {
        address quester;
        uint256 startTime;
        uint256 currX;
        uint256 currY;
        bool reward;
    }

struct RewardData{
    uint256 currZone;
    uint256 tile;
    uint256 passedEvents;
    uint256 luckPerc;
    uint256 gearPerc;
    int lvlDelta;
    uint256[5] wizStats;
}




contract Adventure is IERC721Receiver, Ownable, ReentrancyGuard {

   
    event MoveToTile(
        uint256 wizId,
        uint256 zoneId,
        uint256 targetX,
        uint256 targetY
    );

    event RevealQuest(
        uint256 wizId,
        uint256[] eventIds,
        uint256[] lootIds
    );

    event RetrieveWizard(
        uint256 wizId
    );

    IItems public ITEMS;
    IArcane public ARCANE;
    IEvents public EVENTS;
    ILoot public LOOT;
    ISkillbook public SKILLBOOK;
    IConsumable public CONSUMABLE;
    ICoinReward public COINREWARD;

    uint256 private QUEST_TIME; 
    uint256 private MAX_LVL;
    uint256 private xpPointsDivider;

    bool private pausedQuesting;

    mapping (uint256 => uint256[][]) public tileValues;
    mapping (uint256 => State) public states;
    mapping (uint256 => uint256) public currZones;
    // starting coordinate for each zone
    mapping (uint256 => uint256) public startX;
    mapping (uint256 => uint256) public startY;

    // amount of xp needed to lvl up
    mapping (uint256 => uint256) public xpPerLevel;
    // each wiz XP
    mapping (uint256 => uint256) public wizardsXp;
    mapping (uint256 => uint256) public zoneItemLevel;

    // query last event
    mapping (uint256 => uint256[]) public questEvents;
    mapping (uint256 => uint256[]) public questItemIds;

    modifier wizardOwner(uint256 _wizId) {
        require(
            ARCANE.ownerOf(_wizId) == msg.sender,
            "You don't own this Wizard"
        );
        _;
    }

    // EXTERNAL
    // ------------------------------------------------------

    function moveToTile(uint256 _wizId, uint256 _zoneId, uint256 _targetX, uint256 _targetY) external nonReentrant {
        require(_hoursElapsed(states[_wizId].startTime)>=QUEST_TIME, "You're currently questing");
        require(!states[_wizId].reward, "Reveal your loot before questing again");
        _getTileValue(_zoneId, _targetX, _targetY);
        
        // remove mana
        uint256 manaCost = 120;
        int lvlDelta = int(getLevel(_wizId)) - int(_zoneId);
        if(lvlDelta>0){
            for(uint i=0;i<uint(lvlDelta);i++){
                manaCost -=5;
            }
        } 

        if(manaCost<70) manaCost =70;
        manaCost -= CONSUMABLE.getBonus(_wizId, 0);
        bool hasEnoughMana = SKILLBOOK.useMana(uint8(manaCost), _wizId);
        require(hasEnoughMana, "Not enough mana");
       
        State memory currState = states[_wizId];

        uint256 newX;
        uint256 newY;
        if(currZones[_wizId] !=_zoneId){
            // use starting coord
            newX = startX[_zoneId];
            newY = startY[_zoneId];
            currZones[_wizId] = _zoneId;
        } else{
            int xDelta = int(currState.currX) - int(_targetX);
            int yDelta = int(currState.currY) - int(_targetY);
            if(yDelta==0){
                require(xDelta!=0, "Cannot move to current tile");
            }
            uint256 giantLeap = CONSUMABLE.getBonus(_wizId,6);
            require(abs(xDelta) <=int(1+giantLeap) && abs(yDelta) <=int(1+giantLeap), "You cannot move that far!");
            newX = _targetX;
            newY = _targetY; 
        }

        // edit position
        State memory newPos = State(msg.sender, block.timestamp, newX, newY, true);
        states[_wizId] = newPos;
        
       
        // move Wizard if not done already
        if(ARCANE.ownerOf(_wizId)!=address(this)){
            ARCANE.safeTransferFrom(msg.sender, address(this), _wizId);
        }

        emit MoveToTile(_wizId, _zoneId, _targetX, _targetY);
    }
 
    function revealQuest(uint256 _wizId) external  {
        require(states[_wizId].quester==msg.sender, "You don't own this Wizard");
        require(states[_wizId].reward, "You are not on an adventure.");
        RewardData memory data;
        data.currZone = currZones[_wizId];
        data.tile = _getTileValue(data.currZone, states[_wizId].currX, states[_wizId].currY);
       
        // get events: [ [eventId,rand] , [eventId, rand], ... ]
        Event[] memory events = EVENTS.getEvents(_wizId, data.tile );

        data.passedEvents =1;
        // percentage of luck
        data.luckPerc= 25;
        // percentage of gear impact on success
        data.gearPerc=75;
        data.lvlDelta = int(getLevel(_wizId) - data.currZone);
        data.wizStats= ITEMS.getWizardStats(_wizId);
        // account bonuses/consumables
        for(uint i =0;i<data.wizStats.length;i++){

            data.wizStats[i]+=CONSUMABLE.getBonus(_wizId,i+1);
        }
        // if wizard is less than 2 levels compared to current zone, readjust luck weights
        if(data.lvlDelta<-2){
            data.luckPerc=15;
            data.gearPerc=85;
        }

        // Passing Events

        
        bool passedSpecial;
        // we start at 1 because first event is always passed
        for(uint i=1;i<events.length;i++){
            uint256 minToPass = 100;
            // luckroll - reduces the minimum to pass with luck, maximum dicated by data.luckPerc
            uint luckRoll =uint(keccak256      
            (abi.encodePacked(_wizId,events[0].rand, data.lvlDelta, data.wizStats[0]))) % data.luckPerc;
            minToPass-=luckRoll;

            // gear roll - reduces the minimum to pass thanks to gear. Maximum is 50
            // zoneItemLevel is a static value per zone which dictacts the optimal stat level for that zone
            // Calculated = 50 * (currStat/LvlStat) = (50 * currStat) / lvlStat
            uint256 gearRoll =  50 * (data.wizStats[_eventToStat(events[i].eventType)]) / zoneItemLevel[currZones[_wizId]];
            if(gearRoll>50) gearRoll =50;

            minToPass-=gearRoll;

            if(events[i].rand >= minToPass){
                data.passedEvents++;
                if(events[i].eventType==4){
                    passedSpecial=true;
                }
            }else{
                break;
            }

            
        }
        
       
        // erc20
        if(COINREWARD!=ICoinReward(address(0))){
            COINREWARD.tryReward(_wizId, data.currZone, passedSpecial);
        }

        // give out XP
        _giveXP(_wizId, data.passedEvents);

        // get rewards
        uint256[] memory lootIds;
        uint256[] memory lootAmounts;
        (lootIds,lootAmounts) = LOOT.getLoot(data.currZone,data.tile, events.length, _wizId, passedSpecial);
        for(uint i=0;i<lootIds.length;i++){
        }
        ITEMS.mintItems(msg.sender, lootIds,lootAmounts);

        // flag showing reward has been claimed and quest ended
        State memory currState = states[_wizId];
        currState.reward = false;
        states[_wizId] = currState;

        // save result for engine
        uint256[] memory eventIds = new uint256[](events.length);
        for(uint i = 0;i<eventIds.length;i++){
            eventIds[i]=events[i].eventType;
        }
        questEvents[_wizId] = eventIds;
        questItemIds[_wizId] = lootIds;

        emit RevealQuest(_wizId, eventIds, lootIds);

    }   

    function retrieveWizard(uint256 _wizId) external {
        require(states[_wizId].quester==msg.sender, "You don't own this Wizard");
        require(_hoursElapsed(states[_wizId].startTime)>=QUEST_TIME, "You're currently questing");
        require(!states[_wizId].reward, "Reveal your loot before retrieving");
        ARCANE.safeTransferFrom(address(this),msg.sender, _wizId);

        emit RetrieveWizard(_wizId);
    }

    function forceQuesterChange(uint256 _wizId) external {
        require(ARCANE.ownerOf(_wizId)==msg.sender, "Not the owner");
         State memory currState = states[_wizId];
        currState.quester = msg.sender;
        states[_wizId] = currState;
    }

    function getTilePopulation(uint256 _zoneId, uint256 _x, uint256 _y) external view returns (address[] memory){
        uint256[] memory allQuesters = getAllQuesters();
        address[] memory questing = new address[](allQuesters.length);
        uint256 counter= 0;
        for(uint i=0;i<allQuesters.length;i++){
            uint256 wizId = allQuesters[i];
            if(currZones[wizId]==_zoneId
            && states[wizId].currX == _x
            && states[wizId].currY == _y){
                questing[counter] = states[wizId].quester;
                counter++;
            }
        }
        address[] memory population = new address[](counter);
        for(uint i=0;i<counter;i++){
            population[i] = questing[i];
        }
        return population;
    }

    function getAdventureState(uint256 _wizId) external view returns (uint256 zone, uint256 posX, uint256 posY ){
        return(currZones[_wizId], states[_wizId].currX,states[_wizId].currY);
    }

    function getWizardXp(uint256 _wizId) external view returns (uint256 xp){
        return(wizardsXp[_wizId]);
    }

    function getQuesters(address _owner) external view returns(uint256[] memory){
        uint256[] memory allQuesters = getAllQuesters();
        uint256[] memory wizIds = new uint256[](allQuesters.length);
        uint256 counter=0;

        for(uint i=0;i<allQuesters.length;i++){
            uint256 wizId = allQuesters[i];
            if(states[wizId].quester==_owner){
                wizIds[counter] = wizId;
                counter++;
            }
        }
        uint256[] memory ownedQuesters = new uint256[](counter);
        for(uint i=0;i<counter;i++){
            ownedQuesters[i] = wizIds[i];
        }
        return ownedQuesters;
    }

    function getLatestQuestResult(uint256 _wizId) external view returns(uint256[] memory, uint256[] memory){
        return(questEvents[_wizId],questItemIds[_wizId]);
    }

    function getLevel(uint256 _wizId) public view returns(uint256){
        uint256 currLevel=0;
        for(uint i=0;i<MAX_LVL;i++){
            if(wizardsXp[_wizId]>=xpPerLevel[i]){
                currLevel++;
            }else{
                return currLevel;
            }
        }
        return MAX_LVL;
    }

      function getAllQuesters() public view returns(uint256[] memory){
        uint256[] memory search = new uint256[](5555);
        uint256 counter = 0;
        for(uint i=0;i<5555;i++){
             try ARCANE.ownerOf(i) returns (address) {
                if(ARCANE.ownerOf(i)==address(this)){
                    search[counter]=i;
                    counter++;
                }
            } catch {
                continue;
            }
            
        }
        uint256[] memory questers = new uint256[](counter);
        for(uint i=0;i<counter;i++){
            questers[i] = search[i];
        }
        return questers;
    }

    // INTERNAL
    // ------------------------------------------------------


    function _getTileValue(uint256 _zoneId, uint256 _x, uint256 _y) internal view returns(uint256){
        require(_x >= 0 && _y >= 0, "Move not valid");
        require(tileValues[_zoneId][_x][_y]!=0, "Tile is empty");
        return tileValues[_zoneId][_x][_y];
    }

    function _giveXP(uint256 _wizId, uint256 _eventsAmount) internal {
        if(wizardsXp[_wizId]<xpPerLevel[MAX_LVL]){
            uint256 baseMult = 1 + _eventsAmount;
            // earnedPoints = TOTAL_XP_NEEDED_TO_LEVELUP * amountOfEventsPassed / DIVIDER (dictactes amount of quests needed to level up)
            uint256 earnedPoints = xpPerLevel[currZones[_wizId]] * baseMult / xpPointsDivider;
            uint256 rand =uint(keccak256(abi.encodePacked(_wizId, block.timestamp, _eventsAmount))) % 100;
            earnedPoints += earnedPoints * rand /100;
        
            wizardsXp[_wizId]+=earnedPoints;
        }
    }

    function onERC721Received(
        address,
        address, 
        uint256,
        bytes calldata
    ) external pure override returns (bytes4) {
        return IERC721Receiver.onERC721Received.selector;
    }

    function _hoursElapsed(uint256 _time) internal view returns (uint256) {
        if (block.timestamp <= _time) {
            return 0;
        }

        return (block.timestamp - _time) / (60 * 60);
    }

    function abs(int x) private pure returns (int) {
        return x >= 0 ? x : -x;
    }

    function _eventToStat(uint256 _eventId) internal pure returns(uint256){
        if(_eventId==0){
            // EXPLORE -> Focus
            return 0;
        }else if(_eventId==1){
            // ADVENTURE -> Strength
            return 1;
        }else if(_eventId==2){
            // COMBAT -> Spell
            return 3;
        }else if(_eventId==3){
            // REST -> Endurance
            return 4;
        }else {
            // SPECIAL -> Intellect
            return 2;
        }
    }

    // OWNER
    // ------------------------------------------------------

    function setItems(address _items) external onlyOwner {
        ITEMS = IItems(_items);
    }

    function setZone(uint256 _size, uint256[] memory _gridValues, uint256 _zoneId, uint256 _startX, uint256 _startY) external onlyOwner{
        require(pausedQuesting, "Pause quests before updating zones");
        uint256 counter=0;
        uint256[20][20] memory temp;
        for(uint x = 0;x<_size;x++){
            for(uint y = 0;y<_size;y++){
                temp[x][y]= _gridValues[counter];
                counter++;
            }
        }
        tileValues[_zoneId] = temp;
        startX[_zoneId]=_startX;
        startY[_zoneId]=_startY;
    }

    function pauseQuesting(bool _flag) external onlyOwner{
        pausedQuesting= _flag;
    }

     function setArcane(address _arcane) external onlyOwner {
        ARCANE = IArcane(_arcane);
    }

    function setLoot(address _loot) external onlyOwner{
        LOOT = ILoot(_loot);
    }

    function setEvents(address _events) external onlyOwner{
        EVENTS = IEvents(_events);
    }

    function setSkillbook(address _skillbook) external onlyOwner{
        SKILLBOOK = ISkillbook(_skillbook);
    }

    function setCoinReward(address _coinReward) external onlyOwner{
        COINREWARD = ICoinReward(_coinReward);
    }

    function setConsumable(address _consumable) external onlyOwner{
        CONSUMABLE = IConsumable(_consumable);
    }

    function setQuestTime(uint256 _newTime) external onlyOwner{
        QUEST_TIME=_newTime;
    }

    function setMaxLevel(uint256 _maxLevel) external onlyOwner{
        MAX_LVL=_maxLevel;
    }

    // Start: 100
    function setXpPointsDivider(uint256 _divider) external onlyOwner{
        xpPointsDivider=_divider;
    }

    function setZoneItemLevels(uint256[] memory _zoneIds, uint256[] memory _itemLevels) external onlyOwner{
        for(uint i=0;i<_zoneIds.length;i++){
            zoneItemLevel[_zoneIds[i]] = _itemLevels[i];
        }
    }

     function setXpPerLevel(uint256[] memory _lvlIds, uint256[] memory _xpPerLevels) external onlyOwner{
        for(uint i=0;i<_lvlIds.length;i++){
            xpPerLevel[_lvlIds[i]] = _xpPerLevels[i];
        }
    }

   
}


