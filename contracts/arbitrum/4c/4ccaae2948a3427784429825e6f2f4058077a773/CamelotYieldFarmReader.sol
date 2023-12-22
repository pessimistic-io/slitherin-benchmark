// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeCast.sol";
import "./IERC20.sol";
import "./ICamelotYieldFarmVault.sol";
import "./ICamelotYieldFarmManager.sol";
import "./ILendingPool.sol";
import "./IChainlinkOracle.sol";


contract CamelotYieldFarmReader {
  using SafeCast for uint256;

  /* ========== STATE VARIABLES ========== */

  // Vault's address
  ICamelotYieldFarmVault public immutable vault;
  // Vault's manager address
  ICamelotYieldFarmManager public immutable manager;
  // WAVAX
  IERC20 public immutable tokenA;
  // USDC
  IERC20 public immutable tokenB;
  // Chainlink contract
  IChainlinkOracle public immutable chainlinkOracle;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _manager Manager contract
  */
  constructor(
    ICamelotYieldFarmVault _vault,
    ICamelotYieldFarmManager _manager
  ) {
    require(address(_vault) != address(0), "Vault address is invalid");
    require(address(_manager) != address(0), "Manager address is invalid");

    vault = _vault;
    manager = _manager;
    tokenA = IERC20(vault.tokenA());
    tokenB = IERC20(vault.tokenB());
    chainlinkOracle = IChainlinkOracle(vault.chainlinkOracle());
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the total value of token A & token B assets held by the manager;
    * asset = debt + equity
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue() public view returns (uint256) {
    (uint256 _tokenAAssetAmt, uint256 _tokenBAssetAmt) = manager.assetInfo();

    return tokenValue(address(tokenA), _tokenAAssetAmt)
      + tokenValue(address(tokenB), _tokenBAssetAmt);
  }

  /**
    * Returns the value of token A & token B debt held by the manager
    * @return debtValue   Value of token A and token B debt in 1e18
  */
  function debtValue() public view returns (uint256, uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = manager.debtInfo();
    return (tokenValue(address(tokenA), _tokenADebtAmt),
      tokenValue(address(tokenB), _tokenBDebtAmt));
  }

  /**
    * Returns the value of token A & token B equity held by the manager;
    * equity = asset - debt
    * @return equityValue   Value of total equity in 1e18
  */
  function equityValue() public view returns (uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = manager.debtInfo();
    (uint256 _tokenAAssetAmt, uint256 _tokenBAssetAmt) = manager.assetInfo();

    uint256 _assetValue = tokenValue(address(tokenA), _tokenAAssetAmt) +
      tokenValue(address(tokenB), _tokenBAssetAmt);
    uint256 _debtValue = tokenValue(address(tokenA), _tokenADebtAmt) +
      tokenValue(address(tokenB), _tokenBDebtAmt);

    // in underflow condition return 0
    unchecked {
      if (_assetValue < _debtValue) return 0;

      return _assetValue - _debtValue;
    }
  }

  /**
    * Returns the amt of token A & token B assets held by manager
    * @return assetAmt   Amt of token A and token B asset in asset decimals
  */
  function assetAmt() public view returns (uint256, uint256) {
    (uint256 _tokenAAssetAmt, uint256 _tokenBAssetAmt) = manager.assetInfo();
    return (_tokenAAssetAmt, _tokenBAssetAmt);
  }

  /**
    * Returns the amt of token A & token B debt held by manager
    * @return debtAmt   Amt of token A and token B debt in token decimals
  */
  function debtAmt() public view returns (uint256, uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = manager.debtInfo();
    return (_tokenADebtAmt, _tokenBDebtAmt);
  }

  /**
    * Returns the amt of LP tokens held by manager
    * @return lpAmt   Amt of LP tokens in 1e18
  */
  function lpAmt() public view returns (uint256) {
    return manager.lpTokenAmt();
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
    * Returns the current delta (tokenA equityValue / vault equityValue)
    * Delta refers to the position exposure of this vault's strategy to the
    * underlying volatile asset. This function assumes that tokenA will always
    * be the non-stablecoin token and tokenB always being the stablecoin
    * The delta can be a negative value
    * @return delta  Current delta (0 = Neutral, > 0 = Long, < 0 = Short) in 1e18
  */
  function delta() public view returns (int256) {
    (uint256 _tokenAAmt,) = manager.assetInfo();
    (uint256 _tokenADebtAmt,) = manager.debtInfo();

    if (_tokenAAmt == 0 && _tokenADebtAmt == 0) return 0;

    bool isPositive = _tokenAAmt >= _tokenADebtAmt;

    uint256 unsignedDelta = isPositive ?
      _tokenAAmt - _tokenADebtAmt :
      _tokenADebtAmt - _tokenAAmt;

    int256 signedDelta = (unsignedDelta
      * chainlinkOracle.consultIn18Decimals(address(tokenA))
      / equityValue()).toInt256();

    if (isPositive) return signedDelta;
    else return -signedDelta;
  }

  /**
    * Returns the debt ratio (tokenA and tokenB debtValue) / (total assetValue)
    * When assetValue is 0, we assume the debt ratio to also be 0
    * @return debtRatio   Current debt ratio % in 1e18
  */
  function debtRatio() public view returns (uint256) {
    (uint256 tokenADebtValue, uint256 tokenBDebtValue) = debtValue();
    if (assetValue() == 0) return 0;
    return (tokenADebtValue + tokenBDebtValue) * SAFE_MULTIPLIER / assetValue();
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
    * To get additional capacity vault can hold based on lending pool available liquidity
    @ @return additionalCapacity Additional capacity vault can hold based on lending pool available liquidity
  */
  function additionalCapacity() public view returns (uint256) {
    ICamelotYieldFarmVault.VaultConfig memory _vaultConfig = vault.vaultConfig();

    address tokenALendingPool = manager.tokenALendingPool();
    address tokenBLendingPool = manager.tokenBLendingPool();

    uint256 lendPoolAMax = tokenValue(address(tokenA), ILendingPool(tokenALendingPool).totalAvailableSupply())
      * SAFE_MULTIPLIER
      / (_vaultConfig.tokenADebtRatio
      * (_vaultConfig.targetLeverage - SAFE_MULTIPLIER)
      / SAFE_MULTIPLIER);

    uint256 lendPoolBMax = tokenValue(address(tokenB), ILendingPool(tokenBLendingPool).totalAvailableSupply())
      * SAFE_MULTIPLIER
      / (_vaultConfig.tokenBDebtRatio
      * (_vaultConfig.targetLeverage - SAFE_MULTIPLIER)
      / SAFE_MULTIPLIER);

    return lendPoolAMax > lendPoolBMax ? lendPoolBMax : lendPoolAMax;
  }

  /**
    * External function to get soft capacity vault can hold based on lending pool available liquidity and current equity value
    @ @return capacity soft capacity of vault
  */
  function capacity() external view returns (uint256) {
    return additionalCapacity() + equityValue();
  }
}

