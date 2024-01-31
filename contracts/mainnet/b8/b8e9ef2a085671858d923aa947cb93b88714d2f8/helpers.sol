pragma solidity ^0.7.0;
pragma experimental ABIEncoderV2;


import { DSMath } from "./math.sol";
import { Basic } from "./basic.sol";
import { TokenInterface } from "./interfaces.sol";
import { IStakingRewards, IStakingRewardsFactory, IGUniPoolResolver } from "./interface.sol";

abstract contract Helpers is DSMath, Basic {
  TokenInterface constant internal rewardToken = TokenInterface(0x6f40d4A6237C257fff2dB00FA0510DeEECd303eb);
}
