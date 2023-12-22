// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";

import "./AbstractStrategy.sol";
import "./ILendingPool.sol";
import "./IYieldingPool.sol";
import "./IVault.sol";

import {CompositionToken, LendingPoolTokenPair, PushOptions, PullOptions} from "./Structs.sol";

import "./AddressesArbitrum.sol";
import "./Allocate.sol";

/// @title Aave-GMX Delta Neutral Yield Farming Strategy
/// @author Buooy
/// @notice Aave as lending pool and Gmx as Yield Pool
/// @custom:version v1.0
contract StrategyAaveGmxDeltaNeutralYield is AbstractStrategy {
  using SafeERC20Upgradeable for IERC20Upgradeable;
  using EnumerableSet for EnumerableSet.AddressSet;

  //  Public variables
  uint256 public borrowRate;
  address public yieldingPoolAddress;
  address public lendingPoolAddress;
  address public withdrawAddress;

  EnumerableSet.AddressSet private gmxPoolTokens;
  EnumerableSet.AddressSet private aavePoolTokens;
  EnumerableSet.AddressSet private compositionTokens;

  LendingPoolTokenPair[] private lendingPoolTokenPairs;

  // ============================================================================================
  /// Modifiers
  // ============================================================================================
  modifier notInitialised {
    require(isInitialised == false, "Strategy Already Initialised");
    _;
  }
  modifier initialised {
    require(isInitialised == true, "Strategy Not Initialised");
    _;
  }

  // ============================================================================================
  /// Initialisation
  // ============================================================================================
  /// @custom:oz-upgrades-unsafe-allow constructor
  constructor() {
    _disableInitializers();
  }

  function initialize(
    string memory _strategyName,
    address _withdrawAddress,
    address[] memory _userAddresses,
    address[] memory _gmxPoolTokens,
    address[] memory _aavePoolTokens,
    address[2][] memory _lendingPoolTokenPairs,
    address[] memory _compositionTokens
  ) public initializer {
    __Ownable_init();
    __Pausable_init();

    _preInitialise(
      _gmxPoolTokens,
      _aavePoolTokens,
      _lendingPoolTokenPairs,
      _compositionTokens
    );

    strategyName = _strategyName;
    strategyCategory = "DeltaNeutralYieldFarming";
    borrowRate = 66666;
    isInitialised = true;

    withdrawAddress = _withdrawAddress;
    
    addUserRoles(_userAddresses, "USER_ROLE");

    emit StrategyInitialised(
      address(this),
      _strategyName,
      "DeltaNeutralYieldFarming"
    );
  }

  function _preInitialise(
    address[] memory _gmxPoolTokens,
    address[] memory _aavePoolTokens,
    address[2][] memory _lendingPoolTokenPairs,
    address[] memory _compositionTokens
  ) internal {
    // Initialise gmx pool tokens
    for (uint256 index; index < _gmxPoolTokens.length; index++) {
      gmxPoolTokens.add(_gmxPoolTokens[index]);
    }

    // Initialise aave pool tokens
    for (uint256 index; index < _aavePoolTokens.length; index++) {
      aavePoolTokens.add(_aavePoolTokens[index]);
    }

    for (uint256 index; index < _lendingPoolTokenPairs.length; index++) {
      lendingPoolTokenPairs.push(LendingPoolTokenPair(_lendingPoolTokenPairs[index][0], _lendingPoolTokenPairs[index][1]));
    }

    // Initialise Composition Tokens
    for (uint256 index; index < _compositionTokens.length; index++) {
      compositionTokens.add(_compositionTokens[index]);
    }
  }

  // ============================================================================================
  /// Strategy Functions
  // ============================================================================================
  /// @inheritdoc AbstractStrategy
  function allocate() override external onlyRole(USER_ROLE) {
    // Withdraw the GLP to cover debts
    pullFromYieldingPool();

    // Repay From lending pool
    withdrawFromLendingPool();

    // Send the USDC to the pool
    supplyToLendingPool();

    // Borrow the appropriate hedging tokens from Pool
    borrowFromLendingPool(true);

    // Invest in GLP
    pushToYieldingPool();
  }

  /// @inheritdoc AbstractStrategy
  function exitPositions() override external onlyRole(USER_ROLE) {
    // Withdraw the GLP to cover debts
    pullFromYieldingPool();

    // Repay From lending pool
    withdrawFromLendingPool();
  }

  /// @notice Updates the borrow rate
  /// @param newBorrowRate borrow rate that is divided by 100000 as a base
  function updateBorrowRate(uint256 newBorrowRate) external onlyRole(USER_ROLE) {
    require(newBorrowRate < 100000, "Rate cannot be more than 100000");
    require(newBorrowRate > 0, "Rate cannot be less than 0");

    borrowRate = newBorrowRate;
  }

  function withdrawAll() external onlyRole(USER_ROLE) {
    //  Withdraw USDC
    IERC20Upgradeable(Addresses.USDC_ADDRESS).safeIncreaseAllowance(withdrawAddress, IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this)));
    IERC20Upgradeable(Addresses.USDC_ADDRESS).transfer(withdrawAddress, IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this)));
  }

  // ==================================================================================================
  // Yielding and Lending Pool actions
  // ==================================================================================================
  /// @return uint256 totalCollateralBase
  /// @return uint256 totalDebtBase
  /// @return uint256 availableBorrowBase
  /// @return uint256 currentLiquidiationThreshold
  /// @return uint256 loanToValue
  /// @return uint256 healthFactor
  function getLendingPoolData() external view onlyRole(USER_ROLE) returns (uint256, uint256, uint256, uint256, uint256, uint256) {
    return ILendingPool(lendingPoolAddress).getAccountData();
  }

  /// @notice pull all assets from yield pool based on debt assets
  function pullFromYieldingPool() public onlyRole(USER_ROLE) {
    Allocate.pullFromYieldingPool(yieldingPoolAddress, lendingPoolAddress);
  }

  /// @notice sends all available USDC to the lending pool
  function supplyToLendingPool() public onlyRole(USER_ROLE) {
    Allocate.supplyToLendingPool(lendingPoolAddress);
  }

  /// @notice borrows the token based on the composition of GLP
  /// @param transfer if true, it will transfers the borrowed tokens from lending pool to the yield pool
  function borrowFromLendingPool(bool transfer) public onlyRole(USER_ROLE) {
    Allocate.borrowFromLendingPool(
      lendingPoolAddress,
      yieldingPoolAddress,
      borrowRate,
      _getCompositionTokens(),
      transfer
    );
  }

  /// @notice repay max tokens and withdraw USDC to strategy
  function withdrawFromLendingPool() public onlyRole(USER_ROLE) {
    // repay debt tokens with real tokens
    for (uint8 index; index < lendingPoolTokenPairs.length; index++) {
      if (IERC20Upgradeable(lendingPoolTokenPairs[index].tokenAddress).balanceOf(address(lendingPoolAddress)) > 0) {
        //  Repay amount
        ILendingPool(lendingPoolAddress).repay(
          lendingPoolTokenPairs[index].tokenAddress,
          IERC20Upgradeable(lendingPoolTokenPairs[index].tokenAddress).balanceOf(address(lendingPoolAddress)),
          2
        );
      }
    }

    (,uint256 totalDebtBase,,uint256 currentLiquidationThreshold,,) = ILendingPool(lendingPoolAddress).getAccountData();

    if (currentLiquidationThreshold > 0) {
      ILendingPool(lendingPoolAddress).withdraw(
        Addresses.USDC_ADDRESS,
        //  Withdraw only up to the liquidation threshold
        IERC20Upgradeable(Addresses.AUSDC_ADDRESS)
          .balanceOf(address(lendingPoolAddress))
          * 100
          - (
            totalDebtBase
            * 10000
            / currentLiquidationThreshold
          )
          / 100
      );
    }

    // Withdraw all remaining token
    ILendingPool(lendingPoolAddress).withdrawAll();
  }
  
  /// @notice push all assets to yield pool
  function pushToYieldingPool() public onlyRole(USER_ROLE) {
    // push USDC to yielding pool
    IERC20Upgradeable(Addresses.USDC_ADDRESS).safeIncreaseAllowance(yieldingPoolAddress, IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this)));
    IERC20Upgradeable(Addresses.USDC_ADDRESS).transfer(yieldingPoolAddress, IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this)));

    //  Get all assets and values
    (address[] memory addresses, uint256[] memory tokenValues) = IYieldingPool(yieldingPoolAddress).getPoolTokensValue();

    for (uint256 index = 0; index < addresses.length; index++) {
      if (gmxPoolTokens.contains(addresses[index]) && tokenValues[index] > 0) {
        IYieldingPool(yieldingPoolAddress).push(
          addresses[index],
          tokenValues[index],
          abi.encode(PushOptions(
            0, 0
          ))
        );
      }
    }
  }

  /// @notice claim from the yield pool
  function claimRewardsFromYieldingPool(bytes memory options) public onlyRole(USER_ROLE) {
    IYieldingPool(yieldingPoolAddress).claimRewards(options);
  }

  /// @notice compound the yield pool
  function compoundYieldingPool() public onlyRole(USER_ROLE) {
    IYieldingPool(yieldingPoolAddress).compound();
  }

  /// @notice Gets the borrowing allocation
  /// @return composition borrowing compositions
  function getCompositionTokens() external onlyRole(USER_ROLE) view returns (CompositionToken[] memory composition) {
    return _getCompositionTokens();
  }

  /// @notice Gets the GLP Composition
  /// @return composition the glp composition
  function _getCompositionTokens() internal view returns (CompositionToken[] memory composition) {
    CompositionToken[] memory compositions = new CompositionToken[](compositionTokens.length());
    //  Gets the glp composition and prices from the gmx subgraph
    for (uint index = 0; index < compositionTokens.length(); index++) {
      compositions[index] = CompositionToken(
        compositionTokens.at(index),
        IVault(Addresses.GMX_VAULT).tokenDecimals(compositionTokens.at(index)),
        IVault(Addresses.GMX_VAULT).tokenWeights(compositionTokens.at(index)),
        IVault(Addresses.GMX_VAULT).getMaxPrice(compositionTokens.at(index)),
        IVault(Addresses.GMX_VAULT).getMinPrice(compositionTokens.at(index))
      );
    }
    
    return compositions;
  }

  // ============================================================================================
  /// Getters/Setters
  // ============================================================================================
  /// @inheritdoc AbstractStrategy
  function getStrategyInfo() override external view returns (
    string memory name,
    string memory strategyCategory,
    bool isStrategyInitialised,
    bool isStrategyPaused,
    address[] memory lendingPoolTokenAddresses,
    uint256[] memory lendingPoolTokenValues,
    address[] memory yieldingPoolTokenAddresses,
    uint256[] memory yieldingPoolTokenValues
  ) {
    (
      string memory _strategyName,
      string memory _strategyCategory,
      bool _isInitialised,
      bool _isStrategyPaused
    ) = _getStrategyInfo();

    // Get Lending Pool Information
    (address[] memory _lendingPoolTokenAddresses, uint256[] memory _lendingPoolTokenValues) = ILendingPool(lendingPoolAddress).getPoolTokensValue();
    
    // Get Yield Pool Information
    (address[] memory _yieldingPoolTokenAddresses, uint256[] memory _yieldingPoolTokenValues) = IYieldingPool(yieldingPoolAddress).getPoolTokensValue();

    return (
      _strategyName,
      _strategyCategory,
      _isInitialised,
      _isStrategyPaused,
      _lendingPoolTokenAddresses,
      _lendingPoolTokenValues,
      _yieldingPoolTokenAddresses,
      _yieldingPoolTokenValues
    );
  }

  function setYieldingPoolAddress(address _yieldingPoolAddress) external onlyOwner {
    yieldingPoolAddress = _yieldingPoolAddress;
  }

  function setLendingPoolAddress(address _lendingPoolAddress) external onlyOwner {
    lendingPoolAddress = _lendingPoolAddress;
  } 

  function setWithdrawAddress(address _withdrawAddress) override external onlyOwner {
    withdrawAddress = _withdrawAddress;
  }

  function getWithdrawAddress() override external view returns (address) {
    return withdrawAddress;
  }
}
