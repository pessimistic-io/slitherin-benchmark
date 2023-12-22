// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.19;

import {Ownable} from "./Ownable.sol";
import {IERC20} from "./ERC20_IERC20.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {Address} from "./Address.sol";

/**
 * A collection of functions that make it easy to raid and manipulate a smart contract.
 * Protection against self-goals while running personal contracts.
 */
abstract contract EscapeHatch is Ownable {
    using Address for address payable;
    using SafeERC20 for IERC20;

    function sendEther(address payable _to, uint256 _amount) external payable onlyOwner {
        _to.sendValue(_amount);
    }

    function sendToken(address _token, address _to, uint256 _amount) external onlyOwner {
        IERC20(_token).safeIncreaseAllowance(address(this), _amount);
        IERC20(_token).safeTransfer(_to, _amount);
    }

    function functionCall(address _target, bytes memory _data) external onlyOwner returns (bytes memory) {
        return Address.functionCall(_target, _data, "EscapeHatch: functionCall failed");
    }

    function functionCallWithValue(address _target, bytes memory _data, uint256 _value)
        external
        onlyOwner
        returns (bytes memory)
    {
        return Address.functionCallWithValue(_target, _data, _value, "EscapeHatch: functionCallWithValue failed");
    }
}

