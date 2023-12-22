// SPDX-License-Identifier: MIT
pragma solidity 0.8.21;

import { IERC20 } from "./IERC20.sol";
import { IERC20Metadata } from "./IERC20Metadata.sol";
import { SafeCast } from "./SafeCast.sol";
import { GMXTypes } from "./GMXTypes.sol";

library GMXReader {
  using SafeCast for uint256;

  /* ========== CONSTANTS FUNCTIONS ========== */

  uint256 public constant SAFE_MULTIPLIER = 1e18;

  /* ========== VIEW FUNCTIONS ========== */

  /**
    * @dev Returns the value of each share token; total equity / share token supply
    * @param self Vault store data
    * @return svTokenValue   Value of each share token in 1e18
  */
  function svTokenValue(GMXTypes.Store storage self) public view returns (uint256) {
    uint256 equityValue_ = equityValue(self);
    uint256 totalSupply_ = IERC20(address(self.vault)).totalSupply();
    if (equityValue_ == 0 || totalSupply_ == 0) return SAFE_MULTIPLIER;
    return equityValue_ * SAFE_MULTIPLIER / totalSupply_;
  }

  /**
    * @dev Amount of share pending for minting as a form of mgmt fee
    * @param self Vault store data
    * @return pendingMgmtFee in 1e18
  */
  function pendingMgmtFee(GMXTypes.Store storage self) public view returns (uint256) {
    uint256 totalSupply_ = IERC20(address(self.vault)).totalSupply();
    uint256 _secondsFromLastCollection = block.timestamp - self.lastFeeCollected;
    return (totalSupply_ * self.mgmtFeePerSecond * _secondsFromLastCollection) / SAFE_MULTIPLIER;
  }

  /**
    * @dev Conversion of equity value to svToken shares
    * @param self Vault store data
    * @param value Equity value change after deposit in 1e18
    * @param currentEquity Current equity value of vault in 1e18
    * @return sharesAmt Shares amt in 1e18
  */
  function valueToShares(
    GMXTypes.Store storage self,
    uint256 value,
    uint256 currentEquity
  ) public view returns (uint256) {
    uint256 _sharesSupply = IERC20(address(self.vault)).totalSupply() + pendingMgmtFee(self);
    if (_sharesSupply == 0 || currentEquity == 0) return value;
    return value * _sharesSupply / currentEquity;
  }

  /**
    * @dev Convert token amount to value using oracle price
    * @param self Vault store data
    * @param token Token address
    * @param amt Amount of token in token decimals
    @ @return tokenValue Token USD value in 1e18
  */
  function convertToUsdValue(
    GMXTypes.Store storage self,
    address token,
    uint256 amt
  ) public view returns (uint256) {
    return amt * 10**(18 - IERC20Metadata(token).decimals())
                * self.chainlinkOracle.consultIn18Decimals(token)
                / SAFE_MULTIPLIER;
  }

  /**
    * @dev Return % weighted value of tokens in LP
    * @param self Vault store data
    @ @return (tokenAWeight, tokenBWeight) in 1e18; e.g. 50% = 5e17
  */
  function tokenWeights(GMXTypes.Store storage self) public view returns (uint256, uint256) {
    // Get amounts of tokenA and tokenB in liquidity pool in token decimals
    (uint256 _reserveA, uint256 _reserveB) = self.gmxOracle.getLpTokenReserves(
      address(self.lpToken),
      address(self.tokenA),
      address(self.tokenA),
      address(self.tokenB)
    );

    // Get value of tokenA and tokenB in 1e18
    uint256 _tokenAValue = convertToUsdValue(self, address(self.tokenA), _reserveA);
    uint256 _tokenBValue = convertToUsdValue(self, address(self.tokenB), _reserveB);

    uint256 _totalLpValue = _tokenAValue + _tokenBValue;

    return (
      _tokenAValue * SAFE_MULTIPLIER / _totalLpValue,
      _tokenBValue * SAFE_MULTIPLIER / _totalLpValue
    );
  }

  /**
    * @dev Returns the total value of token A & token B assets held by the vault;
    * asset = debt + equity
    * @param self Vault store data
    * @return assetValue   Value of total assets in 1e18
  */
  function assetValue(GMXTypes.Store storage self) public view returns (uint256) {
    return lpAmt(self) * self.gmxOracle.getLpTokenValue(
      address(self.lpToken),
      address(self.tokenA),
      address(self.tokenA),
      address(self.tokenB),
      false,
      false
    ) / SAFE_MULTIPLIER;
  }

  /**
    * @dev Returns the value of token A & token B debt held by the vault
    * @param self Vault store data
    * @return debtValue   Value of token A and token B debt in 1e18
  */
  function debtValue(GMXTypes.Store storage self) public view returns (uint256, uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = debtAmt(self);
    return (
      convertToUsdValue(self, address(self.tokenA), _tokenADebtAmt),
      convertToUsdValue(self, address(self.tokenB), _tokenBDebtAmt)
    );
  }

  /**
    * @dev Returns the value of token A & token B equity held by the vault;
    * equity = asset - debt
    * @param self Vault store data
    * @return equityValue   Value of total equity in 1e18
  */
  function equityValue(GMXTypes.Store storage self) public view returns (uint256) {
    (uint256 _tokenADebtAmt, uint256 _tokenBDebtAmt) = debtAmt(self);

    uint256 assetValue_ = assetValue(self);

    uint256 _debtValue = convertToUsdValue(self, address(self.tokenA), _tokenADebtAmt)
                         + convertToUsdValue(self, address(self.tokenB), _tokenBDebtAmt);

    // in underflow condition return 0
    unchecked {
      if (assetValue_ < _debtValue) return 0;

      return assetValue_ - _debtValue;
    }
  }

  /**
    * @dev Returns the amt of token A & token B assets held by vault
    * @param self Vault store data
    * @return assetAmt   Amt of token A and token B asset in asset decimals
  */
  function assetAmt(GMXTypes.Store storage self) public view returns (uint256, uint256) {
    (uint256 _reserveA, uint256 _reserveB) = self.gmxOracle.getLpTokenReserves(
      address(self.lpToken),
      address(self.tokenA),
      address(self.tokenA),
      address(self.tokenB)
    );

    return (
      _reserveA * SAFE_MULTIPLIER * lpAmt(self) / self.lpToken.totalSupply() / SAFE_MULTIPLIER,
      _reserveB * SAFE_MULTIPLIER * lpAmt(self) / self.lpToken.totalSupply() / SAFE_MULTIPLIER
    );
  }

  /**
    * @dev Returns the amt of token A & token B debt held by vault
    * @param self Vault store data
    * @return debtAmt   Amt of token A and token B debt in token decimals
  */
  function debtAmt(GMXTypes.Store storage self) public view returns (uint256, uint256) {
    return (
      self.tokenALendingVault.maxRepay(address(self.vault)),
      self.tokenBLendingVault.maxRepay(address(self.vault))
    );
  }

  /**
    * @dev Returns the amt of LP tokens held by vault
    * @param self Vault store data
    * @return lpAmt   Amt of LP tokens in 1e18
  */
  function lpAmt(GMXTypes.Store storage self) public view returns (uint256) {
    return self.lpToken.balanceOf(address(self.vault));
  }

  /**
    * @dev Returns the current leverage (asset / equity)
    * @param self Vault store data
    * @return leverage   Current leverage in 1e18
  */
  function leverage(GMXTypes.Store storage self) public view returns (uint256) {
    if (assetValue(self) == 0 || equityValue(self) == 0) return 0;
    return assetValue(self) * SAFE_MULTIPLIER / equityValue(self);
  }

  /**
    * @dev Returns the current delta (tokenA equityValue / vault equityValue)
    * Delta refers to the position exposure of this vault's strategy to the
    * underlying volatile asset. This function assumes that tokenA will always
    * be the non-stablecoin token and tokenB always being the stablecoin
    * The delta can be a negative value
    * @param self Vault store data
    * @return delta  Current delta (0 = Neutral, > 0 = Long, < 0 = Short) in 1e18
  */
  function delta(GMXTypes.Store storage self) public view returns (int256) {
    (uint256 _tokenAAmt,) = assetAmt(self);
    (uint256 _tokenADebtAmt,) = debtAmt(self);

    if (_tokenAAmt == 0 && _tokenADebtAmt == 0) return 0;

    bool _isPositive = _tokenAAmt >= _tokenADebtAmt;

    uint256 _unsignedDelta = _isPositive ?
      _tokenAAmt - _tokenADebtAmt :
      _tokenADebtAmt - _tokenAAmt;

    int256 signedDelta = (_unsignedDelta
      * self.chainlinkOracle.consultIn18Decimals(address(self.tokenA))
      / equityValue(self)).toInt256();

    if (_isPositive) return signedDelta;
    else return -signedDelta;
  }

  /**
    * @dev Returns the debt ratio (tokenA and tokenB debtValue) / (total assetValue)
    * When assetValue is 0, we assume the debt ratio to also be 0
    * @param self Vault store data
    * @return debtRatio   Current debt ratio % in 1e18
  */
  function debtRatio(GMXTypes.Store storage self) public view returns (uint256) {
    (uint256 _tokenADebtValue, uint256 _tokenBDebtValue) = debtValue(self);
    if (assetValue(self) == 0) return 0;
    return (_tokenADebtValue + _tokenBDebtValue) * SAFE_MULTIPLIER / assetValue(self);
  }

  /**
    * @dev To get additional capacity vault can hold based on lending vault available liquidity
    * @param self Vault store data
    @ @return additionalCapacity Additional capacity vault can hold based on lending vault available liquidity
  */
  function additionalCapacity(GMXTypes.Store storage self) public view returns (uint256) {
    uint256 _additionalCapacity;

    // Long strategy only borrows short token (typically stablecoin)
    if (self.delta == GMXTypes.Delta.Long) {
      _additionalCapacity = convertToUsdValue(
        self,
        address(self.tokenB),
        self.tokenBLendingVault.totalAvailableAsset()
      ) * SAFE_MULTIPLIER
        / ((self.leverage - 1e18) / SAFE_MULTIPLIER)
        / SAFE_MULTIPLIER;
    }

    // Neutral strategy borrows both long (typical volatile) and short token (typically stablecoin)
    // Amount of long token to borrow is equivalent to longTokenWeight of deposited value x leverage
    // Amount of short token to borrow is based on the remaining borrow value after borrowing long token
    if (self.delta == GMXTypes.Delta.Neutral) {
      (uint256 _tokenAWeight, ) = tokenWeights(self);

      uint256 _maxTokenALending = convertToUsdValue(
        self,
        address(self.tokenA),
        self.tokenALendingVault.totalAvailableAsset()
      ) * SAFE_MULTIPLIER
        / (self.leverage * _tokenAWeight / SAFE_MULTIPLIER);

      uint256 _maxTokenBLending = convertToUsdValue(
        self,
        address(self.tokenB),
        self.tokenBLendingVault.totalAvailableAsset()
      ) * SAFE_MULTIPLIER
        / ((self.leverage - 1e18) -
          (self.leverage * _tokenAWeight / SAFE_MULTIPLIER));

      _additionalCapacity = _maxTokenALending > _maxTokenBLending ? _maxTokenBLending : _maxTokenALending;
    }

    return _additionalCapacity;
  }

  /**
    * @dev External function to get soft capacity vault can hold based on lending vault available liquidity and current equity
    * @param self Vault store datavalue
    @ @return capacity soft capacity of vault
  */
  function capacity(GMXTypes.Store storage self) public view returns (uint256) {
    return additionalCapacity(self) + equityValue(self);
  }
}

