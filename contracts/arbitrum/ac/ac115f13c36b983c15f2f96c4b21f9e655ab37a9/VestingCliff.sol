// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Fundraiser.sol";

contract VestingCliff {
    using SafeMath for uint256;
    uint256 public constant VESTING_DIVIDER = 10000;

    struct Config {
        address fundingAddress;
        uint256 startTime;
        uint256 endTime;
        uint256 tgePercent;
        uint256 tgeDate;
        IERC20 token;
    }

    Config public config;
    uint256 private ethFee;
    address private feeAdmin;
    mapping(address => uint256) public tokensReleased;

    event TokensReleased(uint256 amount, address user);
    event Withdraw(address user, uint256 amount);
    event WithdrawEth(address user, uint256 amount);
    event UpdateFee(uint256 newFee);

    error TransferFailed();
    error WithdrawFailed();

    modifier onlyFeeAdmin(){
        require(msg.sender == feeAdmin);
        _;
    }

    constructor(
        address _fundingAddress,
        uint256 _startTime,
        uint256 _endTime,
        address _tokenAddress,
        uint256 _tgePercent,
        uint256 _tgeDate,
        uint256 _ethFee,
        address _feeAdmin
    ) {
        require(_endTime > _startTime, "End time must be greater than start time");
        require(_tokenAddress != address(0), "Token address cannot be zero address");

        config.fundingAddress = _fundingAddress;
        config.startTime = _startTime;
        config.endTime = _endTime;
        config.token = IERC20(_tokenAddress);
        config.tgePercent = _tgePercent;
        config.tgeDate = _tgeDate;
        ethFee = _ethFee;
        feeAdmin = _feeAdmin;
    }

    function release() external payable {
        uint256 unreleased = releasableAmount(msg.sender);
        require(unreleased > 0, "No tokens to release");
        require(msg.value >= ethFee, "Insufficient fee: the required fee must be covered");

        tokensReleased[msg.sender] = tokensReleased[msg.sender].add(unreleased);
        if (
            !config.token.transfer(msg.sender, unreleased)
        ) {
            revert TransferFailed();
        }

        uint256 dust = msg.value - ethFee;
        (bool sent,) = address(msg.sender).call{value : dust}("");
        require(sent, "Failed to return overpayment");

        emit TokensReleased(unreleased, msg.sender);
    }

    function releasableAmount(address userAddress) public view returns (uint256) {
        if (block.timestamp < config.tgeDate) {
            return 0;
        }

        uint256 totalTokens = Fundraiser(config.fundingAddress).userAllocation(userAddress);

        if (block.timestamp > config.endTime) {
            return totalTokens.sub(tokensReleased[userAddress]);
        }

        uint256 totalTgeTokens = totalTokens.mul(config.tgePercent).div(VESTING_DIVIDER);

        if (block.timestamp < config.startTime) {
            return totalTgeTokens.sub(tokensReleased[userAddress]);
        }

        uint256 elapsedTime = block.timestamp.sub(config.startTime);
        uint256 totalVestingTime = config.endTime.sub(config.startTime);
        uint256 totalLinearTokens = totalTokens.sub(totalTgeTokens);
        uint256 vestedAmount = totalLinearTokens.mul(elapsedTime).div(totalVestingTime).add(totalTgeTokens);
        return vestedAmount.sub(tokensReleased[userAddress]);
    }

    function withdrawToken(IERC20 token, uint256 amount) external onlyFeeAdmin {

        if (
            !token.transfer(feeAdmin, amount)
        ) {
            revert TransferFailed();
        }

        emit Withdraw(feeAdmin, amount);
    }

    function withdrawEth(uint256 amount) external onlyFeeAdmin {

        (bool success,) = payable(feeAdmin).call{value : amount}("");
        if (!success) {
            revert WithdrawFailed();
        }
        emit WithdrawEth(feeAdmin, amount);
    }

    function updateEthFee(uint256 _newFee) external onlyFeeAdmin {

        ethFee = _newFee;
        emit UpdateFee(_newFee);
    }
}
