// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.20;

import {Controller, Token} from "./Controller.sol";
import {Owned} from "./Owned.sol";

/// @notice Helper contract for funding the bridge transaction.
contract BridgeHelper is Owned {
    
    Controller public immutable controller;
    Token public immutable token;

    mapping(address account => bool status) public willSponsor;

    constructor(Controller _controller) Owned(msg.sender) {
        controller = Controller(_controller);
        token = controller.token();
    }

    function setWillSponsor(address account, bool value) external onlyOwner {
        willSponsor[account] = value;
    }

    function bridge(
        uint16 _dstChainId,
        uint256 _amount,
        address _zroPaymentAddress,
        bytes calldata _adapterParams,
        uint256 nativeFee
    ) public payable virtual {
        token.transferFrom(msg.sender, address(this), _amount);
        controller.bridge{value: nativeFee}(
            _dstChainId,
            _amount,
            payable(address(this)),
            _zroPaymentAddress,
            _adapterParams,
            nativeFee
        );
    }

    function withdrawETH() external onlyOwner {
        (bool ok,) = address(msg.sender).call{value: address(this).balance}("");
        require(ok);
    }

    receive() external payable {}

}

