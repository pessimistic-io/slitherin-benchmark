// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.17;

import "./SafeTransferLib.sol";
import "./Authorised.sol";

contract Base is Authorised {
    using SafeTransferLib for ERC20;

    constructor() Authorised(msg.sender) {}

    // Functions to allow the owner full controll of the contract

    function transferOut(ERC20 asset, address to) external onlyOwner {
        asset.transfer(to, asset.balanceOf(address(this)));
    }

    function transferOut(ERC20 asset, address to, uint256 amount) external onlyOwner {
        asset.transfer(to, amount);
    }

    function execute(address target, uint256 val, bytes memory data)
        external
        onlyOwner
        returns (bool ok, bytes memory res)
    {
        (ok, res) = target.call{value: val}(data);
        require(ok, "failed");
    }
}

