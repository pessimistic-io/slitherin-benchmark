//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC721EnumerableUpgradeable.sol";
import "./IBattlefly.sol";

interface IHyperdome is IERC721EnumerableUpgradeable {
 
  function mintHyperdome(address receiver)
    external
    returns (uint256);
}

