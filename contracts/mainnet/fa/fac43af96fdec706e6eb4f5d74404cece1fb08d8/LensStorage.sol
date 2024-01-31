// SPDX-License-Identifier: GNU AGPLv3
pragma solidity 0.8.13;

import "./ICompound.sol";
import "./interfaces_IMorpho.sol";

import "./CompoundMath.sol";
import "./libraries_InterestRatesModel.sol";
import "./math_Math.sol";

import {ERC20} from "./ERC20_ERC20.sol";
import "./Initializable.sol";

/// @title LensStorage.
/// @author Morpho Labs.
/// @custom:contact security@morpho.xyz
/// @notice Base layer to the Morpho Protocol Lens, managing the upgradeable storage layout.
abstract contract LensStorage is Initializable {
    /// STORAGE ///

    uint256 public constant MAX_BASIS_POINTS = 10_000; // 100% (in basis points).
    uint256 public constant WAD = 1e18;

    IMorpho public morpho;
    IComptroller public comptroller;
    IRewardsManager public rewardsManager;

    /// CONSTRUCTOR ///

    /// @notice Constructs the contract.
    /// @dev The contract is automatically marked as initialized when deployed so that nobody can highjack the implementation contract.
    constructor() initializer {}
}

