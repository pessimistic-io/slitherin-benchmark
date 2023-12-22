//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Libraries
import { Clones } from "./Clones.sol";
import { SafeERC20 } from "./SafeERC20.sol";

// Contracts
import { AccessControl } from "./AccessControl.sol";
import { Pausable } from "./Pausable.sol";
import { ReentrancyGuard } from "./ReentrancyGuard.sol";
import { ContractWhitelist } from "./ContractWhitelist.sol";
import { OptionsToken } from "./OptionsToken.sol";
import { BaseIrVaultState } from "./BaseIrVaultState.sol";

// Interfaces
import { IERC20 } from "./IERC20.sol";
import { IOptionPricing } from "./IOptionPricing.sol";
import { IVolatilityOracle } from "./IVolatilityOracle.sol";
import { IFeeStrategy } from "./IFeeStrategy.sol";
import { ICrv2PoolGauge } from "./ICrv2PoolGauge.sol";
import { IGaugeOracle } from "./IGaugeOracle.sol";
import { ICrv2Pool } from "./ICrv2Pool.sol";
import { ICrvChildGauge } from "./ICrvChildGauge.sol";

/*                                                                               
                                                       ▓                        
                       ▓                                 ▓                      
                     ▓▓                                   ▓▓                    
                   ▓▓                                      ▓▓▓                  
                 ▓▓▓                                         ▓▓▓                
               ▓▓▓▓                                           ▓▓▓▓              
             ▓▓▓▓▓                                             ▓▓▓▓▓            
           ▓▓▓▓▓                                                ▓▓▓▓▓▓          
         ▓▓▓▓▓▓                                                   ▓▓▓▓▓▓        
       ▓▓▓▓▓▓▓                                                     ▓▓▓▓▓▓▓      
     ▓▓▓▓▓▓▓                                                        ▓▓▓▓▓▓▓▓    
   ▓▓▓▓▓▓▓▓                                                          ▓▓▓▓▓▓▓▓   
 ▓▓▓▓▓▓▓▓▓                                                             ▓▓▓▓▓▓▓▓ 
▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                                   ▓▓▓▓▓▓▓▓▓▓▓▓▓
 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ 
      ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓     
              ▓▓▓▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓▓▓▓▓▓▓           
                ▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓▓                 
               ▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓                   
              ▓▓▓▓▓▓▓                                 ▓▓▓▓▓▓▓                   
             ▓▓▓▓▓▓▓         ▓                        ▓▓▓▓▓▓▓                   
            ▓▓▓▓▓▓▓          ▓▓▓                      ▓▓▓▓▓▓▓                   
            ▓▓▓▓▓▓          ▓▓▓▓▓▓                     ▓▓▓▓▓▓                   
           ▓▓▓▓▓▓▓          ▓▓▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                  
           ▓▓▓▓▓▓▓           ▓▓▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                 
            ▓▓▓▓▓▓▓             ▓▓▓▓▓▓                   ▓▓▓▓▓▓▓                
            ▓▓▓▓▓▓▓▓▓                                     ▓▓▓▓▓▓▓               
              ▓▓▓▓▓▓▓▓▓▓                                   ▓▓▓▓▓▓▓              
               ▓▓▓▓▓▓▓▓▓▓▓▓▓                                ▓▓▓▓▓▓▓             
                  ▓▓▓▓▓▓▓▓▓▓▓▓                               ▓▓▓▓▓▓▓            
                      ▓▓▓▓▓▓▓▓▓▓                              ▓▓▓▓▓▓            
                         ▓▓▓▓▓▓▓▓                             ▓▓▓▓▓▓▓           
                           ▓▓▓▓▓▓▓▓                            ▓▓▓▓▓▓           
                            ▓▓▓▓▓▓▓▓                           ▓▓▓▓▓▓▓          
                              ▓▓▓▓▓▓▓▓                         ▓▓▓▓▓▓           
                               ▓▓▓▓▓▓▓▓▓                     ▓▓▓▓▓▓▓▓           
                                 ▓▓▓▓▓▓▓▓▓                 ▓▓▓▓▓▓▓▓▓            
                                   ▓▓▓▓▓▓▓▓▓▓           ▓▓▓▓▓▓▓▓▓▓              
                                     ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓               
                                       ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓                  
                                           ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓
*/

