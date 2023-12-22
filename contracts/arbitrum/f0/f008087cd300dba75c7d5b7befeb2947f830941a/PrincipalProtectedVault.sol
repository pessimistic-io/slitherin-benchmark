// SPDX-License-Identifier: MIT
pragma solidity ^0.7.6;

import "./IERC20.sol";
import "./SafeMath.sol";
import "./Address.sol";
import "./SafeERC20.sol";
import "./ERC20.sol";
import "./Initializable.sol";
import "./IERC20Upgradeable.sol";
import "./ERC20Upgradeable.sol";
import "./IVovoVault.sol";
import "./Gauge.sol";
import "./Curve.sol";
import "./Uni.sol";
import "./IRouter.sol";
import "./IVault.sol";
import "./IUniswapV2Factory.sol";
import "./IUniswapV2Pair.sol";

/**
 * @title PrincipalProtectedVault
 * @dev A vault that receives vaultToken from users, and then deposits the vaultToken into yield farming pools.
 * Periodically, the vault collects the yield rewards and uses the rewards to open a leverage trade on a perpetual swap exchange.
 */
contract PrincipalProtectedVault is Initializable, ERC20Upgradeable {
  using SafeERC20 for IERC20;
  using Address for address;
  using SafeMath for uint256;

  // usdc token address
  address public constant usdc = address(0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8);
  // weth token address
  address public constant weth = address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1);
  // crv token address
  address public constant crv = address(0x11cDb42B0EB46D95f990BeDD4695A6e3fA034978);
  // gmx router address
  address public constant gmxRouter = address(0xaBBc5F99639c9B6bCb58544ddf04EFA6802F4064);
  // gmx vault address
  address public constant gmxVault = address(0x489ee077994B6658eAfA855C308275EAd8097C4A);
  // sushiswap address
  address public constant sushiswap = address(0x1b02dA8Cb0d097eB8D57A175b88c7D8b47997506);
  // sushiswap factory address
  address public constant sushiFactory = address(0xc35DADB65012eC5796536bD9864eD8773aBc74C4);

  uint256 public constant usdcBase = 1e6;
  uint256 public constant FEE_DENOMINATOR = 10000;
  uint256 public constant DENOMINATOR = 10000;

  address vaultToken; // deposited token of the vault
  address underlying; // underlying token of the leverage position
  address lpToken;
  address gauge;
  uint256 public withdrawalFee;
  uint256 public performanceFee;
  uint256 public slip;
  uint256 public sizeDelta;
  uint256 public totalFarmReward; // lifetime farm reward earnings
  uint256 public totalTradeProfit; // lifetime trade profit
  uint256 public cap;
  uint256 public vaultTokenBase;
  uint256 public underlyingBase;
  uint256 public lastPokeTime;
  uint256 public pokeInterval;
  bool public isDepositEnabled;
  uint256 public leverage;
  bool public isLong;
  address public governor;
  address public admin;
  address public rewards;
  address public dex;
  address public dexFactory;
  /// mapping(keeperAddress => true/false)
  mapping(address => bool) public keepers;
  /// mapping(fromVault => mapping(toVault => true/false))
  mapping(address => mapping(address => bool)) public withdrawMapping;

  event Minted(address to, uint256 shares);
  event LiquidityAdded(uint256 tokenAmount, uint256 lpMinted);
  event GaugeDeposited(uint256 lpDeposited);
  event Harvested(uint256 amount, uint256 totalFarmReward);
  event OpenPosition(address underlying, uint256 sizeDelta, bool isLong);
  event ClosePosition(address underlying, uint256 sizeDelta, bool isLong, uint256 pnl, uint256 fee);
  event Withdraw(address to, uint256 amount, uint256 fee);
  event WithdrawToVault(address owner, uint256 shares, address vault, uint256 receivedShares);
  event GovernanceSet(address governor);
  event AdminSet(address admin);
  event PerformanceFeeSet(uint256 performanceFee);
  event WithdrawalFeeSet(uint256 withdrawalFee);
  event LeverageSet(uint256 leverage);
  event isLongSet(bool isLong);
  event RewardsSet(address rewards);
  event SlipSet(uint256 slip);
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
    pokeInterval = 1 days;
    governor = msg.sender;
    admin = msg.sender;
    dex = sushiswap;
    dexFactory = sushiFactory;
    keepers[msg.sender] = true;
    isDepositEnabled = true;
    withdrawalFee = 50;
    performanceFee = 2000;
    slip = 100;
    sizeDelta = 0;
  }


  /**
   * @notice Get the usd value of this vault: the value of lp + the value of usdc
   */
  function balance() public view returns (uint256) {
    uint256 lpPrice = ICurveFi(lpToken).get_virtual_price();
    uint256 lpAmount = Gauge(gauge).balanceOf(address(this));
    uint256 lpValue = lpPrice.mul(lpAmount).div(1e18).mul(vaultTokenBase).div(1e18);
    return lpValue.add(IERC20(vaultToken).balanceOf(address(this)));
  }

  /**
   * @notice Add liquidity to curve and deposit the LP tokens to gauge
   */
  function earn() public {
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
   * @notice Deposit all the token balance of the sender to this vault
   */
  function depositAll() external {
    deposit(IERC20(vaultToken).balanceOf(msg.sender));
  }

  /**
   * @notice Deposit token to this vault. The vault mints shares to the depositor.
   * @param amount is the amount of token deposited
   */
  function deposit(uint256 amount) public {
    uint256 _pool = balance();
    require(isDepositEnabled && _pool.add(amount) < cap, "!deposit");
    uint256 _before = IERC20(vaultToken).balanceOf(address(this));
    IERC20(vaultToken).safeTransferFrom(msg.sender, address(this), amount);
    uint256 _after = IERC20(vaultToken).balanceOf(address(this));
    amount = _after.sub(_before); // Additional check for deflationary tokens
    uint256 shares = 0;
    if (totalSupply() == 0) {
      shares = amount;
    } else {
      shares = (amount.mul(totalSupply())).div(_pool);
    }
    _mint(msg.sender, shares);
    emit Minted(msg.sender, shares);
  }


  /**
   * @notice 1. Collect reward from Curve Gauge; 2. Close old leverage trade;
             3. Use the reward to open new leverage trade; 4. Deposit the trade profit and new user deposits into Curve to earn reward
   */
  function poke() external {
    require(keepers[msg.sender] || msg.sender == governor, "!keepers");
    require(lastPokeTime + pokeInterval < block.timestamp, "!poke time");
    uint256 tokenReward = 0;
    if (Gauge(gauge).balanceOf(address(this)) > 0) {
      tokenReward = collectReward();
    }
    if (sizeDelta > 0) {
      closeTrade();
    }
    if (tokenReward > 0) {
      openTrade(tokenReward);
    }
    earn();
    lastPokeTime = block.timestamp;
  }

  /**
   * @notice Claim rewards from the gauge and swap the rewards to the underlying token
   * @return tokenReward the amount of underlying swapped from farm reward
   */
  function collectReward() private returns(uint256 tokenReward) {
    uint256 _before = IERC20(underlying).balanceOf(address(this));
    Gauge(gauge).claim_rewards();
    uint256 _crv = IERC20(crv).balanceOf(address(this));
    if (_crv > 0) {
      IERC20(crv).safeApprove(dex, 0);
      IERC20(crv).safeApprove(dex, _crv);
      address[] memory path;
      if (underlying == weth) {
        path = new address[](2);
        path[0] = crv;
        path[1] = weth;
      } else {
        path = new address[](3);
        path[0] = crv;
        path[1] = weth;
        path[2] = underlying;
      }
      Uni(dex).swapExactTokensForTokens(_crv, uint256(0), path, address(this), block.timestamp.add(1800));
    }
    uint256 _after = IERC20(underlying).balanceOf(address(this));
    tokenReward = _after.sub(_before);
    totalFarmReward = totalFarmReward.add(tokenReward);
    emit Harvested(tokenReward, totalFarmReward);
  }

  /**
   * @notice Open leverage position at GMX
   * @param amount the amount of token be used as leverage position collateral
   */
  function openTrade(uint256 amount) private {
    address[] memory _path = new address[](1);
    _path[0] = underlying;
    uint256 _sizeDelta = leverage.mul(amount).mul(getUnderlyingPrice()).mul(1e12).div(underlyingBase);
    uint256 _price = isLong ? IVault(gmxVault).getMaxPrice(underlying) : IVault(gmxVault).getMinPrice(underlying);
    IERC20(underlying).safeApprove(gmxRouter, 0);
    IERC20(underlying).safeApprove(gmxRouter, amount);
    IRouter(gmxRouter).increasePosition(_path, underlying, amount, 0, _sizeDelta, isLong, _price);
    sizeDelta = _sizeDelta;
    emit OpenPosition(underlying, sizeDelta, isLong);
  }

  /**
   * @notice Close leverage position at GMX
   */
  function closeTrade() private {
    (uint256 size,,,,,,,) = IVault(gmxVault).getPosition(address(this), underlying, underlying, isLong);
    if (size == 0) {
      return;
    }
    uint256 _before = IERC20(vaultToken).balanceOf(address(this));
    uint256 price = isLong ? IVault(gmxVault).getMinPrice(underlying) : IVault(gmxVault).getMaxPrice(underlying);
    if (underlying == vaultToken) {
      IRouter(gmxRouter).decreasePosition(underlying, underlying, 0, sizeDelta, isLong, address(this), price);
    } else {
      address[] memory path = new address[](2);
      path = new address[](2);
      path[0] = underlying;
      path[1] = vaultToken;
      IRouter(gmxRouter).decreasePositionAndSwap(path, underlying, 0, sizeDelta, isLong, address(this), price, 0);
    }
    uint256 _after = IERC20(vaultToken).balanceOf(address(this));
    uint256 _tradeProfit = _after.sub(_before);
    uint256 _fee = 0;
    if (_tradeProfit > 0) {
      _fee = _tradeProfit.mul(performanceFee).div(FEE_DENOMINATOR);
      IERC20(vaultToken).safeTransfer(rewards, _fee);
      totalTradeProfit = totalTradeProfit.add(_tradeProfit.sub(_fee));
    }
    emit ClosePosition(underlying, sizeDelta, isLong, _tradeProfit.sub(_fee), _fee);
    sizeDelta = 0;
  }

  /**
   * @notice Withdraw all the funds of the sender
   */
  function withdrawAll() external {
    uint256 withdrawAmount = _withdraw(balanceOf(msg.sender), true);
    IERC20(vaultToken).safeTransfer(msg.sender, withdrawAmount);
  }

  /**
   * @notice Withdraw the funds for the `_shares` of the sender. Withdraw fee is deducted.
   * @param shares is the shares of the sender to withdraw
   */
  function withdraw(uint256 shares) external {
    uint256 withdrawAmount = _withdraw(shares, true);
    IERC20(vaultToken).safeTransfer(msg.sender, withdrawAmount);
  }

  /**
   * @notice Withdraw from this vault to another vault
   * @param shares the number of this vault shares to be burned
   * @param vault the address of destination vault
   */
  function withdrawToVault(uint256 shares, address vault) external {
    require(vault != address(0), "!vault");
    require(withdrawMapping[address(this)][vault], "Withdraw to vault not allowed");

    // vault to vault transfer does not charge any withdraw fee
    uint256 withdrawAmount = _withdraw(shares, false);
    IERC20(vaultToken).safeApprove(vault, withdrawAmount);
    IVovoVault(vault).deposit(withdrawAmount);
    uint256 receivedShares = IERC20(vault).balanceOf(address(this));
    IERC20(vault).safeTransfer(msg.sender, receivedShares);

    emit Withdraw(msg.sender, withdrawAmount, 0);
    emit WithdrawToVault(msg.sender, shares, vault, receivedShares);
  }

  function _withdraw(uint256 shares, bool shouldChargeFee) private returns(uint256 withdrawAmount) {
    require(shares > 0, "!shares");
    uint256 r = (balance().mul(shares)).div(totalSupply());
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
    emit Withdraw(msg.sender, withdrawAmount, fee);
  }

  /**
   * @notice Withdraw the asset that is accidentally sent to this address
   * @param _asset is the token to withdraw
   */
  function withdrawAsset(address _asset) external {
    require(keepers[msg.sender] || msg.sender == governor, "!keepers");
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
    uint256 expectedVaultTokenAmount = _amnt.mul(vaultTokenBase).div(ICurveFi(lpToken).get_virtual_price());
    ICurveFi(lpToken).remove_liquidity_one_coin(_amnt, 0, expectedVaultTokenAmount.mul(DENOMINATOR.sub(slip)).div(DENOMINATOR));
  }

  function getPricePerShare() external view returns (uint256) {
    return balance().mul(1e18).div(totalSupply());
  }

  function getUnderlyingPrice() public view returns (uint256) {
    address pair = IUniswapV2Factory(dexFactory).getPair(usdc, underlying);
    (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
    if (usdc > underlying) {
      (reserve0, reserve1) = (reserve1, reserve0);
    }
    return uint256(reserve0).mul(1e18).div(uint256(reserve1)).mul(underlyingBase).div(usdcBase);
  }

  function setGovernance(address _governor) external onlyGovernor {
    governor = _governor;
    emit GovernanceSet(governor);
  }

  function setAdmin(address _admin) external {
    require(msg.sender == admin || msg.sender == governor, "!authorized");
    admin = _admin;
    emit AdminSet(admin);
  }

  function setPerformanceFee(uint256 _performanceFee) external onlyGovernor {
    performanceFee = _performanceFee;
    emit PerformanceFeeSet(performanceFee);
  }

  function setWithdrawalFee(uint256 _withdrawalFee) external onlyGovernor {
    withdrawalFee = _withdrawalFee;
    emit WithdrawalFeeSet(withdrawalFee);
  }

  function setLeverage(uint256 _leverage) external onlyGovernor {
    leverage = _leverage;
    emit LeverageSet(leverage);
  }

  function setIsLong(bool _isLong) external onlyGovernor {
    isLong = _isLong;
    emit isLongSet(isLong);
  }

  function setRewards(address _rewards) public onlyGovernor {
    rewards = _rewards;
    emit RewardsSet(rewards);
  }

  function setSlip(uint256 _slip) public onlyGovernor {
    slip = _slip;
    emit SlipSet(slip);
  }

  function setDepositEnabled(bool _flag) public onlyGovernor {
    isDepositEnabled = _flag;
    emit DepositEnabled(isDepositEnabled);
  }

  function setCap(uint256 _cap) public onlyGovernor {
    cap = _cap;
    emit CapSet(cap);
  }

  function setPokeInterval(uint256 _pokeInterval) public onlyGovernor {
    pokeInterval = _pokeInterval;
    emit PokeIntervalSet(pokeInterval);
  }

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

  modifier onlyGovernor() {
    require(msg.sender == governor, "!governor");
    _;
  }

  modifier onlyAdmin() {
    require(msg.sender == admin, "!admin");
    _;
  }

}

