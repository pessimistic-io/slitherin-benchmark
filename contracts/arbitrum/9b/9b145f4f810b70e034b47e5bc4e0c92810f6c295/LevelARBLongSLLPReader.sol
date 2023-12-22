// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./ILendingPool.sol";
import "./IChainlinkOracle.sol";
import "./ILevelARBOracle.sol";
import "./ILevelARBLongSLLPVault.sol";
import "./ILevelARBLongSLLPManager.sol";
import "./ILiquidityPool.sol";
import "./IPoolLens.sol";
import "./ILevelMasterV2.sol";
import "./Errors.sol";

contract LevelARBLongSLLPReader {
    /* ========== STATE VARIABLES ========== */

  // Vault's address
  ILevelARBLongSLLPVault public immutable vault;
  // Vault's manager address
  ILevelARBLongSLLPManager public immutable manager;
  // Level liquidity pool
  ILiquidityPool public immutable liquidityPool;
  // Level pool lens
  IPoolLens public immutable poolLens;
  // Chainlink oracle
  IChainlinkOracle public immutable chainlinkOracle;
  // Steadefi deployed Level ARB oracle
  ILevelARBOracle public immutable levelARBOracle;
  // LLP stake pool
  ILevelMasterV2 public immutable sllpStakePool;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant USDT = 0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9;
  address public constant USDC = 0xaf88d065e77c8cC2239327C5EDb3A432268e5831;
  address public constant SLLP = 0x5573405636F4b895E511C9C54aAfbefa0E7Ee458;

  /* ========== MAPPINGS ========== */

  // Mapping of approved tokens
  mapping(address => bool) public tokens;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _manager Manager contract
    * @param _liquidityPool Level liquidity pool
    * @param _poolLens Level pool lens
    * @param _chainlinkOracle Chainlink oracle
    * @param _levelARBOracle Steadefi deployed Level ARB oracle
    * @param _sllpStakePool SLLP stake pool
  */
  constructor(
    ILevelARBLongSLLPVault _vault,
    ILevelARBLongSLLPManager _manager,
    ILiquidityPool _liquidityPool,
    IPoolLens _poolLens,
    IChainlinkOracle _chainlinkOracle,
    ILevelARBOracle _levelARBOracle,
    ILevelMasterV2 _sllpStakePool
  ) {
    tokens[WETH] = true;
    tokens[WBTC] = true;
    tokens[USDT] = true;
    tokens[USDC] = true;
    tokens[SLLP] = true;

    vault = _vault;
    manager = _manager;
    liquidityPool = _liquidityPool;
    poolLens = _poolLens;
    chainlinkOracle = _chainlinkOracle;
    levelARBOracle = _levelARBOracle;
    sllpStakePool = _sllpStakePool;
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the total value of token assets held by the manager; asset = debt + equity
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue() public view returns (uint256) {
    return (sllpPrice(false) * manager.lpAmt() / SAFE_MULTIPLIER);
  }

  /**
    * Returns the total value of token assets held by the manager; asset = debt + equity
    * Allows _sllpPrice to be passed to save gas from recurring calls by external contract(s)
    * @param _sllpPrice    Price of SLLP token in 1e18
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValueWithPrice(uint256 _sllpPrice) external view returns (uint256) {
    return (_sllpPrice * manager.lpAmt() / SAFE_MULTIPLIER);
  }

  /**
    * Returns the value of token debt held by the manager
    * @return debtValue   Value of all debt in 1e18
  */
  function debtValue() public view returns (uint256) {
    return tokenValue(USDT, manager.debtAmt());
  }

  /**
    * Returns the value of token equity held by the manager; equity = asset - debt
    * @return equityValue   Value of total equity in 1e18
  */
  function equityValue() public view returns (uint256) {
    uint256 _assetValue = assetValue();
    uint256 _debtValue = debtValue();
    // in underflow condition return 0
    if (_debtValue > _assetValue) return 0;
    unchecked {
      return (_assetValue - _debtValue);
    }
  }

  /**
    * Returns all SLLP asset token addresses and current weights
    * @return tokenAddresses array of whitelisted tokens
    * @return tokenAmts array of token amts in 1e18
  */
  function assetAmt() public view returns (address[4] memory, uint256[4] memory) {
    address[4] memory tokenAddresses = [WETH, WBTC, USDT, USDC];
    uint256[4] memory tokenAmts;

    uint256 _lpAmt = manager.lpAmt();
    uint256 _totalLpSupply = IERC20(SLLP).totalSupply();

    for (uint256 i = 0; i < tokenAddresses.length;) {
      uint256 _assetAmt = poolLens.getAssetAum(SLLP, tokenAddresses[i], false)
                          * SAFE_MULTIPLIER
                          / chainlinkOracle.consultIn18Decimals(tokenAddresses[i]);

      tokenAmts[i] = _assetAmt * _lpAmt / _totalLpSupply / 1e12 / 10**(18 - IERC20(tokenAddresses[i]).decimals());

      unchecked { i ++; }
    }

    return (tokenAddresses, tokenAmts);
  }

  /**
    * Returns the amt of token debt held by manager
    * @return debtAmt   Amt of token debt in token decimals
  */
  function debtAmt() public view returns (uint256) {
    return manager.debtAmt();
  }

  /**
    * Returns the amt of LP tokens held by manager
    * @return lpAmt   Amt of LP tokens in 1e18
  */
  function lpAmt() public view returns (uint256) {
    return manager.lpAmt();
  }

  /**
    * Returns the current leverage (asset / equity)
    * @return leverage   Current leverage in 1e18
  */
  function leverage() public view returns (uint256) {
    if (assetValue() == 0 || equityValue() == 0) return 0;
    return assetValue() * SAFE_MULTIPLIER / equityValue();
  }

  /**
    * Debt ratio: token debt value / total asset value
    * @return debtRatio   Current debt ratio % in 1e18
  */
  function debtRatio() public view returns (uint256) {
    if (assetValue() == 0) return 0;
    return debtValue() * SAFE_MULTIPLIER / assetValue();
  }

  /**
    * Convert token amount to value using oracle price
    * @param _token Token address
    * @param _amt Amount of token in token decimals
    @ @return tokenValue Token value in 1e18
  */
  function tokenValue(address _token, uint256 _amt) public view returns (uint256) {
    return _amt * 10**(18 - IERC20(_token).decimals())
                * chainlinkOracle.consultIn18Decimals(_token)
                / SAFE_MULTIPLIER;
  }

  /**
    * Gets price of SLLP token
    * @param _bool true for maximum price, false for minimum price
    * @return sllpPrice price of SLLP in 1e18
   */
  function sllpPrice(bool _bool) public view returns (uint256) {
    return levelARBOracle.getLLPPrice(SLLP, _bool) / 1e12;
  }

  /**
    * Returns the current token weight
    * @param _token   token's address
    * @return tokenWeight token weight in 1e18
  */
  function currentTokenWeight(address _token) public view returns (uint256) {
    if (!tokens[_token]) revert Errors.InvalidDepositToken();

    return poolLens.getAssetAum(SLLP, _token, false)
           * 1e18
           / poolLens.getTrancheValue(SLLP, false);
  }

  /**
    * Returns all whitelisted token addresses and current weights
    * Hardcoded to be WETH, WBTC, USDT, USDC
    * @return tokenAddresses array of whitelisted tokens
    * @return tokenWeight array of token weights in 1e18
  */
  function currentTokenWeights() public view returns (address[4] memory, uint256[4] memory) {
    address[4] memory tokenAddresses = [WETH, WBTC, USDT, USDC];
    uint256[4] memory tokenWeight;

    for (uint256 i = 0; i < tokenAddresses.length;) {
      tokenWeight[i] = currentTokenWeight(tokenAddresses[i]);
      unchecked { i ++; }
    }

    return (tokenAddresses, tokenWeight);
  }

  /**
    * Returns the target token weight
    * @param _token   token's address
    * @return tokenWeight token weight in 1e18
  */
  function targetTokenWeight(address _token) public view returns (uint256) {
    if (!tokens[_token]) revert Errors.InvalidDepositToken();

    // normalize weights in 1e3 to 1e18 by multiplying by 1e15
    return liquidityPool.targetWeights(_token) * 1e15;
  }

  /**
    * Returns all whitelisted token addresses and target weights
    * Hardcoded to be WETH, WBTC, USDT, USDC
    * @return tokenAddresses array of whitelisted tokens
    * @return tokenWeight array of token weights in 1e18
  */
  function targetTokenWeights() public view returns (address[4] memory, uint256[4] memory) {
    address[4] memory tokenAddresses = [WETH, WBTC, USDT, USDC];
    uint256[4] memory tokenWeight;

    for (uint256 i = 0; i < tokenAddresses.length;) {
      tokenWeight[i] = targetTokenWeight(tokenAddresses[i]);
      unchecked { i ++; }
    }

    return (tokenAddresses, tokenWeight);
  }

  /**
    * Get tranche LLP value
    * @param _token  Address of LLP
    * @param _bool true for maximum price, false for minimum price
    * @return tranche value in 1e30
  */
  function getTrancheValue(address _token, bool _bool) public view returns (uint256) {
    return liquidityPool.getTrancheValue(_token, _bool);
  }

  /**
    * Get total value of liqudiity pool across all LLPs in USD
    * @return pool value in 1e30
  */
  function getPoolValue() public view returns (uint256) {
    return liquidityPool.getPoolValue(false);
  }

  /**
    * To get additional deposit value (in USD) vault can accept based on lending pools available liquidity
    @ @return additionalCapacity Additional capacity in USDT value 1e18
  */
  function additionalCapacity() public view returns (uint256) {
    ILevelARBLongSLLPVault.VaultConfig memory _vaultConfig = vault.vaultConfig();

    address lendingPool = manager.lendingPoolUSDT();

    uint256 lendPoolMax = tokenValue(address(USDT), ILendingPool(lendingPool).totalAvailableSupply())
      * SAFE_MULTIPLIER
      / (_vaultConfig.targetLeverage - 1e18);

    return lendPoolMax;
  }

  /**
    * External function to get soft capacity vault can hold based on lending pool available liquidity and current equity value
    @ @return capacity soft capacity of vault
  */
  function capacity() external view returns (uint256) {
    return additionalCapacity() + equityValue();
  }
}

