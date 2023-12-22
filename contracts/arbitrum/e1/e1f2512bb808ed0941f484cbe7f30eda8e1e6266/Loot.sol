pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./Strings.sol";


interface IRandom { 
    function getRandoms(string memory seed, uint256 _size) external view returns (uint256[] memory);
}

contract Loot is Ownable{

    IRandom private RANDOM;

    mapping (uint256 => uint256[]) compoIds;
    mapping (uint256 => uint256)  specialItems;
    mapping (uint256 => uint256) droprates;

    function getLoot(uint256 _zoneId, uint256 _tile, uint256 _eventAmount, uint256 _wizId, bool passedSpecial) external view returns(uint256[] memory, uint256[] memory ){
            
            uint256[] memory randoms = RANDOM.getRandoms(string(abi.encodePacked(_wizId, _tile)), 9); 

            // compoIds include all items for each zone, with their corresponding craftbook id
            uint256[6] memory filler;
            uint256 counter=1;
            for(uint i=0;i<filler.length;i++){
                filler[i]=10000;
            }

            // add event amount
            for(uint i=0;i<_eventAmount;i++){
                randoms[0] +=10;
            }
            if(randoms[0]>99) randoms[0] = 99;

            // min
            filler[0] = compoIds[_zoneId][randoms[2] % compoIds[_zoneId].length];
            if(randoms[1]>50){
                filler[1] = compoIds[_zoneId][randoms[3] % compoIds[_zoneId].length];
                counter++;
            }

            // mid
            if(randoms[0] >= 50){
                filler[2] = compoIds[_zoneId][randoms[5] % compoIds[_zoneId].length];
                counter++;
                if(randoms[4]>50){
                    filler[3] = compoIds[_zoneId][randoms[6] % compoIds[_zoneId].length];
                    counter++;

                }
            }

            // high - find item : zoneLvl * 33 + rand (0-33)
            if(randoms[0]>=75){
                filler[4] = (_zoneId * 33) + (randoms[7] % 33);
                counter++;

            }
            // additional roll for special
            if(_tile>1 && passedSpecial){
                
                if(randoms[8]<=droprates[_tile]){
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

    function setRandom (address _random) external onlyOwner {
        RANDOM = IRandom(_random);
    }

    function setCompoIds(uint256 _zoneId , uint256[] memory _itemIds) external onlyOwner{
        compoIds[_zoneId]=_itemIds;
    }

    function setSpecialDrops(uint256[] memory _tileIds, uint256[] memory _itemIds, uint256[] memory _dropRates ) external onlyOwner{
        for(uint i=0;i<_tileIds.length;i++){
            specialItems[_tileIds[i]] = _itemIds[i];
            droprates[_tileIds[i]] = _dropRates[i];
        }
    }

}
