// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./SafeMath.sol";
import "./Address.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./PausableUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./IVovoVault.sol";
import "./Gauge.sol";
import "./Curve.sol";
import "./Uni.sol";
import "./IRouter.sol";
import "./IVault.sol";

/**
 * @title PrincipalProtectedVault
 * @dev A vault that receives vaultToken from users, and then deposits the vaultToken into yield farming pools.
 * Periodically, the vault collects the yield rewards and uses the rewards to open a leverage trade on a perpetual swap exchange.
 */
contract PrincipalProtectedVault is Initializable, ERC20Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  // usdc token address
  address public constant usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
  // weth token address
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  // crv token address
  address public constant crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
  // sushiswap address
  address public constant sushiswap = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);

  uint256 public constant FEE_DENOMINATOR = 10000;
  uint256 public constant DENOMINATOR = 10000;

  address public vaultToken; // deposited token of the vault
  address public underlying; // underlying token of the leverage position
  address public lpToken;
  address public gauge;
  uint256 public withdrawalFee;
  uint256 public performanceFee;
  uint256 public slip;
  uint256 public maxCollateralMultiplier;
  uint256 public cap;
  uint256 public vaultTokenBase;
  uint256 public underlyingBase;
  uint256 public lastPokeTime;
  uint256 public pokeInterval;
  uint256 public currentTokenReward;
  uint256 public currentPokeInterval;
  bool public isKeeperOnly;
  bool public isDepositEnabled;
  uint256 public leverage;
  bool public isLong;
  address public governor;
  address public admin;
  address public guardian;
  address public rewards;
  address public dex;
  address public gmxPositionManager;
  address public gmxRouter;
  address public gmxVault;
  /// mapping(keeperAddress => true/false)
  mapping(address => bool) public keepers;
  /// mapping(fromVault => mapping(toVault => true/false))
  mapping(address => mapping(address => bool)) public withdrawMapping;

  event Deposit(address account, uint256 amount, uint256 shares);
  event LiquidityAdded(uint256 tokenAmount, uint256 lpMinted);
  event GaugeDeposited(uint256 lpDeposited);
  event Poked(uint256 minPricePerShare, uint256 maxPricePerShare);
  event OpenPosition(address underlying, uint256 underlyingPrice, uint256 vaultTokenPrice, uint256 sizeDelta, bool isLong, uint256 collateralAmountVaultToken);
  event ClosePosition(address underlying, uint256 underlyingPrice, uint256 vaultTokenPrice,uint256 sizeDelta, bool isLong, uint256 collateralAmountVaultToken, uint256 fee);
  event Withdraw(address account, uint256 amount, uint256 shares, uint256 fee);
  event WithdrawToVault(address owner, uint256 shares, address vault, uint256 receivedShares);
  event GovernanceSet(address governor);
  event AdminSet(address admin);
  event GuardianSet(address guardian);
  event FeeSet(uint256 performanceFee, uint256 withdrawalFee);
  event LeverageSet(uint256 leverage);
  event isLongSet(bool isLong);
  event RewardsSet(address rewards);
  event GmxContractsSet(address gmxPositionManager, address gmxRouter, address gmxVault);
  event MaxCollateralMultiplierSet(uint256 maxCollateralMultiplier);
  event IsKeeperOnlySet(bool isKeeperOnly);
  event DepositEnabled(bool isDepositEnabled);
  event CapSet(uint256 cap);
  event PokeIntervalSet(uint256 pokeInterval);
  event KeeperAdded(address keeper);
  event KeeperRemoved(address keeper);
  event VaultRegistered(address fromVault, address toVault);
  event VaultRevoked(address fromVault, address toVault);

  function initialize(
    string memory _vaultName,
    string memory _vaultSymbol,
    uint8 _vaultDecimal,
    address _vaultToken,
    address _underlying,
    address _lpToken,
    address _gauge,
    address _rewards,
    uint256 _leverage,
    bool _isLong,
    uint256 _cap,
    uint256 _vaultTokenBase,
    uint256 _underlyingBase
  ) public initializer {
    __ERC20_init(_vaultName, _vaultSymbol);
    _setupDecimals(_vaultDecimal);
    __Pausable_init();
    vaultToken = _vaultToken;
    underlying = _underlying;
    lpToken = _lpToken;
    gauge = _gauge;
    rewards = _rewards;
    leverage = _leverage;
    isLong = _isLong;
    cap = _cap;
    vaultTokenBase = _vaultTokenBase;
    underlyingBase = _underlyingBase;
    lastPokeTime = block.timestamp;
    pokeInterval = 7 days;
    governor = msg.sender;
    admin = msg.sender;
    guardian = msg.sender;
    dex = sushiswap;
    gmxPositionManager = address(0x98a00666CfCb2BA5A405415C2BF6547C63bf5491);
    gmxRouter = address(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
    gmxVault = address(0x489ee077994B6658eAfA855C308275EAd8097C4A);
    keepers[msg.sender] = true;
    isKeeperOnly = true;
    isDepositEnabled = true;
    withdrawalFee = 30;
    performanceFee = 1000;
    slip = 30;
    maxCollateralMultiplier = leverage;
  }


  /**
   * @notice Get the value of this vault in vaultToken:
   * @param isMax the flag for optimistic or pessimistic calculation of the vault value
   * if isMax is true: the value of lp in vaultToken + the amount of vaultToken in this contract + the value of open leveraged position + estimated pending rewards
   * if isMax is false: the value of lp in vaultToken + the amount of vaultToken in this contract
   */
  function balance(bool isMax) public view returns (uint256) {
    uint256 lpPrice = ICurveFi(lpToken).get_virtual_price();
    uint256 lpAmount = Gauge(gauge).balanceOf(address(this));
    uint256 lpValue = lpPrice.mul(lpAmount).mul(vaultTokenBase).div(1e36);
    if (isMax) {
      return lpValue.add(getActivePositionValue()).add(getEstimatedPendingRewardValue()).add(IERC20(vaultToken).balanceOf(address(this)));
    }
    return lpValue.add(IERC20(vaultToken).balanceOf(address(this)));
  }

  /**
   * @notice Add liquidity to curve and deposit the LP tokens to gauge
   */
  function earn() whenNotPaused public {
    require(keepers[msg.sender] || !isKeeperOnly, "!keepers");
    uint256 tokenBalance = IERC20(vaultToken).balanceOf(address(this));
    if (tokenBalance > 0) {
      IERC20(vaultToken).safeApprove(lpToken, 0);
      IERC20(vaultToken).safeApprove(lpToken, tokenBalance);
      uint256 expectedLpAmount = tokenBalance.mul(1e18).div(vaultTokenBase).mul(1e18).div(ICurveFi(lpToken).get_virtual_price());
      uint256 lpMinted = ICurveFi(lpToken).add_liquidity([tokenBalance, 0], expectedLpAmount.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR));
      emit LiquidityAdded(tokenBalance, lpMinted);
    }
    uint256 lpBalance = IERC20(lpToken).balanceOf(address(this));
    if (lpBalance > 0) {
      IERC20(lpToken).safeApprove(gauge, 0);
      IERC20(lpToken).safeApprove(gauge, lpBalance);
      Gauge(gauge).deposit(lpBalance);
      emit GaugeDeposited(lpBalance);
    }
  }

  /**
   * @notice Deposit token to this vault. The vault mints shares to the depositor.
   * @param amount is the amount of token deposited
   */
  function deposit(uint256 amount) public whenNotPaused nonReentrant {
    uint256 _pool = balance(true); // use max vault balance for deposit
    require(isDepositEnabled && _pool.add(amount) < cap, "!deposit");
    uint256 _before = IERC20(vaultToken).balanceOf(address(this));
    IERC20(vaultToken).safeTransferFrom(msg.sender, address(this), amount);
    uint256 _after = IERC20(vaultToken).balanceOf(address(this));
    amount = _after.sub(_before);
    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = amount;
    } else {
      shares = (amount.mul(totalSupply())).div(_pool);
    }
    require(shares > 0, "!shares");
    _mint(msg.sender, shares);
    emit Deposit(msg.sender, amount, shares);
  }


  /**
   * @notice 1. Collect reward from Curve Gauge; 2. Close old leverage trade;
             3. Use the reward to open new leverage trade; 4. Deposit the trade profit and new user deposits into Curve to earn reward
   */
  function poke() external whenNotPaused nonReentrant {
    require(keepers[msg.sender] || !isKeeperOnly, "!keepers");
    require(lastPokeTime.add(pokeInterval) < block.timestamp, "!poke time");
    currentPokeInterval = block.timestamp.sub(lastPokeTime);
    uint256 tokenReward = 0;
    if (Gauge(gauge).balanceOf(address(this)) > 0) {
      tokenReward = collectReward();
    }
    closeTrade();
    if (tokenReward > 0) {
      openTrade(tokenReward);
    }
    currentTokenReward = tokenReward;
    earn();
    lastPokeTime = block.timestamp;
    emit Poked(getPricePerShare(false), getPricePerShare(true));
  }

  /**
   * @notice Only can be called by keepers in case the poke() does not work
   *         Claim rewards from the gauge and swap the rewards to the vault token
   * @return tokenReward the amount of vault token swapped from farm reward
   */
  function collectRewardByKeeper() external returns(uint256 tokenReward) {
    require(keepers[msg.sender], "!keepers");
    tokenReward = collectReward();
  }

  /**
   * @notice Claim rewards from the gauge and swap the rewards to the vault token
   * @return tokenReward the amount of vault token swapped from farm reward
   */
  function collectReward() private returns(uint256 tokenReward) {
    uint256 _before = IERC20(vaultToken).balanceOf(address(this));
    Gauge(gauge).claim_rewards(address(this));
    uint256 _crv = IERC20(crv).balanceOf(address(this));
    if (_crv > 0) {
      IERC20(crv).safeApprove(dex, 0);
      IERC20(crv).safeApprove(dex, _crv);
      address[] memory path;
      if (vaultToken == weth) {
        path = new address[](2);
        path[0] = crv;
        path[1] = weth;
      } else {
        path = new address[](3);
        path[0] = crv;
        path[1] = weth;
        path[2] = vaultToken;
      }
      Uni(dex).swapExactTokensForTokens(_crv, 0, path, address(this), block.timestamp.add(1800))[path.length - 1];
    }
    uint256 _after = IERC20(vaultToken).balanceOf(address(this));
    tokenReward = _after.sub(_before);
  }

  /**
   * @notice Open leverage position at GMX
   * @param amount the amount of token be used as leverage position collateral
   */
  function openTrade(uint256 amount) private {
    address[] memory _path;
    address collateral = isLong ? underlying : usdc;
    if (vaultToken == collateral) {
      _path = new address[](1);
      _path[0] = vaultToken;
    } else {
      _path = new address[](2);
      _path[0] = vaultToken;
      _path[1] = collateral;
    }
    uint256 _underlyingPrice = isLong ? IVault(gmxVault).getMaxPrice(underlying) : IVault(gmxVault).getMinPrice(underlying);
    uint256 _vaultTokenPrice = IVault(gmxVault).getMinPrice(vaultToken);
    uint256 _sizeDelta = leverage.mul(amount).mul(_vaultTokenPrice).div(vaultTokenBase);
    IERC20(vaultToken).safeApprove(gmxRouter, 0);
    IERC20(vaultToken).safeApprove(gmxRouter, amount);
    IRouter(gmxRouter).approvePlugin(gmxPositionManager);
    IRouter(gmxPositionManager).increasePosition(_path, underlying, amount, 0, _sizeDelta, isLong, _underlyingPrice);
    emit OpenPosition(underlying, _underlyingPrice, _vaultTokenPrice, _sizeDelta, isLong, amount);
  }

  /**
   * @notice Only can be called by keepers to close the position in case the poke() does not work
   */
  function closeTradeByKeeper() external {
    require(keepers[msg.sender], "!keepers");
    closeTrade();
  }

  /**
   * @notice Close leverage position at GMX
   */
  function closeTrade() private {
    (uint256 size,,,,,,,) = IVault(gmxVault).getPosition(address(this), underlying, underlying, isLong);
    uint256 _underlyingPrice = isLong ? IVault(gmxVault).getMinPrice(underlying) : IVault(gmxVault).getMaxPrice(underlying);
    uint256 _vaultTokenPrice = IVault(gmxVault).getMinPrice(vaultToken);
    if (size == 0) {
      emit ClosePosition(underlying, _underlyingPrice, _vaultTokenPrice, size, isLong, 0, 0);
      return;
    }
    address collateral = isLong ? underlying : usdc;
    uint256 _before = IERC20(vaultToken).balanceOf(address(this));
    if (vaultToken == collateral) {
      IRouter(gmxRouter).decreasePosition(collateral, underlying, 0, size, isLong, address(this), _underlyingPrice);
    } else {
      address[] memory path = new address[](2);
      path = new address[](2);
      path[0] = collateral;
      path[1] = vaultToken;
      IRouter(gmxRouter).decreasePositionAndSwap(path, underlying, 0, size, isLong, address(this), _underlyingPrice, 0);
    }
    uint256 _after = IERC20(vaultToken).balanceOf(address(this));
    uint256 _tradeProfit = _after.sub(_before);
    uint256 _fee = 0;
    if (_tradeProfit > 0) {
      _fee = _tradeProfit.mul(performanceFee).div(FEE_DENOMINATOR);
      IERC20(vaultToken).safeTransfer(rewards, _fee);
    }
    emit ClosePosition(underlying, _underlyingPrice, _vaultTokenPrice, size, isLong, _tradeProfit, _fee);
  }

  /**
   * @notice Withdraw the funds for the `_shares` of the sender. Withdraw fee is deducted.
   * @param shares is the shares of the sender to withdraw
   */
  function withdraw(uint256 shares) external whenNotPaused nonReentrant {
    uint256 withdrawAmount = _withdraw(shares, true);
    IERC20(vaultToken).safeTransfer(msg.sender, withdrawAmount);
  }

  /**
   * @notice Withdraw from this vault to another vault
   * @param shares the number of this vault shares to be burned
   * @param vault the address of destination vault
   */
  function withdrawToVault(uint256 shares, address vault) external whenNotPaused nonReentrant {
    require(vault != address(0), "!vault");
    require(withdrawMapping[address(this)][vault], "Withdraw to vault not allowed");

    // vault to vault transfer does not charge any withdraw fee
    uint256 withdrawAmount = _withdraw(shares, false);
    IERC20(vaultToken).safeApprove(vault, withdrawAmount);
    IVovoVault(vault).deposit(withdrawAmount);
    uint256 receivedShares = IERC20(vault).balanceOf(address(this));
    IERC20(vault).safeTransfer(msg.sender, receivedShares);

    emit Withdraw(msg.sender, withdrawAmount, shares, 0);
    emit WithdrawToVault(msg.sender, shares, vault, receivedShares);
  }

  function _withdraw(uint256 shares, bool shouldChargeFee) private returns(uint256 withdrawAmount) {
    require(shares > 0, "!shares");
    uint256 r = (balance(false).mul(shares)).div(totalSupply()); // use minimum vault balance for deposit
    _burn(msg.sender, shares);

    uint256 b = IERC20(vaultToken).balanceOf(address(this));
    if (b < r) {
      uint256 lpPrice = ICurveFi(lpToken).get_virtual_price();
      // amount of LP tokens to withdraw
      uint256 lpAmount = (r.sub(b)).mul(1e18).div(vaultTokenBase).mul(1e18).div(lpPrice);
      _withdrawSome(lpAmount);
      uint256 _after = IERC20(vaultToken).balanceOf(address(this));
      uint256 _diff = _after.sub(b);
      if (_diff < r.sub(b)) {
        r = b.add(_diff);
      }
    }
    uint256 fee = 0;
    if (shouldChargeFee) {
      fee = r.mul(withdrawalFee).div(FEE_DENOMINATOR);
      IERC20(vaultToken).safeTransfer(rewards, fee);
    }
    withdrawAmount = r.sub(fee);
    emit Withdraw(msg.sender, r, shares, fee);
  }

  /**
   * @notice Withdraw the asset that is accidentally sent to this address
   * @param _asset is the token to withdraw
   */
  function withdrawAsset(address _asset) external onlyGovernor {
    require(_asset != vaultToken, "!vaultToken");
    IERC20(_asset).safeTransfer(msg.sender, IERC20(_asset).balanceOf(address(this)));
  }

  /**
   * @notice Withdraw the LP tokens from Gauge, and then withdraw vaultToken from Curve vault
   * @param lpAmount is the amount of LP tokens to withdraw
   */
  function _withdrawSome(uint256 lpAmount) private {
    uint256 _before = IERC20(lpToken).balanceOf(address(this));
    Gauge(gauge).withdraw(lpAmount);
    uint256 _after = IERC20(lpToken).balanceOf(address(this));
    _withdrawOne(_after.sub(_before));
  }

  /**
   * @notice Withdraw vaultToken from Curve vault
   * @param _amnt is the amount of LP tokens to withdraw
   */
  function _withdrawOne(uint256 _amnt) private {
    IERC20(lpToken).safeApprove(lpToken, 0);
    IERC20(lpToken).safeApprove(lpToken, _amnt);
    uint256 expectedVaultTokenAmount = _amnt.mul(vaultTokenBase).mul(ICurveFi(lpToken).get_virtual_price()).div(1e36);
    ICurveFi(lpToken).remove_liquidity_one_coin(_amnt, 0, expectedVaultTokenAmount.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR));
  }

  /// ===== View Functions =====

  function getPricePerShare(bool isMax) public view returns (uint256) {
    return balance(isMax).mul(1e18).div(totalSupply());
  }

  /**
   * @notice get the active leverage position value in vaultToken
   */
  function getActivePositionValue() public view returns (uint256) {
    (uint256 size, uint256 collateral,,uint256 entryFundingRate,,,,) = IVault(gmxVault).getPosition(address(this), underlying, underlying, isLong);
    if (size == 0) {
      return 0;
    }
    (bool hasProfit, uint256 delta) = IVault(gmxVault).getPositionDelta(address(this), underlying, underlying, isLong);
    uint256 feeUsd = IVault(gmxVault).getPositionFee(size);
    uint256 fundingFee = IVault(gmxVault).getFundingFee(underlying, size, entryFundingRate);
    feeUsd = feeUsd.add(fundingFee);
    uint256 positionValueUsd = hasProfit ? collateral.add(delta).sub(feeUsd) : collateral.sub(delta).sub(feeUsd);
    uint256 positionValue = IVault(gmxVault).usdToTokenMin(vaultToken, positionValueUsd);
    // Cap the positionValue to avoid the oracle manipulation
    if (positionValue > currentTokenReward.mul(maxCollateralMultiplier)) {
      positionValue = currentTokenReward.mul(maxCollateralMultiplier);
    }
    return positionValue;
  }

  /**
   * @notice get the estimated pending reward value in vaultToken, based on the reward from last period
   */
  function getEstimatedPendingRewardValue() public view returns(uint256) {
    if (currentPokeInterval == 0) {
      return 0;
    }
    return currentTokenReward.mul(block.timestamp.sub(lastPokeTime)).div(currentPokeInterval);
  }

  /// ===== Permissioned Actions: Governance =====

  function setGovernance(address _governor) external onlyGovernor {
    governor = _governor;
    emit GovernanceSet(governor);
  }

  function setAdmin(address _admin) external {
    require(msg.sender == admin || msg.sender == governor, "!authorized");
    admin = _admin;
    emit AdminSet(admin);
  }

  function setGuardian(address _guardian) external onlyGovernor {
    guardian = _guardian;
    emit GuardianSet(guardian);
  }

  function setFees(uint256 _performanceFee, uint256 _withdrawalFee) external onlyGovernor {
    // ensure performanceFee is smaller than 50% and withdraw fee is smaller than 5%
    require(_performanceFee < 5000 && _withdrawalFee < 500, "!too-much");
    performanceFee = _performanceFee;
    withdrawalFee = _withdrawalFee;
    emit FeeSet(performanceFee, withdrawalFee);
  }

  function setLeverage(uint256 _leverage) external onlyGovernor {
    require(_leverage >= 1 && _leverage <= 50, "!leverage");
    leverage = _leverage;
    emit LeverageSet(leverage);
  }

  function setIsLong(bool _isLong) external onlyGovernor {
    closeTrade();
    isLong = _isLong;
    emit isLongSet(isLong);
  }

  function setRewards(address _rewards) external onlyGovernor {
    rewards = _rewards;
    emit RewardsSet(rewards);
  }

  function setGmxContracts(address _gmxPositionManager, address _gmxRouter, address _gmxVault) external onlyGovernor {
    gmxPositionManager = _gmxPositionManager;
    gmxRouter = _gmxRouter;
    gmxVault = _gmxVault;
    emit GmxContractsSet(gmxPositionManager, gmxRouter, gmxVault);
  }

  function setSlip(uint256 _slip) external onlyGovernor {
    slip = _slip;
  }

  function setMaxCollateralMultiplier(uint256 _maxCollateralMultiplier) external onlyGovernor {
    require(_maxCollateralMultiplier >= 1 && _maxCollateralMultiplier <= 50, "!maxCollateralMultiplier");
    maxCollateralMultiplier = _maxCollateralMultiplier;
    emit MaxCollateralMultiplierSet(maxCollateralMultiplier);
  }

  function setIsKeeperOnly(bool _isKeeperOnly) external onlyGovernor {
    isKeeperOnly = _isKeeperOnly;
    emit IsKeeperOnlySet(_isKeeperOnly);
  }

  function setDepositEnabledAndCap(bool _flag, uint256 _cap) external onlyGovernor {
    isDepositEnabled = _flag;
    cap = _cap;
    emit DepositEnabled(isDepositEnabled);
    emit CapSet(cap);
  }

  function setPokeInterval(uint256 _pokeInterval) external onlyGovernor {
    pokeInterval = _pokeInterval;
    emit PokeIntervalSet(pokeInterval);
  }

  // ===== Permissioned Actions: Admin =====

  function addKeeper(address _keeper) external onlyAdmin {
    keepers[_keeper] = true;
    emit KeeperAdded(_keeper);
  }

  function removeKeeper(address _keeper) external onlyAdmin {
    keepers[_keeper] = false;
    emit KeeperRemoved(_keeper);
  }

  function registerVault(address fromVault, address toVault) external onlyAdmin {
    withdrawMapping[fromVault][toVault] = true;
    emit VaultRegistered(fromVault, toVault);
  }

  function revokeVault(address fromVault, address toVault) external onlyAdmin {
    withdrawMapping[fromVault][toVault] = false;
    emit VaultRevoked(fromVault, toVault);
  }

  /// ===== Permissioned Actions: Guardian =====

  function pause() external onlyGuardian {
    _pause();
  }

  /// ===== Permissioned Actions: Governance =====

  function unpause() external onlyGovernor {
    _unpause();
  }

  /// ===== Modifiers =====

  modifier onlyGovernor() {
    require(msg.sender == governor, "!governor");
    _;
  }

  modifier onlyAdmin() {
    require(msg.sender == admin, "!admin");
    _;
  }

  modifier onlyGuardian() {
    require(msg.sender == guardian, "!pausers");
    _;
  }

}

