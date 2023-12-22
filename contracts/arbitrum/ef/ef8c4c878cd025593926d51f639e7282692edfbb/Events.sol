pragma solidity ^0.8.0;

import "./Ownable.sol";


contract Events is Ownable {
    enum EventType { EXPLORE, ADVENTURE, COMBAT, REST, SPECIAL }

    struct Event {
        uint8 eventType;
        uint256 rand;
    } 

    // EXTERNAL
    // ------------------------------------------------------

    // events + loots... so format should be [ [ eventId, rand ], [ eventId, rand ] ]
    function getEvents(uint256 _wizId, uint256 _tile) external view returns (Event[] memory) {
        // get our array of randoms
        uint[] memory randArr = new uint[](10);
        for (uint i = 0; i < 10; i++){
            randArr[i] = i;
        }
        // 0 is #of events, 1 2 3 4  are events Id, 5 6 7 8 are rands
        bool specialTile = _tile > 1;
        uint[] memory eventRands= _randomArr(randArr,_wizId, specialTile);
    
        Event[] memory toReturn = new Event[](eventRands[0]);
        for(uint e=0;e<eventRands[0];e++){
            // choose type 
            Event memory newEvent = Event(uint8(eventRands[e+1]), eventRands[e+5]);
            toReturn[e] = newEvent;
        }
        // TODO make a last pass on the events and make one SPECIAL if its a special tile
        // otherwise it will alwyas come last?
        // BUT special can never be index 0 or it will have 100% chance to trigger

        return toReturn;
    }

    // INTERNAL
    // ------------------------------------------------------

    // if _special, include the last type of events
     // Returns:  0 is #of events, 1 2 3 4 are events Id, 5 6 7 8 are rands
    function _randomArr(uint[] memory _myArray, uint256 _wizId, bool _special) internal view returns(uint[] memory){
        // uint a = _myArray.length; 
        uint b = _myArray.length;
        for(uint i = 0; i< b ; i++){
            uint div = 100;
            if(i==0) div = 4;
            // if it's a special tile, any of the events can be special, even multiple
            if(_special){
                if(i>0 && i<5) div = 5;              
            }else{
                if(i>0 && i<5) div = 4;
            }
            uint randNumber =uint(keccak256      
            (abi.encodePacked(block.timestamp, _wizId,_myArray[i]))) % div;
            // uint randForInterim=(randNumber % a) +1;
            // _myArray[randForInterim-1]= _myArray[a-1];
            _myArray[i] = randNumber;
            // a = a-1;
        }
        // uint256[] memory result;
        // result = _myArray; 
        if(_myArray[0]<1) _myArray[0]=1;      
        return _myArray;        
    }

}
