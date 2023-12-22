pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Strings.sol";

interface IRandom { 
    function getRandoms(string memory seed, uint256 _size) external view returns (uint256[] memory);
}

contract Loot is Ownable{

    IRandom private RANDOM;
    // list of all itemIds that can be looted
    mapping (uint256 => uint256[]) compoIds;
    mapping (uint256 => uint256[]) compoDroprates;
    // a unique item ID per zone that can be looted with the special event
    mapping (uint256 => uint256)  specialItems;
    // specialItems droprates
    mapping (uint256 => uint256) specialDroprates;

    function getLoot(uint256 _zoneId, uint256 _tile, uint256 _eventAmount, uint256 _wizId, bool passedSpecial) external view returns(uint256[] memory, uint256[] memory ){
            
            uint256[] memory randoms = RANDOM.getRandoms(string(abi.encodePacked(_wizId, _tile)), 9); 

            // compoIds include all items for each zone, with their corresponding craftbook id
            uint256[6] memory filler;
            uint256 counter=1;
            for(uint i=0;i<filler.length;i++){
                filler[i]=10000;
            }

            // random[0] dictates how many loots you'll get
            // we add 10 for each successful events (min: 1, max: 4)
            for(uint i=0;i<_eventAmount;i++){
                randoms[0] +=10;
            }
            if(randoms[0]>99) randoms[0] = 99;

            // minimum - guaranteed first item
            filler[0] = compoIds[_zoneId][_getCompo(_zoneId, randoms[2])];

            // second item
            if(randoms[1]>50){
                filler[1] = compoIds[_zoneId][_getCompo(_zoneId, randoms[3])];
                counter++;
            }

            // third and potentially fourth item
            if(randoms[0] >= 50){
                filler[2] = compoIds[_zoneId][_getCompo(_zoneId, randoms[5])];
                counter++;
                if(randoms[4]>50){
                    filler[3] = compoIds[_zoneId][_getCompo(_zoneId, randoms[6])];
                    counter++;

                }
            }

            // fourth 
            if(randoms[0]>=75){
                filler[4] = compoIds[_zoneId][_getCompo(_zoneId, randoms[7])];
                counter++;

            }
            // additional roll for special
            if(_tile>1 && passedSpecial){
                
                if(randoms[8]<=specialDroprates[_tile]){
                    filler[5] = specialItems[_tile];
                    counter++;
                }
            }

            uint256[] memory lootIds = new uint256[](counter);
            uint256[] memory lootAmounts= new uint256[](counter);
            uint256 counter2 =0;
            for(uint i=0;i<filler.length;i++){
                if(filler[i]!=10000){
                    lootIds[counter2]=filler[i];
                    lootAmounts[counter2] = 1;
                    counter2++;
                }
            }
            return(lootIds, lootAmounts);
    }

    function _getCompo(uint256 _zoneId, uint256 _rand) internal view returns(uint256){
         uint256 totalWeight = 0;
        for (uint256 i = 0; i < compoDroprates[_zoneId].length; i++) {
            totalWeight += compoDroprates[_zoneId][i];
        }
        
        uint256 randomWeight = _rand * totalWeight / 100;
        for (uint256 i = 0; i < compoDroprates[_zoneId].length; i++) {
            if (randomWeight < compoDroprates[_zoneId][i]) {
                return i;
            }
            randomWeight -= compoDroprates[_zoneId][i];
        }
        
        revert("Weighted selection failed");
    }

    function setRandom (address _random) external onlyOwner {
        RANDOM = IRandom(_random);
    }

    function setCompoIds(uint256 _zoneId , uint256[] memory _itemIds, uint256[] memory _dropRates) external onlyOwner{
        compoIds[_zoneId]=_itemIds;
        compoDroprates[_zoneId] = _dropRates;
    }

    function setSpecialDrops(uint256[] memory _tileIds, uint256[] memory _itemIds, uint256[] memory _dropRates ) external onlyOwner{
        for(uint i=0;i<_tileIds.length;i++){
            specialItems[_tileIds[i]] = _itemIds[i];
            specialDroprates[_tileIds[i]] = _dropRates[i];
        }
    }

}
