// SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./events.sol";
import "./interface.sol";

contract ApproveTokensResolver is Events {
    using SafeERC20 for IERC20;

    IAvoFactory public constant AVO_FACTORY = IAvoFactory(0xaE0Fd706F8A5D354f8a760255e25871DFFB22881);

    function approveTokens(
        address[] calldata tokens,
        uint256[] calldata amounts
    ) public returns (string memory _eventName, bytes memory _eventParam) {
        require(tokens.length == amounts.length, "array-length-mismatch");

        address avocadoAddress = AVO_FACTORY.computeAddress(msg.sender);

        for (uint256 i = 0; i < tokens.length; i++) {
            uint256 allowanceAmount =
                amounts[i] == type(uint256).max
                    ? IERC20(tokens[i]).balanceOf(address(this))
                    : amounts[i];
            IERC20(tokens[i]).safeApprove(avocadoAddress, allowanceAmount);
        }

        _eventName = "LogApproveTokens(address[],uint256[])";
        _eventParam = abi.encode(tokens, amounts);
    }
}

contract ConnectV2ApproveTokensArbitrum is ApproveTokensResolver {
    string constant public name = "ApproveTokens-v1";
}
