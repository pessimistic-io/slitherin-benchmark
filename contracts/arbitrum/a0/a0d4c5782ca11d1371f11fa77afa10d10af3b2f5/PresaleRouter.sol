// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.19;

import "./SafeERC20.sol";

import "./IStargateReceiver.sol";
import "./IKEIReferrals.sol";

import "./IPresaleRouter.sol";

/**
 * @notice Implementation of the {IPresaleRouter} interface.
 */
contract PresaleRouter is IPresaleRouter {
    using SafeERC20 for IERC20;

    IPresale public immutable PRESALE;
    IERC20 public immutable PRESALE_ASSET;
    IKEIReferrals public immutable REFERRALS;

    constructor(IPresale presale, IKEIReferrals referrals) {
        PRESALE = presale;
        REFERRALS = referrals;
        PRESALE_ASSET = presale.PRESALE_ASSET();
        PRESALE_ASSET.approve(address(PRESALE), type(uint256).max);
    }

    function purchase(PurchaseParams memory params) public override {
        uint256 _currentBalance = PRESALE_ASSET.balanceOf(address(this));
        if (_currentBalance < params.assetAmount) {
            PRESALE_ASSET.safeTransferFrom(msg.sender, address(this), params.assetAmount - _currentBalance);
        }

        try REFERRALS.register(params.account, params.referrer) {
            // do nothing also
        } catch {
            // do nothing
        }

        bool _success;
        IPresale.Receipt memory _receipt;
        try PRESALE.purchase(params.account, params.assetAmount) returns (IPresale.Receipt memory receipt) {
            _success = true;
            _receipt = receipt;
        } catch {
            // in the event the purchase failed then send the assets to the account
            PRESALE_ASSET.safeTransfer(params.account, params.assetAmount);
        }

        emit PurchaseResult(params, _success, _receipt, msg.sender);
    }
}

