// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.9;

// Contracts
import {ERC20} from "./ERC20.sol";
import {ERC4626} from "./ERC4626.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

// Libraries
import {Strings} from "./Strings.sol";

import {OptionScalp} from "./OptionScalp.sol";

/**
 * @title Scalp LP Token
 */
contract ScalpLP is ERC4626 {

    using SafeTransferLib for ERC20;

    /// @dev The address of the scalp contract creating the lp token
    OptionScalp public scalp;

    /// @dev The address of the collateral contract for the scalp lp
    ERC20 public collateral;

    /// @dev The symbol reperesenting the underlying asset of the scalp lp
    string public underlyingSymbol;

    /// @dev The symbol representing the collateral token of the scalp lp
    string public collateralSymbol;

    // @dev Total collateral assets available
    uint public _totalAssets;

    // @dev Locked liquidity in active scalp positions
    uint public _lockedLiquidity;

    /*==== CONSTRUCTOR ====*/
    /**
     * @param _scalp The address of the scalp contract creating the lp token
     * @param _collateral The address of the collateral asset in the scalp contract
     * @param _collateralSymbol The symbol of the collateral asset token
     */
    constructor(
        address _scalp,
        address _collateral,
        string memory _collateralSymbol
    ) ERC4626(ERC20(_collateral), "Scalp LP Token", "ScLP") {
        scalp = OptionScalp(_scalp);
        collateralSymbol = _collateralSymbol;

        symbol = concatenate(_collateralSymbol, "-LP");
    }

    /*==== PURE FUNCTIONS ====*/

    /**
     * @notice Returns a concatenated string of a and b
     * @param _a string a
     * @param _b string b
     */
    function concatenate(string memory _a, string memory _b)
        internal
        pure
        returns (string memory)
    {
        return string(abi.encodePacked(_a, _b));
    }

    function totalAssets() public view virtual override returns (uint) {
        return _totalAssets;
    }

    function totalAvailableAssets() public view returns (uint) {
        return _totalAssets - _lockedLiquidity;
    }

    function lockLiquidity(uint amount) public  {
        require(msg.sender == address(scalp), "Only scalp can call this function");
        _lockedLiquidity += amount;
    }

    function unlockLiquidity(uint amount) public {
        require(msg.sender == address(scalp), "Only scalp can call this function");
        _lockedLiquidity -= amount;
    }

    // Adds premium and fees to total available assets
    function addProceeds(uint proceeds) public {
        require(msg.sender == address(scalp), "Only scalp can call this function");
        _totalAssets += proceeds;
    }

    // Subtract loss from total available assets
    function subtractLoss(uint loss) public {
        require(msg.sender == address(scalp), "Only scalp can call this function");
        _totalAssets -= loss;
    }

    function beforeWithdraw(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        require(assets <= totalAvailableAssets(), "Not enough available assets to satisfy withdrawal");
        /// -----------------------------------------------------------------------
        /// Withdraw assets from Scalp contract
        /// -----------------------------------------------------------------------
        scalp.claimCollateral(assets);
        _totalAssets -= assets;
    }

    function afterDeposit(uint256 assets, uint256 /*shares*/ ) internal virtual override {
        /// -----------------------------------------------------------------------
        /// Deposit assets into Scalp contract
        /// -----------------------------------------------------------------------
        _totalAssets += assets;
        // approve to scalp
        asset.safeApprove(address(scalp), assets);
        // deposit into scalp
        asset.safeTransfer(address(scalp), assets);
    }
}

