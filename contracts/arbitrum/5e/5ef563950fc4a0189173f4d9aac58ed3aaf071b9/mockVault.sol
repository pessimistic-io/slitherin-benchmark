// SPDX-License-Identifier: MIT
pragma solidity 0.8.18;

import {ERC20} from "./ERC20.sol";
import {SafeTransferLib} from "./SafeTransferLib.sol";
import {WETH} from "./WETH.sol";

contract MockVault {
    using SafeTransferLib for ERC20;
    ERC20 public asset;

    mapping(address => uint256) public balanceOf;

    constructor(address _asset) {
        asset = ERC20(_asset);
    }

    // FUNCTIONS //
    function depositEth(uint256 vaultId, address sender) external payable {
        WETH(payable(address(asset))).deposit{value: msg.value}();
        balanceOf[sender] += msg.value;
    }

    function deposit(uint256 vaultId, uint256 amount, address sender) external {
        asset.safeTransferFrom(msg.sender, address(this), amount);
        balanceOf[sender] += amount;
    }

    function withdraw(
        uint256 _id,
        uint256 _shares,
        address _receiver,
        address _owner
    ) external {
        if (_receiver == address(0)) revert AddressZero();
        if (msg.sender != _owner) revert Unauthorized();
        uint256 assets = balanceOf[_owner];
        asset.safeTransfer(_receiver, assets);
    }

    /// ERRORS ///
    error AddressZero();
    error Unauthorized();
}

