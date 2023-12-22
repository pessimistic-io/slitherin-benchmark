// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./AccessControl.sol";
import "./IERC20.sol";
import "./IFeeCollectorV2.sol";
import "./ILuckyStrikeMaster.sol";
import "./IVault.sol";

contract LuckyStrikeMaster is AccessControl, ILuckyStrikeMaster {
  uint256 public constant TOTAL_DRAW_ODDS = 1e7; // 10 million
  uint256 public chancePerUSDWager = 1; // 1 in 1e7 chance to win the jackpot per 1 USD wagered
  mapping(address => bool) public allowedGames;

  address[] public allWhitelistedTokensFeeCollector;

  IERC20 public wlp;
  IVault public vault;
  IFeeCollectorV2 public feeCollector;

  constructor() {
    _grantRole(DEFAULT_ADMIN_ROLE, _msgSender());
  }

  modifier onlyGovernance() {
    require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()), "VM: Not governance");
    _;
  }

  // modifier if caller is allowed game
  modifier onlyAllowedGames() {
    require(allowedGames[_msgSender()], "LuckyStrikeMaster: Only allowed games");
    _;
  }

  // function that sets feecollector address
  function setFeeCollector(IFeeCollectorV2 _feeCollector) external onlyGovernance {
    feeCollector = _feeCollector;
  }

  // function that sets chancePerUSDWager
  function setChancePerUSDWager(uint256 _chancePerUSDWager) external onlyGovernance {
    chancePerUSDWager = _chancePerUSDWager;
  }

  // function that sets wlp address
  function setWLP(IERC20 _wlp) external onlyGovernance {
    wlp = _wlp;
  }

  // function that sets vault address
  function setVault(IVault _vault) external onlyGovernance {
    vault = _vault;
  }

  /**
   * @notice function that returns how much usd value of tokens, sit in the vault that will be partly go towards the jackpot
   */
  function getWagerFeesValueTotalInVault() public view returns (uint256 totalValue_) {
    uint256 length_ = allWhitelistedTokensFeeCollector.length;
    uint256 amount_;
    for (uint256 i = 0; i < length_; ++i) {
      address token_ = allWhitelistedTokensFeeCollector[i];
      amount_ = vault.wagerFeeReserves(token_);
      totalValue_ += vault.tokenToUsdMin(token_, amount_);
    }
    return totalValue_;
  }

  function valueOfLuckyStrikeJackpot() external view returns (uint256 valueTotalJackpot_) {
    // fetch amount of WLP in the feeCollector
    uint256 wlpInFeeCollector_ = feeCollector.returnAmountWlpForLuckyStrike();
    // fetch amount of WLP in this contract
    uint256 balance_ = wlp.balanceOf(address(this));
    // calculate the value of the wlp in the feeCollector and in this contract
    uint256 valueOfWlpContract_ = ((balance_ + wlpInFeeCollector_) * vault.getWlpValue()) / 1e18;

    // calculate the total value of the tokens in the vault that will be used for the jackpot when it is farmed/collected (in case player wins the jackpot)
    uint256 valueOnCollect_ = getWagerFeesValueTotalInVault();

    // calculate how much of the 'to be collected' wagerfees will go toward the progressive jackpot
    uint256 valueForJackpot_ = (valueOnCollect_ * feeCollector.returnLuckyStrikeRatio()) / 1e4;

    // calculate the total value of the jackpot in usd (scaled 1e30)
    valueTotalJackpot_ = valueForJackpot_ + valueOfWlpContract_;
  }

  function syncTokens() external onlyGovernance {
    _syncWhitelistedTokens();
  }

  /**
   * @notice function that syncs the whitelisted tokens with the vault
   */
  function _syncWhitelistedTokens() internal {
    delete allWhitelistedTokensFeeCollector;
    uint256 count_ = feeCollector.allWhitelistedTokensLength();
    for (uint256 i = 0; i < count_; ++i) {
      address token_ = feeCollector.allWhitelistedTokensFeeCollectorAtIndex(i);
      allWhitelistedTokensFeeCollector.push(token_);
    }
    emit SyncTokens();
  }

  function hasLuckyStrike(
    uint256 _randomness,
    uint256 _wagerUSD
  ) external view returns (bool hasWon_) {
    // scale the random number to the TOTAL_DRAW_ODDS (so a value below 1e7 or whatever te max odds value is)
    uint256 scaledRandom_;
    unchecked {
      scaledRandom_ = (_randomness % TOTAL_DRAW_ODDS) + 1;
    }

    /**
     * Lottery flow:
     * 1. Calculate the odds for the wager with chancePerUSDWager
     * 2. Take the randomness of the VRF and scale it to the TOTAL_DRAW_ODDS (so a value below 1e7)
     * 3. The result is a random value between 0 and 1e7 (should be evenly distributed, to be checked?)
     * 4. If the scaled random number is below the odds for the category, the player has won the lottery
     *
     * The higher the odds value, the larger the chance of the oddsForCategory_ to be lower than scaledRandom_. scaledRandom_ is a random number between 0 and 1e7, so the higher the oddsForCategory_ the higher the chance of winning. Since higher odds means higher number so larger change the scaledRandom_ is lower than that number.
     *
     * This gives us the desired effect of having a higher chance of winning the lottery when the wager is higher.
     */

    unchecked {
      if (((chancePerUSDWager * _wagerUSD) / 1e30) >= scaledRandom_) {
        hasWon_ = true;
      }
    }
  }

  function withdrawTokenByGovernance(address _token, uint256 _amount) external onlyGovernance {
    IERC20(_token).transfer(_msgSender(), _amount);
    emit WithdrawByGovernance(_token, _amount);
  }

  function processLuckyStrike(
    address _player
  ) external onlyAllowedGames returns (uint256 wlpBalance_) {
    // collect the pending fees in the feecollector for the progressive jackpot
    feeCollector.collectFeesOnLotteryWin();
    // check how much wlp tokens are now in this contract (so this is the jackpot)
    wlpBalance_ = wlp.balanceOf(address(this));
    // transfer the wlp to the winning player
    wlp.transfer(_player, wlpBalance_);
    emit LuckyStrikePayout(_player, wlpBalance_);
    return wlpBalance_;
  }

  // function that adds a game to the allowed games mapping
  function addGame(address _game) external onlyGovernance {
    allowedGames[_game] = true;
    emit GameAdded(_game);
  }

  // function that removes a game from the allowed games mapping
  function removeGame(address _game) external onlyGovernance {
    allowedGames[_game] = false;
    emit GameRemoved(_game);
  }
}

