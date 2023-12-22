//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {AtlanticStraddle} from "./AtlanticStraddle.sol";
import {IERC20} from "./IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";

contract AtlanticStraddleUtils {
    using SafeERC20 for IERC20;

    function multideposit(
        address _atlanticStraddle,
        address[] memory _users,
        bool[] memory _shouldRollovers,
        uint256[] memory _amounts
    ) external {
        require(_amounts.length == _users.length, "Lengths don't match");
        require(
            _amounts.length == _shouldRollovers.length,
            "Lengths don't match"
        );

        AtlanticStraddle asContract = AtlanticStraddle(_atlanticStraddle);
        uint256 totalLength = _amounts.length;
        uint256 totalAmount;

        for (uint256 i; i < totalLength; ) {
            totalAmount += _amounts[i];

            unchecked {
                ++i;
            }
        }

        IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8).safeTransferFrom(
            msg.sender,
            address(this),
            totalAmount
        );

        IERC20(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8)
            .safeIncreaseAllowance(_atlanticStraddle, totalAmount);

        for (uint256 i; i < totalLength; ) {
            asContract.deposit(_amounts[i], _shouldRollovers[i], _users[i]);

            unchecked {
                ++i;
            }
        }
    }
}

