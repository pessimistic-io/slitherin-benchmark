// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./Ownable.sol";

contract Rewarder is Ownable {
    using SafeERC20 for IERC20;

    address public masterchef;
    IERC20 public rewardToken;

    constructor(
        IERC20 _rewardToken
    ) public {
        rewardToken = _rewardToken;
    }

    function setMasterchef(address _masterchef) external onlyOwner {
        masterchef = _masterchef;

        resetAllowance();
    }

    function resetAllowance() public {
        rewardToken.safeApprove(masterchef, uint256(-1));
    }

    function withdrawToken(address _token, uint _amount) external onlyOwner {
        IERC20(_token).safeTransfer(msg.sender, _amount);
    }
}
