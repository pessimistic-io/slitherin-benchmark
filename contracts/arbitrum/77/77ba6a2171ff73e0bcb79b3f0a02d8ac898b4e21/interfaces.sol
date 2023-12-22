// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

interface IYVault {
  function withdraw(uint shares) external;
  function deposit(uint amount) external;
}

interface IAPool {
  function exchange(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
  function exchange_underlying(int128 i, int128 j, uint256 dx, uint256 min_dy) external;
  function remove_liquidity_one_coin(uint256 _token_amount, int128 i, uint256 _min_amount, bool _use_underlying) external;
  function add_liquidity(uint256[3] memory _amounts, uint256 _min_mint_amount, bool _use_underlying) external;
}

interface IVGHST {
  function enter(uint256 _amount) external;
  function leave(uint256 _share) external;
}

interface IUniswapV2Pair {
  event Approval(address indexed owner, address indexed spender, uint value);
  event Transfer(address indexed from, address indexed to, uint value);
  function name() external pure returns (string memory);
  function symbol() external pure returns (string memory);
  function decimals() external pure returns (uint8);
  function totalSupply() external view returns (uint);
  function balanceOf(address owner) external view returns (uint);
  function allowance(address owner, address spender) external view returns (uint);
  function approve(address spender, uint value) external returns (bool);
  function transfer(address to, uint value) external returns (bool);
  function transferFrom(address from, address to, uint value) external returns (bool);
  function DOMAIN_SEPARATOR() external view returns (bytes32);
  function PERMIT_TYPEHASH() external pure returns (bytes32);
  function nonces(address owner) external view returns (uint);
  function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;
  event Mint(address indexed sender, uint amount0, uint amount1);
  event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
  event Swap(
      address indexed sender,
      uint amount0In,
      uint amount1In,
      uint amount0Out,
      uint amount1Out,
      address indexed to
  );
  event Sync(uint112 reserve0, uint112 reserve1);
  function MINIMUM_LIQUIDITY() external pure returns (uint);
  function factory() external view returns (address);
  function token0() external view returns (address);
  function token1() external view returns (address);
  function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
  function price0CumulativeLast() external view returns (uint);
  function price1CumulativeLast() external view returns (uint);
  function kLast() external view returns (uint);
  function mint(address to) external returns (uint liquidity);
  function burn(address to) external returns (uint amount0, uint amount1);
  function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
  function skim(address to) external;
  function sync() external;
}

interface QiDaoVault {
  function _minimumCollateralPercentage() external view returns (uint256);

  function approve(address to, uint256 tokenId) external;

  function balanceOf(address owner) external view returns (uint256);

  function baseURI() external view returns (string memory);

  function borrowToken(uint256 vaultID, uint256 amount) external;

  function burn(uint256 amountToken) external;

  function changeEthPriceSource(address ethPriceSourceAddress) external;

  function checkCollateralPercentage(uint256 vaultID)
      external
      view
      returns (uint256);

  function checkCost(uint256 vaultID) external view returns (uint256);

  function checkExtract(uint256 vaultID) external view returns (uint256);

  function checkLiquidation(uint256 vaultID) external view returns (bool);

  function closingFee() external view returns (uint256);

  function collateral() external view returns (address);

  function createVault() external returns (uint256);

  function debtRatio() external view returns (uint256);

  function depositCollateral(uint256 vaultID, uint256 amount) external;

  function destroyVault(uint256 vaultID) external;

  function ethPriceSource() external view returns (address);

  function exists(uint256 vaultID) external view returns (bool);

  function gainRatio() external view returns (uint256);

  function getApproved(uint256 tokenId) external view returns (address);

  function getClosingFee() external view returns (uint256);

  function getDebtCeiling() external view returns (uint256);

  function getEthPriceSource() external view returns (uint256);

  function getPaid() external;

  function getTokenPriceSource() external view returns (uint256);

  function isApprovedForAll(address owner, address operator)
      external
      view
      returns (bool);

  function isOwner() external view returns (bool);

  function liquidateVault(uint256 vaultID) external;

  function mai() external view returns (address);

  function maticDebt(address) external view returns (uint256);

  function name() external view returns (string memory);

  function owner() external view returns (address);

  function ownerOf(uint256 tokenId) external view returns (address);

  function payBackToken(uint256 vaultID, uint256 amount) external;

  function priceSourceDecimals() external view returns (uint256);

  function renounceOwnership() external;

  function safeTransferFrom(
      address from,
      address to,
      uint256 tokenId
  ) external;

  function safeTransferFrom(
      address from,
      address to,
      uint256 tokenId,
      bytes memory _data
  ) external;

  function setApprovalForAll(address to, bool approved) external;

  function setDebtRatio(uint256 _debtRatio) external;

