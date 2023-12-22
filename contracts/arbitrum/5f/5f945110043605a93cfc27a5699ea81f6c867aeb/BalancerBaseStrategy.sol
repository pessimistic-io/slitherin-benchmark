// SPDX-License-Identifier: GNU GPLv3
pragma solidity >=0.8.10;

////////////////////////////////////////////////////////////////////////////////////////
//                                                                                    //
//                                                                                    //
//                              #@@@@@@@@@@@@@@@@@@@@&,                               //
//                      .@@@@@   .@@@@@@@@@@@@@@@@@@@@@@@@@@@*                        //
//                  %@@@,    @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                    //
//               @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@                 //
//             @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@               //
//           *@@@#    .@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//          *@@@%    &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@     @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//          @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@           //
//                                                                                    //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//          (@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@,           //
//                                                                                    //
//            &&@    @@   @@      @   @       @       @   @      @@    @&&            //
//            &@@    @@   @@     @@@ @@@     @_@     @@@ @@@     @@@   @@&            //
//           /&&@     &@@@@    @@  @@  @@  @@ ^ @@  @@  @@  @@   @@@   @&&            //
//                                                                                    //
//          @@@@@      @@@%    *@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          @@@@@      @@@@    %@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@            //
//          .@@@@      @@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@             //
//            @@@@@  &@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@              //
//                (&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&&(                 //
//                                                                                    //
//                                                                                    //
////////////////////////////////////////////////////////////////////////////////////////

// Libraries
import {ERC4626} from "./ERC4626.sol";
import {ERC20} from "./ERC20.sol";
import {FixedPointMathLib} from "./FixedPointMathLib.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";

// Interfaces
import {IStrategy} from "./IStrategy.sol";
import {Strategy} from "./Strategy.sol";
import {IRewardOnlyGauge} from "./IRewardOnlyGauge.sol";
import {IVault} from "./IVault.sol";

/// @title Balancer Base Strategy
/// @author 0xdapper prΞpop

