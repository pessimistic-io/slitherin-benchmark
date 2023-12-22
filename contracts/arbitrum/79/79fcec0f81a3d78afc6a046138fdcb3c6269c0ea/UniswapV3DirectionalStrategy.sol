// SPDX-License-Identifier: BUSL-1.1

pragma solidity ^0.8.17;

import "./AccessControl.sol";
import "./IAddressProvider.sol";
import "./IBorrower.sol";
import "./ISwapper.sol";
import "./IOracle.sol";
import "./IController.sol";
import "./IStrategyVault.sol";
import "./ILendVault.sol";
import "./IWETH.sol";
import "./IUniswapV3Integration.sol";
import "./IUniswapV3StrategyData.sol";
import "./AddressArray.sol";
import "./UintArray.sol";
import "./UniswapV3BaseStrategy.sol";
import "./UniswapV3DeltaNeutralStrategy.sol";
import "./Math.sol";
import "./Address.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";
import "./SafeERC20.sol";
import {FullMath} from "./FullMath.sol";
import "./INonfungiblePositionManager.sol";
import "./IUniswapV3Pool.sol";
import "./LiquidityAmounts.sol";
import "./TickMath.sol";
import "./console.sol";

/**
 * @notice Strategy that borrows from LendVault and deposits into a uni v3 pool
 */
contract UniswapV3DirectionalStrategy is UniswapV3DeltaNeutralStrategy {
    using AddressArray for address[];
    using Address for address;
    using SafeERC20 for IERC20;
    using UintArray for uint[];

    /**
     * @notice Initialize upgradeable contract
     */
    function initialize(
        address _provider,
        Addresses memory _addresses,
        Thresholds memory _thresholds,
        Parameters memory _parameters
    ) external override initializer {
        _UniswapV3BaseStrategy__init(_provider, _addresses, _thresholds, _parameters);
    }
    
    /**
     * @notice Perform amm check and check if strategy needs rebalancing, returns equity, price change and amount to rebalance by
     * @return ammCheck Wether uniswap pool and oracle price are close to each other
     * @return health Health of the strategy calculated by the LendVault
     * @return equity Total asset value minus total debt value reported in terms of the deposit token
     * @return currentPrice current price of the volatile token
     */
    function heartBeat()
        override
        public
        view
        returns (
            bool ammCheck,
            int256 health,
            int256 equity,
            uint256 currentPrice
        )
    {
        ILendVault lendVault = ILendVault(provider.lendVault());
        IOracle oracle = IOracle(provider.oracle());
        equity = balance();
        ammCheck = _ammCheck();
        health = lendVault.checkHealth(address(this));
        currentPrice = oracle.getPrice(addresses.stableToken);
    }

    /**
     * @notice Update the strategy leverage and tick range
     * @dev This function can be used to change leverage, rebalance and set ticks,
     * since all of them involve a complete withdrawal followed by strategy parameter
     * changes and a new deposit
     * @dev Adding a tick update with leverage change and rebalance has the benefit of
     * ensuring the uniswap pool tick stays within range as well as ensuring that the
     * borrowed amounts are in the desired ratio based on the strategy leverage
     */
    function setLeverageAndTicks(
        uint _leverage,
        int24 _multiplier0,
        int24 _multiplier1
    ) external override restrictAccess(KEEPER | GOVERNOR) requireAmmCheck trackPriceChangeImpact {
        require(_leverage>parameters.minLeverage && _leverage<parameters.maxLeverage, "E8");
        _withdraw(PRECISION);
        _harvest();
        parameters.leverage = _leverage;
        _setTicks(_multiplier0, _multiplier1);
        positionId = 0;
        numRebalances+=1;
        _deposit();

        // Update price anchor
        IOracle oracle = IOracle(provider.oracle());
        priceAnchor = oracle.getPrice(addresses.stableToken);

        emit SetLeverageAndTicks(_leverage, parameters.tick0, parameters.tick1);
    }

    function getAddresses() external override view returns (address want, address stableToken, address volatileToken, address positionsManager) {
        want = addresses.want;
        stableToken = addresses.volatileToken;
        volatileToken = addresses.stableToken;
        positionsManager = addresses.positionsManager;
    }
}
