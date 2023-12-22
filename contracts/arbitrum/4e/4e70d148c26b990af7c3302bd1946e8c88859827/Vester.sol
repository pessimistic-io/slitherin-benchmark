// SPDX-License-Identifier: MIT

pragma solidity 0.8.19;

import "./SafeERC20.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";


contract VKAVesting is ReentrancyGuard, Ownable {
    using SafeERC20 for IERC20;

    struct UserData {
        uint256 balance;
        uint256 totalClaimed;
        uint256 lastClaimTime;
        uint256 category;
        bool permitted;
    }
    
    address public mainToken;
    uint256 public vestingStart;

    mapping(address => UserData) public usersData;
    mapping(uint256 => uint256) public categoryCliff;
    mapping(uint256 => bool) public categoryInitialized;
    mapping(uint256 => uint256) public vestingPeriods;

    event TokensClaimed(address indexed user, uint256 amount);
    event VestingInitialized(uint256 timestamp);
    event PermissionChanged(address user, bool status);
    event CategorySet(uint256 category, uint256 cliff, uint256 vestingPeriod);
    event RetrievedTokens(address tokenAddress);

    constructor(
        address _tokenAddress,
        uint256[] memory _cliff, //cliff, starts after this time elapsed
        uint256[] memory _durations //vesting duration
    ) {
        mainToken = _tokenAddress;
        
        require(_cliff.length == _durations.length,"Array length mismatch");

        for (uint256 i = 0; i < _cliff.length; i++) {
            require(_durations[i] != 0, "Incorrect duration");
            setVestingCategory(i, _cliff[i], _durations[i]);
        }
    }

    // -- View Functions -- //

    function tokensToClaim(address user) public view returns (uint256) {
        uint256 pending = usersData[user].totalClaimed;
        //totalClaimedPerUser[user];
        uint256 nextClaim = nextClaimAmount(user);

        return pending + (nextClaim);
    }

    function nextClaimAmount(address user) public view returns (uint256) {
        UserData memory _userData = usersData[user];
        uint256 elapsedTime = block.timestamp - _userData.lastClaimTime;
        uint256 userBalance = _userData.balance;
        
        if (userBalance == 0) {
            return 0;
        }
        
        uint256 totalVestAmount = userBalance + _userData.totalClaimed;
        uint256 claimAmount = totalVestAmount * (elapsedTime) / (vestingPeriods[_userData.category]);

        if (claimAmount < userBalance) {
            return claimAmount;
        } else {
            return userBalance;
        }
    }

    // -- Owner Functions -- //
    function initializeVesting() external onlyOwner {
        require(vestingStart == 0, "Vesting already initialized");
        vestingStart = block.timestamp;

        emit VestingInitialized(block.timestamp);
    }

    function modifyClaimPermission(address user, bool status) external onlyOwner {
        UserData storage _userData = usersData[user];
        require(_userData.permitted != status, "Permission already set");
        _userData.permitted = status;

        emit PermissionChanged(user, status);
    }

    function setVestingCategory(uint256 category, uint256 cliff, uint256 vestingPeriod) public onlyOwner {
        require(!categoryInitialized[category], "Category already initialized");
        categoryCliff[category] = cliff;
        vestingPeriods[category] = vestingPeriod;
        categoryInitialized[category] = true;

        emit CategorySet(category, cliff, vestingPeriod);
    }

    function withdrawTokens(address tokenAddress) external onlyOwner {
        IERC20(tokenAddress).safeTransfer(owner(), IERC20(tokenAddress).balanceOf(address(this)));

        emit RetrievedTokens(tokenAddress);
    }

    function addTokensForUsers(
        address[] memory users,
        uint256[] memory amounts,
        uint256[] memory categories
    ) public onlyOwner {
        require(
            users.length == amounts.length &&
            amounts.length == categories.length,
            "Array length mismatch"
        );

        for (uint256 i = 0; i < users.length; i++) {
            require(!usersData[users[i]].permitted, "User already added");
            _updateVestForUser(users[i]);
            _issueTokens(users[i], amounts[i]);
            usersData[users[i]].category = categories[i];
            usersData[users[i]].lastClaimTime = block.timestamp + (categoryCliff[categories[i]]);
            usersData[users[i]].permitted = true;
        }
    }

    // -- Public Functions -- //

    function claimTokens() external nonReentrant returns (uint256) {
        UserData storage _userData = usersData[msg.sender];

        require(block.timestamp >= vestingStart + (categoryCliff[_userData.category]),"Claim period not started");
        require(vestingStart != 0, "Vesting not started");
        require(_userData.permitted, "Not permitted to claim");
        require(_userData.balance > 0, "No tokens to claim");
        
        uint256 amountToClaim = _updateVestForUser(msg.sender);
        _userData.totalClaimed += amountToClaim;

        IERC20(mainToken).safeTransfer(msg.sender, amountToClaim);

        emit TokensClaimed(msg.sender, amountToClaim);
        return amountToClaim;
    }

    // -- Internal Functions -- //

    function _updateVestForUser(address user) internal returns (uint256) {
        UserData storage _userData = usersData[user];
        uint256 amount = nextClaimAmount(user);
        _userData.lastClaimTime = block.timestamp;

        if (amount == 0) {
            return 0;
        } else {
            _removeTokens(user, amount);
            _userData.totalClaimed += amount;
        }

        return amount;
    }

    function _issueTokens(address user, uint256 amount) internal {
        UserData storage _userData = usersData[user];
        require(user != address(0), "Cannot issue to zero address");
        _userData.balance += amount;

    }

    function _removeTokens(address user, uint256 amount) internal {
        UserData storage _userData = usersData[user];
        require(user != address(0), "Cannot remove from zero address");
        _userData.balance -= amount;
    }

}

