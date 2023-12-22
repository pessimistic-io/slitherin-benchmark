// SPDX-License-Identifier: MIT LICENSE
import "./Strings.sol";
import "./ITraits.sol";
import "./IPeekABoo.sol";

pragma solidity ^0.8.0;

contract TraitsBase {
    using Strings for uint256;

    IPeekABoo public peekaboo;
    mapping(uint256 => mapping(uint256 => ITraits.Trait))[2] public traitData;
    mapping(uint256 => uint256[4])[2] public traitRarityIndex;
}

