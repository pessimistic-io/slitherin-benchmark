// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {SafeCast} from "./SafeCast.sol";

import {IAssetPool} from "./IAssetPool.sol";
import {ICouponManager} from "./ICouponManager.sol";
import {IPositionLocker} from "./IPositionLocker.sol";
import {ERC721Permit} from "./ERC721Permit.sol";
import {LockData, LockDataLibrary} from "./LockData.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {IPositionManager} from "./IPositionManager.sol";

abstract contract PositionManager is ERC721Permit, IPositionManager {
    using SafeERC20 for IERC20;
    using CouponLibrary for Coupon;
    using LockDataLibrary for LockData;

    address internal immutable _couponManager;
    address public immutable override assetPool;

    string public override baseURI;
    string public override contractURI;
    uint256 public override nextId = 1;

    LockData private _lockData;

    // @dev Since the epoch is greater than 0, the coupon ID and address can never be the same.
    mapping(address locker => mapping(uint256 assetId => int256 delta)) public override assetDelta;

    constructor(
        address couponManager_,
        address assetPool_,
        string memory baseURI_,
        string memory contractURI_,
        string memory name_,
        string memory symbol_
    ) ERC721Permit(name_, symbol_, "1") {
        _couponManager = couponManager_;
        assetPool = assetPool_;
        baseURI = baseURI_;
        contractURI = contractURI_;
    }

    modifier modifyPosition(uint256 positionId) {
        _;
        _unsettlePosition(positionId);
    }

    modifier onlyByLocker() {
        address locker = _lockData.getActiveLock();
        if (msg.sender != locker) revert LockedBy(locker);
        _;
    }

    function lock(bytes calldata data) external returns (bytes memory result) {
        _lockData.push(msg.sender);

        result = IPositionLocker(msg.sender).positionLockAcquired(data);

        if (_lockData.length == 1) {
            if (_lockData.nonzeroDeltaCount != 0) revert NotSettled();
            delete _lockData;
        } else {
            _lockData.pop();
        }
    }

    function _isSettled(uint256 positionId) internal view virtual returns (bool);

    function _setPositionSettlement(uint256 positionId, bool settled) internal virtual;

    function _unsettlePosition(uint256 positionId) internal {
        if (!_isSettled(positionId)) return;
        _setPositionSettlement(positionId, false);
        unchecked {
            _lockData.nonzeroDeltaCount++;
        }
    }

    function _accountDelta(uint256 assetId, uint256 amount0, uint256 amount1) internal returns (int256 delta) {
        if (amount0 == amount1) return 0;

        address locker = _lockData.getActiveLock();
        int256 current = assetDelta[locker][assetId];
        unchecked {
            if (amount0 > amount1) {
                delta = SafeCast.toInt256(amount0 - amount1);
            } else {
                delta = -SafeCast.toInt256(amount1 - amount0);
            }
        }
        int256 next = current + delta;

        unchecked {
            if (next == 0) {
                _lockData.nonzeroDeltaCount--;
            } else if (current == 0) {
                _lockData.nonzeroDeltaCount++;
            }
        }

        assetDelta[locker][assetId] = next;
    }

    function withdrawToken(address token, address to, uint256 amount) external onlyByLocker {
        _accountDelta(uint256(uint160(token)), amount, 0);
        _withdrawAsset(token, amount, to);
    }

    function _withdrawAsset(address asset, uint256 amount, address to) internal {
        IAssetPool(assetPool).withdraw(asset, amount, to);
    }

    function mintCoupons(Coupon[] calldata coupons, address to, bytes calldata data) external onlyByLocker {
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), coupons[i].amount, 0);
            }
            _mintCoupons(to, coupons, data);
        }
    }

    function _mintCoupons(address recipient, Coupon[] memory coupons, bytes memory data) internal {
        ICouponManager(_couponManager).mintBatch(recipient, coupons, data);
    }

    function depositToken(address token, uint256 amount) external onlyByLocker {
        if (amount == 0) return;
        IERC20(token).safeTransferFrom(msg.sender, assetPool, amount);
        _accountDelta(uint256(uint160(token)), 0, amount);
    }

    function burnCoupons(Coupon[] calldata coupons) external onlyByLocker {
        unchecked {
            ICouponManager(_couponManager).burnBatch(msg.sender, coupons);
            for (uint256 i = 0; i < coupons.length; ++i) {
                _accountDelta(coupons[i].id(), 0, coupons[i].amount);
            }
        }
    }

    function settlePosition(uint256 positionId) public virtual {
        if (_isSettled(positionId)) return;
        _setPositionSettlement(positionId, true);
        unchecked {
            _lockData.nonzeroDeltaCount--;
        }
    }

    function _baseURI() internal view override returns (string memory) {
        return baseURI;
    }

    function lockData() external view override returns (uint128, uint128) {
        return (_lockData.length, _lockData.nonzeroDeltaCount);
    }

    function _mint(address to, uint256 positionId) internal virtual override {
        super._mint(to, positionId);
        _setPositionSettlement(positionId, false);
        unchecked {
            _lockData.nonzeroDeltaCount++;
        }
    }
}