/// @title Curve pool IR vault
/// @dev Option tokens are in erc20 18 decimals
/// Base token and quote token calculations are done in their respective erc20 precision
/// Strikes are in 1e8 precision
/// Price is in 1e8 precision
contract BaseIRVault is
  ContractWhitelist,
  Pausable,
  ReentrancyGuard,
  BaseIrVaultState,
  AccessControl
{
  using SafeERC20 for IERC20;
  using SafeERC20 for ICrv2Pool;

  /// @dev crvLP (Curve 2Pool LP token)
  ICrv2Pool public immutable crvLP;

  /// @dev Manager role
  bytes32 public constant MANAGER_ROLE = keccak256("MANAGER_ROLE");

  /*==== CONSTRUCTOR ====*/

  constructor(Addresses memory _addresses) {
    addresses = _addresses;
    _setupRole(DEFAULT_ADMIN_ROLE, msg.sender);
    _setupRole(MANAGER_ROLE, msg.sender);

    crvLP = ICrv2Pool(_addresses.crvLP);

    crvLP.safeIncreaseAllowance(_addresses.crv2PoolGauge, type(uint256).max);
  }

  /*==== SETTER METHODS ====*/

  /// @notice Pauses the vault for emergency cases
  /// @dev Can only be called by governance
  /// @return Whether it was successfully paused
  function pause() external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
    _pause();
    return true;
  }

  /// @notice Unpauses the vault
  /// @dev Can only be called by governance
  /// @return Whether it was successfully unpaused
  function unpause() external onlyRole(DEFAULT_ADMIN_ROLE) returns (bool) {
    _unpause();
    return true;
  }

  /// @notice Add a contract to the whitelist
  /// @dev Can only be called by the owner
  /// @param _contract Address of the contract that needs to be added to the whitelist
  function addToContractWhitelist(address _contract)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _addToContractWhitelist(_contract);
  }

  /// @notice Remove a contract to the whitelist
  /// @dev Can only be called by the owner
  /// @param _contract Address of the contract that needs to be removed from the whitelist
  function removeFromContractWhitelist(address _contract)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
  {
    _removeFromContractWhitelist(_contract);
  }

  /// @notice Updates the delay tolerance for the expiry epoch function
  /// @dev Can only be called by governance
  /// @return Whether it was successfully updated
  function updateExpireDelayTolerance(uint256 _expireDelayTolerance)
    external
    onlyRole(MANAGER_ROLE)
    returns (bool)
  {
    expireDelayTolerance = _expireDelayTolerance;
    emit ExpireDelayToleranceUpdate(_expireDelayTolerance);
    return true;
  }

  /// @notice Sets (adds) a list of addresses to the address list
  /// @dev Can only be called by the owner
  /// @param _addresses addresses of contracts in the Addresses struct
  function setAddresses(Addresses calldata _addresses)
    external
    onlyRole(MANAGER_ROLE)
  {
    addresses = _addresses;
    emit AddressesSet(_addresses);
  }

  /*==== METHODS ====*/

  /// @notice Transfers all funds to msg.sender
  /// @dev Can only be called by governance
  /// @param tokens The list of erc20 tokens to withdraw
  /// @param transferNative Whether should transfer the native currency
  /// @return Whether emergency withdraw was successful
  function emergencyWithdraw(address[] calldata tokens, bool transferNative)
    external
    onlyRole(DEFAULT_ADMIN_ROLE)
    whenPaused
    returns (bool)
  {
    if (transferNative) payable(msg.sender).transfer(address(this).balance);

    for (uint256 i = 0; i < tokens.length; i++) {
      IERC20 token = IERC20(tokens[i]);
      token.safeTransfer(msg.sender, token.balanceOf(address(this)));
    }

    emit EmergencyWithdraw(msg.sender);

    return true;
  }

  /// @notice Sets the current epoch as expired.
  /// @return Whether expire was successful
  function expireEpoch() external whenNotPaused nonReentrant returns (bool) {
    _isEligibleSender();
    uint256 epoch = currentEpoch;
    require(!totalEpochData[epoch].isEpochExpired, "E3");
    (, uint256 epochExpiry) = getEpochTimes(epoch);
    require((block.timestamp >= epochExpiry), "E4");
    require(block.timestamp <= epochExpiry + expireDelayTolerance, "E21");

    totalEpochData[epoch].rateAtSettlement = getCurrentRate();

    _updateFinalEpochBalances();

    totalEpochData[epoch].isEpochExpired = true;

    emit EpochExpired(msg.sender, totalEpochData[epoch].rateAtSettlement);

    return true;
  }

  /// @notice Sets the current epoch as expired. Only can be called by governance.
  /// @param rateAtSettlement The rate at settlement
  /// @return Whether expire was successful
  function expireEpoch(uint256 rateAtSettlement)
    external
    onlyRole(MANAGER_ROLE)
    whenNotPaused
    returns (bool)
  {
    uint256 epoch = currentEpoch;
    require(!totalEpochData[epoch].isEpochExpired, "E3");
    (, uint256 epochExpiry) = getEpochTimes(epoch);
    require((block.timestamp > epochExpiry + expireDelayTolerance), "E4");

    totalEpochData[epoch].rateAtSettlement = rateAtSettlement;

    _updateFinalEpochBalances();

    totalEpochData[epoch].isEpochExpired = true;

    emit EpochExpired(msg.sender, totalEpochData[epoch].rateAtSettlement);

    return true;
  }

  /// @dev Updates the final epoch crvLP balances per strike of the vault
  function _updateFinalEpochBalances() private {
    IERC20 crv = IERC20(addresses.crv);
    uint256 crvRewards = crv.balanceOf(address(this));
    uint256 epoch = currentEpoch;

    // Withdraw curve LP from the curve gauge and claim rewards
    ICrv2PoolGauge(addresses.crv2PoolGauge).withdraw(
      totalEpochData[epoch].totalTokenDeposits +
        totalEpochData[epoch].epochCallsPremium +
        totalEpochData[epoch].epochPutsPremium,
      address(this),
      true /* _claim_rewards */
    );

    // Mint the crv rewards
    ICrvChildGauge(addresses.crvChildGauge).mint(addresses.crv2PoolGauge);

    crvRewards = crv.balanceOf(address(this)) - crvRewards;

    totalEpochData[epoch].crvToDistribute = crvRewards;

    if (totalEpochData[epoch].totalTokenDeposits > 0) {
      uint256[] memory strikes = totalEpochData[epoch].epochStrikes;
      uint256[] memory callsLeverages = totalEpochData[epoch].callsLeverages;
      uint256[] memory putsLeverages = totalEpochData[epoch].putsLeverages;

      for (uint256 i = 0; i < strikes.length; i++) {
        // PnL from ssov option settlements

        uint256 callsSettlement = calculatePnl(
          totalEpochData[epoch].rateAtSettlement,
          strikes[i],
          totalStrikeData[epoch][strikes[i]].totalCallsPurchased,
          false
        );

        for (uint256 j = 1; j < callsLeverages.length; j++) {
          if (
            totalStrikeData[epoch][strikes[i]].leveragedCallsDeposits[j] > 0
          ) {
            totalStrikeData[epoch][strikes[i]].totalCallsStrikeBalance[
                j
              ] = calculateFinalBalance(
              false,
              strikes[i],
              i,
              j,
              (callsSettlement *
                totalStrikeData[epoch][strikes[i]].leveragedCallsDeposits[j]) /
                totalStrikeData[epoch][strikes[i]].totalCallsStrikeDeposits
            );
          } else {
            totalStrikeData[epoch][strikes[i]].totalCallsStrikeBalance[j] = 0;
          }
        }

        uint256 putsSettlement = calculatePnl(
          totalEpochData[epoch].rateAtSettlement,
          strikes[i],
          totalStrikeData[epoch][strikes[i]].totalPutsPurchased,
          true
        );
        for (uint256 j = 1; j < putsLeverages.length; j++) {
          if (totalStrikeData[epoch][strikes[i]].leveragedPutsDeposits[j] > 0) {
            totalStrikeData[epoch][strikes[i]].totalPutsStrikeBalance[
                j
              ] = calculateFinalBalance(
              true,
              strikes[i],
              i,
              j,
              (putsSettlement *
                totalStrikeData[epoch][strikes[i]].leveragedPutsDeposits[j]) /
                totalStrikeData[epoch][strikes[i]].totalPutsStrikeDeposits
            );
          } else {
            totalStrikeData[epoch][strikes[i]].totalPutsStrikeBalance[j] = 0;
          }
        }
      }
    }
  }

  /// @notice calculates the final amount for a strike and leverage accounting for settlements and premiums
  /// @param isPut is put
  /// @param strike strike
  /// @param strikeIndex strike index
  /// @param leverageIndex leverage index
  /// @param settlement settlement amount
  /// @return final withdrawable amount for a strike and leverage
  function calculateFinalBalance(
    bool isPut,
    uint256 strike,
    uint256 strikeIndex,
    uint256 leverageIndex,
    uint256 settlement
  ) private returns (uint256) {
    uint256 epoch = currentEpoch;
    if (isPut) {
      if (totalStrikeData[epoch][strike].totalPutsStrikeDeposits == 0) {
        return 0;
      }
      uint256 premium = (totalEpochData[epoch].epochStrikePutsPremium[
        strikeIndex
      ] * totalStrikeData[epoch][strike].leveragedPutsDeposits[leverageIndex]) /
        totalStrikeData[epoch][strike].totalPutsStrikeDeposits;

      uint256 leverageSettlement = ((settlement *
        totalStrikeData[epoch][strike].leveragedPutsDeposits[leverageIndex]) /
        totalStrikeData[epoch][strike].totalPutsStrikeDeposits);
      if (
        leverageSettlement >
        premium +
          (totalStrikeData[epoch][strike].leveragedPutsDeposits[leverageIndex] /
            totalEpochData[epoch].putsLeverages[leverageIndex])
      ) {
        totalStrikeData[epoch][strike].putsSettlement +=
          premium +
          (totalStrikeData[epoch][strike].leveragedPutsDeposits[leverageIndex] /
            totalEpochData[epoch].putsLeverages[leverageIndex]);
        return 0;
      } else {
        totalStrikeData[epoch][strike].putsSettlement += settlement;
        return (premium +
          (totalStrikeData[epoch][strike].leveragedPutsDeposits[leverageIndex] /
            totalEpochData[epoch].putsLeverages[leverageIndex]) -
          settlement);
      }
    } else {
      if (totalStrikeData[epoch][strike].totalCallsStrikeDeposits == 0) {
        return 0;
      }
      uint256 premium = (totalEpochData[epoch].epochStrikeCallsPremium[
        strikeIndex
      ] *
        totalStrikeData[epoch][strike].leveragedCallsDeposits[leverageIndex]) /
        totalStrikeData[epoch][strike].totalCallsStrikeDeposits;

      uint256 leverageSettlement = ((settlement *
        totalStrikeData[epoch][strike].leveragedCallsDeposits[leverageIndex]) /
        totalStrikeData[epoch][strike].totalCallsStrikeDeposits);
      if (
        leverageSettlement >
        premium +
          (totalStrikeData[epoch][strike].leveragedCallsDeposits[
            leverageIndex
          ] / totalEpochData[epoch].callsLeverages[leverageIndex])
      ) {
        totalStrikeData[epoch][strike].callsSettlement +=
          premium +
          (totalStrikeData[epoch][strike].leveragedCallsDeposits[
            leverageIndex
          ] / totalEpochData[epoch].callsLeverages[leverageIndex]);
        return 0;
      } else {
        totalStrikeData[epoch][strike].callsSettlement += settlement;
        return (premium +
          (totalStrikeData[epoch][strike].leveragedCallsDeposits[
            leverageIndex
          ] / totalEpochData[epoch].callsLeverages[leverageIndex]) -
          settlement);
      }
    }
  }

  /**
   * @notice Bootstraps a new epoch and mints option tokens equivalent to user deposits for the epoch
   * @return Whether bootstrap was successful
   */
  function bootstrap()
    external
    onlyRole(MANAGER_ROLE)
    whenNotPaused
    nonReentrant
    returns (bool)
  {
    uint256 nextEpoch = currentEpoch + 1;
    require(!totalEpochData[nextEpoch].isVaultReady, "E5");
    require(totalEpochData[nextEpoch].epochStrikes.length > 0, "E6");
    require(totalEpochData[nextEpoch].callsLeverages.length > 0, "E6");
    require(totalEpochData[nextEpoch].putsLeverages.length > 0, "E6");

    if (nextEpoch - 1 > 0) {
      // Previous epoch must be expired
      require(totalEpochData[nextEpoch - 1].isEpochExpired, "E7");
    }
    (, uint256 expiry) = getEpochTimes(nextEpoch);
    for (
      uint256 i = 0;
      i < totalEpochData[nextEpoch].epochStrikes.length;
      i++
    ) {
      uint256 strike = totalEpochData[nextEpoch].epochStrikes[i];
      // Create options tokens representing puts for selected strike in epoch
      OptionsToken _callOptionsToken = OptionsToken(
        Clones.clone(addresses.optionsTokenImplementation)
      );

      OptionsToken _putOptionsToken = OptionsToken(
        Clones.clone(addresses.optionsTokenImplementation)
      );

      _callOptionsToken.initialize(
        address(this),
        false,
        strike,
        expiry,
        nextEpoch,
        "IRVault",
        "CRV"
      );

      _putOptionsToken.initialize(
        address(this),
        true,
        strike,
        expiry,
        nextEpoch,
        "IRVault",
        "CRV"
      );

      totalEpochData[nextEpoch].callsToken.push(address(_callOptionsToken));
      totalEpochData[nextEpoch].putsToken.push(address(_putOptionsToken));

      // Mint tokens equivalent to deposits for strike in epoch
      _callOptionsToken.mint(
        address(this),
        (totalStrikeData[nextEpoch][strike].totalCallsStrikeDeposits *
          getLpPrice()) / 1e18
      );
      _putOptionsToken.mint(
        address(this),
        (totalStrikeData[nextEpoch][strike].totalPutsStrikeDeposits *
          getLpPrice()) / 1e18
      );
    }

    // Mark vault as ready for epoch
    totalEpochData[nextEpoch].isVaultReady = true;
    // Increase the current epoch
    currentEpoch = nextEpoch;

    emit Bootstrap(nextEpoch);

    return true;
  }

  /**
   * @notice initializes the arrays for a epoch with 0's array
   * @param nextEpoch expoch to initalize data with
   */

  function initalizeDefault(uint256 nextEpoch) private {
    uint256[] memory _defaultStrikesArray = new uint256[](
      totalEpochData[nextEpoch].epochStrikes.length
    );
    uint256[] memory _defaultCallsLeverageArray = new uint256[](
      totalEpochData[nextEpoch].callsLeverages.length
    );
    uint256[] memory _defaultPutsLeverageArray = new uint256[](
      totalEpochData[nextEpoch].putsLeverages.length
    );

    // initalize default values
    totalEpochData[nextEpoch].epochStrikeCallsPremium = _defaultStrikesArray;
    totalEpochData[nextEpoch].epochStrikePutsPremium = _defaultStrikesArray;

    for (
      uint256 i = 0;
      i < totalEpochData[nextEpoch].epochStrikes.length;
      i++
    ) {
      uint256 strike = totalEpochData[nextEpoch].epochStrikes[i];
      // initalize default values
      totalStrikeData[nextEpoch][strike]
        .leveragedCallsDeposits = _defaultCallsLeverageArray;
      totalStrikeData[nextEpoch][strike]
        .leveragedPutsDeposits = _defaultPutsLeverageArray;
      totalStrikeData[nextEpoch][strike]
        .totalCallsStrikeBalance = _defaultCallsLeverageArray;
      totalStrikeData[nextEpoch][strike]
        .totalPutsStrikeBalance = _defaultPutsLeverageArray;
    }
  }

  /**
   * @notice Sets strikes for next epoch
   * @param strikes Strikes to set for next epoch
   * @param _expiry Expiry for the next epoch
   * @param callsLeverages Calls leverages to set for next epoch
   * @param putsLeverages Puts leverages to set for next epoch
   * @return Whether strikes were set
   */
  function initializeEpoch(
    uint256[] memory strikes,
    uint256 _expiry,
    uint256[] memory callsLeverages,
    uint256[] memory putsLeverages
  ) external onlyRole(MANAGER_ROLE) whenNotPaused returns (bool) {
    uint256 nextEpoch = currentEpoch + 1;

    require(totalEpochData[nextEpoch].totalTokenDeposits == 0, "E8");
    require(_expiry > totalEpochData[nextEpoch].epochStartTimes, "E25");

    if (currentEpoch > 0) {
      (, uint256 epochExpiry) = getEpochTimes(nextEpoch - 1);
      require((block.timestamp > epochExpiry), "E9");
    }

    // Set the next epoch strikes
    totalEpochData[nextEpoch].epochStrikes = strikes;

    // Set the next epoch leverages
    totalEpochData[nextEpoch].callsLeverages = callsLeverages;
    totalEpochData[nextEpoch].putsLeverages = putsLeverages;

    // Set the next epoch start time
    totalEpochData[nextEpoch].epochStartTimes = block.timestamp;

    // Set epoch expiry
    totalEpochData[nextEpoch].epochExpiryTime = _expiry;

    for (uint256 i = 0; i < strikes.length; i++)
      emit StrikeSet(nextEpoch, strikes[i]);

    for (uint256 i = 0; i < callsLeverages.length; i++)
      emit CallsLeverageSet(nextEpoch, callsLeverages[i]);

    for (uint256 i = 0; i < putsLeverages.length; i++)
      emit PutsLeverageSet(nextEpoch, putsLeverages[i]);

    initalizeDefault(nextEpoch);
    return true;
  }

  /**
   * @notice Deposit Curve 2Pool LP into the ssov to mint options in the next epoch for selected strikes
   * @param strikeIndex array of strike Indexs
   * @param callLeverageIndex array of call leverage Indexs
   * @param putLeverageIndex array of put leverage Indexs
   * @param amount array of amounts
   * @param user Address of the user to deposit for
   * @return Whether deposit was successful
   */
  function depositMultiple(
    uint256[] memory strikeIndex,
    uint256[] memory callLeverageIndex,
    uint256[] memory putLeverageIndex,
    uint256[] memory amount,
    address user
  ) external whenNotPaused nonReentrant returns (bool) {
    _isEligibleSender();
    require(strikeIndex.length == callLeverageIndex.length, "E2");
    require(putLeverageIndex.length == callLeverageIndex.length, "E2");

    for (uint256 i = 0; i < strikeIndex.length; i++) {
      deposit(
        strikeIndex[i],
        callLeverageIndex[i],
        putLeverageIndex[i],
        amount[i],
        user
      );
    }
    return true;
  }

  /**
   * @notice Deposit Curve 2Pool LP into the ssov to mint options in the next epoch for selected strikes
   * @param strikeIndex Index of strike
   * @param callLeverageIndex index of leverage
   * @param putLeverageIndex index of leverage
   * @param amount Amout of crvLP to deposit
   * @param user Address of the user to deposit for
   * @return Whether deposit was successful
   */
  function deposit(
    uint256 strikeIndex,
    uint256 callLeverageIndex,
    uint256 putLeverageIndex,
    uint256 amount,
    address user
  ) private whenNotPaused returns (bool) {
    _isEligibleSender();
    uint256 nextEpoch = currentEpoch + 1;

    if (currentEpoch > 0) {
      require(
        totalEpochData[currentEpoch].isEpochExpired &&
          !totalEpochData[nextEpoch].isVaultReady,
        "E18"
      );
    }

    // Must be a valid strikeIndex
    require(strikeIndex < totalEpochData[nextEpoch].epochStrikes.length, "E10");

    // Must be a valid levereageIndex
    require(
      callLeverageIndex < totalEpochData[nextEpoch].callsLeverages.length,
      "E22"
    );
    require(
      putLeverageIndex < totalEpochData[nextEpoch].putsLeverages.length,
      "E22"
    );
    // Both leverages can not be zero
    require(callLeverageIndex > 0 || putLeverageIndex > 0, "E24");
    // Must +ve amount
    require(amount > 0, "E11");

    // Must be a valid strike
    uint256 strike = totalEpochData[nextEpoch].epochStrikes[strikeIndex];

    // Must be a valid leverage
    uint256 callLeverage = totalEpochData[nextEpoch].callsLeverages[
      callLeverageIndex
    ];
    uint256 putLeverage = totalEpochData[nextEpoch].putsLeverages[
      putLeverageIndex
    ];

    bytes32 userStrike = keccak256(
      abi.encodePacked(user, strike, callLeverage, putLeverage)
    );

    // Transfer crvLP from msg.sender (maybe different from user param) to ssov
    crvLP.safeTransferFrom(msg.sender, address(this), amount);

    // Add to user epoch deposits
    userEpochStrikeDeposits[nextEpoch][userStrike].amount += amount;

    // Add to user epoch call leverages
    userEpochStrikeDeposits[nextEpoch][userStrike].callLeverage = callLeverage;

    // Add to user epoch put leverages
    userEpochStrikeDeposits[nextEpoch][userStrike].putLeverage = putLeverage;

    // Add to total epoch strike deposits
    totalStrikeData[nextEpoch][strike].leveragedCallsDeposits[
      callLeverageIndex
    ] += amount * callLeverage;

    totalStrikeData[nextEpoch][strike].leveragedPutsDeposits[
      putLeverageIndex
    ] += amount * putLeverage;

    totalStrikeData[nextEpoch][strike].totalCallsStrikeDeposits +=
      amount *
      callLeverage;
    totalStrikeData[nextEpoch][strike].totalPutsStrikeDeposits +=
      amount *
      putLeverage;

    totalEpochData[nextEpoch].totalCallsDeposits += amount * callLeverage;
    totalEpochData[nextEpoch].totalPutsDeposits += amount * putLeverage;

    totalEpochData[nextEpoch].totalTokenDeposits += amount;
    totalStrikeData[nextEpoch][strike].totalTokensStrikeDeposits += amount;

    // Deposit curve LP to the curve gauge for rewards
    ICrv2PoolGauge(addresses.crv2PoolGauge).deposit(
      amount,
      address(this),
      false /* _claim_rewards */
    );

    emit Deposit(nextEpoch, strike, amount, user, msg.sender);

    return true;
  }

  /**
   * @notice Purchases puts for the current epoch
   * @param strikeIndex Strike index for current epoch
   * @param amount Amount of puts to purchase
   * @param user User to purchase options for
   * @return Whether purchase was successful
   */
  function purchase(
    uint256 strikeIndex,
    bool isPut,
    uint256 amount,
    address user
  ) external whenNotPaused nonReentrant returns (uint256, uint256) {
    _isEligibleSender();
    uint256 epoch = currentEpoch;
    (, uint256 epochExpiry) = getEpochTimes(epoch);
    require((block.timestamp < epochExpiry), "E3");
    require(totalEpochData[epoch].isVaultReady, "E19");
    require(strikeIndex < totalEpochData[epoch].epochStrikes.length, "E10");
    require(amount > 0, "E11");

    uint256 strike = totalEpochData[epoch].epochStrikes[strikeIndex];
    bytes32 userStrike = keccak256(abi.encodePacked(user, strike));

    // Get total premium for all puts being purchased
    uint256 premium = calculatePremium(strike, amount, isPut);

    // Total fee charged
    uint256 totalFee = calculatePurchaseFees(
      getCurrentRate(),
      strike,
      amount,
      isPut
    );

    // Transfer premium from msg.sender (need not be same as user)
    crvLP.safeTransferFrom(msg.sender, address(this), premium + totalFee);

    // Transfer fee to FeeDistributor
    crvLP.safeTransfer(addresses.feeDistributor, totalFee);

    // Deposit curve LP to the curve gauge for rewards
    ICrv2PoolGauge(addresses.crv2PoolGauge).deposit(
      premium,
      address(this),
      false /* _claim_rewards */
    );

    if (isPut) {
      // Add to total epoch data
      totalEpochData[epoch].totalPutsPurchased += amount;
      // Add to total epoch puts purchased
      totalStrikeData[epoch][strike].totalPutsPurchased += amount;
      // Add to user epoch puts purchased
      userStrikePurchaseData[epoch][userStrike].putsPurchased += amount;
      // Add to epoch premium per strike
      totalEpochData[epoch].epochStrikePutsPremium[strikeIndex] += premium;
      // Add to total epoch premium
      totalEpochData[epoch].epochPutsPremium += premium;
      // Add to user epoch premium
      userStrikePurchaseData[epoch][userStrike].userEpochPutsPremium += premium;
      // Transfer option tokens to user
      IERC20(totalEpochData[epoch].putsToken[strikeIndex]).safeTransfer(
        user,
        amount
      );
    } else {
      // Add tp total epoch data
      totalEpochData[epoch].totalCallsPurchased += amount;
      // Add to total epoch puts purchased
      totalStrikeData[epoch][strike].totalCallsPurchased += amount;
      // Add to user epoch puts purchased
      userStrikePurchaseData[epoch][userStrike].callsPurchased += amount;
      // Add to epoch premium per strike
      totalEpochData[epoch].epochStrikeCallsPremium[strikeIndex] += premium;
      // Add to total epoch premium
      totalEpochData[epoch].epochCallsPremium += premium;
      // Add to user epoch premium
      userStrikePurchaseData[epoch][userStrike]
        .userEpochCallsPremium += premium;
      // Transfer option tokens to user
      IERC20(totalEpochData[epoch].callsToken[strikeIndex]).safeTransfer(
        user,
        amount
      );
    }

    emit Purchase(epoch, strike, amount, premium, totalFee, user);

    return (premium, totalFee);
  }

  /**
   * @notice Settle calculates the PnL for the user and withdraws the PnL in the crvPool to the user. Will also the burn the option tokens from the user.
   * @param strikeIndex Strike index
   * @param isPut Whether the option is a put
   * @param amount Amount of options
   * @return pnl
   */
  function settle(
    uint256 strikeIndex,
    bool isPut,
    uint256 amount,
    uint256 epoch
  ) external whenNotPaused nonReentrant returns (uint256 pnl) {
    _isEligibleSender();
    require(strikeIndex < totalEpochData[epoch].epochStrikes.length, "E10");
    require(amount > 0, "E11");
    require(totalEpochData[epoch].isEpochExpired, "E16");

    uint256 strike = totalEpochData[epoch].epochStrikes[strikeIndex];
    require(strike != 0, "E12");

    OptionsToken optionToken = OptionsToken(
      isPut
        ? totalEpochData[epoch].putsToken[strikeIndex]
        : totalEpochData[epoch].callsToken[strikeIndex]
    );

    if (isPut) {
      require(optionToken.balanceOf(msg.sender) >= amount, "E15");
      pnl =
        (totalStrikeData[epoch][strike].putsSettlement * amount) /
        totalStrikeData[epoch][strike].totalPutsPurchased;
    } else {
      require(optionToken.balanceOf(msg.sender) >= amount, "E15");
      pnl =
        (totalStrikeData[epoch][strike].callsSettlement * amount) /
        totalStrikeData[epoch][strike].totalCallsPurchased;
    }
    optionToken.burnFrom(msg.sender, amount);

    // Total fee charged
    uint256 totalFee = calculateSettlementFees(
      totalEpochData[epoch].rateAtSettlement,
      pnl,
      amount,
      isPut
    );

    require(pnl > 0, "E14");

    // Transfer fee to FeeDistributor
    crvLP.safeTransfer(addresses.feeDistributor, totalFee);

    // Transfer PnL to user
    crvLP.safeTransfer(msg.sender, pnl - totalFee);

    emit Settle(epoch, strike, msg.sender, amount, pnl - totalFee, totalFee);
  }

  /**
   * @notice Withdraw function for user to withdraw their deposit for a strike, call and put leverages.
   * @param epoch epoch
   * @param strikeIndex Strike index
   * @param callLeverageIndex Call leverage index
   * @param putLeverageIndex Put leverage index
   * @return userCrvLpWithdrawAmount userCrvLpWithdrawAmount
   * @return rewards crv rewards for the user
   */
  function withdraw(
    uint256 epoch,
    uint256 strikeIndex,
    uint256 callLeverageIndex,
    uint256 putLeverageIndex,
    address user
  )
    private
    whenNotPaused
    returns (uint256 userCrvLpWithdrawAmount, uint256 rewards)
  {
    _isEligibleSender();
    require(totalEpochData[epoch].isEpochExpired, "E16");
    require(strikeIndex < totalEpochData[epoch].epochStrikes.length, "E10");

    // Must be a valid strike
    uint256 strike = totalEpochData[epoch].epochStrikes[strikeIndex];
    require(strike != 0, "E12");

    // Must be a valid leverage
    uint256 callLeverage = totalEpochData[epoch].callsLeverages[
      callLeverageIndex
    ];
    uint256 putLeverage = totalEpochData[epoch].putsLeverages[putLeverageIndex];

    bytes32 userStrike = keccak256(
      abi.encodePacked(user, strike, callLeverage, putLeverage)
    );

    uint256 userStrikeDeposits = userEpochStrikeDeposits[epoch][userStrike]
      .amount;
    require(userStrikeDeposits > 0, "E17");

    userCrvLpWithdrawAmount = getUserCrvLpWithdrawAmount(
      epoch,
      strike,
      callLeverageIndex,
      putLeverageIndex,
      userStrikeDeposits
    );

    rewards = getUserRewards(epoch, strike, strikeIndex, userStrikeDeposits);

    userEpochStrikeDeposits[epoch][userStrike].amount = 0;

    IERC20(addresses.crv).safeTransfer(user, rewards);

    crvLP.safeTransfer(user, userCrvLpWithdrawAmount);

    emit Withdraw(
      epoch,
      strike,
      user,
      userStrikeDeposits,
      userCrvLpWithdrawAmount,
      rewards
    );
  }

  /**
   * @notice Withdraw function for user to withdraw all their deposits.
   * @param epoch epoch
   * @param strikeIndex Strike index array
   * @param callLeverageIndex Call leverage index array
   * @param putLeverageIndex Put leverage index array
   * @return boolean success
   */
  function withdrawMultiple(
    uint256 epoch,
    uint256[] memory strikeIndex,
    uint256[] memory callLeverageIndex,
    uint256[] memory putLeverageIndex,
    address user
  ) external whenNotPaused nonReentrant returns (bool) {
    _isEligibleSender();
    require(strikeIndex.length == callLeverageIndex.length, "E2");
    require(putLeverageIndex.length == callLeverageIndex.length, "E2");
    for (uint256 i = 0; i < strikeIndex.length; i++) {
      withdraw(
        epoch,
        strikeIndex[i],
        callLeverageIndex[i],
        putLeverageIndex[i],
        user
      );
    }
    return true;
  }

  /**
   * @notice calculates user's LP withdraw amount.
   * @param epoch epoch
   * @param strike Strike
   * @param callLeverageIndex Call leverage index
   * @param putLeverageIndex Put leverage index
   * @param userStrikeDeposits user deposit amount without any leverage
   * @return usercrvLPWithdrawAmount userCrvLpWithdrawAmount
   */
  function getUserCrvLpWithdrawAmount(
    uint256 epoch,
    uint256 strike,
    uint256 callLeverageIndex,
    uint256 putLeverageIndex,
    uint256 userStrikeDeposits
  ) private view whenNotPaused returns (uint256 usercrvLPWithdrawAmount) {
    if (callLeverageIndex > 0) {
      usercrvLPWithdrawAmount =
        (totalStrikeData[epoch][strike].totalCallsStrikeBalance[
          callLeverageIndex
        ] * userStrikeDeposits) /
        (totalStrikeData[epoch][strike].leveragedCallsDeposits[
          callLeverageIndex
        ] / totalEpochData[epoch].callsLeverages[callLeverageIndex]);
    }

    if (putLeverageIndex > 0) {
      usercrvLPWithdrawAmount +=
        (totalStrikeData[epoch][strike].totalPutsStrikeBalance[
          putLeverageIndex
        ] * userStrikeDeposits) /
        (totalStrikeData[epoch][strike].leveragedPutsDeposits[
          putLeverageIndex
        ] / totalEpochData[epoch].putsLeverages[putLeverageIndex]);
    }
    if (callLeverageIndex > 0 && putLeverageIndex > 0) {
      usercrvLPWithdrawAmount = usercrvLPWithdrawAmount - userStrikeDeposits;
    }
  }

  /**
   * @notice calculates user's crv rewards amount.
   * @param epoch epoch
   * @param strike Strike
   * @param strikeIndex strike index
   * @param userStrikeDeposits user deposit amount without any leverage
   * @return rewards crv rewards
   */
  function getUserRewards(
    uint256 epoch,
    uint256 strike,
    uint256 strikeIndex,
    uint256 userStrikeDeposits
  ) private view whenNotPaused returns (uint256 rewards) {
    rewards =
      (totalEpochData[epoch].crvToDistribute *
        (totalStrikeData[epoch][strike].totalTokensStrikeDeposits +
          totalEpochData[epoch].epochStrikeCallsPremium[strikeIndex] +
          totalEpochData[epoch].epochStrikePutsPremium[strikeIndex])) /
      (totalEpochData[epoch].totalTokenDeposits +
        totalEpochData[epoch].epochCallsPremium +
        totalEpochData[epoch].epochPutsPremium);

    rewards =
      (rewards * userStrikeDeposits) /
      totalStrikeData[epoch][strike].totalTokensStrikeDeposits;
  }

  /*==== VIEWS ====*/

  /// @notice Returns the volatility from the volatility oracle
  /// @param _strike Strike of the option
  function getVolatility(uint256 _strike) public view returns (uint256) {
    return IVolatilityOracle(addresses.volatilityOracle).getVolatility(_strike);
  }

  /// @notice Calculate premium for an option
  /// @param _strike Strike price of the option
  /// @param _amount Amount of options
  /// @param _isPut is it a put option
  /// @return premium in crvLP
  function calculatePremium(
    uint256 _strike,
    uint256 _amount,
    bool _isPut
  ) public view returns (uint256 premium) {
    uint256 currentPrice = getCurrentRate();
    (, uint256 expiryTimestamp) = getEpochTimes(currentEpoch);
    uint256 expiry = (expiryTimestamp - block.timestamp) / 864;
    uint256 epochDuration = (expiryTimestamp -
      totalEpochData[currentEpoch].epochStartTimes) / 864;

    premium = (
      IOptionPricing(addresses.optionPricing).getOptionPrice(
        int256(currentPrice), // 1e8
        _strike, // 1e8
        int256(getVolatility(_strike) * 10), // 1e1
        int256(_amount), // 1e18
        _isPut, // isPut
        expiry, // 1e2
        epochDuration // 1e2
      )
    );

    premium = ((premium * 1e18) / getLpPrice());
  }

  /// @notice Calculate Pnl
  /// @param price price of crvPool
  /// @param strike strike price of the option
  /// @param amount amount of options
  /// @param isPut is it a put option
  /// Pnl is calculated as the difference between the strike and current intrest rate and the amount of intrest the notional has accured in the duration of the option
  function calculatePnl(
    uint256 price,
    uint256 strike,
    uint256 amount,
    bool isPut
  ) public view returns (uint256) {
    uint256 pnl;
    (uint256 start, uint256 end) = getEpochTimes(currentEpoch);
    uint256 duration = (end - start) / 86400;
    isPut
      ? (
        strike > price
          ? (pnl = (((strike - price) * amount * duration) / 36500) / 1e8) // (Strike - spot) x Notional x duration/365 / 100 for puts
          : (pnl = 0)
      )
      : (
        strike > price
          ? (pnl = 0)
          : (pnl = (((price - strike) * amount * duration) / 36500) / 1e8) // (Spot-Strike) x Notional x duration/365 / 100 for calls
      );
    return pnl;
  }

  /// @notice Calculate Fees for purchase
  /// @param price price of crvPool
  /// @param strike strike price of the crvPool option
  /// @param amount amount of options being bought
  /// @return the purchase fee in crvLP
  function calculatePurchaseFees(
    uint256 price,
    uint256 strike,
    uint256 amount,
    bool isPut
  ) public view returns (uint256) {
    return ((IFeeStrategy(addresses.feeStrategy).calculatePurchaseFees(
      price,
      strike,
      amount,
      isPut
    ) * 1e18) / getLpPrice());
  }

  /// @notice Calculate Fees for settlement of options
  /// @param rateAtSettlement settlement price of crvPool
  /// @param pnl total pnl
  /// @param amount amount of options being settled
  function calculateSettlementFees(
    uint256 rateAtSettlement,
    uint256 pnl,
    uint256 amount,
    bool isPut
  ) public view returns (uint256) {
    return ((IFeeStrategy(addresses.feeStrategy).calculateSettlementFees(
      rateAtSettlement,
      pnl,
      amount,
      isPut
    ) * 1e18) / getLpPrice());
  }

  /**
   * @notice Returns start and end times for an epoch
   * @param epoch Target epoch
   */
  function getEpochTimes(uint256 epoch)
    public
    view
    epochGreaterThanZero(epoch)
    returns (uint256 start, uint256 end)
  {
    return (
      totalEpochData[epoch].epochStartTimes,
      totalEpochData[epoch].epochExpiryTime
    );
  }

  /**
   * Returns epoch strike tokens arrays and strikes set for an epoch
   * @param epoch Target epoch
   */
  function getEpochData(uint256 epoch)
    external
    view
    epochGreaterThanZero(epoch)
    returns (
      uint256[] memory,
      address[] memory,
      address[] memory
    )
  {
    uint256 strikesLength = totalEpochData[epoch].epochStrikes.length;

    uint256[] memory _epochStrikes = new uint256[](strikesLength);
    address[] memory _epochCallsStrikeTokens = new address[](strikesLength);
    address[] memory _epochPutsStrikeTokens = new address[](strikesLength);

    for (uint256 i = 0; i < strikesLength; i++) {
      _epochCallsStrikeTokens[i] = totalEpochData[epoch].callsToken[i];
      _epochPutsStrikeTokens[i] = totalEpochData[epoch].putsToken[i];
      _epochStrikes[i] = totalEpochData[epoch].epochStrikes[i];
    }

    return (_epochStrikes, _epochCallsStrikeTokens, _epochPutsStrikeTokens);
  }

  /**
   * Returns calls and puts strike tokens arrays for an epoch
   * @param epoch Target epoch
   */
  function getEpochTokens(uint256 epoch)
    external
    view
    epochGreaterThanZero(epoch)
    returns (address[] memory, address[] memory)
  {
    uint256 strikesLength = totalEpochData[epoch].epochStrikes.length;

    address[] memory _epochCallsStrikeTokens = new address[](strikesLength);
    address[] memory _epochPutsStrikeTokens = new address[](strikesLength);

    for (uint256 i = 0; i < strikesLength; i++) {
      _epochCallsStrikeTokens[i] = totalEpochData[epoch].callsToken[i];
      _epochPutsStrikeTokens[i] = totalEpochData[epoch].putsToken[i];
    }

    return (_epochCallsStrikeTokens, _epochPutsStrikeTokens);
  }

  /**
   * Returns strikes set for a epoch
   * @param epoch Target epoch
   */
  function getEpochStrikes(uint256 epoch)
    external
    view
    epochGreaterThanZero(epoch)
    returns (uint256[] memory)
  {
    uint256 strikesLength = totalEpochData[epoch].epochStrikes.length;

    uint256[] memory _epochStrikes = new uint256[](strikesLength);

    for (uint256 i = 0; i < strikesLength; i++) {
      _epochStrikes[i] = totalEpochData[epoch].epochStrikes[i];
    }

    return (_epochStrikes);
  }

  /**
   * Returns leverages set for the epoch
   * @param epoch Target epoch
   */
  function getEpochLeverages(uint256 epoch)
    external
    view
    epochGreaterThanZero(epoch)
    returns (uint256[] memory, uint256[] memory)
  {
    uint256 callsLeveragesLength = totalEpochData[epoch].callsLeverages.length;

    uint256 putsLeveragesLength = totalEpochData[epoch].putsLeverages.length;

    uint256[] memory _callsLeverages = new uint256[](callsLeveragesLength);

    uint256[] memory _putsLeverages = new uint256[](putsLeveragesLength);

    for (uint256 i = 0; i < callsLeveragesLength; i++) {
      _callsLeverages[i] = totalEpochData[epoch].callsLeverages[i];
    }
    for (uint256 i = 0; i < putsLeveragesLength; i++) {
      _putsLeverages[i] = totalEpochData[epoch].putsLeverages[i];
    }

    return (_callsLeverages, _putsLeverages);
  }

  /**
   * Returns arrays for calls and puts premiums collected
   * @param epoch Target epoch
   */
  function getEpochPremiums(uint256 epoch)
    external
    view
    epochGreaterThanZero(epoch)
    returns (uint256[] memory, uint256[] memory)
  {
    uint256 strikesLength = totalEpochData[epoch].epochStrikes.length;

    uint256[] memory _callsPremium = new uint256[](strikesLength);

    uint256[] memory _putsPremium = new uint256[](strikesLength);

    for (uint256 i = 0; i < strikesLength; i++) {
      _callsPremium[i] = totalEpochData[epoch].epochStrikeCallsPremium[i];
      _putsPremium[i] = totalEpochData[epoch].epochStrikePutsPremium[i];
    }

    return (_callsPremium, _putsPremium);
  }

  /**
   * Returns epoch strike calls and puts deposits arrays
   * @param epoch Target epoch
   * @param strike Target strike
   */
  function getEpochStrikeData(uint256 epoch, uint256 strike)
    external
    view
    epochGreaterThanZero(epoch)
    returns (uint256[] memory, uint256[] memory)
  {
    uint256 callsLeveragesLength = totalEpochData[epoch].callsLeverages.length;

    uint256 putsLeveragesLength = totalEpochData[epoch].putsLeverages.length;

    uint256[] memory _callsDeposits = new uint256[](callsLeveragesLength);

    uint256[] memory _putsDeposits = new uint256[](putsLeveragesLength);

    for (uint256 i = 0; i < callsLeveragesLength; i++) {
      _callsDeposits[i] = totalStrikeData[epoch][strike].leveragedCallsDeposits[
        i
      ];
    }

    for (uint256 i = 0; i < putsLeveragesLength; i++) {
      _putsDeposits[i] = totalStrikeData[epoch][strike].leveragedPutsDeposits[
        i
      ];
    }

    return (_callsDeposits, _putsDeposits);
  }

  /**
   * @notice Returns the rate of the crvPool in ie8
   */
  function getCurrentRate() public view returns (uint256) {
    (uint256 start, uint256 end) = getEpochTimes(currentEpoch);
    return
      uint256(
        IGaugeOracle(addresses.gaugeOracle).getRate(
          start,
          end,
          addresses.curvePoolGauge
        )
      );
  }

  /**
   * @notice Returns the price of the Curve 2Pool LP token in 1e18
   */
  function getLpPrice() public view returns (uint256) {
    return crvLP.get_virtual_price();
  }

  /*==== MODIFIERS ====*/

  modifier epochGreaterThanZero(uint256 epoch) {
    require(epoch > 0, "E13");
    _;
  }
}

