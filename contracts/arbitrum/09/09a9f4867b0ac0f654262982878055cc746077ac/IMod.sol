//SPDX-License-Identifier: Unlicense
pragma solidity >=0.6.0;
import "./IERC721EnumerableUpgradeable.sol";

interface IMod is IERC721EnumerableUpgradeable {
    function mintMod(address receiver) external returns (uint256);
}

