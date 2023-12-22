// SPDX-License-Identifier: Unlicense
pragma solidity ^0.8.0;

import "./SmolsLibrary.sol";

interface ISmolsTraitStorage {
    function traits(uint256 _traitId, uint256 _dependencyLevel) external view returns(Trait memory);

    function getTrait(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (Trait memory);

    function getTraitType(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory);
        
    function getTraitName(uint256 _traitId, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory);

    function getTraitImage(uint256 _traitId, uint8 _gender, uint256 _dependencyLevel)
        external
        view
        returns (bytes memory);
}

