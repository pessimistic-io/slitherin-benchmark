// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.19;

import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IClaimProcessor.sol";

contract TokenDistrbutor is Ownable {
    using SafeERC20 for IERC20;

    struct UpdateData {
        address user;
        uint256 amount;
    }

    struct UserData {
        uint256 amount;
        uint256 claimed;
    }

    IERC20 public immutable token;
    uint256 public totalAmount;
    uint256 public totalClaimed;
    address public keeper;
    IClaimProcessor public claimProcessor;
    mapping(address => UserData) public userData;

    function availableToClaim(address user) external view returns (uint256) {
        UserData memory data = userData[user];
        return data.amount - data.claimed;
    }

    event Claimed(address indexed user, uint256 amount);
    event ClaimProcessorUpdated(IClaimProcessor claimProcessor);
    event KeeperUpdated(address keeper);
    event UsersDataUpdated(UpdateData[]);

    constructor(address token_, address keeper_) {
        require(token_ != address(0), "Token is zero address");
        token = IERC20(token_);
        _updateKeeper(keeper_);
    }

    function claim(uint256 amount) external returns (bool) {
        UserData storage data = userData[msg.sender];
        require(amount <= token.balanceOf(address(this)), "Claim amount gt contract balance");
        require(amount <= data.amount - data.claimed, "Claim amount gt available");
        data.claimed += amount;
        totalClaimed += amount;
        if (address(claimProcessor) != address(0)) {
            token.approve(address(claimProcessor), amount);
            require(claimProcessor.processClaim(msg.sender, amount), "Claim processing error");
        } else token.safeTransfer(msg.sender, amount);
        emit Claimed(msg.sender, amount);
        return true;
    }

    function updateClaimProcessor(IClaimProcessor processor) external onlyOwner returns (bool) {
        require(address(processor) != address(0), "Processor is zero address");
        claimProcessor = processor;
        emit ClaimProcessorUpdated(processor);
        return true;
    }

    function updateKeeper(address keeper_) external onlyOwner returns (bool) {
        _updateKeeper(keeper_);
        return true;
    }

    function updateUsersData(UpdateData[] memory usersData) external returns (bool) {
        require(msg.sender == keeper, "Caller not keeper");
        for (uint256 i = 0; i < usersData.length; i++) {
            UpdateData memory newData = usersData[i];
            UserData storage data = userData[newData.user];
            require(newData.amount > data.amount, "Update amount lte amount");
            totalAmount += newData.amount - data.amount;
            data.amount = newData.amount;
        }
        emit UsersDataUpdated(usersData);
        return true;
    }

    function _updateKeeper(address keeper_) private {
        require(keeper_ != address(0), "Keeper is zero address");
        keeper = keeper_;
        emit KeeperUpdated(keeper_);
    }
}

