// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./PriceConvertor.sol";
import "./IPool.sol";
import "./IERC20X.sol";
import "./ISyntheX.sol";
import "./Errors.sol";
import "./SafeERC20Upgradeable.sol";
import "./IWETH.sol";

library PoolLogic {
    using PriceConvertor for uint256;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    uint constant BASIS_POINTS = 10000;

    /* -------------------------------------------------------------------------- */
    /*                                 Collaterals                                */
    /* -------------------------------------------------------------------------- */
    event CollateralParamsUpdated(address indexed asset, uint cap, uint baseLTV, uint liqThreshold, uint liqBonus, bool isEnabled);

    /**
     * @notice Update collateral params
     * @notice Only L1Admin can call this function 
     */
    function update(
        mapping(address => DataTypes.Collateral) storage collaterals, 
        address _collateral, 
        DataTypes.Collateral memory _params
    ) public {
        DataTypes.Collateral storage collateral = collaterals[_collateral];
        // if max deposit is less than total deposits, set max deposit to total deposits
        if(_params.cap < collateral.totalDeposits){
            _params.cap = collateral.totalDeposits;
        }
        // update collateral params
        collateral.cap = _params.cap;
        require(_params.baseLTV >= 0 && _params.baseLTV <= BASIS_POINTS, Errors.INVALID_ARGUMENT);
        collateral.baseLTV = _params.baseLTV;
        require(_params.liqThreshold >= _params.baseLTV && _params.liqThreshold <= BASIS_POINTS, Errors.INVALID_ARGUMENT);
        collateral.liqThreshold = _params.liqThreshold;
        require(_params.liqBonus >= BASIS_POINTS && _params.liqBonus <= BASIS_POINTS + (BASIS_POINTS - (_params.liqThreshold)), Errors.INVALID_ARGUMENT);
        collateral.liqBonus = _params.liqBonus;

        collateral.isActive = _params.isActive;

        emit CollateralParamsUpdated(_collateral, _params.cap, _params.baseLTV, _params.liqThreshold, _params.liqBonus, _params.isActive);
    }

    /* -------------------------------------------------------------------------- */
    /*                                   Synths                                   */
    /* -------------------------------------------------------------------------- */

    event SynthUpdated(address indexed synth, bool isActive, bool isDisabled, uint mintFee, uint burnFee);
    event SynthRemoved(address indexed synth);

    /**
     * @dev Add a new synth to the pool
     * @notice Only L1Admin can call this function
     */
    function add(mapping(address => DataTypes.Synth) storage synths, address[] storage synthsList, address _synth, DataTypes.Synth memory _params) public {
        for(uint i = 0; i < synthsList.length; i++){
            require(synthsList[i] != _synth, Errors.ASSET_NOT_ACTIVE);
        }
        // Add the synth to the list of synths
        synthsList.push(_synth);
        // Update synth params
        update(synths, _synth, _params);
    }

    /**
     * @dev Update synth params
     * @notice Only L1Admin can call this function
     */
    function update(mapping(address => DataTypes.Synth) storage synths, address _synth, DataTypes.Synth memory _params) public {
        // Update synth params
        synths[_synth].isActive = _params.isActive;
        synths[_synth].isDisabled = _params.isDisabled;
        require(_params.mintFee < BASIS_POINTS, Errors.INVALID_ARGUMENT);
        synths[_synth].mintFee = _params.mintFee;
        require(_params.burnFee < BASIS_POINTS, Errors.INVALID_ARGUMENT);
        synths[_synth].burnFee = _params.burnFee;

        // Emit event on synth enabled
        emit SynthUpdated(_synth, _params.isActive, _params.isDisabled, _params.mintFee, _params.burnFee);
    }

    /**
     * @dev Removes the synth from the pool
     * @param _synth The address of the synth to remove
     * @notice Removes from synthList => would not contribute to pool debt
     * @notice Only L1Admin can call this function
     */
    function remove(mapping(address => DataTypes.Synth) storage synths, address[] storage synthsList, address _synth) public {
        synths[_synth].isActive = false;
        for (uint i = 0; i < synthsList.length; i++) {
            if (synthsList[i] == _synth) {
                synthsList[i] = synthsList[synthsList.length - 1];
                synthsList.pop();
                emit SynthRemoved(_synth);
                break;
            } 
        }
    }

    /* -------------------------------------------------------------------------- */
    /*                                  Liquidity                                 */
    /* -------------------------------------------------------------------------- */

    /**
     * @dev Get the total adjusted position of an account: E(amount of an asset)*(volatility ratio of the asset)
     */
    function accountLiquidity(
        IPriceOracle oracle, 
        address[] memory accountCollaterals, 
        mapping(address => uint) storage accountCollateralBalance, 
        mapping(address => DataTypes.Collateral) storage collaterals,
        uint userDebt
    ) public view returns(DataTypes.AccountLiquidity memory liq) {
        // Iterate over all the collaterals of the account
        for(uint i = 0; i < accountCollaterals.length; i++){
            address collateral = accountCollaterals[i];
            uint price = oracle.getAssetPrice(collateral);
            // Add the collateral amount
            // AdjustedCollateralAmountUSD = CollateralAmount * Price * volatilityRatio
            liq.liquidity += int(
                (accountCollateralBalance[collateral]
                 * (collaterals[collateral].baseLTV)
                 / (BASIS_POINTS))                      // adjust for volatility ratio
                .toUSD(price));
            // collateralAmountUSD = CollateralAmount * Price 
            liq.collateral += (
                accountCollateralBalance[collateral]
                .toUSD(price)
            );
        }

        liq.debt = userDebt;
        liq.liquidity -= int(liq.debt);
    }

    /**
     * @dev Get the total debt of a trading pool
     * @return totalDebt The total debt of the trading pool
     */
    function totalDebtUSD(
        address[] memory _synths, 
        IPriceOracle _oracle
    ) public view returns(uint totalDebt) {
        totalDebt = 0;
        // Iterate through the list of synths and add each synth's total supply in USD to the total debt
        for(uint i = 0; i < _synths.length; i++){
            address synth = _synths[i];
            // synthDebt = synthSupply * price
            totalDebt += (
                IERC20X(synth).totalSupply().toUSD(_oracle.getAssetPrice(synth))
            );
        }
    }

    /**
     * @dev Get the debt of an account in this trading pool
     * @param totalSupply The total supply of the trading pool's debt tokens
     * @param balance The balance of the account's debt tokens
     * @param totalDebt The total debt of the trading pool in USD
     */
    function userDebtUSD(
        uint totalSupply, 
        uint balance, 
        uint totalDebt
    ) public pure returns(uint){
        // If totalShares == 0, there's zero pool debt
        if(totalSupply == 0){
            return 0;
        }
        // Get the debt of the account in the trading pool, based on its debt share balance
        return balance * totalDebt / totalSupply; 
    }
}
