// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

contract ShrineConst {
    uint private ceilSuccessNo;
    uint private get1TotalSupply;
    uint private pancakeSupply;
    uint256 public nonce;
    constructor()  {
       get1TotalSupply = 510;
       pancakeSupply = 18;
       nonce=1;
        ceilSuccessNo = 10000;
    }

    function random(uint8 from, uint256 to) private returns (uint) {
        uint256 randomnumber = uint(keccak256(abi.encodePacked(block.timestamp, msg.sender, nonce))) % to;
        randomnumber = from + randomnumber;
        nonce++;
        return randomnumber;
    }


    function revealNumber(uint8 from, uint256 to) external returns(uint256){
        uint num =  random(from,to);
        return num;
    }

    function revealSuccessNumber() external returns(uint256){
        uint num =  random(1,ceilSuccessNo);
        return num;
    }

    function revealGen1NftId() external returns(uint256){
        uint num = random(1,get1TotalSupply);
        return num;
    }

    function revealPancakeIdNftId() external returns(uint256){
        uint num = random(1,pancakeSupply);
        return num;
    }
}
