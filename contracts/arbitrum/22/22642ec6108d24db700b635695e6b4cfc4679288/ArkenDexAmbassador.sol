// SPDX-License-Identifier: UNLICENSED

pragma solidity =0.8.16;

import "./SafeERC20.sol";

contract ArkenDexAmbassador {
    uint256 internal constant _MAX_UINT_256_ = 2**256 - 1;
    address public constant _ETH_ = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
    using SafeERC20 for IERC20;

    receive() external payable {}

    function _increaseAllowance(
        address token,
        address spender,
        uint256 amount
    ) public {
        uint256 allowance = IERC20(token).allowance(address(this), spender);
        if (amount > allowance) {
            uint256 increaseAmount = _MAX_UINT_256_ - allowance;
            IERC20(token).safeIncreaseAllowance(spender, increaseAmount);
        }
    }

     function _getBalance(
        address token,
        address account
    ) public view returns (uint256) {
        if (_ETH_ == token) {
            return account.balance;
        } else {
            return IERC20(token).balanceOf(account);
        }
    }

    function tradeWithTarget(
        address srcToken,
        address dstToken,
        uint256 amountIn,
        bytes calldata interactionDataOutside,
        address targetOutside
    ) external payable {
        if (_ETH_ != srcToken) {
            _increaseAllowance(srcToken, targetOutside, amountIn);
        }
        // call target contract, full credit to @nlordell and cowprotocol.
        // NOTE: Use assembly to call the interaction instead of a low level
        // call for two reasons:
        // - We don't want to copy the return data, since we discard it for
        // interactions.
        // - Solidity will under certain conditions generate code to copy input
        // calldata twice to memory (the second being a "memcopy loop").
        // <https://github.com/gnosis/gp-v2-contracts/pull/417#issuecomment-775091258>
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let freeMemoryPointer := mload(0x40)
            calldatacopy(
                freeMemoryPointer,
                interactionDataOutside.offset,
                interactionDataOutside.length
            )
            if iszero(
                call(
                    gas(),
                    targetOutside,
                    callvalue(),
                    freeMemoryPointer,
                    interactionDataOutside.length,
                    0,
                    0
                )
            ) {
                returndatacopy(0, 0, returndatasize())
                revert(0, returndatasize())
            }
        }
         uint256 returnAmount = _getBalance(
            dstToken,
            address(this)
        );
        if (_ETH_ == dstToken) {
            (bool sent, ) = msg.sender.call{value: returnAmount}('');
            require(sent, 'Failed to send Ether');
        } else {
            IERC20(dstToken).safeTransfer(msg.sender, returnAmount);
        }
    }
}

