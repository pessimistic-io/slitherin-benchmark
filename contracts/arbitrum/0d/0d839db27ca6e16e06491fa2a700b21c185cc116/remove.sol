// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./SafeMath.sol";
import "./Ownable.sol";

import "./ICamelotPair.sol";

// import "hardhat/console.sol";

interface IWETH is IERC20 {
    function deposit() external payable;

    function withdraw(uint256) external;
}

contract LiquidityRemover is Ownable {
    using SafeERC20 for IERC20;
    ICamelotPair public LPToken;

    address private factory = 0x6EcCab422D763aC031210895C81787E87B43A652;

    event PairChanged(address newPair);

    constructor() {
        LPToken = ICamelotPair(0x933B7B4daD8EF63D9fC06679472ee7b8dFF424a4);
    }

    function removeLiquidity(uint256 amount) external {
        require(amount > 0, "Invalid amount");
        IERC20(address(LPToken)).safeTransferFrom(
            msg.sender,
            address(LPToken),
            amount
        );
        LPToken.burn(msg.sender);
    }

    function setPair(address newPair) external onlyOwner {
        require(newPair != address(0), "Invalid address");
        LPToken = ICamelotPair(newPair);
        emit PairChanged(newPair);
    }

    receive() external payable {}
}

