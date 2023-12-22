// SPDX-License-Identifier: BUSL-1.1
pragma solidity ^0.8.17;
import {MarketConfigStruct} from "./MarketConfigStruct.sol";
import {IFeeRouter} from "./IFeeRouter.sol";
import {IVaultRouter} from "./IVaultRouter.sol";
import {IOrderBook} from "./IOrderBook.sol";
import {IFeeRouter} from "./IFeeRouter.sol";
import {IPositionBook} from "./IPositionBook.sol";
import {Order} from "./OrderStruct.sol";
import {MarketPositionCallBackIntl, MarketOrderCallBackIntl, MarketCallBackIntl} from "./IMarketCallBackIntl.sol";
import "./IERC20.sol";
import "./TransferHelper.sol";
import "./MarketDataTypes.sol";

library MarketLib {
    /**
     * @dev Withdraws fees from the specified collateral address.
     * @param collAddr The address of the collateral token.
     * @param _account The address of the account to receive the fees.
     * @param fee The amount of fees to be withdrawn.
     * @param collateralTokenDigits The number of decimal places for the collateral token.
     * @param fr The address of the fee router.
     */
    function feeWithdraw(
        address collAddr,
        address _account,
        int256 fee,
        uint8 collateralTokenDigits,
        address fr
    ) internal {
        require(_account != address(0), "feeWithdraw:!userAccount");
        if (fee < 0) {
            IFeeRouter(fr).withdraw(
                collAddr,
                _account,
                TransferHelper.formatCollateral(
                    uint256(-fee),
                    collateralTokenDigits
                )
            );
        }
    }

    /**
     * @dev Withdraws profit and loss (PnL) from the vault.
     * @param _account The address of the account to receive the PnL.
     * @param pnl The amount of profit and loss to be withdrawn.
     * @param collateralTokenDigits The number of decimal places for the collateral token.
     * @param vr The address of the vault router.
     */
    function vaultWithdraw(
        address /* collAddr */,
        address _account,
        int256 pnl,
        uint8 collateralTokenDigits,
        address vr
    ) internal {
        require(_account != address(0), "vaultWithdraw:!userAccount");
        if (pnl > 0) {
            IVaultRouter(vr).transferFromVault(
                _account,
                TransferHelper.formatCollateral(
                    uint256(pnl),
                    collateralTokenDigits
                )
            );
        }
    }

    /**
     * @dev Calculates the delta collateral for decreasing a position.
     * @param isKeepLev Boolean flag indicating whether to keep leverage.
     * @param size Current size of the position.
     * @param dSize Delta size of the position.
     * @param collateral Current collateral amount.
     * @return deltaCollateral The calculated delta collateral.
     */
    function getDecreaseDeltaCollateral(
        bool isKeepLev,
        uint256 size,
        uint256 dSize,
        uint256 collateral
    ) internal pure returns (uint256 deltaCollateral) {
        if (isKeepLev) {
            deltaCollateral = (collateral * dSize) / size;
        } else {
            deltaCollateral = 0;
        }
    }

    /**
     * @dev Executes the necessary actions after updating a position.
     * @param _item The update position event data.
     * @param plugins The array of plugin addresses.
     * @param erc20Token The address of the ERC20 token.
     * @param market The address of the market.
     */
    function afterUpdatePosition(
        MarketPositionCallBackIntl.UpdatePositionEvent memory _item,
        uint256 /* gasLimit */,
        address[] memory plugins,
        address erc20Token,
        address market
    ) internal {
        uint256 balanceBefore = IERC20(erc20Token).balanceOf(market);
        for (uint256 i = 0; i < plugins.length; i++) {
            if (MarketCallBackIntl(plugins[i]).getHooksCalls().updatePosition) {
                try
                    MarketPositionCallBackIntl(plugins[i])
                        .updatePositionCallback(_item)
                {} catch {}
            }
            // plugins[i].call{gas: gasLimit}(
            //     abi.encodeWithSelector(SELECTOR_updatePositionCallback, _item)
            // );
        }
        uint256 balanceAfter = IERC20(erc20Token).balanceOf(market);
        require(balanceAfter == balanceBefore, "ERC20 token balance changed");
    }

    /**
     * @dev Executes the necessary actions after updating an order.
     * @param _item The update order inputs data.
     * @param plugins The array of plugin addresses.
     * @param collateralToken The address of the collateral token.
     * @param market The address of the market.
     */
    function afterUpdateOrder(
        MarketDataTypes.UpdateOrderInputs memory _item,
        uint256 /* gasLimit */,
        address[] memory plugins,
        address collateralToken,
        address market
    ) internal {
        uint256 balanceBefore = IERC20(collateralToken).balanceOf(market);
        for (uint256 i = 0; i < plugins.length; i++) {
            if (MarketCallBackIntl(plugins[i]).getHooksCalls().updateOrder) {
                try
                    MarketOrderCallBackIntl(plugins[i]).updateOrderCallback(
                        _item
                    )
                {} catch {}
            }
            // plugins[i].call{gas: gasLimit}(
            //     abi.encodeWithSelector(selector_updateOrderCallback, _item)
            // );
        }
        uint256 balanceAfter = IERC20(collateralToken).balanceOf(market);
        require(balanceAfter == balanceBefore, "ERC20 token balance changed");
    }

    /**
     * @dev Executes the necessary actions after deleting an order.
     * @param e The delete order event data.
     * @param plugins The array of plugin addresses.
     * @param erc20Token The address of the ERC20 token.
     * @param market The address of the market.
     */
    function afterDeleteOrder(
        MarketOrderCallBackIntl.DeleteOrderEvent memory e,
        uint256 /* gasLimit */,
        address[] memory plugins,
        address erc20Token,
        address market
    ) internal {
        uint256 balanceBefore = IERC20(erc20Token).balanceOf(market);
        for (uint256 i = 0; i < plugins.length; i++) {
            // TODO 确认是否有风险, 可能会存在gas预估错误
            // 确认memtamask唤起的时候是否能设置gaslimit & approve amount
            //TODO
            // (bool suc, bytes memory returnData) = plugins[i].call{
            //     gas: gasLimit
            // }(abi.encodeWithSelector(selector_afterDeleteOrder, e));
            // (, string memory errorMessage) = abi.decode(
            //     returnData,
            //     (bool, string)
            // );
            // require(suc, "call failed");
            if (MarketCallBackIntl(plugins[i]).getHooksCalls().deleteOrder) {
                try
                    MarketOrderCallBackIntl(plugins[i]).deleteOrderCallback(e)
                {} catch {}
            }
        }
        uint256 balanceAfter = IERC20(erc20Token).balanceOf(market);
        require(balanceAfter == balanceBefore, "ERC20 token balance changed");
    }

    /**
     * @dev Updates the cumulative funding rate for the market.
     * @param positionBook The address of the position book.
     * @param feeRouter The address of the fee router.
     */
    function _updateCumulativeFundingRate(
        IPositionBook positionBook,
        IFeeRouter feeRouter
    ) internal {
        (uint256 _longSize, uint256 _shortSize) = positionBook.getMarketSizes();

        feeRouter.updateCumulativeFundingRate(
            address(this),
            _longSize,
            _shortSize
        );
    }
}

