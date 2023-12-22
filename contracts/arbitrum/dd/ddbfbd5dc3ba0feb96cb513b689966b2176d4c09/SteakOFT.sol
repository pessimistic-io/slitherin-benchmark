pragma solidity ^0.8.0;

import "./OFTWithFee.sol";

contract SteakOFT is OFTWithFee {
    constructor(address _lzEndpoint) OFTWithFee("STEAK", "STEAK", 8, _lzEndpoint){}

    function decimals() public pure override returns (uint8){
        return 18;
    }
}

/*
npx hardhat verify --contract contracts/SteakOFT.sol:SteakOFT --network arbitrum 0xddBfBd5dc3BA0FeB96Cb513B689966b2176d4c09 0x3c2269811836af69497E5F486A85D7316753cf62

*/
