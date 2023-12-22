// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.0;

import "./IPriceOracle.sol";
import "./DataTypes.sol";

abstract contract PoolStorage {
    /// @notice The address of the price oracle
    IPriceOracle public priceOracle;

    /// @notice Issuer allocation (%) of fee
    uint public issuerAlloc;

    /// @notice Basis points constant. 10000 basis points * 1e18 = 100%
    uint public constant BASIS_POINTS = 10000;
    uint public constant SCALER = 1e18;

    address public WETH_ADDRESS;

    /// @notice The synth token used to pass on to vault as fee
    address public feeToken;

    /// @notice If synth is enabled
    mapping(address => DataTypes.Synth) public synths;
    /// @notice The list of synths in the pool. Needed to calculate total debt
    address[] public synthsList;

    /// @notice Collateral asset addresses. User => Collateral => Balance
    mapping(address => mapping(address => uint256)) public accountCollateralBalance;
    /// @notice Checks in account has entered the market
    // market -> account -> isMember
    mapping(address => mapping(address => bool)) public accountMembership;
    /// @notice Collaterals the user has deposited
    mapping(address => address[]) public accountCollaterals;

    /// @notice Mapping from collateral asset address to collateral data
    mapping(address => DataTypes.Collateral) public collaterals;

    uint256[50] private __gap;
}
