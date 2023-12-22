// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import { ControllableUpgradeable } from "./ControllableUpgradeable.sol";
import { Constants } from "./Constants.sol";

abstract contract FeeMapping is ControllableUpgradeable {
    error feePercTooLarge();
    error indexOutOfBound();

    /// @dev keep track of fee types being used by the vault
    mapping(bytes32 => uint256) internal feeMapping;

    /// @dev add the fee types being used by the vault
    /// note if we want to delete the mapping, pass _feeType with empty array
    function addFeePerc(bytes32[] memory _feeType, uint256[] memory _perc) public onlyMultisig {
        uint256 _feeTypeLength = _feeType.length;
        if (_feeTypeLength != _perc.length) revert indexOutOfBound();

        for (uint256 i; i < _feeTypeLength; ++i) {
            if (_perc[i] > Constants.MAX_FEE_PERC) revert feePercTooLarge();
            feeMapping[_feeType[i]] = _perc[i];
        }
    }

    function getFeePerc(bytes32 _feeType) public view returns (uint256 perc) {
        return (feeMapping[_feeType]);
    }

    uint256[49] private __gap;
}