  function setGainRatio(uint256 _gainRatio) external;

  function setMinCollateralRatio(uint256 minimumCollateralPercentage)
      external;

  function setStabilityPool(address _pool) external;

  function setTokenURI(string memory _uri) external;

  function setTreasury(uint256 _treasury) external;

  function stabilityPool() external view returns (address);

  function supportsInterface(bytes4 interfaceId) external view returns (bool);

  function symbol() external view returns (string memory);

  function tokenByIndex(uint256 index) external view returns (uint256);

  function tokenOfOwnerByIndex(address owner, uint256 index)
      external
      view
      returns (uint256);

  function tokenPeg() external view returns (uint256);

  function tokenURI(uint256 tokenId) external view returns (string memory);

  function totalBorrowed() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function transferFrom(
      address from,
      address to,
      uint256 tokenId
  ) external;

  function transferOwnership(address newOwner) external;

  function treasury() external view returns (uint256);

  function uri() external view returns (string memory);

  function vaultCollateral(uint256) external view returns (uint256);

  function vaultCount() external view returns (uint256);

  function vaultDebt(uint256) external view returns (uint256);

  function withdrawCollateral(uint256 vaultID, uint256 amount) external;
}

interface ISmartVault {

  function setStrategy(address _strategy) external;

  function changeActivityStatus(bool _active) external;

  function changeProtectionMode(bool _active) external;

  function changePpfsDecreaseAllowed(bool _value) external;

  function setLockPeriod(uint256 _value) external;

  function setLockPenalty(uint256 _value) external;

  function setToInvest(uint256 _value) external;

  function doHardWork() external;

  function rebalance() external;

  function disableLock() external;

  function notifyTargetRewardAmount(address _rewardToken, uint256 reward) external;

  function notifyRewardWithoutPeriodChange(address _rewardToken, uint256 reward) external;

  function deposit(uint256 amount) external;

  function depositAndInvest(uint256 amount) external;

  function depositFor(uint256 amount, address holder) external;

  function withdraw(uint256 numberOfShares) external;

  function exit() external;

  function getAllRewards() external;

  function getAllRewardsFor(address rewardsReceiver) external;

  function getReward(address rt) external;

  function underlying() external view returns (address);

  function strategy() external view returns (address);

  function getRewardTokenIndex(address rt) external view returns (uint256);

  function getPricePerFullShare() external view returns (uint256);

  function underlyingUnit() external view returns (uint256);

  function duration() external view returns (uint256);

  function underlyingBalanceInVault() external view returns (uint256);

  function underlyingBalanceWithInvestment() external view returns (uint256);

  function underlyingBalanceWithInvestmentForHolder(address holder) external view returns (uint256);

  function availableToInvestOut() external view returns (uint256);

  function earned(address rt, address account) external view returns (uint256);

  function earnedWithBoost(address rt, address account) external view returns (uint256);

  function rewardPerToken(address rt) external view returns (uint256);

  function lastTimeRewardApplicable(address rt) external view returns (uint256);

  function rewardTokensLength() external view returns (uint256);

  function active() external view returns (bool);

  function rewardTokens() external view returns (address[] memory);

  function periodFinishForToken(address _rt) external view returns (uint256);

  function rewardRateForToken(address _rt) external view returns (uint256);

  function lastUpdateTimeForToken(address _rt) external view returns (uint256);

  function rewardPerTokenStoredForToken(address _rt) external view returns (uint256);

  function userRewardPerTokenPaidForToken(address _rt, address account) external view returns (uint256);

  function rewardsForToken(address _rt, address account) external view returns (uint256);

  function userLastWithdrawTs(address _user) external view returns (uint256);

  function userLastDepositTs(address _user) external view returns (uint256);

  function userBoostTs(address _user) external view returns (uint256);

  function userLockTs(address _user) external view returns (uint256);

  function addRewardToken(address rt) external;

  function removeRewardToken(address rt) external;

  function stop() external;

  function ppfsDecreaseAllowed() external view returns (bool);

  function lockPeriod() external view returns (uint256);

  function lockPenalty() external view returns (uint256);

  function toInvest() external view returns (uint256);

  function depositFeeNumerator() external view returns (uint256);

  function lockAllowed() external view returns (bool);

  function protectionMode() external view returns (bool);
}

uint160 constant MIN_SQRT_RATIO_PLUS_ONE = 4295128740;
uint160 constant MAX_SQRT_RATIO_MINUS_ONE = 1461446703485210103287273052203988822378723970341;

interface IUniswapV3Pool {
  function swap(
    address recipient,
    bool zeroForOne,
    int256 amountSpecified,
    uint160 sqrtPriceLimitX96,
    bytes calldata data
  ) external returns (int256 amount0, int256 amount1);
}

