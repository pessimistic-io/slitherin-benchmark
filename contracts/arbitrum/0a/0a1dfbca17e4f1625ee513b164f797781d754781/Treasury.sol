// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./SafeERC20.sol";
import "./IERC20.sol";
import { Transfers } from "./Transfers.sol";
import { IAddressManager } from "./IAddressManager.sol";
import { IACLManager } from "./IACLManager.sol";
import { ITreasury } from "./ITreasury.sol";

contract Treasury is ITreasury {
    using Transfers for address;

    IAddressManager public immutable addressManager;

    modifier onlyCegaEntry() {
        require(
            msg.sender == addressManager.getCegaEntry(),
            "403:NotCegaEntry"
        );
        _;
    }

    constructor(IAddressManager _addressManager) {
        addressManager = _addressManager;
    }

    receive() external payable {}

    function withdraw(
        address asset,
        address receiver,
        uint256 amount
    ) external onlyCegaEntry {
        asset.transfer(receiver, amount);

        emit Withdrawn(asset, receiver, amount);
    }
}

