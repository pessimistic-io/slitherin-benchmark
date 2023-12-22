import {IERC20Metadata as IERC20} from "./extensions_IERC20Metadata.sol";
import {IAggregator} from "./IAggregator.sol";
import {ICToken} from "./compound_ICToken.sol";
import {Addresses} from "./Addresses.sol";

/*
* @notice Security contract: Without this contract someone can arbitrarily execute deposits or withdraws for another account
* This is because Balancer takes an address to flash loan to as a parameter
* Prevents someone from flashloaning this contract with their own parameters
*/
contract PendingExecutor {
  IAggregator public immutable sequencerUptimeFeed = IAggregator(Addresses.sequencerFeed);
  uint256 private constant GRACE_PERIOD_TIME = 3600;
  // Check the sequencer status and return the latest price
  function validateSequencer() public view {
    // prettier-ignore
    (
      /*uint80 roundID*/,
      int256 answer,
      uint256 startedAt,
      /*uint256 updatedAt*/,
      /*uint80 answeredInRound*/
    ) = sequencerUptimeFeed.latestRoundData();

    // Answer == 0: Sequencer is up
    // Answer == 1: Sequencer is down
    bool isSequencerUp = answer == 0;
    uint256 timeSinceUp = block.timestamp - startedAt;
    require(isSequencerUp, 'Sequencer is down');
    require(timeSinceUp > GRACE_PERIOD_TIME, 'Grace period not over');
  }
  struct WithdrawParams {
    address account;
    ICToken redeemMarket;
    uint redeemAmount;
    ICToken[] repayMarkets;
    uint[] repayAmounts;
    uint24 maxSlippage;
  }
  mapping(address => WithdrawParams) private pendingWithdraws;
  mapping(address => bool) private hasPendingWithdraw;


  struct DepositParams {
    address account;
    IERC20 depositToken;
    uint256 depositAmount;
    uint leverageProportion;
    ICToken[] borrowMarkets;
    uint[] borrowProportions;
    ICToken destMarket;
    uint24 maxSlippage;
  }

  mapping(address => DepositParams) private pendingDeposits;
  mapping(address => bool) private hasPendingDeposit;

  function getPendingWithdraw(
    address account
  ) internal view returns (WithdrawParams memory) {
    require(hasPendingWithdraw[account], 'No Withdraw registered by account');
    return pendingWithdraws[account];
  }

  function getPendingDeposit(
    address account
  ) internal view returns (DepositParams memory) {
    require(hasPendingDeposit[account], 'No Withdraw registered by account');
    return pendingDeposits[account];
  }

  function setPendingWithdraw(
    address account,
    WithdrawParams memory data
  ) internal {
    pendingWithdraws[account] = data;
    hasPendingWithdraw[account] = true;
  }

  function setPendingDeposit(
    address account,
    DepositParams memory data
  ) internal {
    pendingDeposits[account] = data;
    hasPendingDeposit[account] = true;
  }

  function removePendingWithdraw(
    address account
  ) internal {
    delete pendingWithdraws[account];
    hasPendingWithdraw[account] = false;
  }

  function removePendingDeposit(
    address account
  ) internal {
    delete pendingDeposits[account];
    hasPendingDeposit[account] = false;
  }
}

