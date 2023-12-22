// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.0;

/**
 * @title DUB Vault Contract
 * @notice The Vault contract stores assets. On a deposit, DUB will be minted
           and sent to the depositor. On a withdrawal, DUB will be burned and
           assets will be sent to the withdrawer. The Vault accepts deposits of
           interest from yield bearing strategies which will modify the supply
           of DUB.
 * @author Stabl Protocol Inc

 * @dev The following are the meaning of abbreviations used in the contracts
        PS: Primary Stable
        PSD: Primary Stable Decimals
 */

import { SafeERC20 } from "./SafeERC20.sol";
import { SafeMath } from "./SafeMath.sol";
import "./ReentrancyGuardUpgradeable.sol";
import { StableMath } from "./StableMath.sol";
import { IBuyback } from "./IBuyback.sol";
import { IWombatRouter } from "./IWombatRouter.sol";
import "./VaultStorage.sol";
import "./console.sol";

contract VaultCore is
  VaultStorage,
  ReentrancyGuardUpgradeable
{
  using SafeERC20 for IERC20;
  using StableMath for uint256;
  using SafeMath for uint256;

  /**
   * @dev Verifies that the rebasing is not paused.
   */
  modifier whenNotRebasePaused() {
    require(!rebasePaused, "Rebasing paused");
    _;
  }

  /**
   * @dev Verifies that the deposits are not paused.
   */
  modifier whenNotCapitalPaused() {
    require(!capitalPaused, "Capital paused");
    _;
  }

  modifier onlyGovernorOrRebaseManager() {
    require(
      (msg.sender == owner()) || rebaseManagers[msg.sender],
      "Caller is not the Governor or Rebase Manager or Dripper"
    );
    _;
  }

  function initialize(bool _rebasePaused, bool _capitalPaused,
    address _swapRouter, address[] calldata _assets, address[][] calldata _pathPools) external initializer {
    rebasePaused = _rebasePaused;
    capitalPaused = _capitalPaused;
    swapRouter = _swapRouter;
    require(_assets.length == _pathPools.length, "Length of the assets and pathPools arrays is not the same.");
    require(_assets.length > 0 && _pathPools.length > 0, "arrays should not be empty.");
    for(uint i; i < _assets.length; ++i){
      _setAssetsPoolPaths(_assets[i], _pathPools[i]);
    }
    __Ownable_init();
    __ReentrancyGuard_init();
  }

  /**
     * @dev Deposit a supported asset to the Vault and mint DUB. Asset will be swapped to 
            the PS and allocated to Quick Deposit Strategies
     * @param _asset Address of the asset being deposited
     * @param _amount Amount of the asset being deposited (decimals based on _asset)
     * @param _minimumDUBAmount Minimum DUB to mint (1e18)
     */
  function mint(
    address _asset,
    uint256 _amount,
    uint256 _minimumDUBAmount
  ) external whenNotCapitalPaused nonReentrant {
    _mint(_asset, _amount, _minimumDUBAmount);
    // Swap to primaryStable, if needed
    _swapAsset(_asset, primaryStableAddress);
    _quickAllocate();
  }

  /**
   * @dev Deposit a supported asset to the Vault and mint DUB.
   * @param _asset Address of the asset being deposited
   * @param _amount Amount of the asset being deposited (decimals based on _asset)
   * @param _minimumDUBAmount Minimum DUB to mint (1e18)
   */
  function _mint(
    address _asset,
    uint256 _amount,
    uint256 _minimumDUBAmount
  ) internal {
    require(assets[_asset], "Asset is not supported");
    require(_amount > 0, "Amount must be greater than 0");

    uint256 price = IOracle(priceProvider).price(_asset);
    if (price > 1e8) {
      price = 1e8;
    }
    require(price >= MINT_MINIMUM_ORACLE, "Asset price below Peg");
    uint256 assetDecimals = Helpers.getDecimals(_asset);
    // Scale up to 18 decimal
    uint256 unitAdjustedDeposit = _amount.scaleBy(18, assetDecimals);
    uint256 priceAdjustedDeposit = _amount.mulTruncateScale(
      price.scaleBy(18, 8), // Oracles have 8 decimal precision
      10 ** assetDecimals
    );

    if (_minimumDUBAmount > 0) {
      require(
        priceAdjustedDeposit >= _minimumDUBAmount,
        "Mint amount lower than minimum"
      );
    }

    emit Mint(msg.sender, priceAdjustedDeposit);

    // Rebase must happen before any transfers occur.
    if (unitAdjustedDeposit >= rebaseThreshold && !rebasePaused) {
      _rebase();
    }
    // Mint matching DUB
    dub.mint(msg.sender, priceAdjustedDeposit);
    // Transfer the deposited coins to the vault
    IERC20 asset = IERC20(_asset);

    asset.safeTransferFrom(msg.sender, address(this), _amount);
  }

  // In memoriam

  /**
   * @dev Withdraw a supported asset and burn DUB.
   * @param _amount Amount of DUB to burn
   * @param _minimumUnitAmount Minimum stablecoin units to receive in return
   */
  function redeem(
    uint256 _amount,
    uint256 _minimumUnitAmount
  ) external whenNotCapitalPaused nonReentrant {
    _redeem(_amount, _minimumUnitAmount);
  }

  /**
   * @dev Withdraw the PS against DUB and burn DUB.
   * @param _amount Amount of DUB to burn
   * @param _minimumUnitAmount Minimum stablecoin units to receive in return
   */
  function _redeem(uint256 _amount, uint256 _minimumUnitAmount) internal {
    require(_amount > 0, "Amount must be greater than 0");
    require(dub.balanceOf(msg.sender) >= _amount, "Insufficient Amount!");
    (
      uint256 output,
      uint256 backingValue,
      uint256 redeemFee
    ) = _calculateRedeemOutput(_amount);
    uint256 primaryStableDecimals = Helpers.getDecimals(primaryStableAddress);
    // Check that DUB is backed by enough assets
    uint256 _totalSupply = dub.totalSupply();
    if (maxSupplyDiff > 0) {
      // Allow a max difference of maxSupplyDiff% between
      // backing assets value and DUB total supply
      uint256 diff = _totalSupply.divPrecisely(backingValue);
      require(
        (diff > 1e18 ? diff.sub(1e18) : uint256(1e18).sub(diff)) <=
          maxSupplyDiff,
        "Backing supply liquidity error"
      );
    }
    if (_minimumUnitAmount > 0) {
      uint256 unitTotal = output.scaleBy(18, primaryStableDecimals);
      require(
        unitTotal >= _minimumUnitAmount,
        "Redeem amount lower than minimum"
      );
    }
    emit Redeem(msg.sender, _amount);

    // Send output
    require(output > 0, "Nothing to redeem");
    IERC20 primaryStable = IERC20(primaryStableAddress);
    address[] memory strategiesToWithdrawFrom = new address[](
      strategyWithWeights.length
    );
    uint256[] memory amountsToWithdraw = new uint256[](
      strategyWithWeights.length
    );
    uint256 totalAmount = primaryStable.balanceOf(address(this));
    if (
      (totalAmount < (output + redeemFee)) && (strategyWithWeights.length == 0)
    ) {
      revert("Source strats not set");
    }
    uint8 strategyIndex = 0;
    uint8 index = 0;
    while (
      (totalAmount < (output + redeemFee)) &&
      (strategyIndex < strategyWithWeights.length)
    ) {
      uint256 currentStratBal = IStrategy(
        strategyWithWeights[strategyIndex].strategy
      ).checkBalance();
      if (currentStratBal > 0) {
        if ((currentStratBal + totalAmount) > (output + redeemFee)) {
          strategiesToWithdrawFrom[index] = strategyWithWeights[strategyIndex]
            .strategy;
          amountsToWithdraw[index] =
            currentStratBal -
            ((currentStratBal + totalAmount) - (output + redeemFee));
          totalAmount +=
            currentStratBal -
            ((currentStratBal + totalAmount) - (output + redeemFee));
        } else {
          strategiesToWithdrawFrom[index] = strategyWithWeights[strategyIndex]
            .strategy;
          amountsToWithdraw[index] = 0; // 0 means withdraw all
          totalAmount += currentStratBal;
        }
        index++;
      }
      strategyIndex++;
    }
    require(
      totalAmount >= (output + redeemFee),
      "Not enough funds anywhere to redeem."
    );

    // Withdraw from strategies
    for (uint8 i = 0; i < strategyWithWeights.length; i++) {
      if (strategiesToWithdrawFrom[i] == address(0)) {
        break;
      }
      if (amountsToWithdraw[i] > 0) {
        IStrategy(strategiesToWithdrawFrom[i]).withdraw(
          address(this),
          primaryStableAddress,
          amountsToWithdraw[i]
        );
      } else {
        IStrategy(strategiesToWithdrawFrom[i]).withdrawAll();
      }
    }

    if (primaryStable.balanceOf(address(this)) < (output + redeemFee)) {
      redeemFee = primaryStable.balanceOf(address(this)) - output;
    }

    require(
      primaryStable.balanceOf(address(this)) >= (output + redeemFee),
      "Not enough funds after withdrawl."
    );

    primaryStable.safeTransfer(msg.sender, output);
    primaryStable.safeTransfer(teamAddress, redeemFee);

    dub.burn(msg.sender, _amount);

    // Remaining amount i.e redeem fees will be rebased for all other DUB holders

    // Until we can prove that we won't affect the prices of our assets
    // by withdrawing them, this should be here.
    // It's possible that a strategy was off on its asset total, perhaps
    // a reward token sold for more or for less than anticipated.
    if (_amount > rebaseThreshold && !rebasePaused) {
      _rebase();
    }
  }

    /**
     * @notice Withdraw PS against all the sender's DUB.
     * @param _minimumUnitAmount Minimum stablecoin units to receive in return
     */
    function redeemAll(
        uint256 _minimumUnitAmount
    ) external whenNotCapitalPaused nonReentrant {
      console.log("dub balance at redeemAll", dub.balanceOf(msg.sender));
        _redeem(dub.balanceOf(msg.sender), _minimumUnitAmount);
    }

  /**
   * @dev Allocate unallocated PS in the Vault to quick deposit strategies.
   **/
  function quickAllocate() external whenNotCapitalPaused nonReentrant {
    _quickAllocate();
  }

  /**
   * @dev Allocate unallocated PS in the Vault to quick deposit strategies.
   **/
  function _quickAllocate() internal {
    require(
      strategyWithWeights.length > 0,
      "There must be at least 1 strategy."
    );
    require(
      quickDepositStrategyIndex <= strategyWithWeights.length - 1,
      "not correct quickDepositStrategyIndex."
    );
    address quickDepositStrategyAddr = strategyWithWeights[
      quickDepositStrategyIndex
    ].strategy;
    uint256 allocateAmount = IERC20(primaryStableAddress).balanceOf(
      address(this)
    );
    if (quickDepositStrategyAddr != address(0) && allocateAmount > 0) {
      IStrategy strategy = IStrategy(quickDepositStrategyAddr);
      IERC20(primaryStableAddress).safeTransfer(
        address(strategy),
        allocateAmount
      );
      strategy.deposit(primaryStableAddress, allocateAmount);
      emit AssetAllocated(
        primaryStableAddress,
        quickDepositStrategyAddr,
        allocateAmount
      );
    }
  }

  /**
   * @dev Rebalance primary asset in all strategies
   **/
  function strategyRebalance() external onlyGovernorOrRebaseManager {
    _strategyRebalance();
  }

  /**
   * @dev Rebalance primary asset in all strategies
   **/
  function _strategyRebalance() internal {
    // TODO change to allStrategies.length > 1
    require(
      allStrategies.length > 1,
      "Should be more than 1 strategy for rebalance."
    );
    uint256 allStrategiesLength = allStrategies.length;
    // Array with all strategies targetWeight to check their sum in _sumArray()
    uint256[] memory allStrategyTargetWeights = new uint256[](
      allStrategiesLength
    );

    // Withdraw all primary stable from strategies
    for (uint256 i; i < allStrategiesLength; ) {
      IStrategy strategy = IStrategy(allStrategies[i]);
      if(strategy.checkBalance() > 0){
        strategy.withdrawAll();
      }
      StrategyWithWeight memory currentStrategy = strategyWithWeights[i];
      allStrategyTargetWeights[i] = currentStrategy.targetWeight;
      unchecked {
        ++i;
      }
    }
    require(
      _sumArray(allStrategyTargetWeights) <= 100000,
      "Total strategies weight can't be more than 100%."
    );

    uint256 totalStrategiesBalance = IERC20(primaryStableAddress).balanceOf(
      address(this)
    );

    // Rebalance and deposit in specific proportions again
    if (totalStrategiesBalance > 0) {
      for (uint256 i; i < allStrategiesLength; ) {
        StrategyWithWeight memory strategy = strategyWithWeights[i];
        uint allocateAmount = (totalStrategiesBalance * strategy.targetWeight) /
          100000;
        IERC20(primaryStableAddress).safeTransfer(
          strategy.strategy,
          allocateAmount
        );
        IStrategy strategyDepositTo = IStrategy(strategy.strategy);
        strategyDepositTo.deposit(primaryStableAddress, allocateAmount);
        emit AssetAllocated(
          primaryStableAddress,
          strategy.strategy,
          allocateAmount
        );
        unchecked {
          ++i;
        }
      }
    }
  }

  /**
   * @dev Sum all elements in array
   * @param _values Array of uint256
   **/
  function _sumArray(
    uint256[] memory _values
  ) internal pure returns (uint256 sum) {
    uint256 _valuesLength = _values.length;
    require(_valuesLength > 0, "Values array should not be empty.");
    for (uint256 i; i < _valuesLength; ) {
      sum += _values[i];
      unchecked {
        ++i;
      }
    }
  }

  /**
   * @dev Calculate the total value of assets held by the Vault and all
   *      strategies and update the supply of DUB.
   */
  function rebase() external virtual nonReentrant onlyGovernorOrRebaseManager {
    _rebase();
  }

  /**
   * @dev Calculate the total value of assets held by the Vault and all
   *      strategies and update the supply of DUB, optionally sending a
   *      portion of the yield to the trustee.
   */
  function _rebase() internal whenNotRebasePaused {
    uint256 cashSupply = dub.totalSupply();
    if (cashSupply == 0) {
      return;
    }
    uint256 primaryStableDecimals = Helpers.getDecimals(primaryStableAddress);
    uint256 vaultValue = _checkBalance().scaleBy(18, primaryStableDecimals);

    // Only rachet DUB supply upwards
    cashSupply = dub.totalSupply(); // Final check should use latest value
    if (vaultValue > cashSupply) {
      dub.changeSupply(vaultValue);
      lastRebaseAmount = vaultValue - cashSupply;
      totalRebaseAmount += vaultValue - cashSupply;
    }
  }

  /**
   * @notice Get the balance of an asset held in Vault and all strategies.
   * @return uint256 Balance of asset in decimals of asset
   */
  function checkBalance() external view returns (uint256) {
    return _checkBalance();
  }

  /**
   * @notice Get the balance of an asset held in Vault and all strategies.
   * @return balance Balance of asset in decimals of asset
   */
  function _checkBalance() internal view virtual returns (uint256 balance) {
    IERC20 asset = IERC20(primaryStableAddress);
    balance = asset.balanceOf(address(this));

    for (uint256 i = 0; i < allStrategies.length; i++) {
      IStrategy strategy = IStrategy(allStrategies[i]);
      balance = balance.add(strategy.checkBalance());
    }
  }

  /**
   * @dev Determine the total value of assets held by the vault and its
   *         strategies.
   * @return value Total value in USDC (1e6)
   */
  function totalValue() external view virtual returns (uint256 value) {
    value = _totalValue();
  }

  /**
   * @dev Internal Calculate the total value of the assets held by the
   *         vault and its strategies.
   * @return value Total value in USDC (1e6)
   */
  function _totalValue() internal view virtual returns (uint256 value) {
    return _checkBalance();
  }

  /**
   * @notice Calculate the output for a redeem function
   */
  function calculateRedeemOutput(
    uint256 _amount
  ) external view returns (uint256) {
    (uint256 output, , ) = _calculateRedeemOutput(_amount);
    return output;
  }

  /**
   * @notice Calculate the output for a redeem function
   */
  function redeemOutputs(
    uint256 _amount
  ) external view returns (uint256, uint256, uint256) {
    return _calculateRedeemOutput(_amount);
  }

  /**
   * @notice Calculate the output for a redeem function
   * @param _amount Amount to redeem (1e18)
   * @return output  amount respective to the primary stable  (1e6)
   * @return totalBalance Total balance of Vault (1e18)
   * @return redeemFee redeem fee on _amount (1e6)
   */
  function _calculateRedeemOutput(
    uint256 _amount
  ) internal view returns (uint256, uint256, uint256) {
    IOracle oracle = IOracle(priceProvider);
    uint256 primaryStablePrice = oracle.price(primaryStableAddress).scaleBy(
      18,
      8
    );
    uint256 primaryStableBalance = _checkBalance();
    uint256 primaryStableDecimals = Helpers.getDecimals(primaryStableAddress);
    uint256 totalBalance = primaryStableBalance.scaleBy(
      18,
      primaryStableDecimals
    );

    if (totalBalance < _amount) {
      _amount = totalBalance;
    }

    uint256 redeemFee = 0;
    // Calculate redeem fee
    if (teamFeeBps > 0) {
      redeemFee = _amount.mul(teamFeeBps).div(10000);
      _amount = _amount.sub(redeemFee);
    }

    // Never give out more than one
    // stablecoin per dollar of DUB
    if (primaryStablePrice < 1e18) {
      primaryStablePrice = 1e18;
    }

    // Calculate final outputs
    uint256 factor = _amount.divPrecisely(primaryStablePrice);
    // Should return totalBalance in 1e6
    return (
      primaryStableBalance.mul(factor).div(totalBalance),
      totalBalance,
      redeemFee.div(10 ** (18 - primaryStableDecimals))
    );
  }

  /********************************
                Swapping
    *********************************/
  /**
   * @dev Swapping one asset to another using the Swapper present inside Vault
   * @param tokenFrom address of token to swap from
   * @param tokenTo address of token to swap to
   */
  function _swapAsset(address tokenFrom, address tokenTo) internal {
    if (
      (tokenFrom != tokenTo) && (IERC20(tokenFrom).balanceOf(address(this)) > 0)
    ) {
      if (tokenFrom != primaryStableAddress) {
        uint amount = IERC20(tokenFrom).balanceOf(address(this));
        IERC20(tokenFrom).approve(swapRouter, amount);
        address[] memory tokenPath = new address[](2);
        tokenPath[0] = tokenFrom;
        tokenPath[1] = tokenTo;
        address[] memory poolPath = assetsPoolPaths[tokenFrom];
//        (uint _amountOut, ) = IWombatRouter(swapRouter).getAmountOut(
//          tokenPath,
//          poolPath,
//          int256(amount)
//        );
//        uint minAmount = _amountOut - (_amountOut * 5) / 1000;

        uint amountOut = IWombatRouter(swapRouter).swapExactTokensForTokens(
          tokenPath,
          poolPath,
          amount,
          0,
          address(this),
          block.timestamp
        );
      } else {
        return;
      }
    }
  }

  /***************************************
                    Utils
    ****************************************/

  /**
   * @dev Return the number of assets supported by the Vault.
   */
  function getAssetCount() public view returns (uint256) {
    return allAssets.length;
  }

  /**
   * @dev Return all asset addresses in order
   */
  function getAllAssets() external view returns (address[] memory) {
    return allAssets;
  }

  /**
   * @dev Return the number of strategies active on the Vault.
   */
  function getStrategyCount() external view returns (uint256) {
    return allStrategies.length;
  }

  /**
   * @dev Return the array of all strategies
   */
  function getAllStrategies() external view returns (address[] memory) {
    return allStrategies;
  }

  function isSupportedAsset(address _asset) external view returns (bool) {
    return assets[_asset];
  }

  function getTotalRebaseAmount() external view returns (uint256) {
    return totalRebaseAmount;
  } 

  function getLastRebasePayout() external view returns (uint256) {
    return lastRebaseAmount;
  }

  function getStrategiesWithWeights() external view returns (StrategyWithWeight[] memory) {
    return strategyWithWeights;
  }
}

