// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;
import "./IAugustus.sol";
import "./IERC20.sol";

contract ParaSwapper {
    IAugustus immutable augustus;

    constructor(IAugustus _augustus) {
        augustus = _augustus;
    }

    function paraSwap(
        IERC20 srcToken,
        uint256 amount,
        bytes memory augustusCalldata // data field in POST /transaction response
    ) internal {
        srcToken.approve(augustus.getTokenTransferProxy(), amount); // give allowance to augustus' transfer proxy

        (bool success, ) = address(augustus).call(augustusCalldata); // swap tokens with ParaSwap
        
        if (!success) {
            // Copy revert reason from call
            assembly {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
        require(success, "swap failed"); // check if swap was successful or not

    }
}