abstract contract BalancerBaseStrategy is Strategy {
    using FixedPointMathLib for uint256;

    /************************************************
     *  IMMUTABLES & CONSTANTS
     ***********************************************/
    IRewardOnlyGauge public immutable gauge;

    IVault public constant VAULT =
        IVault(0xBA12222222228d8Ba445958a75a0704d566BF2C8);

    ERC20 public constant BAL =
        ERC20(0x040d1EdC9569d4Bab2D15287Dc5A4F10F56a56B8);
    ERC20 public constant WETH =
        ERC20(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);

    bytes32 constant BAL_WETH_POOL =
        0xcc65a812ce382ab909a11e434dbf75b34f1cc59d000200000000000000000001;
    bytes32 public immutable balancerPool;

    /************************************************
     *  ERRORS
     ***********************************************/

    error InconsistentParams();

    /************************************************
     *  CONSTRUCTOR
     ***********************************************/

    constructor(
        ERC20 _asset,
        IRewardOnlyGauge _gauge,
        bytes32 _balancerPool,
        string memory vaultName,
        string memory vaultSymbol
    ) Strategy(_asset, vaultName, vaultSymbol) {
        gauge = _gauge;
        balancerPool = _balancerPool;

        asset.approve(address(_gauge), type(uint256).max);
        BAL.approve(address(VAULT), type(uint256).max);
        WETH.approve(address(VAULT), type(uint256).max);

        ADMIN_FEE_BIPS = 500; //5%
        REINVEST_FEE_BIPS = 50; //0.5%
        WITHDRAW_FEE_BIPS = 50; //0.5%

        feeRecipient = msg.sender;
    }

    /**
     * @notice deposit the BPT to balancer pool gauge for staking rewards
     * @param assets: the amount of assets in the deposit
     * @param shares: the amount of shares returned from the desposit
     */
    function _afterDeposit(
        address receiver,
        uint256 assets,
        uint256 shares
    ) internal override {
        gauge.deposit(assets);
    }

    /**
     * @notice claim the staking rewards from balancer pool, swap for more underlying and stake. Pays out fees.
     */
    function reinvest() external onlyEOA {
        // claim rewards
        gauge.claim_rewards();
        uint256 rewardsBalance = BAL.balanceOf(address(this));

        if (rewardsBalance <= 0) revert NotEnoughRewards();

        uint256 adminFee = rewardsBalance.mulDivDown(
            ADMIN_FEE_BIPS,
            BIPS_DIVISOR
        );
        uint256 reinvestFee = rewardsBalance.mulDivDown(
            REINVEST_FEE_BIPS,
            BIPS_DIVISOR
        );

        if (adminFee > 0)
            SafeTransferLib.safeTransfer(BAL, feeRecipient, adminFee);
        if (reinvestFee > 0)
            SafeTransferLib.safeTransfer(BAL, msg.sender, reinvestFee);

        uint256 reinvestableBAL = rewardsBalance - adminFee - reinvestFee;

        // swap BAL for pool asset
        (address poolAssetAddr, uint256 poolAssetAmount) = _swapBALForPoolAsset(
            reinvestableBAL
        );

        // join the balancer pool with pool asset
        address[] memory assets = _getPoolAssets();
        uint256[] memory maxAmountsIn = _getAmountsIn(
            assets,
            poolAssetAddr,
            poolAssetAmount
        );

        if (assets.length != maxAmountsIn.length) revert InconsistentParams();

        VAULT.joinPool(
            balancerPool,
            address(this),
            address(this),
            IVault.JoinPoolRequest({
                assets: assets,
                maxAmountsIn: maxAmountsIn,
                userData: abi.encode(
                    IVault.JoinKind.EXACT_TOKENS_IN_FOR_BPT_OUT,
                    maxAmountsIn,
                    0
                ),
                fromInternalBalance: false
            })
        );

        uint256 newLPShares = asset.balanceOf(address(this));
        _totalAssets += newLPShares;
        emit Reinvest(_totalAssets, totalSupply);

        gauge.deposit(newLPShares);
    }

    /**
     * @notice  withdraw the staked assets before burning vault tokens and sending back the underlying to the user
     * @param _receiver the address who will receive the withdrawn assets
     * @param _assets the amount of assets in the withdrawal
     * @param _shares the amount of share sin the withdrawal
     * @param assetsBeforeFees the amount of assets to be sent to user + fees
     */
    function _beforeWithdraw(
        address _receiver,
        uint256 _assets,
        uint256 _shares,
        uint256 assetsBeforeFees
    ) internal override {
        gauge.withdraw(assetsBeforeFees);
    }

    /**
     * @notice return an array of assets' addresses that will be used as input while joining the pool.
     */
    function _getPoolAssets() internal pure virtual returns (address[] memory);

    /**
     * @notice called to swap BAL rewards for underlying pool asset which will be used to join the pool for more BPT.
     * @param amountOfBAL amount of BAL tokens to swap
     * @return poolAsset address of the pool asset that we swapped into
     * @return assetAmount amount of pool asset we got from the swap
     */
    function _swapBALForPoolAsset(uint256 amountOfBAL)
        internal
        virtual
        returns (address poolAsset, uint256 assetAmount);

    /**
     * @notice Get sets the ammount in for each asset in the poolAssets Array.
     * @param poolAssets address array of the assets in the pool
     * @param poolAssetAddr address of the asset for entering
     * @param poolAssetAmount amount of the asset for entering
     * @return amountsIn array of token amounts in.
     */
    function _getAmountsIn(
        address[] memory poolAssets,
        address poolAssetAddr,
        uint256 poolAssetAmount
    ) internal pure returns (uint256[] memory) {
        uint256[] memory amountsIn = new uint256[](poolAssets.length);
        for (uint256 i = 0; i < poolAssets.length; i++) {
            if (poolAssets[i] == poolAssetAddr) {
                amountsIn[i] = poolAssetAmount;
            } else {
                amountsIn[i] = 0;
            }
        }
        return amountsIn;
    }
}

