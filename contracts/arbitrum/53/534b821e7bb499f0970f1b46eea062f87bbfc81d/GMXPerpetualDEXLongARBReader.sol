// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./IERC20.sol";
import "./IGMXPerpetualDEXLongVault.sol";
import "./IGMXPerpetualDEXLongManager.sol";
import "./ILendingPool.sol";
import "./IChainlinkOracle.sol";
import "./IGMXVault.sol";
import "./IGMXGLPManager.sol";
import "./IGMXStakePool.sol";

contract GMXPerpetualDEXLongARBReader {
    /* ========== STATE VARIABLES ========== */

  // Vault's address
  IGMXPerpetualDEXLongVault public immutable vault;
  // Vault's manager address
  IGMXPerpetualDEXLongManager public immutable manager;
  // Chainlink oracle
  IChainlinkOracle public immutable chainlinkOracle;
  // GMX Vault
  IGMXVault public immutable gmxVault;
  // GMX GLP Manager
  IGMXGLPManager public immutable glpManager;
  // GLP Stake pool
  IGMXStakePool public immutable stakePool;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;
  address public constant WETH = 0x82aF49447D8a07e3bd95BD0d56f35241523fBab1;
  address public constant WBTC = 0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f;
  address public constant USDC = 0xFF970A61A04b1cA14834A43f5dE4533eBDDB5CC8;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _manager Manager contract
    * @param _chainlinkOracle Chainlink oracle
    * @param _gmxVault GMX Vault
    * @param _glpManager GMX GLP Manager
    * @param _stakePool GLP Stake pool
  */
  constructor(
    IGMXPerpetualDEXLongVault _vault,
    IGMXPerpetualDEXLongManager _manager,
    IChainlinkOracle _chainlinkOracle,
    IGMXVault _gmxVault,
    IGMXGLPManager _glpManager,
    IGMXStakePool _stakePool
  ) {
    vault = _vault;
    manager = _manager;
    chainlinkOracle = _chainlinkOracle;
    gmxVault = _gmxVault;
    glpManager = _glpManager;
    stakePool = _stakePool;
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the value of each vault share token; obtained by total equity divided by share token supply
    * @return svTokenValue   Value of each share token in 1e18
  */
   function svTokenValue() external view returns (uint256) {
    uint256 _equityValue = equityValue();
    if (_equityValue == 0 || vault.totalSupply() == 0) return SAFE_MULTIPLIER;
    return _equityValue * SAFE_MULTIPLIER / vault.totalSupply();
  }

  /**
    * Returns the total value of token assets held by the manager; asset = debt + equity
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue() public view returns (uint256) {
    return (glpPrice(false) * manager.lpAmt() / SAFE_MULTIPLIER);
  }

  /**
    * Returns the total value of token assets held by the manager; asset = debt + equity
    * Allows _glpPrice to be passed to save gas from recurring calls by external contract(s)
    * @param _glpPrice    Price of GLP token in 1e18
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValueWithPrice(uint256 _glpPrice) external view returns (uint256) {
    return (_glpPrice * manager.lpAmt() / SAFE_MULTIPLIER);
  }

  /**
    * Returns the value of token debt held by the manager
    * @return debtValue   Value of all debt in 1e18
  */
  function debtValue() public view returns (uint256) {
    return tokenValue(USDC, manager.debtAmt());
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
    * Returns all GLP asset token addresses and current weights
    * @return tokenAddresses array of whitelied tokens
    * @return tokenAmts array of token amts
  */
  function assetAmt() public view returns (address[] memory, uint256[] memory) {
    // get manager's glp balance
    uint256 _lpAmt = manager.lpAmt();
    // get total supply of glp
    uint256 glpTotalSupply = stakePool.totalSupply();
    // get total supply of USDG
    uint256 usdgSupply = getTotalUsdgAmount();

    // calculate manager's glp amt in USDG
    uint256 glpAmtInUsdg = (_lpAmt * SAFE_MULTIPLIER / glpTotalSupply)
      * usdgSupply
      / SAFE_MULTIPLIER;

    uint256 length = gmxVault.allWhitelistedTokensLength();
    address[] memory tokenAddresses = new address[](length);
    uint256[] memory tokenAmts = new uint256[](length);

    address whitelistedToken;
    bool isWhitelisted;
    uint256 tokenWeight;

    for (uint256 i = 0; i < length;) {
      // check if token is whitelisted
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        tokenAddresses[i] = whitelistedToken;
        // calculate token weight expressed in token amt
        tokenWeight = gmxVault.usdgAmounts(whitelistedToken) * SAFE_MULTIPLIER / usdgSupply;
        tokenAmts[i] = (tokenWeight * glpAmtInUsdg / SAFE_MULTIPLIER)
                      * SAFE_MULTIPLIER
                      / (gmxVault.getMinPrice(whitelistedToken) / 1e12);
      }
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
    * Gets price of GLP token
    * @param _bool true for maximum price, false for minimum price
    * @return glpPrice price of GLP in 1e18
   */
  function glpPrice(bool _bool) public view returns (uint256) {
    return glpManager.getPrice(_bool) / 1e12;
  }

  /**
    * Returns the desired token weight
    * @param _token   token's address
    * @return tokenWeight token weight in 1e18
  */
  function currentTokenWeight(address _token) public view returns (uint256) {
    uint256 usdgSupply = getTotalUsdgAmount();

    return gmxVault.usdgAmounts(_token) * SAFE_MULTIPLIER / usdgSupply;
  }

  /**
    * Returns all whitelisted token addresses and current weights
    * @return tokenAddress array of whitelied tokens
    * @return tokenWeight array of token weights in 1e18
  */
  function currentTokenWeights() public view returns (address[] memory, uint256[]memory) {
    uint256 usdgSupply = getTotalUsdgAmount();
    uint256 length = gmxVault.allWhitelistedTokensLength();

    address[] memory tokenAddress = new address[](length);
    uint256[] memory tokenWeight = new uint256[](length);

    address whitelistedToken;
    bool isWhitelisted;

    for (uint256 i = 0; i < length;) {
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        tokenAddress[i] = whitelistedToken;
        tokenWeight[i] = gmxVault.usdgAmounts(whitelistedToken)
          * (SAFE_MULTIPLIER)
          / (usdgSupply);
      }
      unchecked { i ++; }
    }

    return (tokenAddress, tokenWeight);
  }

  /**
    * Get total USDG supply
    * @return usdgSupply
  */
  function getTotalUsdgAmount() public view returns (uint256) {
    uint256 length = gmxVault.allWhitelistedTokensLength();
    uint256 usdgSupply;

    address whitelistedToken;
    bool isWhitelisted;

    for (uint256 i = 0; i < length;) {
      whitelistedToken = gmxVault.allWhitelistedTokens(i);
      isWhitelisted = gmxVault.whitelistedTokens(whitelistedToken);
      if (isWhitelisted) {
        usdgSupply += gmxVault.usdgAmounts(whitelistedToken);
      }
      unchecked { i += 1; }
    }
    return usdgSupply;
  }

  /**
    * To get additional capacity vault can hold based on lending pool available liquidity
    @ @return additionalCapacity Additional capacity in USDC value 1e18
  */
  function additionalCapacity() public view returns (uint256) {
    IGMXPerpetualDEXLongVault.VaultConfig memory _vaultConfig = vault.vaultConfig();

    address lendingPool = manager.lendingPoolUSDC();

    uint256 lendPoolMax = tokenValue(address(USDC), ILendingPool(lendingPool).totalAvailableSupply())
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

