// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./IStakingInterface.sol";
import "./IDEXRouterInterface.sol";

contract AutoCompounder is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;
    // The address of the underlying staker where the deposits and withdrawals are made
    address immutable public staker;
    // The reward token
    address immutable public rewardToken;
    // The staked token
    address immutable public depositToken;
    // The address of the router that is used for conducting swaps
    address immutable public router;
    // uint256 public depositFeeBps;
    uint256 public totalShares;
    address[] public stakers; // List of addresses that have staked tokens
    mapping(address => bool) private isInStakers; // Mapping to check if an address is already in stakers list


    struct UserInfo {
        uint256 shares;
        uint256 depositAmount;
    }

    mapping(address => UserInfo) public userInfo;

    event Deposit(address indexed user, uint256 amount);
    event Withdraw(address indexed user, uint256 amount);
    event EmergencyWithdraw(address indexed user, uint256 amount);


    constructor(
        address _depositToken,
        address _rewardToken,
        address _stakingContract,
        address _dexRouter
        // uint256 _depositFeeBps
    ) {
        // require(_depositFeeBps <= 500, "Invalid deposit fee");
        staker = _stakingContract;
        depositToken = IStakingInterface(staker).stakedToken();
        rewardToken = IStakingInterface(staker).rewardToken();
        router = _dexRouter;
        // depositFeeBps = _depositFeeBps;
    }

    // function setDepositFeeBps(uint256 _depositFeeBps) external onlyOwner {
    //     require(_depositFeeBps <= 500, "Invalid deposit fee");
    //     depositFeeBps = _depositFeeBps;
    // }



    function deposit(uint256 _amount) external nonReentrant {
    require(_amount > 0, "Invalid deposit amount");

    IERC20Metadata(depositToken).transferFrom(address(msg.sender), address(this), _amount);

    uint256 depositAmount = _amount;

    uint256 stakingBalance = IERC20Metadata(depositToken).balanceOf(address(this));
    uint256 shares;

    if (totalShares == 0 || stakingBalance == 0) {
        shares = depositAmount;
    } else {
        shares = (depositAmount * totalShares) / stakingBalance;
    }

    userInfo[msg.sender].shares += shares;
    userInfo[msg.sender].depositAmount += depositAmount;
    totalShares += shares;

    if (!isInStakers[msg.sender]) {
        stakers.push(msg.sender);
        isInStakers[msg.sender] = true;
    }
    IStakingInterface(staker).deposit(depositAmount);
    emit Deposit(msg.sender, depositAmount);
}

    function _removeStaker(address user) private {
        for (uint256 i = 0; i < stakers.length; i++) {
            if (stakers[i] == user) {
                stakers[i] = stakers[stakers.length - 1];
                stakers.pop();
                isInStakers[user] = false;
                break;
            }
        }
    }

    function withdraw(uint256 _shares) external {
        UserInfo storage user = userInfo[msg.sender];
        require(_shares > 0 && _shares <= user.shares, "Invalid withdraw shares");

        autoCompound();

        uint256 stakingBalance = IERC20Metadata(depositToken).balanceOf(address(this));
        uint256 withdrawAmount = (stakingBalance * _shares) / totalShares;

        user.shares -= _shares;
        user.depositAmount -= withdrawAmount;
        totalShares -= _shares;

        if (user.shares == 0) {
            _removeStaker(msg.sender);
        }

        IStakingInterface(staker).withdraw(withdrawAmount);
        IERC20Metadata(depositToken).transfer(msg.sender, withdrawAmount);
        if (_shares == user.shares) {
            
        }

        emit Withdraw(msg.sender, withdrawAmount);
    }

    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.shares > 0, "Withdraw: Nothing to withdraw");

        uint256 stakingBalance = IERC20Metadata(depositToken).balanceOf(address(this));
        uint256 withdrawAmount = (stakingBalance * user.shares) / totalShares;

        totalShares -= user.shares;
        user.shares = 0;
        user.depositAmount = 0;

         _removeStaker(msg.sender);

        IStakingInterface(staker).withdraw(withdrawAmount);
        IERC20Metadata(depositToken).transfer(msg.sender, withdrawAmount);

        emit EmergencyWithdraw(msg.sender, withdrawAmount);
    }

    function autoCompound() public {
    uint256 pendingReward = IStakingInterface(staker).pendingReward(address(this));
    if (pendingReward > 0) {
        IStakingInterface(staker).deposit(0);

        uint256 rewardBalance = IERC20Metadata(rewardToken).balanceOf(address(this));
        if (rewardBalance > 0) {
            address[] memory path = new address[](2);
            path[0] = address(rewardToken);
            path[1] = address(depositToken);

            IDEXRouterInterface(router).swapExactTokensForTokens(
                rewardBalance,
                uint256(0),
                path,
                address(this),
                block.timestamp + 60
            );

            uint256 swappedAmount = IERC20Metadata(depositToken).balanceOf(address(this));

            uint256 stakingBalance = IERC20Metadata(depositToken).balanceOf(address(this));
            uint256 totalNewShares = (swappedAmount * totalShares) / stakingBalance;

            totalShares += totalNewShares;

            for (uint256 i = 0; i < stakers.length; i++) {
                address userAddress = stakers[i];
                UserInfo storage user = userInfo[userAddress];
                if (user.shares > 0) {
                    uint256 userNewShares = (user.shares * totalNewShares) / totalShares;
                    user.shares += userNewShares;
                    user.depositAmount += (userNewShares * stakingBalance) / totalShares;
                }
            }

            IStakingInterface(staker).deposit(swappedAmount);
        }
    }   
}
}
