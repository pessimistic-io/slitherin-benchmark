// SPDX-License-Identifier: GPL-3.0

pragma solidity ^0.8.0;

// Contracts
import "./Ownable.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IERC721 } from "./IERC721.sol";

contract TokenSale is Ownable {
  using SafeERC20 for IERC20;

  // Total amount of ETH collected
  uint256 public totalEthCollected;

  // Claim start time
  uint256 public claimStartTime;

  // Claim end time
  uint256 public claimEndTime;

  // Mithical nft contract
  address mithicalNFTContract;

  // Mithical pfp contract
  address mithicalPfpContract;

  // Dsquared token contract addresses
  address[] public dsquaredTokens;

  // Amount of tokens released
  uint256[] public dsquaredTokenAmounts;

  // Mapping from user addresses to their deposit
  mapping(address => uint256) public deposits;

  // Mapping from user addresses to their claimed tokens
  mapping(address => uint256) public LastClaimedTime;

  // Events to track eth deposits
  event Deposit(address indexed depositer, uint256 amount);

  // Event to track token claims
  event TokensClaimed(address indexed user, uint256 amount);

  // Constructor function to initialize the contract
  constructor(address _mithicalNFTContract, address _mithicalPfpContract) {
    require(
      _mithicalNFTContract != address(0),
      "Address can't be zero address"
    );
    require(
      _mithicalPfpContract != address(0),
      "Address can't be zero address"
    );
    mithicalNFTContract = _mithicalNFTContract;
    _mithicalPfpContract = _mithicalPfpContract;
  }

  // Recieve function
  receive() external payable {}

  // deposit function
  function deposit() public payable {
    require(
      IERC721(mithicalNFTContract).balanceOf(msg.sender) >= 1 ||
        IERC721(mithicalPfpContract).balanceOf(msg.sender) >= 1,
      "You do not have a mithical NFT"
    );
    // Check that the user has sent some ETH
    require(msg.value > 0, "Must send some ETH");

    // Add the ETH to the user's deposit
    deposits[msg.sender] += msg.value;

    totalEthCollected += msg.value;

    // Emit the deposit event
    emit Deposit(msg.sender, msg.value);
  }

  // Funnction to set token addresses
  function setDsquaredTokens(address[] memory _dsquaredTokens)
    public
    onlyOwner
  {
    dsquaredTokens = _dsquaredTokens;
  }

  // Function to withdraw the eth
  function withdrawOwner(address[] calldata tokens, bool transferNative)
    external
    onlyOwner
  {
    if (transferNative) payable(msg.sender).transfer(address(this).balance);

    IERC20 token;

    for (uint256 i; i < tokens.length; ) {
      token = IERC20(tokens[i]);
      token.safeTransfer(msg.sender, token.balanceOf(address(this)));

      unchecked {
        ++i;
      }
    }
  }

  // Function to initalize the claim
  function bootstrap(
    uint256[] memory _totalClaimableTokens,
    uint256 _claimEndTime
  ) external onlyOwner {
    claimStartTime = block.timestamp;
    claimEndTime = _claimEndTime;
    for (uint256 i = 0; i < _totalClaimableTokens.length; i++) {
      dsquaredTokenAmounts.push(_totalClaimableTokens[i]);
    }
  }

  // Function to claim tokens
  function claimTokens() public {
    require(claimStartTime > 0, "Claim not started");
    require(deposits[msg.sender] > 0, "You have not deposited any ETH");
    uint256 startTime;
    if (LastClaimedTime[msg.sender] == 0) {
      startTime = claimStartTime;
    } else {
      startTime = LastClaimedTime[msg.sender];
    }
    for (uint256 i = 0; i < dsquaredTokens.length; i++) {
      uint256 rewardRate = dsquaredTokenAmounts[i] /
        (claimEndTime - claimStartTime);

      if (block.timestamp > claimEndTime) {
        uint256 claimableAmount = (rewardRate *
          (claimEndTime - LastClaimedTime[msg.sender]) *
          deposits[msg.sender]) / totalEthCollected;
        LastClaimedTime[msg.sender] = claimEndTime;
        IERC20(dsquaredTokens[i]).safeTransfer(msg.sender, claimableAmount);
      } else {
        uint256 claimableAmount = rewardRate *
          (block.timestamp - LastClaimedTime[msg.sender]);
        LastClaimedTime[msg.sender] = block.timestamp;
        IERC20(dsquaredTokens[i]).safeTransfer(msg.sender, claimableAmount);
      }
    }
  }
}

