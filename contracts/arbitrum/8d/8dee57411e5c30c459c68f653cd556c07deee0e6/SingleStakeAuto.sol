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

    IERC20 public depositToken;
    IERC20 public rewardToken;
    IStakingInterface public stakingContract;
    IDEXRouterInterface public dexRouter;
    uint256 public depositFeeBps;
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
        address _dexRouter,
        uint256 _depositFeeBps
    ) {
        require(_depositFeeBps <= 500, "Invalid deposit fee");
        depositToken = IERC20(_depositToken);
        rewardToken = IERC20(_rewardToken);
        stakingContract = IStakingInterface(_stakingContract);
        dexRouter = IDEXRouterInterface(_dexRouter);
        depositFeeBps = _depositFeeBps;
    }

    function setDepositFeeBps(uint256 _depositFeeBps) external onlyOwner {
        require(_depositFeeBps <= 500, "Invalid deposit fee");
        depositFeeBps = _depositFeeBps;
    }

    function deposit(uint256 _amount) external {
        require(_amount > 0, "Invalid deposit amount");
        autoCompound();

        depositToken.safeTransferFrom(msg.sender, address(this), _amount);
        uint256 depositFee = (_amount * depositFeeBps) / 10000;
        uint256 depositAmount = _amount - depositFee;

        uint256 stakingBalance = stakingContract.balanceOf(address(this));
        uint256 shares = (depositAmount * totalShares) / stakingBalance;

        userInfo[msg.sender].shares += shares;
        userInfo[msg.sender].depositAmount += depositAmount;
        totalShares += shares;

         if (!isInStakers[msg.sender]) {
            stakers.push(msg.sender);
            isInStakers[msg.sender] = true;
        }

        stakingContract.deposit(depositAmount);

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

        uint256 stakingBalance = stakingContract.balanceOf(address(this));
        uint256 withdrawAmount = (stakingBalance * _shares) / totalShares;

        user.shares -= _shares;
        user.depositAmount -= withdrawAmount;
        totalShares -= _shares;

        if (user.shares == 0) {
            _removeStaker(msg.sender);
        }

        stakingContract.withdraw(withdrawAmount);
        depositToken.safeTransfer(msg.sender, withdrawAmount);
        if (_shares == user.shares) {
            
        }

        emit Withdraw(msg.sender, withdrawAmount);
    }

    function emergencyWithdraw() external nonReentrant {
        UserInfo storage user = userInfo[msg.sender];
        require(user.shares > 0, "Withdraw: Nothing to withdraw");

        uint256 stakingBalance = stakingContract.balanceOf(address(this));
        uint256 withdrawAmount = (stakingBalance * user.shares) / totalShares;

        totalShares -= user.shares;
        user.shares = 0;
        user.depositAmount = 0;

         _removeStaker(msg.sender);

        stakingContract.withdraw(withdrawAmount);
        depositToken.safeTransfer(msg.sender, withdrawAmount);

        emit EmergencyWithdraw(msg.sender, withdrawAmount);
    }

    function autoCompound() public {
    uint256 pendingReward = stakingContract.pendingReward(address(this));
    if (pendingReward > 0) {
        stakingContract.claimReward();

        uint256 rewardBalance = rewardToken.balanceOf(address(this));
        if (rewardBalance > 0) {
            address[] memory path = new address[](2);
            path[0] = address(rewardToken);
            path[1] = address(depositToken);

            dexRouter.swapExactTokensForTokens(
                rewardBalance,
                uint256(0),
                path,
                address(this),
                block.timestamp + 60
            );

            uint256 swappedAmount = depositToken.balanceOf(address(this));

            uint256 stakingBalance = stakingContract.balanceOf(address(this));
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

            stakingContract.deposit(swappedAmount);
        }
    }   
}
}
