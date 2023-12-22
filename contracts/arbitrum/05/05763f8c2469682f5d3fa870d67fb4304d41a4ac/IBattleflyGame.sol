//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;

interface IBattleflyGame {
  function mintBattlefly(address receiver, uint256 battleflyType)
    external
    returns (uint256);
    function mintSpecialNFT(address receiver, uint256 specialNFTType)
    external
    returns (uint256);
    function mintBattleflies(address receiver, uint256 battleflyType, uint256 amount) external returns (uint256[] memory);
    function mintSpecialNFTs(address receiver, uint256 specialNFTType, uint256 amount) external returns (uint256[] memory) ;

}

