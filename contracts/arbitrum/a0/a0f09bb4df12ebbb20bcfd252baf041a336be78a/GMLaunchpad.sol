// SPDX-License-Identifier: MIT

pragma solidity ^0.8.1;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./ERC20.sol";
import "./SafeERC20.sol";

// GMLaunchpadV1 v2.0
contract GMLaunchpad is Ownable, ReentrancyGuard {
  using SafeERC20 for ERC20;

  // The address of the token to be launched
  address public launchedToken;

  // Total amount of launched tokens to be claimable by others
  uint256 public totalClaimable;

  // Total amount of tokens already claimed
  uint256 public totalClaimed;

  // Time the claiming perioud ends
  uint256 public endTime;

  // Price represents amount of tokens required to pay (paymentToken) per token claimed (launchedToken)
  uint256 public price;

  // Stores all whitelisted address
  mapping(address => uint256) public whitelist;

  // Stores all claims per address
  mapping(address => uint256) public claims;

  // Limit executions to uninitalized launchpad state only
  modifier onlyUninitialized() {
    require(launchedToken == address(0x0), "You can only initialize a launchpad once!");
    _;
  }

  // Initalizes the launchpad and ensures that launchedToken are set.
  // Makes sure you cant initialize the launchpad without any claimable token amounts.
  function init(address _launchedToken) external onlyUninitialized onlyOwner returns (bool) {
    require(_launchedToken != address(0x0), "Zero Address: Not Allowed");
    // require(_paymentToken != address(0x0), "Zero Address: Not Allowed");
    launchedToken = _launchedToken;
    totalClaimable = ERC20(launchedToken).balanceOf(address(this));
    require(totalClaimable > 0, "You need to initalize the launchpad with claimable tokens!");
    return true;
  }

  // Limit executions to initalized launchpad state only
  modifier onlyInitialized() {
    require(totalClaimable > 0, "Launchpad has not been initialized yet!");
    _;
  }

  // Limit executions to unstarted launchpad state only
  modifier onlyUnstarted() {
    require(endTime == 0, "You can only start a launchpad once!");
    _;
  }

  // Starts the claiming process.
  // Makes sure endTime is in the future and not to far in the future.
  // Also makes sure that the price per launched token is set properly.
  function start(uint256 _endTime, uint256 _price) external onlyOwner onlyInitialized onlyUnstarted returns (bool) {
    require(_endTime > block.timestamp, "endTime needs to be in the future!");
    require(_endTime < (block.timestamp + 12 weeks), "endTime needs to be less than 12 weeks in the future!");
    endTime = _endTime;
    price = _price;
    return true;
  }

  // Whitelist address (enables them to claim launched token)
  function _whitelistAddress(address _address, uint256 _allocation) private returns (bool) {
    require(_address != address(0x0), "Zero Address: Not Allowed");
    whitelist[_address] = _allocation;
    return true;
  }

  // Whitelist single address
  function whitelistAddress(address _address, uint256 _allocation) external onlyOwner returns (bool) {
    require(_whitelistAddress(_address, _allocation));
    return true;
  }

  function whitelistAddresses(address[] memory _addresses, uint256[] memory _allocations)
    external
    onlyOwner
    returns (bool)
  {
    require(_addresses.length == _allocations.length, "Error: array lengths not equal");
    for (uint256 i = 0; i < _addresses.length; i++) {
      require(_whitelistAddress(_addresses[i], _allocations[i]));
    }
    return true;
  }

  // Limit executions to launchpad in progress only
  modifier onlyInProgress() {
    require(endTime > 0, "Launchpad has not been started yet!");
    require(endTime > block.timestamp, "Launchpad has been finished!");
    _;
  }

  // Claims a token allocation for claimedAmount.
  // Makes sure that the payment for the allocation is sent along and stored in the smart contract (payedAmount).
  // Also ensures that its not possible to claim more than allocation and totalClaimable.
  function claimWithEth(address forAddress, uint256 claimedAmount)
    external
    payable
    onlyInProgress
    nonReentrant
    returns (bool)
  {
    require(whitelist[forAddress] > 0, "Address has not been whitelisted for this launch!");
    uint256 payedAmount = (claimedAmount * price) / (10**18);
    require(payedAmount == msg.value, "Incorrect ETH amount for the claimed Amount");
    claims[forAddress] += claimedAmount;
    totalClaimed += claimedAmount;
    require(claims[forAddress] <= whitelist[forAddress], "Claiming attempt exceeds allocation amount!");
    require(totalClaimed <= totalClaimable, "Claiming attempt exceeds totalClaimable amount!");
    return true;
  }

  // Limit executions to launchpad ended state only
  modifier onlyEnded() {
    require(endTime > 0, "Launchpad has not been started yet!");
    require(endTime < block.timestamp, "Launchpad has not ended yet!");
    _;
  }

  // Releases ones claim for the launched token.
  // Can be executed by anyone, but makes sure the claimed token is released to claimer and not to the sender.
  function _releaseAmount(address forAddress, uint256 releaseAmount) private returns (bool) {
    uint256 claimedAmount = claims[forAddress];
    require(claimedAmount > 0, "Nothing to release!");
    require(claimedAmount >= releaseAmount, "Not enought claimedAmount!");
    ERC20(launchedToken).safeTransfer(forAddress, releaseAmount);
    claims[forAddress] -= releaseAmount;
    return true;
  }

  // Releases claim for a single address
  function releaseAmount(address forAddress, uint256 releaseAmount)
    external
    onlyEnded
    onlyOwner
    nonReentrant
    returns (bool)
  {
    require(_releaseAmount(forAddress, releaseAmount));
    return true;
  }

  // Releases claim for multiple addresses
  function multiReleaseAmount(address[] memory forAddresses, uint256[] memory amounts)
    external
    onlyEnded
    onlyOwner
    nonReentrant
    returns (bool)
  {
    for (uint256 i = 0; i < forAddresses.length; i++) {
      require(_releaseAmount(forAddresses[i], amounts[i]));
    }
    return true;
  }

  // Releases ones claim for the launched token.
  // Can be executed by anyone, but makes sure the claimed token is released to claimer and not to the sender.
  function _release(address forAddress) private returns (bool) {
    uint256 claimedAmount = claims[forAddress];
    require(claimedAmount > 0, "Nothing to release!");
    ERC20(launchedToken).safeTransfer(forAddress, claimedAmount);
    claims[forAddress] = 0;
    return true;
  }

  // Releases claim for a single address
  function release(address forAddress) external onlyEnded onlyOwner nonReentrant returns (bool) {
    require(_release(forAddress));
    return true;
  }

  // Releases claim for multiple addresses
  function multiRelease(address[] memory forAddresses) external onlyEnded onlyOwner nonReentrant returns (bool) {
    for (uint256 i = 0; i < forAddresses.length; i++) {
      require(_release(forAddresses[i]));
    }
    return true;
  }

  // Releases ETH payment to the owner.
  function releaseEthPayments() external onlyEnded onlyOwner nonReentrant returns (bool) {
    uint256 amountETH = address(this).balance;
    payable(owner()).transfer(amountETH);
    return true;
  }

  // Releases unclaimed launched tokens back to the owner.
  function releaseUnclaimed() external onlyEnded onlyOwner nonReentrant returns (bool) {
    uint256 unclaimed = totalClaimable - totalClaimed;
    ERC20(launchedToken).safeTransfer(owner(), unclaimed);
    totalClaimable = 0;
    return true;
  }
}

