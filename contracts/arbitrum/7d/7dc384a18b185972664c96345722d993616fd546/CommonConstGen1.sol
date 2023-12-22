// SPDX-License-Identifier: MIT

pragma solidity >=0.8.9 <0.9.0;

import "./Ownable.sol";

contract CommonConstGen1 is Ownable {
    struct IngredientType {
        uint8 from;
        uint8 to;
        uint8[] tokenIds;
    }
    mapping(uint => IngredientType) private ingredientTypes;
    uint256 public nonce;
    uint8 public typeCount;
    uint8[] private common;
    uint8[] private uncommon;
    uint8[] private rare;
    uint8[] private epic;

    constructor()  {
        common = [1,2,3,4,5];
        uncommon = [6,7,8];
        rare = [9,10,11,12,13,14,15,16,17,18,19];
        epic = [20,21,22,23,24];
        ingredientTypes[1] = IngredientType({from:1,to:60,tokenIds:common});
        ingredientTypes[2] = IngredientType({from:61,to:90,tokenIds:uncommon});
        ingredientTypes[3] = IngredientType({from:91,to:98,tokenIds:rare});
        ingredientTypes[4] = IngredientType({from:99,to:100,tokenIds:epic});
        nonce = 1;
        typeCount=4;
    }

    function random(uint8 from, uint256 to) private returns (uint8) {
        uint256 randomnumber = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))) % to;
        randomnumber = from + randomnumber;
        nonce++;
        return uint8(randomnumber);
    }

    function setCategory(uint8 category,uint8 from, uint8 to, uint8[] memory tokenIds) external onlyOwner{
        require(category <= typeCount, "only 4 categories exist");
        require(from <= to, "Invalid range");
        ingredientTypes[category] = IngredientType({from:from,to:to,tokenIds:tokenIds});
    }


    function getNftId(uint8 category) private returns(uint8){
        IngredientType memory ingredient = ingredientTypes[category];
        uint to = ingredient.tokenIds.length;
        uint num = random(1, to);
        return ingredient.tokenIds[num-1];
    }

    function getCategory(uint number) private view returns(uint8){
        uint8 index = 0;
        for(uint8 i = 1; i <= typeCount; i++) {
            if(number >= ingredientTypes[i].from &&  number <= ingredientTypes[i].to) {
                index = i;
            }
        }
        return index;
    }

    function revealIngredientNftId() external  returns(uint8){
        uint8 number = random(1,100);
        uint8 category = getCategory(number);
        return getNftId(category);
    }

    function printCategory(uint8 category) external view returns(IngredientType memory){
        return ingredientTypes[category];
    }
}
