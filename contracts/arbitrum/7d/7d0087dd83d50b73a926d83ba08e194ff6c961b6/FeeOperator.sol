// SPDX-License-Identifier: GPL-3.0-only

pragma solidity >=0.8.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

/**
 * @title Allows the owner to set fee collector and allows fee collectors to collect fees
 * @author Padoriku
 */
abstract contract FeeOperator is Ownable {
    using SafeERC20 for IERC20;

    address public feeCollector;

    event FeeCollectorUpdated(address from, address to);

    modifier onlyFeeCollector() {
        require(msg.sender == feeCollector, "not fee collector");
        _;
    }

    constructor(address _feeCollector) {
        feeCollector = _feeCollector;
    }

    function collectFee(address[] calldata _tokens, address _to) external onlyFeeCollector {
        for (uint256 i = 0; i < _tokens.length; i++) {
            uint256 balance = IERC20(_tokens[i]).balanceOf(address(this));
            IERC20(_tokens[i]).safeTransfer(_to, balance);
        }
    }

    function setFeeCollector(address _feeCollector) external onlyOwner {
        address oldFeeCollector = feeCollector;
        feeCollector = _feeCollector;
        emit FeeCollectorUpdated(oldFeeCollector, _feeCollector);
    }
}

