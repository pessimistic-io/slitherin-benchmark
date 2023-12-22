/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./Math.sol";
import "./Ownable2Step.sol";
import "./ReentrancyGuard.sol";
import "./ICSS.sol";
import "./IChef.sol";

/**
 * @title TokenVesting
 * @author Consensus party
 * @notice This contract serves as a locker for Consensus Token (CSS) {ICSS}.
 *
 * Constant settings:
 * - TEAM_PERCENT: 7% of the unlocked supply allocated for team members and advisors.
 * - MARKETING_PERCENT: 2% of the unlocked supply allocated for marketing and promotion.
 * - COMMUNITY_PERCENT: 91% of the unlocked supply allocated for liquidity and community.
 *
 * This contract has ability to mint the unlocked token supply, with specific percentages reserved for
 * various purposes. The tokens will be locked and gradually released over time to their respective
 * beneficiaries according to the terms specified in the vesting schedule.
 */
contract TokenVesting is Ownable2Step, ReentrancyGuard {
  struct Emission {
    uint256 startTime;
    uint256 estimatedEndTime;
    uint256 unlockTokensPerSec;
    uint256 lastUnlockedTime;
    uint256 lockingAmount;
  }

  event EmitToken(uint256 duration, uint256 liqAmount, uint256 locking);
  event SetEmission(uint256 startTime, uint256 endTime, uint256 unlockTokensPerSec, uint256 locking);
  event SetTeamAddress(address teamAddress);
  event SetMarketingAddress(address marketingAddress);

  bool public constant IS_CONSENSUS_VESTING = true;

  uint256 public constant MAX_PERCENT = 100_00;
  uint256 public constant TEAM_PERCENT = 7_00;
  uint256 public constant MARKETING_PERCENT = 2_00;
  uint256 public constant COMMUNITY_PERCENT = 91_00;

  ICSS public immutable cssToken;
  address public teamWallet;
  address public marketingWallet;

  Emission private _emission;

  /**
   * @param token Address of the CSS token
   * @param teamAddr Address of team
   * @param marketingAddr Marketing address
   */
  constructor(address admin, ICSS token, address teamAddr, address marketingAddr) {
    _transferOwnership(admin);
    cssToken = token;
    teamWallet = teamAddr;
    marketingWallet = marketingAddr;
    assert(MAX_PERCENT == TEAM_PERCENT + MARKETING_PERCENT + COMMUNITY_PERCENT);
    emit SetTeamAddress(teamAddr);
    emit SetMarketingAddress(marketingAddr);
  }

  fallback() external payable {}
  receive() external payable {}

  /**
   * @dev Rescues funds in case some tokens are unexpectedly transferred to CSS.
   *
   * @param tokens the token addresses.
   */
  function rescueTokens(IERC20[] calldata tokens, address payable to) external onlyOwner {
    cssToken.rescueTokens(tokens);
    uint256 ethBalance = address(this).balance;
    for (uint256 i = 0; i < tokens.length; i++) {
      uint256 balance = tokens[i].balanceOf(address(this));
      require(tokens[i].transfer(to, balance), "CSSToken: transfer failed");
    }

    if (ethBalance > 0) {
      (bool success,) = to.call{value: ethBalance}(new bytes(0));
      require(success, "TokenVesting: cannot withdraw");
    }
  }

  /**
   * @param chefs Address list of the chefs.
   */
  function addChefs(IChef[] calldata chefs) external onlyOwner {
    for (uint256 i = 0; i < chefs.length; i++) {
      require(chefs[i].IS_CONSENSUS_CHEF(), "TokenVesting: incorrect chef");
      cssToken.approve(address(chefs[i]), type(uint256).max);
    }
  }

  /**
   * @param chefs Address list of the chefs.
   */
  function removeChefs(IChef[] calldata chefs) external onlyOwner {
    for (uint256 i = 0; i < chefs.length; i++) {
      cssToken.approve(address(chefs[i]), 0);
    }
  }

  /**
   * @dev Set team address.
   *
   * Emits a {SetTeamAddress} event .
   *
   * @param teamAddr Address of team
   */
  function setTeamAddress(address teamAddr) external onlyOwner {
    teamWallet = teamAddr;
    emit SetTeamAddress(teamAddr);
  }

  /**
   * @dev Set team address.
   *
   * Emits a {SetMarketingAddress} event .
   *
   * @param marketingAddr Marketing address
   */
  function setMarketingAddress(address marketingAddr) external onlyOwner {
    marketingWallet = marketingAddr;
    emit SetMarketingAddress(marketingAddr);
  }

  /**
   * @dev Getter for emission.
   */
  function getEmission() public view returns (Emission memory) {
    return _emission;
  }

  /**
   * @dev Unlocks the token.
   *
   * Emits a {EmitToken} event.
   */
  function emitToken() public nonReentrant {
    if (block.timestamp <= _emission.lastUnlockedTime || _emission.lockingAmount == 0) {
      return;
    }

    uint256 duration = Math.min(block.timestamp, _emission.estimatedEndTime) - _emission.lastUnlockedTime;
    uint256 amount = duration * _emission.unlockTokensPerSec;
    uint256 liq;

    if (amount > 0) {
      cssToken.safeMint(teamWallet, amount * TEAM_PERCENT / MAX_PERCENT);
      cssToken.safeMint(marketingWallet, amount * MARKETING_PERCENT / MAX_PERCENT);
      liq = cssToken.safeMint(address(this), amount * COMMUNITY_PERCENT / MAX_PERCENT);
    }

    uint256 cap = cssToken.cap();
    uint256 totalSupply = cssToken.totalSupply();
    uint256 locking = cap > totalSupply ? cap - totalSupply : 0;
    _sync(locking);
    emit EmitToken(duration, liq, _emission.lockingAmount);
  }

  /**
   * @dev Sets emission for the current token `cssToken`.
   *
   * Emits a {SetEmission} event.
   *
   * Requirements:
   *
   * - the duration is at least 5 min.
   * - the start time is at least from now.
   * - this contract must have the `MINTER_ROLE` of token.
   *
   * @param startTime the timestamp to start emit token
   * @param duration the duration to emit token
   */
  function setEmission(uint256 startTime, uint256 duration) public onlyOwner {
    require(startTime >= block.timestamp && duration >= 5 minutes, "MasterChef: invalid timestamp");
    require(address(cssToken.tokenVesting()) == address(this), "MasterChef: must set token vesting for CSS");

    uint256 locking = cssToken.cap() - cssToken.totalSupply();
    uint256 unlockTokensPerSec = locking / duration;

    _emission.startTime = startTime;
    _emission.unlockTokensPerSec = unlockTokensPerSec;
    if (unlockTokensPerSec * duration < locking) duration++;
    _emission.estimatedEndTime = startTime + duration;
    _emission.lastUnlockedTime = startTime;
    _emission.lockingAmount = locking;
    emit SetEmission(startTime, _emission.estimatedEndTime, _emission.unlockTokensPerSec, locking);
  }

  /**
   * @dev See {TokenVesting-setEmission}.
   */
  function setEmissionNow(uint256 duration) external {
    setEmission(block.timestamp, duration);
  }

  /**
   * @dev Hook that sync the emission.
   *
   * @param locking the token amount that being locked
   */
  function _sync(uint256 locking) private {
    _emission.lockingAmount = locking;

    if (block.timestamp < _emission.startTime) {
      return;
    } else if (locking == 0) {
      delete _emission.unlockTokensPerSec;
    }

    _emission.lastUnlockedTime = block.timestamp;
  }
}

