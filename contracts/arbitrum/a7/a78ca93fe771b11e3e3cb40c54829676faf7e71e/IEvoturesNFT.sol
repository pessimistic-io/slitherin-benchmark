pragma solidity ^0.8.14;

// SPDX-License-Identifier: MIT

interface IEvoturesNFT {

    function mint(uint8 _evotures, uint8 _boosters, address to) external payable;
    function chainlinkMint(uint256[] memory _randomWords, uint8 _evotures, uint8 boosters_, address _minter) external;

    function BOOSTER_PRICE() external view returns(uint64);
    function dev() external view returns(address);
    function multipliers(uint16 id) external view returns(uint16 mult);
}
