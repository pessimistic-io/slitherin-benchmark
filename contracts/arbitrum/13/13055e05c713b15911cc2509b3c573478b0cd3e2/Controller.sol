// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IERC20Permit} from "./IERC20Permit.sol";
import {ERC1155Holder} from "./ERC1155Holder.sol";
import {Ownable2Step} from "./Ownable2Step.sol";

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

abstract contract Controller is
    IController,
    ERC1155Holder,
    CloberMarketSwapCallbackReceiver,
    Ownable2Step,
    ReentrancyGuard
{
    using SafeERC20 for IERC20;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;

    IWrapped1155Factory internal immutable _wrapped1155Factory;
    CloberMarketFactory internal immutable _cloberMarketFactory;
    ICouponManager internal immutable _couponManager;
    IWETH9 internal immutable _weth;

    mapping(uint256 couponId => address market) internal _couponMarkets;

    constructor(address wrapped1155Factory, address cloberMarketFactory, address couponManager, address weth) {
        _wrapped1155Factory = IWrapped1155Factory(wrapped1155Factory);
        _cloberMarketFactory = CloberMarketFactory(cloberMarketFactory);
        _couponManager = ICouponManager(couponManager);
        _weth = IWETH9(weth);
    }

    modifier wrapETH() {
        if (address(this).balance > 0) _weth.deposit{value: address(this).balance}();
        _;
    }

    function _executeCouponTrade(
        address user,
        address token,
        Coupon[] memory couponsToMint,
        Coupon[] memory couponsToBurn,
        uint256 amountToPay,
        uint256 maxPayInterest,
        uint256 leftRequiredInterest
    ) internal {
        if (couponsToBurn.length > 0) {
            Coupon memory lastCoupon = couponsToBurn[couponsToBurn.length - 1];
            assembly {
                mstore(couponsToBurn, sub(mload(couponsToBurn), 1))
            }
            bytes memory data = abi.encode(
                user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, maxPayInterest, leftRequiredInterest
            );
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
            bytes memory data = abi.encode(
                user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, maxPayInterest, leftRequiredInterest
            );
            assembly {
                mstore(couponsToMint, add(mload(couponsToMint), 1))
            }

            CloberOrderBook market = CloberOrderBook(_couponMarkets[lastCoupon.id()]);
            market.marketOrder(address(this), 0, 0, lastCoupon.amount, 2, data);
        } else {
            if (leftRequiredInterest > 0) revert ControllerSlippage();
            _ensureBalance(token, user, amountToPay);
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
        unchecked {
            Coupon[] memory couponsToMint;
            Coupon[] memory couponsToBurn;
            uint256 amountToPay;
            uint256 maxPayInterest;
            uint256 leftRequiredInterest;
            (user, lastCoupon, couponsToMint, couponsToBurn, amountToPay, maxPayInterest, leftRequiredInterest) =
                abi.decode(data, (address, Coupon, Coupon[], Coupon[], uint256, uint256, uint256));

            if (asset == inputToken) {
                if (maxPayInterest < inputAmount) revert ControllerSlippage();
                maxPayInterest -= inputAmount;
                amountToPay += inputAmount;
            } else {
                if (leftRequiredInterest > outputAmount) {
                    leftRequiredInterest -= outputAmount;
                } else {
                    leftRequiredInterest = 0;
                }
            }

            _executeCouponTrade(
                user, asset, couponsToMint, couponsToBurn, amountToPay, maxPayInterest, leftRequiredInterest
            );
        }

        // transfer input tokens
        if (inputAmount > 0) IERC20(inputToken).safeTransfer(msg.sender, inputAmount);
        uint256 couponBalance = IERC20(inputToken).balanceOf(address(this));
        if (asset != inputToken && couponBalance > 0) {
            bytes memory metadata = Wrapped1155MetadataBuilder.buildWrapped1155Metadata(lastCoupon.key);
            _wrapped1155Factory.unwrap(address(_couponManager), lastCoupon.id(), couponBalance, user, metadata);
        }
    }

    function _permitERC20(address token, ERC20PermitParams calldata p) internal {
        if (p.signature.deadline > 0) {
            try IERC20Permit(ISubstitute(token).underlyingToken()).permit(
                msg.sender,
                address(this),
                p.permitAmount,
                p.signature.deadline,
                p.signature.v,
                p.signature.r,
                p.signature.s
            ) {} catch {}
        }
    }

    function _permitERC721(IERC721Permit permitNFT, uint256 positionId, PermitSignature calldata p) internal {
        if (p.deadline > 0) try permitNFT.permit(address(this), positionId, p.deadline, p.v, p.r, p.s) {} catch {}
    }

    function _burnAllSubstitute(address substitute, address to) internal {
        uint256 leftAmount = IERC20(substitute).balanceOf(address(this));
        if (leftAmount == 0) return;
        ISubstitute(substitute).burn(leftAmount, to);
    }

    function _ensureBalance(address token, address user, uint256 amount) internal {
        address underlyingToken = ISubstitute(token).underlyingToken();
        uint256 thisBalance = IERC20(token).balanceOf(address(this));
        uint256 underlyingBalance = IERC20(underlyingToken).balanceOf(address(this));
        if (amount > thisBalance + underlyingBalance) {
            unchecked {
                IERC20(underlyingToken).safeTransferFrom(user, address(this), amount - thisBalance - underlyingBalance);
                underlyingBalance = amount - thisBalance;
            }
        }
        if (underlyingBalance > 0) {
            IERC20(underlyingToken).approve(token, underlyingBalance);
            ISubstitute(token).mint(underlyingBalance, address(this));
        }
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

