// SPDX-License-Identifier: BSD-4-Clause

pragma solidity ^0.8.13;

import { Ownable } from "./Ownable.sol";
import { Address } from "./Address.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { IERC20 } from "./IERC20.sol";
import { IBhavishAdministrator } from "./IBhavishAdministrator.sol";

interface IBhavishNoLossPool {
    function claimWinningRewards(address _user) external;
}

interface IBhavishLossyPool {
    function withdrawForAdmin(address _user) external;
}

/**
 * @title BhavishAdministrator
 */
contract BhavishAdministrator is IBhavishAdministrator, Ownable, ReentrancyGuard {
    using Address for address;
    using SafeERC20 for IERC20;
    address public admin;
    address public lossyPool;
    address public noLossPool;
    IERC20 public lossyToken;
    IERC20 public rewardToken;

    event NewAdmin(address indexed admin);

    constructor() {
        admin = msg.sender;
    }

    /**
     * @notice Add funds
     */
    receive() external payable {}

    /**
     * @notice Claim Treasury Fund
     * @dev Callable by admin
     */
    // for Lossy, withdrawForAdmin will send native to admin contract,
    // so do claimTreasury to transfer treasury.
    // For NoLoss, redeeming BRN in admin contract will send matic to contract,
    // so do claimTreasury to transfer treasury.
    function claimTreasury() external override nonReentrant onlyOwner {
        if (rewardToken.balanceOf(address(this)) > 0) IBhavishNoLossPool(noLossPool).claimWinningRewards(address(this));
        if (lossyToken.balanceOf(address(this)) > 0) IBhavishLossyPool(lossyPool).withdrawForAdmin(address(this));
        uint256 balance = address(this).balance;
        (bool success, ) = admin.call{ value: balance }("");
        require(success, "TransferHelper: TRANSFER_FAILED");

        emit TreasuryClaim(admin, balance);
    }

    function setAdmin(address _admin) external onlyOwner {
        require(_admin != address(0), "zero address");
        admin = _admin;
    }

    function setLossyToken(address _token) external onlyOwner {
        require(_token != address(0), "zero address");
        lossyToken = IERC20(_token);
    }

    function setRewardToken(address _token) external onlyOwner {
        require(_token != address(0), "zero address");
        rewardToken = IERC20(_token);
    }

    function setLossyPool(address _pool) external onlyOwner {
        require(_pool != address(0), "zero address");
        lossyPool = _pool;
    }

    function setNoLossPool(address _pool) external onlyOwner {
        require(_pool != address(0), "zero address");
        noLossPool = _pool;
    }
}

