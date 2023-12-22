// SPDX-License-Identifier: BUSL1.1

pragma solidity ^0.8.0;

import {ReaperBaseStrategyv4} from "./ReaperBaseStrategyv4.sol";
import {IStabilityPool} from "./IStabilityPool.sol";
import {IPriceFeed} from "./IPriceFeed.sol";
import {IVault} from "./IVault.sol";
import {AggregatorV3Interface} from "./AggregatorV3Interface.sol";
import {IERC20MetadataUpgradeable} from "./IERC20MetadataUpgradeable.sol";
import {SafeERC20Upgradeable} from "./SafeERC20Upgradeable.sol";
import {MathUpgradeable} from "./MathUpgradeable.sol";

/**
 * @dev Strategy to _compound rewards and liquidation collateral gains in the Ethos stability pool
 */
contract ReaperStrategyStabilityPool is ReaperBaseStrategyv4 {
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    // 3rd-party contract addresses
    IStabilityPool public stabilityPool;
    IPriceFeed public priceFeed;

    uint256 public constant ETHOS_DECIMALS = 18;

    /**
     * @dev Initializes the strategy. Sets parameters, saves routes, and gives allowances.
     * @notice see documentation for each variable above its respective declaration.
     */
    function initialize(
        address _vault,
        address _swapper,
        address _want,
        address[] memory _strategists,
        address[] memory _multisigRoles,
        address[] memory _keepers,
        address _stabilityPool,
        address _priceFeed
    ) public initializer {
        require(_vault != address(0), "vault is 0 address");
        require(_swapper != address(0), "swapper is 0 address");
        require(_want != address(0), "want is 0 address");
        require(_strategists.length != 0, "no strategists");
        require(_multisigRoles.length == 3, "invalid amount of multisig roles");
        require(_stabilityPool != address(0), "stabilityPool is 0 address");
        require(_priceFeed != address(0), "priceFeed is 0 address");
        __ReaperBaseStrategy_init(_vault, _swapper, _want, _strategists, _multisigRoles, _keepers);
        stabilityPool = IStabilityPool(_stabilityPool);
        priceFeed = IPriceFeed(_priceFeed);
    }

    function _liquidateAllPositions() internal override returns (uint256 amountFreed) {
        _withdraw(type(uint256).max);
        _harvestCore();
        return balanceOfWant();
    }

    function _beforeHarvestSwapSteps() internal override {
        _withdraw(0); // claim rewards
    }

    /**
     * @dev Function that puts the funds to work.
     * It gets called whenever someone deposits in the strategy's vault contract.
     * !audit we increase the allowance in the balance amount but we deposit the amount specified
     */
    function _deposit(uint256 toReinvest) internal override {
        if (toReinvest != 0) {
            stabilityPool.provideToSP(toReinvest);
        }
    }

    /**
     * @dev Withdraws funds and sends them back to the vault.
     */
    function _withdraw(uint256 _amount) internal override {
        if (_hasInitialDeposit(address(this))) {
            stabilityPool.withdrawFromSP(_amount);
        }
    }

    function balanceOfPool() public view override returns (uint256) {
        uint256 lusdValue = stabilityPool.getCompoundedLUSDDeposit(address(this));
        uint256 collateralValue = getCollateralGain();
        // assumes 1 ERN = 1 USD
        return lusdValue + collateralValue;
    }

    function getCollateralGain() public view returns (uint256 collateralGain) {
        (address[] memory assets, uint256[] memory amounts) = stabilityPool.getDepositorCollateralGain(address(this));

        for (uint256 i = 0; i < assets.length; i++) {
            address asset = assets[i];
            uint256 amount = amounts[i] + IERC20MetadataUpgradeable(asset).balanceOf(address(this));
            collateralGain += _getUSDEquivalentOfCollateral(asset, amount);
        }
    }

    // Returns USD equivalent of {_amount} of {_collateral} with 18 digits of decimal precision.
    // The precision of {_amount} is whatever {_collateral}'s native decimals are (ex. 8 for wBTC)
    function _getUSDEquivalentOfCollateral(address _collateral, uint256 _amount) internal view returns (uint256) {
        uint256 scaledAmount = _getScaledFromCollAmount(_amount, IERC20MetadataUpgradeable(_collateral).decimals());
        uint256 price = _getCollateralPrice(_collateral);
        uint256 USDAssetValue = (scaledAmount * price) / (10 ** _getCollateralDecimals(_collateral));
        return USDAssetValue;
    }

    function _hasInitialDeposit(address _user) internal view returns (bool) {
        return stabilityPool.deposits(_user).initialValue != 0;
    }

    function _getCollateralPrice(address _collateral) internal view returns (uint256 price) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        (, int256 signedPrice,,,) = aggregator.latestRoundData();
        price = uint256(signedPrice);
    }

    function _getCollateralDecimals(address _collateral) internal view returns (uint256 decimals) {
        AggregatorV3Interface aggregator = AggregatorV3Interface(priceFeed.priceAggregator(_collateral));
        decimals = uint256(aggregator.decimals());
    }

    function _getScaledFromCollAmount(uint256 _collAmount, uint256 _collDecimals)
        internal
        pure
        returns (uint256 scaledColl)
    {
        scaledColl = _collAmount;
        if (_collDecimals > ETHOS_DECIMALS) {
            scaledColl = scaledColl / (10 ** (_collDecimals - ETHOS_DECIMALS));
        } else if (_collDecimals < ETHOS_DECIMALS) {
            scaledColl = scaledColl * (10 ** (ETHOS_DECIMALS - _collDecimals));
        }
    }
}

