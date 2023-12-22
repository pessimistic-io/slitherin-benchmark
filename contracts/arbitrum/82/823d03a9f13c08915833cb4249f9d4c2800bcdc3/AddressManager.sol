// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

// external
import "./Initializable.sol";

// internal
import "./ProxyOwned.sol";
import "./ProxyPausable.sol";

import "./IAddressManager.sol";

/// @title An address manager where all common addresses are stored
contract AddressManager is Initializable, ProxyOwned, ProxyPausable {
    address public safeBox;

    address public referrals;

    address public stakingThales;

    address public multiCollateralOnOffRamp;

    address public pyth;

    address public speedMarketsAMM;

    function initialize(
        address _owner,
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    ) external initializer {
        setOwner(_owner);
        safeBox = _safeBox;
        referrals = _referrals;
        stakingThales = _stakingThales;
        multiCollateralOnOffRamp = _multiCollateralOnOffRamp;
        pyth = _pyth;
        speedMarketsAMM = _speedMarketsAMM;
    }

    //////////////////getters/////////////////

    /// @notice get all addresses
    function getAddresses() external view returns (IAddressManager.Addresses memory) {
        IAddressManager.Addresses memory allAddresses;

        allAddresses.safeBox = safeBox;
        allAddresses.referrals = referrals;
        allAddresses.stakingThales = stakingThales;
        allAddresses.multiCollateralOnOffRamp = multiCollateralOnOffRamp;
        allAddresses.pyth = pyth;
        allAddresses.speedMarketsAMM = speedMarketsAMM;

        return allAddresses;
    }

    //////////////////setters/////////////////

    /// @notice set corresponding addresses
    function setAddresses(
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    ) external onlyOwner {
        safeBox = _safeBox;
        referrals = _referrals;
        stakingThales = _stakingThales;
        multiCollateralOnOffRamp = _multiCollateralOnOffRamp;
        pyth = _pyth;
        speedMarketsAMM = _speedMarketsAMM;
        emit SetAddresses(_safeBox, _referrals, _stakingThales, _multiCollateralOnOffRamp, _pyth, _speedMarketsAMM);
    }

    //////////////////events/////////////////

    event SetAddresses(
        address _safeBox,
        address _referrals,
        address _stakingThales,
        address _multiCollateralOnOffRamp,
        address _pyth,
        address _speedMarketsAMM
    );
}

