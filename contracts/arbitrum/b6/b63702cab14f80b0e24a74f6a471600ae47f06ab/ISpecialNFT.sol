//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC721EnumerableUpgradeable.sol";
import "./IMod.sol";

interface ISpecialNFT is IERC721EnumerableUpgradeable {
  function mintSpecialNFT(address receiver, uint256 specialNFTType)
    external
    returns (uint256);
  function mintSpecialNFTs(address receiver, uint256 _specialNFTType, uint256 amount)  external
    returns (uint256[] memory);
}

