/*

    Copyright 2022 Dolomite.

    Licensed under the Apache License, Version 2.0 (the "License");
    you may not use this file except in compliance with the License.
    You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

    Unless required by applicable law or agreed to in writing, software
    distributed under the License is distributed on an "AS IS" BASIS,
    WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
    See the License for the specific language governing permissions and
    limitations under the License.

*/

pragma solidity ^0.5.7;
pragma experimental ABIEncoderV2;

import { SafeMath } from "./SafeMath.sol";
import { IERC20 } from "./IERC20.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";

import { IDolomiteMargin } from "./IDolomiteMargin.sol";
import { IExchangeWrapper } from "./IExchangeWrapper.sol";

import { Account } from "./Account.sol";
import { Actions } from "./Actions.sol";
import { Decimal } from "./Decimal.sol";
import { Interest } from "./Interest.sol";
import { DolomiteMarginMath } from "./DolomiteMarginMath.sol";
import { Monetary } from "./Monetary.sol";
import { Require } from "./Require.sol";
import { Time } from "./Time.sol";
import { Types } from "./Types.sol";

import { ERC20Helper } from "./ERC20Helper.sol";
import { LiquidatorProxyHelper } from "./LiquidatorProxyHelper.sol";
import { OnlyDolomiteMargin } from "./OnlyDolomiteMargin.sol";


/**
 * @title ParaswapTraderProxyWithBackup
 * @author Dolomite
 *
 * Contract for performing an external trade with Paraswap with a backup to other venues if the trade fails.
 */
contract ParaswapTraderProxyWithBackup is OnlyDolomiteMargin, LiquidatorProxyHelper, IExchangeWrapper {

    // ============ Constants ============

    bytes32 private constant FILE = "ParaswapTraderProxyWithBackup";

    // ============ Events ============

    /**
     * @param solidAccountOwner         The liquidator's address
     * @param heldToken                 The held token (collateral) that will be received by the liquidator
     * @param heldDeltaWeiWithReward    The amount of `heldToken` the liquidator will receive, including the reward
     *                                  (positive number)
     * @param profitHeldWei             The amount of profit the liquidator will realize by performing the liquidation
     *                                  and atomically selling off the collateral. Can be negative or positive.
     * @param owedToken                 The debt token that will be received by the liquidator
     * @param owedDeltaWei              The amount of `owedToken` that will be received by the liquidator (previously a
     *                                  negative number, from taking the debt of the liquidated account)
     */
    event LogLiquidateWithParaswap(
        address indexed solidAccountOwner,
        address heldToken,
        uint256 heldDeltaWeiWithReward,
        Types.Wei profitHeldWei, // calculated as `heldWeiWithReward - soldHeldWeiToBreakEven`
        address owedToken,
        uint256 owedDeltaWei
    );

    // ============ Storage ============

    address PARASWAP_AUGUSTUS_ROUTER;
    address PARASWAP_TRANSFER_PROXY;

    // ============ Constructor ============

    constructor(
        address _paraswapAugustusRouter,
        address _paraswapTransferProxy,
        address _dolomiteMargin
    ) public OnlyDolomiteMargin(_dolomiteMargin) {
        PARASWAP_AUGUSTUS_ROUTER = _paraswapAugustusRouter;
        PARASWAP_TRANSFER_PROXY = _paraswapTransferProxy;
    }

    // ============ Public Functions ============

    function exchange(
        address _tradeOriginator,
        address _receiver,
        address _makerToken,
        address _takerToken,
        uint256 _requestedFillAmount,
        bytes calldata _orderData
    )
    external
    onlyDolomiteMargin(msg.sender)
    returns (uint256) {
        ERC20Helper.checkAllowanceAndApprove(_takerToken, PARASWAP_TRANSFER_PROXY, _requestedFillAmount);

        (uint256 minAmountOutWei, bytes memory paraswapCallData) = abi.decode(_orderData, (uint256, bytes));

        _callAndCheckSuccess(paraswapCallData);

        uint256 amount = IERC20(_makerToken).balanceOf(address(this));

        Require.that(
            amount >= minAmountOutWei,
            FILE,
            "insufficient output amount",
            amount,
            minAmountOutWei
        );

        emit LogLiquidateWithParaswap(
            _tradeOriginator,
            _takerToken,
            _requestedFillAmount,
            Types.Wei(true, amount - minAmountOutWei),
            _makerToken,
            amount
        );

        ERC20Helper.checkAllowanceAndApprove(_makerToken, _receiver, amount);

        return amount;
    }

    function getExchangeCost(
        address,
        address,
        uint256,
        bytes calldata
    )
    external
    view
    returns (uint256) {
        revert(string(abi.encodePacked(Require.stringifyTruncated(FILE), "::getExchangeCost: not implemented")));
    }

    // ============ Private Functions ============

    function _callAndCheckSuccess(bytes memory _paraswapCallData) internal {
        // solium-disable-next-line security/no-low-level-calls
        (bool success, bytes memory result) = PARASWAP_AUGUSTUS_ROUTER.call(_paraswapCallData);
        if (!success) {
            if (result.length < 68) {
                revert(string(abi.encodePacked(Require.stringifyTruncated(FILE), ": revert")));
            } else {
                // solium-disable-next-line security/no-inline-assembly
                assembly {
                    result := add(result, 0x04)
                }
                revert(string(abi.encodePacked(Require.stringifyTruncated(FILE), ": ", abi.decode(result, (string)))));
            }
        }
    }

}

