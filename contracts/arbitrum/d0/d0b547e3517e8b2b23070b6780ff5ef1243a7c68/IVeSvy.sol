// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.17;

import "./IERC721Receiver.sol";
import "./IVeERC20.sol";

/**
 * @dev Interface of the VeSvy
 */
interface IVeSvy is IVeERC20 {
    function isUser(address _addr) external view returns (bool);

    function stake(uint256 _amount) external;

    function claimable(address _addr) external view returns (uint256);

    function claim() external;

    function unstake(uint256 _amount) external;

    function getStakedSvy(address _addr) external view returns (uint256);

    function getVotes(address _account) external view returns (uint256);

    function getVeSVYEarnRatePerSec(
        address _addr
    ) external view returns (uint256);

    function getMaxVeSVYEarnable(address _addr) external view returns (uint256);
}

