// SPDX-License-Identifier: AGPL-3.0-only
pragma solidity ^0.8.10;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {Kernel, Module} from "./Kernel.sol";

error IsAlreadyReserveAsset();
error NotReserveAsset();

contract BarnTreasury is Module {
    using SafeTransferLib for ERC20;

    event AssetAdded(address indexed token);
    event AssetRemoved(address indexed token);
    event FundsDeposited(address indexed from, address indexed token, uint256 amount);
    event FundsWithdrawn(address indexed to, address indexed token, uint256 amount);

    /// @inheritdoc Module
    function KEYCODE() public pure override returns (bytes5) {
        return "TRSRY";
    }

    /// @inheritdoc Module
    function VERSION() external pure override returns (uint8 major, uint8 minor) {
        return (1, 0);
    }

    // VARIABLES

    mapping(ERC20 => bool) public isReserveAsset;
    ERC20[] public reserveAssets;
    mapping(ERC20 => uint256) public totalInflowsForAsset;
    mapping(ERC20 => uint256) public totalOutflowsForAsset;

    constructor(Kernel kernel_, ERC20[] memory initialAssets_) Module(kernel_) {
        uint256 length = initialAssets_.length;
        for (uint256 i; i < length; ) {
            ERC20 asset = initialAssets_[i];
            isReserveAsset[asset] = true;
            reserveAssets.push(asset);
            unchecked {
                ++i;
            }
        }
    }

    // Policy Interface

    function getReserveAssets() public view returns (ERC20[] memory reserveAssets_) {
        reserveAssets_ = reserveAssets;
    }

    // whitelisting: add and remove reserve assets (if the treasury supports these currencies)
    function addReserveAsset(ERC20 asset_) public permissioned {
        if (isReserveAsset[asset_]) {
            revert IsAlreadyReserveAsset();
        }
        isReserveAsset[asset_] = true;
        reserveAssets.push(asset_);
        emit AssetAdded(address(asset_));
    }

    function removeReserveAsset(ERC20 asset_) public permissioned {
        if (!isReserveAsset[asset_]) {
            revert NotReserveAsset();
        }
        isReserveAsset[asset_] = false;

        uint256 numAssets = reserveAssets.length;
        for (uint256 i; i < numAssets; ) {
            if (reserveAssets[i] == asset_) {
                reserveAssets[i] = reserveAssets[numAssets - 1];
                reserveAssets.pop();
                break;
            }
            unchecked {
                ++i;
            }
        }
        emit AssetRemoved(address(asset_));
    }

    // more convenient than "transferFrom", since users only have to approve the Treasury
    // and any policy can make approved transfers on the Treasury's behalf.
    // beware of approving malicious policies that can rug the user.

    function deposit(
        ERC20 asset_,
        address from_,
        uint256 amount_
    ) external permissioned {
        if (!isReserveAsset[asset_]) {
            revert NotReserveAsset();
        }
        asset_.safeTransferFrom(from_, address(this), amount_);

        totalInflowsForAsset[asset_] += amount_;

        emit FundsDeposited(from_, address(asset_), amount_);
    }

    // must withdraw assets to approved policies, where withdrawn assets are handled in their internal logic.
    // no direct withdraws to arbitrary addresses allowed.
    function withdraw(ERC20 asset_, uint256 amount_) external permissioned {
        if (!isReserveAsset[asset_]) {
            revert NotReserveAsset();
        }
        asset_.safeTransfer(msg.sender, amount_);

        totalOutflowsForAsset[asset_] += amount_;

        emit FundsWithdrawn(msg.sender, address(asset_), amount_);
    }
}

