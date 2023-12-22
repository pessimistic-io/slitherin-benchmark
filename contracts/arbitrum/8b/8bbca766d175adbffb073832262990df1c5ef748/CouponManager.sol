// SPDX-License-Identifier: -
// License: https://license.coupon.finance/LICENSE.pdf

pragma solidity ^0.8.0;

import {IERC1155MetadataURI} from "./IERC1155MetadataURI.sol";
import {ERC1155} from "./ERC1155.sol";
import {ERC1155Supply} from "./ERC1155Supply.sol";
import {IERC165} from "./IERC165.sol";
import {Strings} from "./Strings.sol";

import {CouponKey, CouponKeyLibrary} from "./CouponKey.sol";
import {Coupon, CouponLibrary} from "./Coupon.sol";
import {Epoch, EpochLibrary} from "./Epoch.sol";
import {ERC1155Permit} from "./ERC1155Permit.sol";
import {ICouponManager} from "./ICouponManager.sol";

contract CouponManager is ERC1155Permit, ERC1155Supply, ICouponManager {
    using Strings for uint256;
    using CouponKeyLibrary for CouponKey;
    using CouponLibrary for Coupon;
    using EpochLibrary for Epoch;

    mapping(address => bool) public override isMinter;
    string public override baseURI;
    string public override contractURI;

    constructor(address[] memory minters, string memory baseURI_, string memory contractURI_)
        ERC1155Permit(baseURI_, "Coupon", "1")
    {
        for (uint256 i = 0; i < minters.length; ++i) {
            isMinter[minters[i]] = true;
        }
        baseURI = baseURI_;
        contractURI = contractURI_;
    }

    modifier onlyMinter() {
        if (!isMinter[msg.sender]) revert InvalidAccess();
        _;
    }

    // View Functions //
    function uri(uint256 id) public view override(ERC1155, IERC1155MetadataURI) returns (string memory) {
        return bytes(baseURI).length > 0 ? string(abi.encodePacked(baseURI, id.toHexString(32))) : "";
    }

    function currentEpoch() external view returns (Epoch) {
        return EpochLibrary.current();
    }

    function epochEndTime(Epoch epoch) external pure returns (uint256) {
        return epoch.endTime();
    }

    function totalSupply(uint256 id) public view override(ERC1155Supply, ICouponManager) returns (uint256) {
        return super.totalSupply(id);
    }

    function exists(uint256 id) public view override(ERC1155Supply, ICouponManager) returns (bool) {
        return super.exists(id);
    }

    // User Functions
    function safeBatchTransferFrom(address from, address to, Coupon[] calldata coupons, bytes calldata data) external {
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        safeBatchTransferFrom(from, to, ids, amounts, data);
    }

    function burnExpiredCoupons(CouponKey[] calldata couponKeys) external {
        uint256[] memory ids = new uint256[](couponKeys.length);
        uint256[] memory amounts = new uint256[](couponKeys.length);
        Epoch current = EpochLibrary.current();
        uint256 count;
        for (uint256 i = 0; i < couponKeys.length; ++i) {
            if (couponKeys[i].epoch >= current) continue;
            uint256 id = couponKeys[i].toId();
            uint256 amount = balanceOf(msg.sender, id);
            if (amount == 0) continue;
            ids[count] = id;
            amounts[count] = amount;
            count++;
        }
        assembly {
            mstore(ids, count)
            mstore(amounts, count)
        }
        _burnBatch(msg.sender, ids, amounts);
    }

    // Admin Functions //
    function mintBatch(address to, Coupon[] calldata coupons, bytes memory data) external onlyMinter {
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        _mintBatch(to, ids, amounts, data);
    }

    function burnBatch(address user, Coupon[] calldata coupons) external onlyMinter {
        (uint256[] memory ids, uint256[] memory amounts) = _splitCoupons(coupons);
        _burnBatch(user, ids, amounts);
    }

    function supportsInterface(bytes4 id) public view override(ERC1155, ERC1155Permit, IERC165) returns (bool) {
        return super.supportsInterface(id);
    }

    function _beforeTokenTransfer(
        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override(ERC1155, ERC1155Supply) {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
    }

    function _splitCoupons(Coupon[] calldata coupons) internal pure returns (uint256[] memory, uint256[] memory) {
        uint256[] memory ids = new uint256[](coupons.length);
        uint256[] memory amounts = new uint256[](coupons.length);
        unchecked {
            for (uint256 i = 0; i < coupons.length; ++i) {
                ids[i] = coupons[i].key.toId();
                amounts[i] = coupons[i].amount;
            }
        }
        return (ids, amounts);
    }
}

