// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface ILuckyStrikeMaster {
  event LuckyStrikePayout(address indexed player, uint256 wonAmount);
  event DeleteTokenFromWhitelist(address indexed token);
  event TokenAddedToWhitelist(address indexed token);
  event SyncTokens();
  event GameRemoved(address indexed game);
  event GameAdded(address indexed game);
  event DeleteAllWhitelistedTokens();
  event LuckyStrike(address indexed player, uint256 wonAmount, bool won);
  event WithdrawByGovernance(address indexed token, uint256 amount);

  function withdrawTokenByGovernance(address _token, uint256 _amount) external;

  function hasLuckyStrike(
    uint256 _randomness,
    uint256 _wagerUSD
  ) external view returns (bool hasWon_);

  function valueOfLuckyStrikeJackpot() external view returns (uint256 valueTotal_);

  function processLuckyStrike(address _player) external returns (uint256 wonAmount_);
}

