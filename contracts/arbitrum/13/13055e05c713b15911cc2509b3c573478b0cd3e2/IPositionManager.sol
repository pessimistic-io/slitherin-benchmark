// SPDX-License-Identifier: GPL-2.0-or-later

pragma solidity ^0.8.0;

import {IERC721Metadata} from "./IERC721Metadata.sol";

import {IERC721Permit} from "./IERC721Permit.sol";
import {Coupon} from "./Coupon.sol";

interface IPositionManagerTypes {
    error LockedBy(address locker);
    error NotSettled();
}

interface IPositionManager is IERC721Metadata, IERC721Permit, IPositionManagerTypes {
    function baseURI() external view returns (string memory);

    function contractURI() external view returns (string memory);

    function nextId() external view returns (uint256);

    function assetPool() external view returns (address);

    function lockData() external view returns (uint128, uint128);

    function assetDelta(address locker, uint256 assetId) external view returns (int256);

    function lock(bytes calldata data) external returns (bytes memory);

    function settlePosition(uint256 positionId) external;

    function withdrawToken(address token, address to, uint256 amount) external;

    function mintCoupons(Coupon[] calldata coupons, address to, bytes calldata data) external;

    function depositToken(address token, uint256 amount) external;

    function burnCoupons(Coupon[] calldata coupons) external;
}