// ERROR MAPPING:
// {
//   "E1": "SSOV: Address cannot be a zero address",
//   "E2": "SSOV: Input lengths must match",
//   "E3": "SSOV: Epoch must not be expired",
//   "E4": "SSOV: Cannot expire epoch before epoch's expiry",
//   "E5": "SSOV: Already bootstrapped",
//   "E6": "SSOV: Strikes have not been set for next epoch",
//   "E7": "SSOV: Previous epoch has not expired",
//   "E8": "SSOV: Deposit already started",
//   "E9": "SSOV: Cannot set next strikes before current epoch's expiry",
//   "E10": "SSOV: Invalid strike index",
//   "E11": "SSOV: Invalid amount",
//   "E12": "SSOV: Invalid strike",
//   "E13": "SSOV: Epoch passed must be greater than 0",
//   "E14": "SSOV: Strike is higher than current price",
//   "E15": "SSOV: Option token balance is not enough",
//   "E16": "SSOV: Epoch must be expired",
//   "E17": "SSOV: User strike deposit amount must be greater than zero",
//   "E18": "SSOV: Deposit is only available between epochs",
//   "E19": "SSOV: Not bootstrapped",
//   "E21": "SSOV: Expire delay tolerance exceeded",
//   "E22": "SSOV: Invalid leverage Index",
//   "E23": "SSOV: Strikes not set for the epoch",
//   "E24": "SSOV: Can not deposit with both leverages set to 0",
//   "E25": "SSOV: Epoch expiry must be greater than epoch start time",
// }

