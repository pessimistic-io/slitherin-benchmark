// SPDX-License-Identifier: agpl-3.0
pragma solidity 0.8.19;

import { IERC20, SafeERC20 } from "./SafeERC20.sol";
import { MerkleDistributor } from "./MerkleDistributor.sol";
import { GovernanceInitiationData } from "./GovernanceInitiationData.sol";
import "./GovernanceErrors.sol";

error EndTimeInPast();
error ClaimWindowFinished();
error NoWithdrawDuringClaim();

/**
 * @title MerkleDistributorWithDeadline
 * @author Cora Dev Team
 * @notice This contract is used to airdrop tokens to users based on a merkle root.
 * @dev Modified version of Uniswap's merkle distributor with deadline https://github.com/Uniswap/merkle-distributor/blob/master/contracts/MerkleDistributorWithDeadline.sol
 * It accepts a GovernanceInitiationData as parameter to get the token address.
 */
contract MerkleDistributorWithDeadline is MerkleDistributor {
  using SafeERC20 for IERC20;

  uint256 public immutable endTime;
  uint256 private immutable END_TIME_AFTER_DEPLOYMENT = 14 days;

  constructor(GovernanceInitiationData _initiationData, bytes32 _merkleRoot)
    MerkleDistributor(_initiationData, _merkleRoot)
  {
    endTime = block.timestamp + END_TIME_AFTER_DEPLOYMENT;
  }

  function claim(uint256 index, address account, uint256 amount, bytes32[] calldata merkleProof)
    public
    override
  {
    if (block.timestamp > endTime) revert ClaimWindowFinished();
    super.claim(index, account, amount, merkleProof);
  }

  function withdraw() external onlyDao {
    if (block.timestamp < endTime) revert NoWithdrawDuringClaim();
    IERC20(token).safeTransfer(msg.sender, IERC20(token).balanceOf(address(this)));
  }

  modifier onlyDao() {
    if (msg.sender != initiationData.timelockAddress()) {
      revert OnlyDAO();
    }
    _;
  }
}

