//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Initializable.sol";

import "./TreasuryContracts.sol";

abstract contract TreasurySettings is Initializable, TreasuryContracts {

    function __TreasurySettings_init() internal initializer {
        TreasuryContracts.__TreasuryContracts_init();
    }

    function setUtilNeededToPowerBW(uint256 _utilNeededToPowerBW) external onlyAdminOrOwner {
        require(_utilNeededToPowerBW <= 1 * 10**18, "Bad percent");
        utilNeededToPowerBW = _utilNeededToPowerBW;
    }

    function setpercentMagicToMine(uint256 _percentMagicToMine) external onlyAdminOrOwner {
        require(_percentMagicToMine >= 0 && _percentMagicToMine <= 100, "Bad percent");
        percentMagicToMine = _percentMagicToMine;
    }

}
