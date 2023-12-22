pragma solidity ^0.8.0;

import "./Ownable.sol";

import "./SafeERC20.sol";
import "./IERC20.sol";

// The locker stores IERC20 tokens and only allows the owner to withdraw them after the UNLOCK_UNIXTIME has been reached.
contract Locker is Ownable {
    using SafeERC20 for IERC20;

    uint256 public immutable UNLOCK_UNIXTIME;

    event Claim(address token, address to);

    /**
     * @notice Constructs the Locker contract.
     */
    constructor(uint256 unlockTime) public {
        require(block.timestamp + 100 < unlockTime, "unixtime must be reasonably in the future");
        UNLOCK_UNIXTIME = unlockTime;
    }


    /**
     * @notice claimToken allows the owner to withdraw tokens sent manually to this contract.
     * It is only callable once UNLOCK_UNIXTIME has passed.
     */
    function claimToken(address token, address to) external onlyOwner {
        require(block.timestamp > UNLOCK_UNIXTIME, "still vesting...");

        IERC20(token).safeTransfer(to, IERC20(token).balanceOf(address(this)));

        emit Claim(token, to);
    }
}
