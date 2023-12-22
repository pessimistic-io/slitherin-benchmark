// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./IERC20.sol";

import "./WardedLivingUpgradeable.sol";
import "./IDefexaExchange.sol";

contract Arbitrage is Initializable,
    UUPSUpgradeable, OwnableUpgradeable, WardedLivingUpgradeable {

    function initialize() public initializer {
        __Ownable_init();
        __WardedLiving_init();
    }

    function _authorizeUpgrade(address newImplementation) internal override onlyOwner {}

    receive() external payable {}

    function multiCall(
        address[] calldata targets,
        bytes[] calldata data
    ) public payable {
        require(targets.length == data.length, "target length != data length");

        for (uint i; i < targets.length; i++) {
            (bool success, bytes memory reason) = targets[i].call(data[i]);
            require(success, _getRevertMsg(reason));
        }
    }

    function multiSwap(
        address swapToken,
        uint256 amount,
        address[] calldata targets,
        bytes[] calldata data
    ) external payable {
        for (uint i; i < targets.length; i++) {
            IERC20(swapToken).approve(targets[i], amount);
        }

        multiCall(targets, data);
    }

    function approve(address token, address spender, uint256 amount) external auth {
        IERC20(token).approve(spender, amount);
    }

    function _getRevertMsg(bytes memory _returnData)
    internal
    pure
    returns (string memory)
    {
        // If the _res length is less than 68, then the transaction failed silently (without a revert message)
        if (_returnData.length < 68) return "call fail";

        assembly {
        // Slice the sighash.
            _returnData := add(_returnData, 0x04)
        }
        return abi.decode(_returnData, (string)); // All that remains is the revert string
    }
}
