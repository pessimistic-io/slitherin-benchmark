// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.19;

import {Vesting, ERC20, SafeTransferLib} from "./Vesting.sol";

// Disclamer: avoid using this contract with feeOnTransfer or rebase tokens.
contract VestingFactory {

    using SafeTransferLib for ERC20;

    address public immutable implementation = address(new Vesting());

    function createVesting(
        address token,
        uint256 amount,
        address recipient,
        uint256 startTime,
        uint256 endTime
    ) external returns (Vesting instance) {
        instance = Vesting(_clone(implementation));
        ERC20(token).safeTransferFrom(msg.sender, address(instance), amount);
        instance.init(token, amount, recipient, startTime, endTime);
    }

    // Open Zeppelin's implementation of ERC1167
    function _clone(address target) internal returns (address instance) {
        assembly {
            mstore(0x00, or(shr(0xe8, shl(0x60, target)), 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000))
            mstore(0x20, or(shl(0x78, target), 0x5af43d82803e903d91602b57fd5bf3))
            instance := create(0, 0x09, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

}

