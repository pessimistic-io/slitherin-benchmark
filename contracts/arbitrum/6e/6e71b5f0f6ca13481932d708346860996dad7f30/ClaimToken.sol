// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./ERC721Enumerable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./LegoAINFT.sol";

contract ClaimToken is Ownable, ReentrancyGuard {
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    LegoAINFT public nftToken;
    IERC20 public rewardToken;
    address payable public treasury;
    uint256 public claimFeeForMinter = 0.001 ether;
    uint256 public claimAmountForMinter = 1000 * 1e18;
    uint256 public claimFeeForAKRMAirdrop = 0.0015 ether;
    uint256 public claimAmountForAKRMAirdrop = 2000 * 1e18;

    mapping(address => bool) public claimedToken;

    event RewardClaimed(address indexed user, uint256 reward);
    event EmergencyWithdraw(address indexed user, uint256 amount);

    constructor(address _nftToken, IERC20 _rewardToken, address payable _treasury) {
        nftToken = LegoAINFT(_nftToken);
        rewardToken = _rewardToken;
        treasury = _treasury;
    }

    function updateConfigForMinter(uint256 _claimFee, uint256 _claimAmount) public onlyOwner {
        claimAmountForMinter = _claimAmount;
        claimFeeForMinter = _claimFee;
    }

    function updateConfigForAKRMAirdrop(uint256 _claimFee, uint256 _claimAmount) public onlyOwner {
        claimAmountForAKRMAirdrop = _claimAmount;
        claimFeeForAKRMAirdrop = _claimFee;
    }

    function calculateReward(address user) public view returns (uint256, uint256) {
        uint256 totalNFT = nftToken.balanceOf(user);
        uint256 claimAmount = claimAmountForAKRMAirdrop;
        uint256 claimFee = claimFeeForAKRMAirdrop;
        if (nftToken.isMinter(user)) {
            claimAmount = claimAmountForMinter;
            claimFee = claimFeeForMinter;
        }
        if (totalNFT > 0) {
            claimAmount = claimAmount * totalNFT;
        }
        return (claimAmount, claimFee);
    }

    function claim() external payable nonReentrant {
        uint256 totalRewardAmount = rewardToken.balanceOf(address(this));
        require(totalRewardAmount > 0, "Reward pool is empty");
        require(!claimedToken[msg.sender], "You have already claimed token");
        (uint256 claimAmount, uint256 claimFee) = calculateReward(msg.sender);
        require(totalRewardAmount - claimAmount > 0, "Not enough rewards");
        require(msg.value >= claimFee, "Incorrect claimFee");

        // Transfer the reward to the user
        rewardToken.safeTransfer(msg.sender, claimAmount);

        // Set claimedToken for msg sender
        claimedToken[msg.sender] = true;
        // Transfer the claimFee to the treasury
        (bool success, ) = treasury.call{value: claimFee}("");
        require(success, "Failed to transfer claim fee");

        emit RewardClaimed(msg.sender, claimAmount);
    }

    function emergencyWithdraw() external onlyOwner {
        uint256 balance = address(this).balance;
        require(balance > 0, "No balance to withdraw");

        (bool success, ) = payable(owner()).call{value: balance}("");
        require(success, "Failed to transfer balance");

        emit EmergencyWithdraw(msg.sender, balance);
    }

    // This function allows the contract to receive native token.
    receive() external payable {}
}

