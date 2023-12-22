// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IHotpotRoute.sol";
import "./IHotpotToken.sol";
import "./IERC20.sol";

contract HotpotRoute is IHotpotRoute {
    modifier ensure(uint256 deadline) {
        require(deadline >= block.timestamp, "expired");
        _;
    }

    function swap(
        address fromTokenAddr,
        address toTokenAddr,
        uint256 amount,
        uint256 minReturn,
        address to,
        uint256 deadline
    ) external ensure(deadline) {
        IHotpotToken fromToken = IHotpotToken(fromTokenAddr);
        IHotpotToken toToken = IHotpotToken(toTokenAddr);
        (uint tokenReceived, uint raisingTokenAmount) = getAmountOut(fromTokenAddr, toTokenAddr, amount);
        require(tokenReceived >= minReturn, "can not reach minReturn");
        IERC20(fromTokenAddr).transferFrom(msg.sender, address(this), amount);
        fromToken.burn(address(this), amount, raisingTokenAmount);
        address raisingToken = fromToken.getRaisingToken();
        if (raisingToken != address(0)) {
            IERC20(raisingToken).approve(toTokenAddr, raisingTokenAmount);
        }
        toToken.mint{value: raisingToken == address(0) ? raisingTokenAmount : 0}(
            address(to),
            raisingTokenAmount,
            tokenReceived
        );
    }

    function getAmountOut(
        address fromTokenAddr,
        address toTokenAddr,
        uint256 amount
    ) public view returns (uint256 returnAmount, uint256 raisingTokenAmount) {
        require(
            IHotpotToken(fromTokenAddr).getRaisingToken() == IHotpotToken(toTokenAddr).getRaisingToken(),
            "not the same raising token"
        );
        (, raisingTokenAmount, , ) = IHotpotToken(fromTokenAddr).estimateBurn(amount);
        (returnAmount, , , ) = IHotpotToken(toTokenAddr).estimateMint(raisingTokenAmount);
    }

    receive() external payable {}
}

