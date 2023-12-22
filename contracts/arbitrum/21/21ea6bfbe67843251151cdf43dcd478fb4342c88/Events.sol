pragma solidity ^0.8.0;

import "./Ownable.sol";

interface IRandom { 
    function getRandoms(string memory seed, uint256 _size) external view returns (uint256[] memory);
}

contract Events is Ownable {
    enum EventType { EXPLORE, ADVENTURE, COMBAT, REST, SPECIAL }

    struct Event {
        uint8 eventType;
        uint256 rand;
    } 

    IRandom public RANDOM;

    // EXTERNAL
    // ------------------------------------------------------

    // events + loots... so format should be [ [ eventId, rand ], [ eventId, rand ] ]
    function getEvents(uint256 _wizId, uint256 _tileType) external view returns (Event[] memory) {
        // get our array of randoms
        uint[] memory randArr = new uint[](10);
        for (uint i = 0; i < 10; i++){
            randArr[i] = i;
        }
        // maximum 4 events
        // 0 is # of events, 1 2 3 4  are events Id, 5 6 7 8 are rands
        bool specialTile = _tileType > 1;
        uint[] memory eventRands= _randomArr(randArr,_wizId, specialTile);
    
        Event[] memory toReturn = new Event[](eventRands[0]);
        for(uint e=0;e<eventRands[0];e++){
            // choose type 
            Event memory newEvent = Event(uint8(eventRands[e+1]), eventRands[e+5]);
            toReturn[e] = newEvent;
        }

        return toReturn;
    }

    // INTERNAL
    // ------------------------------------------------------
    // some tiles are marked 'special' and trigger the 5th type of event
     // Returns:  0 is # of events, 1 2 3 4 are events Id, 5 6 7 8 are rands
    function _randomArr(uint[] memory _myArray, uint256 _wizId, bool _special) internal view returns(uint[] memory){
        uint256[] memory rands = RANDOM.getRandoms(string(abi.encodePacked(_wizId,_special)), 10);
        for(uint i = 0; i< _myArray.length ; i++){
            uint div = 100;
            if(i==0) div = 4;
            // if it's a special tile, any of the events can be special, even multiple
            if(_special){
                if(i>0 && i<5) div = 5;              
            }else{
                if(i>0 && i<5) div = 4;
            }
            uint randNumber = rands[i] % div;

            _myArray[i] = randNumber;
        }
        if(_myArray[0]<1) _myArray[0]=1;      
        return _myArray;        
    }

    function setRandomizer(address _random) external onlyOwner(){
        RANDOM = IRandom(_random);
    }

}
