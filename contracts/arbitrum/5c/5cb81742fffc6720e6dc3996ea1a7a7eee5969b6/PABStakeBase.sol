// SPDX-License-Identifier: MIT LICENSE
pragma solidity ^0.8.0;

import "./IPABStake.sol";
import "./IPeekABoo.sol";
import "./IBOO.sol";
import "./IStakeManager.sol";

contract PABStakeBase {
    IPeekABoo public peekaboo;
    IBOO public boo;
    IStakeManager public sm;

    mapping(uint256 => IPABStake.PeekABooNormalStaked) public pabstake;

    uint256[6] public DAILY_BOO_RATE;
    uint256 public EMISSION_RATE;
    uint256 public unaccountedRewards;
    uint256 public MINIMUM_TO_EXIT;

    uint256 public totalTaxedBoo;
    uint256 public totalBooEarned;
    uint256 public totalPeekABooStaked;
    uint256 public lastClaimTimestamp;

    event TokenStaked(address owner, uint256 tokenId, uint256 value);
    event PeekABooClaimed(uint256 tokenId, uint256 earned, bool unstaked);
    event Debug1(uint256 earnedAmount);
}

