// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.12;

import {SafeERC20, IERC20} from "./SafeERC20.sol";

interface IOps {
    function gelato() external view returns (address payable);
    function createTaskNoPrepayment(
        address _execAddress,
        bytes4 _execSelector,
        address _resolverAddress,
        bytes calldata _resolverData,
        address _feeToken
    ) external returns (bytes32 task);
    function cancelTask(bytes32 _taskId) external;
    function getFeeDetails() external view returns (uint256, address);
}

contract OpsReady {
    address public ops;
    address payable public gelato;
    address public constant ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;

    modifier onlyOps() {
        require(msg.sender == ops, "OpsReady: onlyOps");
        _;
    }

    function __OpsReadyInit (address _ops) internal {
        ops = _ops;
        gelato = IOps(_ops).gelato();
    }

    function _transfer(uint256 _amount, address _paymentToken) internal virtual {
        if (_paymentToken == ETH) {
            (bool success, ) = gelato.call{value: _amount}("");
            require(success, "_transfer: ETH transfer failed");
        } else {
            SafeERC20.safeTransfer(IERC20(_paymentToken), gelato, _amount);
        }
    }
}