/*
@@@@@@@@@@@@@@@@@@@@@@@@@@@@&#G5J?7!~~~::::::::::::::::~^^^:::::^:G@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@#GY7~:.                                    5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@#P?^.                                          5@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@#Y!.                    ~????????????????????????7B@@@@@@@@@@@@@
@@@@@@@@@@@@@&P!.                       5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@&Y:                          5@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@&Y:                      .::^~^7YYYYYYYYYYYYYYYYYYYYYYYYY#@@@@@@@@@@@@@
@@@@@@@@P:                  .^7YPB#&@@@&.                         5@@@@@@@@@@@@@
@@@@@@&7                 :?P#@@@@@@@@@@&.                         5@@@@@@@@@@@@@
@@@@@B:               .7G&@@@@@@@@@&#BBP.                         5@@@@@@@@@@@@@
@@@@G.              .J#@@@@@@@&GJ!^:.                             5@@@@@@@@@@@@@
@@@G.              7#@@@@@@#5~.                                   5@@@@@@@@@@@@@
@@#.             :P@@@@@@#?.                                      5@@@@@@@@@@@@@
@@~             :#@@@@@@J.       .~JPGBBBBBBBBBBBBBBBBBBBBBBBBBBBB&@@@@@@@@@@@@@
@5             .#@@@@@&~       !P&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
@~             P@@@@@&^      ^G@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
B             ~@@@@@@7      ^&@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
5             5@@@@@#      .#@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@
Y   ..     .. P#####5      7@@@@@@@@@@@@@@@@@@@@@@@@&##########################&
@############B:    .       !@@@@@@@@@@@@@@@@@@@@@@@@5            ..            7
@@@@@@@@@@@@@@:            .#@@@@@@@@@@@@@@@@@@@@@@@~                          7
@@@@@@@@@@@@@@J             ~&@@@@@@@@@@@@@@@@@@@@@?       ......              5
@@@@@@@@@@@@@@#.             ^G@@@@@@@@@@@@@@@@@@#!      .G#####G.            .#
@@@@@@@@@@@@@@@P               !P&@@@@@@@@@@@@@G7.      :G@@@@@@~             ?@
@@@@@@@@@@@@@@@@5                :!JPG####BPY7:        7#@@@@@&!             :#@
@@@@@@@@@@@@@@@@@P:                   ....           !B@@@@@@#~              P@@
@@@@@@@@@@@@@@@@@@#!                             .^J#@@@@@@@Y.              J@@@
@@@@@@@@@@@@@@@@@@@@G~                      .^!JP#@@@@@@@&5^               Y@@@@
@@@@@@@@@@@@@@@@@@@@@@G7.               ?BB#&@@@@@@@@@@#J:                5@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@&P7:            5@@@@@@@@@@&GJ~.                ^B@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@B5?~:.      5@@@@&#G5?~.                  .Y@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@#BGP5YJ~~~^^..                      ?#@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                         .?B@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                       ^Y&@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                    ^JB@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.                :!5#@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&.         ..^!JP#@@@@@@@@@@@@@@@@@@@@@@@
@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@@&~::^~!7?5PB&@@@@@@@@@@@@@@@@@@@@@@@@@@@@*/

