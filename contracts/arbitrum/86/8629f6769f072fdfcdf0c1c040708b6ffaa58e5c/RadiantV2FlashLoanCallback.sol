// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

import {SafeERC20, IERC20, Address} from "./SafeERC20.sol";
import {IAgent} from "./IAgent.sol";
import {DataType} from "./DataType.sol";
import {IRouter} from "./IRouter.sol";
import {IAaveV2FlashLoanCallback} from "./IAaveV2FlashLoanCallback.sol";
import {IAaveV2Provider} from "./IAaveV2Provider.sol";
import {ApproveHelper} from "./ApproveHelper.sol";
import {FeeLibrary} from "./FeeLibrary.sol";
import {CallbackFeeBase} from "./CallbackFeeBase.sol";

/// @title Radiant V2 flash loan callback
/// @notice Invoked by Radiant V2 pool to call the current user's agent
contract RadiantV2FlashLoanCallback is IAaveV2FlashLoanCallback, CallbackFeeBase {
    using SafeERC20 for IERC20;
    using Address for address;
    using FeeLibrary for DataType.Fee;

    address public immutable router;
    address public immutable radiantV2Provider;
    bytes32 internal constant _META_DATA = bytes32(bytes('radiant-v2:flash-loan'));

    constructor(address router_, address radiantV2Provider_, uint256 feeRate_) CallbackFeeBase(feeRate_, _META_DATA) {
        router = router_;
        radiantV2Provider = radiantV2Provider_;
    }

    /// @dev No need to check if `initiator` is the agent as it's certain when the below conditions are satisfied:
    ///      1. The `to` address used in agent is Radiant Pool, i.e, the user signed a correct `to`
    ///      2. The callback address set in agent is this callback, i.e, the user signed a correct `callback`
    ///      3. The `msg.sender` of this callback is Radiant Pool
    ///      4. The Radiant pool is benign
    function executeOperation(
        address[] calldata assets,
        uint256[] calldata amounts,
        uint256[] calldata premiums,
        address, // initiator
        bytes calldata params
    ) external returns (bool) {
        address pool = IAaveV2Provider(radiantV2Provider).getLendingPool();
        if (msg.sender != pool) revert InvalidCaller();
        bool charge;
        uint256[] memory initBalances = new uint256[](assets.length);
        {
            (, address agent) = IRouter(router).getCurrentUserAgent();
            charge = feeRate > 0 && IAgent(agent).isCharging();

            // Transfer assets to the agent and record initial balances
            for (uint256 i; i < assets.length; ) {
                address asset = assets[i];
                IERC20(asset).safeTransfer(agent, amounts[i]);
                initBalances[i] = IERC20(asset).balanceOf(address(this));

                unchecked {
                    ++i;
                }
            }

            agent.functionCall(
                abi.encodePacked(IAgent.executeByCallback.selector, params),
                'ERROR_RADIANT_V2_FLASH_LOAN_CALLBACK'
            );
        }

        // Approve assets for pulling from Radiant Pool
        for (uint256 i; i < assets.length; ) {
            address asset = assets[i];
            uint256 amount = amounts[i];
            uint256 amountOwing = amount + premiums[i];

            if (charge) {
                bytes32 defaultReferral = IRouter(router).defaultReferral();
                DataType.Fee memory fee = FeeLibrary.calcFee(asset, amount, feeRate, metadata);
                fee.pay(defaultReferral);
            }

            // Check balance is valid
            if (IERC20(asset).balanceOf(address(this)) != initBalances[i] + amountOwing) revert InvalidBalance(asset);

            // Save gas by only the first user does approve. It's safe since this callback don't hold any asset
            ApproveHelper.approveMax(asset, pool, amountOwing);

            unchecked {
                ++i;
            }
        }

        return true;
    }
}

