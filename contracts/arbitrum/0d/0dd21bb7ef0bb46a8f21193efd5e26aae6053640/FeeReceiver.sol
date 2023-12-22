// SPDX-License-Identifier: BSL-1.1
pragma solidity 0.8.20;

import "./TransferHelper.sol";

contract FeeReceiver {
    // storage
    address internal s_setter;
    address internal s_collector;

    modifier onlySetter() {
        require(msg.sender == s_setter, "FeeReciever: NOT_SETTER");
        _;
    }

    modifier onlyCollector() {
        require(msg.sender == s_collector, "FeeReciever: NOT_COLLECTOR");
        _;
    }

    constructor(address setter) {
        s_setter = setter;
    }

    // accepting ETH
    receive() external payable {}

    function setSetter(address setter) external onlySetter {
        s_setter = setter;
    }

    function setCollector(address collector) external onlySetter {
        s_collector = collector;
    }

    function collect(
        address token,
        address recipient,
        uint256 amount
    ) external onlyCollector {
        if (token == address(0)) {
            TransferHelper.safeTransferETH(recipient, amount);
        } else {
            TransferHelper.safeTransfer(token, recipient, amount);
        }
    }

    function getSetter() external view returns (address) {
        return s_setter;
    }

    function getCollector() external view returns (address) {
        return s_collector;
    }
}

