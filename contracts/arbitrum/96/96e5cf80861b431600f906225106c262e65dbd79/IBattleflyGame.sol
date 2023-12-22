//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;

interface IBattleflyGame {
  function mintBattlefly(address receiver, uint256 battleflyType)
    external
    returns (uint256);
    function mintSpecialNFT(address receiver, uint256 specialNFTType)
    external
    returns (uint256);
    function mintBattleflies(address[] memory receivers, uint256[] memory battleflyTypes) external  returns (uint256[] memory);
    function mintSpecialNFTs(address[] memory receivers, uint256[] memory specialNFTTypes) external  returns (uint256[] memory);

}

