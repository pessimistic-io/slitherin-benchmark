//    SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./SafeERC20.sol";

import "./SwapHandler.sol";
import "./FeeModule.sol";
import "./IAggregator.sol";

contract Aggregator is SwapHandler, IAggregator {
    using SafeERC20 for IERC20;

    constructor(
        uint256[3] memory fees_,
        address[] memory routers_,
        Router[] memory routerDetails_,
        address governor_,
        address aggregationRouter_,
        address wNative_,
        address protocolFeeVault_,
        address feeDiscountNft_
    )
        SwapHandler(routers_, routerDetails_, aggregationRouter_, wNative_)
        FeeModule(fees_, governor_, protocolFeeVault_, feeDiscountNft_)
    {}

    function rescueFunds(
        IERC20 token_,
        address to_,
        uint256 amount_
    ) external onlyGovernance {
        require(to_ != address(0), "DZ001");

        if (_isNative(token_)) {
            _safeNativeTransfer(to_, amount_);
        } else {
            token_.safeTransfer(to_, amount_);
        }

        emit TokensRescued(to_, address(token_), amount_);
    }

    receive() external payable {}
}
