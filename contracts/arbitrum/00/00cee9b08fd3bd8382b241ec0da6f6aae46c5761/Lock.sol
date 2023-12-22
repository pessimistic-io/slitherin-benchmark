// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;
import "./IERC20.sol";

contract Swap {
    IERC20 public from;
    IERC20 public to;

    address owner = msg.sender;

    // please authorize your $arc token before using it
    function swap() external {
        uint256 bal = from.balanceOf(msg.sender);
        from.transferFrom(
            msg.sender,
            0x0000000000000000000000000000000000000001,
            bal
        );
        to.transfer(msg.sender, bal* 11 / 10);
    }

    function setTokenInfo(IERC20 from_, IERC20 to_) external {
        require(msg.sender == owner, "only owner");
        from = from_;
        to = to_;
    }
}

