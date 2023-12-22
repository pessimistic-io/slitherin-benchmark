// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Permit} from "./IERC20Permit.sol";
import {ERC1155Holder} from "./ERC1155Holder.sol";
import {Ownable2Step} from "./Ownable2Step.sol";
import {Ownable} from "./Ownable.sol";
import {SafeCast} from "./SafeCast.sol";

import {CloberMarketSwapCallbackReceiver} from "./CloberMarketSwapCallbackReceiver.sol";
import {CloberMarketFactory} from "./CloberMarketFactory.sol";
import {IWETH9} from "./IWETH9.sol";
import {IWrapped1155Factory} from "./IWrapped1155Factory.sol";
import {CloberOrderBook} from "./CloberOrderBook.sol";
import {ICouponManager} from "./ICouponManager.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {CouponKey, CouponKeyLibrary} from "./CouponKey.sol";
import {Wrapped1155MetadataBuilder} from "./Wrapped1155MetadataBuilder.sol";
import {IERC721Permit} from "./IERC721Permit.sol";
import {ISubstitute} from "./ISubstitute.sol";
import {IController} from "./IController.sol";
import {ReentrancyGuard} from "./ReentrancyGuard.sol";
import {SubstituteLibrary} from "./Substitute.sol";

import {Epoch} from "./Epoch.sol";

abstract contract Controller is
    IController,
    ERC1155Holder,
    CloberMarketSwapCallbackReceiver,
    Ownable2Step,
    ReentrancyGuard
{
    using SafeCast for uint256;
    using SafeERC20 for IERC20;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using SubstituteLibrary for ISubstitute;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    CloberMarketFactory internal immutable _cloberMarketFactory;
    ICouponManager internal immutable _couponManager;
    IWETH9 internal immutable _weth;

    mapping(uint256 couponId => address market) internal _couponMarkets;

    constructor(address wrapped1155Factory, address cloberMarketFactory, address couponManager, address weth)
        Ownable(msg.sender)
    {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberMarketFactory = CloberMarketFactory(cloberMarketFactory);
        _couponManager = ICouponManager(couponManager);
        _weth = IWETH9(weth);
    }

    modifier wrapAndRefundETH() {
        bool hasMsgValue = address(this).balance > 0;
        if (hasMsgValue) _weth.deposit{value: address(this).balance}();
        _;
        if (hasMsgValue) {
            uint256 leftBalance = _weth.balanceOf(address(this));
            if (leftBalance > 0) {
                _weth.withdraw(leftBalance);
                (bool success,) = msg.sender.call{value: leftBalance}("");
                require(success);
            }
        }
    }

    function _executeCouponTrade(
        address user,
        address token,
        Coupon[] memory couponsToMint,
        Coupon[] memory couponsToBurn,
        uint256 amountToPay,
        int256 remainingInterest
    ) internal {
        if (couponsToBurn.length > 0) {
            Coupon memory lastCoupon = couponsToBurn[couponsToBurn.length - 1];
            assembly {
                mstore(couponsToBurn, sub(mload(couponsToBurn), 1))
            }
            bytes memory data =
                abi.encode(user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, remainingInterest);
            assembly {
                mstore(couponsToBurn, add(mload(couponsToBurn), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            uint256 dy = lastCoupon.amount - IERC20(market.baseToken()).balanceOf(address(this));
            market.marketOrder(address(this), type(uint16).max, type(uint64).max, dy, 1, data);
        } else if (couponsToMint.length > 0) {
            Coupon memory lastCoupon = couponsToMint[couponsToMint.length - 1];
            assembly {
                mstore(couponsToMint, sub(mload(couponsToMint), 1))
            }
            bytes memory data =
                abi.encode(user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, remainingInterest);
            assembly {
                mstore(couponsToMint, add(mload(couponsToMint), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            market.marketOrder(address(this), 0, 0, lastCoupon.amount, 2, data);
        } else {
            if (remainingInterest < 0) revert ControllerSlippage();
            ISubstitute(token).ensureBalance(user, amountToPay);
        }
    }

    function cloberMarketSwapCallback(
        address inputToken,
        address,
        uint256 inputAmount,
        uint256 outputAmount,
        bytes calldata data
    ) external payable {
        // check if caller is registered market
        if (_cloberMarketFactory.getMarketHost(msg.sender) == address(0)) revert InvalidAccess();

        address asset = CloberOrderBook(msg.sender).quoteToken();
        address user;
        Coupon memory lastCoupon;
        Coupon[] memory couponsToMint;
        Coupon[] memory couponsToBurn;
        uint256 amountToPay;
        int256 remainingInterest;
        (user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, remainingInterest) =
            abi.decode(data, (address, Coupon, Coupon[], Coupon[], uint256, int256));

        if (asset == inputToken) {
            remainingInterest -= inputAmount.toInt256();
            amountToPay += inputAmount;
        } else {
            remainingInterest += outputAmount.toInt256();
        }

        _executeCouponTrade(user, asset, couponsToMint, couponsToBurn, amountToPay, remainingInterest);

        // transfer input tokens
        if (inputAmount > 0) IERC20(inputToken).safeTransfer(msg.sender, inputAmount);
        uint256 couponBalance = IERC20(inputToken).balanceOf(address(this));
        if (asset != inputToken && couponBalance > 0) {
            bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(lastCoupon.key);
            _wrapped1155Factory.unwrap(address(_couponManager), lastCoupon.id(), couponBalance, user, metadata);
        }
    }

    function _getUnderlyingToken(address substitute) internal view returns (address) {
        return ISubstitute(substitute).underlyingToken();
    }

    function _wrapCoupons(Coupon[] memory coupons) internal {
        // wrap 1155 to 20
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons);
        _couponManager.safeBatchTransferFrom(address(this), address(_wrapped1155Factory), coupons, metadata);
    }

    function _unwrapCoupons(Coupon[] memory coupons) internal {
        uint256[] memory tokenIds = new uint256[](coupons.length);
        uint256[] memory amounts = new uint256[](coupons.length);
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                tokenIds[i] = coupons[i].id();
                amounts[i] = coupons[i].amount;
            }
        }
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155BatchMetadata(coupons);
        _wrapped1155Factory.batchUnwrap(address(_couponManager), tokenIds, amounts, address(this), metadata);
    }

    function getCouponMarket(CouponKey memory couponKey) external view returns (address) {
        return _couponMarkets[couponKey.toId()];
    }

    function setCouponMarket(CouponKey memory couponKey, address cloberMarket) public virtual onlyOwner {
        bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(couponKey);
        uint256 id = couponKey.toId();
        address wrappedCoupon = _wrapped1155Factory.getWrapped1155(address(_couponManager), id, metadata);
        CloberMarketFactory.MarketInfo memory marketInfo = _cloberMarketFactory.getMarketInfo(cloberMarket);
        if (
            (marketInfo.host == address(0)) || (CloberOrderBook(cloberMarket).baseToken() != wrappedCoupon)
                || (CloberOrderBook(cloberMarket).quoteToken() != couponKey.asset)
        ) {
            revert InvalidMarket();
        }

        _couponMarkets[id] = cloberMarket;
        emit SetCouponMarket(couponKey.asset, couponKey.epoch, cloberMarket);
    }

    receive() external payable {}
}

