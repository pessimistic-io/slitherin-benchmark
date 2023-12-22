// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "./SafeCast.sol";
import "./IERC20Metadata.sol";
import "./ICamelotVault.sol";
import "./ICamelotManager.sol";
import "./ICamelotReader.sol";
import "./ILendingPool.sol";
import "./IChainlinkOracle.sol";
import "./ICamelotOracle.sol";
import "./ICamelotSpNft.sol";

contract CamelotReader is ICamelotReader {
  using SafeCast for uint256;

  /* ========== STATE VARIABLES ========== */

  // e.g. WAVAX
  IERC20 public immutable tokenA;
  // e.g USDCe
  IERC20 public immutable tokenB;
  // Vault's address
  ICamelotVault public immutable vault;
  // Vault's manager address
  ICamelotManager public immutable manager;
  // Token A Lending pool
  ILendingPool public immutable tokenALendingPool;
  // Token B Lending pool
  ILendingPool public immutable tokenBLendingPool;
  // Chainlink contract
  IChainlinkOracle public immutable chainlinkOracle;
  // Camelot Oracle contract
  ICamelotOracle public immutable camelotOracle;
  // Camelot SPNFT contract
  ICamelotSpNft public immutable spNft;

  /* ========== CONSTANTS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== CONSTRUCTOR ========== */

  /**
    * @param _vault Vault contract
    * @param _manager Manager contract
    * @param _chainlinkOracle Chainlink oracle contract
    * @param _camelotOracle Camelot oracle contract
  */
  constructor(
    ICamelotVault _vault,
    ICamelotManager _manager,
    IChainlinkOracle _chainlinkOracle,
    ICamelotOracle _camelotOracle
  ) {
    vault = _vault;
    manager = _manager;
    tokenA = IERC20(vault.tokenA());
    tokenB = IERC20(vault.tokenB());
    chainlinkOracle = _chainlinkOracle;
    camelotOracle = _camelotOracle;
    tokenALendingPool = ILendingPool(manager.tokenALendingPool());
    tokenBLendingPool = ILendingPool(manager.tokenBLendingPool());
    spNft = ICamelotSpNft(manager.spNft());
  }

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * Returns the total value of token A & token B assets held by the manager;
    * asset = debt + equity
    * @param _addProtocolFees   Boolean to include pending protocol fees or not
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue(bool _addProtocolFees) public view returns (uint256) {
    return lpAmt()
           * camelotOracle.getLpTokenValue(manager.lpToken(), _addProtocolFees)
           * 1e10
           / SAFE_MULTIPLIER;
  }

  /**
    * Returns the value of token A & token B debt held by the manager
    * @return debtValue   Value of token A and token B debt in 1e18
  */
  function debtValue() public view returns (uint256, uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = debtAmt();
    return (
      tokenValue(address(tokenA), _tokenADebtAmt),
      tokenValue(address(tokenB), _tokenBDebtAmt)
    );
  }

  /**
    * Returns the value of token A & token B equity held by the manager;
    * equity = asset - debt
    * Includes any pending protocol fees which are added to lp token total supply
    * by calling the getLpTokenReservesAddProtocolFees function
    * @param _addProtocolFees   Boolean to include pending protocol fees or not
    * @return equityValue   Value of total equity in 1e18
  */
  function equityValue(bool _addProtocolFees) public view returns (uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = debtAmt();

    uint256 _assetValue = assetValue(_addProtocolFees);

    uint256 _debtValue = tokenValue(address(tokenA), _tokenADebtAmt)
                         + tokenValue(address(tokenB), _tokenBDebtAmt);

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
    (uint256 _tokenAAssetAmt, uint256 _tokenBAssetAmt) =
      camelotOracle.getLpTokenReserves(
      lpAmt(),
      address(tokenA),
      address(tokenB),
      manager.lpToken()
    );
    return (_tokenAAssetAmt, _tokenBAssetAmt);
  }

  /**
    * Returns the amt of token A & token B debt held by manager
    * @return debtAmt   Amt of token A and token B debt in token decimals
  */
  function debtAmt() public view returns (uint256, uint256) {
    return (
      tokenALendingPool.maxRepay(address(manager)),
      tokenBLendingPool.maxRepay(address(manager))
    );
  }

  /**
    * Returns the amt of LP tokens held by manager
    * @return lpAmt   Amt of LP tokens in 1e18
  */
  function lpAmt() public view returns (uint256) {
    uint256 positionId = manager.positionId();
    (uint256 amount,,,,,,,) = spNft.getStakingPosition(positionId);

    return amount;
  }

  /**
    * Returns the amt of LP tokens held by manager
    * @return lpAmtWithMultiplier   Amt of LP tokens with multiplier in 1e18
  */
  function lpAmtWithMultiplier() public view returns (uint256) {
    uint256 positionId = manager.positionId();
    (,uint256 amountWithMultiplier,,,,,,) = spNft.getStakingPosition(positionId);

    return amountWithMultiplier;
  }

  /**
    * Returns the current leverage (asset / equity)
    * @return leverage   Current leverage in 1e18
  */
  function leverage() public view returns (uint256) {
    if (assetValue(false) == 0 || equityValue(false) == 0) return 0;
    return assetValue(false) * SAFE_MULTIPLIER / equityValue(false);
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
    (uint256 _tokenAAmt,) = assetAmt();
    (uint256 _tokenADebtAmt,) = debtAmt();

    if (_tokenAAmt == 0 && _tokenADebtAmt == 0) return 0;

    bool isPositive = _tokenAAmt >= _tokenADebtAmt;

    uint256 unsignedDelta = isPositive ?
      _tokenAAmt - _tokenADebtAmt :
      _tokenADebtAmt - _tokenAAmt;

    int256 signedDelta = (unsignedDelta
      * chainlinkOracle.consultIn18Decimals(address(tokenA))
      / equityValue(false)).toInt256();

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
    if (assetValue(false) == 0) return 0;
    return (tokenADebtValue + tokenBDebtValue) * SAFE_MULTIPLIER / assetValue(false);
  }

  /**
    * Convert token amount to value using oracle price
    * @param _token Token address
    * @param _amt Amount of token in token decimals
    @ @return tokenValue Token value in 1e18
  */
  function tokenValue(address _token, uint256 _amt) public view returns (uint256) {
    return _amt * 10**(18 - IERC20Metadata(_token).decimals())
                * chainlinkOracle.consultIn18Decimals(_token)
                / SAFE_MULTIPLIER;
  }

  /**
    * To get additional capacity vault can hold based on lending pool available liquidity
    @ @return additionalCapacity Additional capacity vault can hold based on lending pool available liquidity
  */
  function additionalCapacity() public view returns (uint256) {
    ICamelotVault.VaultConfig memory _vaultConfig = vault.getVaultConfig();

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
    return additionalCapacity() + equityValue(false);
  }
}

