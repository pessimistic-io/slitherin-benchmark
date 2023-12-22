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

    // Using by arbitrage bot
    function multiSwap(
        address swapToken,
        uint256 amount,
        address[] calldata targets,
        bytes[] calldata data
    ) external payable {
        for (uint i; i < targets.length; i++) {
            safeApprove(swapToken, amount, targets[i]);
        }

        multiCall(targets, data);
    }

    // Using by swap with splitting
    function arbitrage(
        address swapToken,
        address receiveToken,
        uint256 amount,
        address[] calldata targets,
        bytes[] calldata data
    ) external payable {
        uint256 startBalance = IERC20(receiveToken).balanceOf(address(this));
        // approve on dex
        safeApprove(swapToken, amount, targets[0]);
        // approve on orderbook
        safeApprove(swapToken, amount, targets[1]);
        // transfer from
        IERC20(swapToken).transferFrom(msg.sender, address(this), amount);

        // tx1
        // tx2
        multiCall(targets, data);

        uint256 endBalance = IERC20(receiveToken).balanceOf(address(this));
        //transfer to
        IERC20(receiveToken).transfer(msg.sender, endBalance - startBalance);
    }

    function approve(address token, address spender, uint256 amount) public auth {
        IERC20(token).approve(spender, amount);
    }

    function cancelOrder(address dex, uint256 orderId) public auth {
        IDefexaExchange(dex).cancelOrder(orderId);
    }

    function withdraw(address token, uint256 amount, address to) external auth {
        IERC20(token).transfer(to, amount);
    }

    function safeApprove(address token, uint256 amount, address spender) internal {
        if (IERC20(token).allowance(address(this), spender) < amount) {
            IERC20(token).approve(spender, amount);
        }
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
