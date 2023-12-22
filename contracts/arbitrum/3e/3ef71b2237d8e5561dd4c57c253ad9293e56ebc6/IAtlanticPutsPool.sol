//SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

// Structs
import { DepositPosition, Addresses, OptionsPurchase, Checkpoint, VaultState, VaultConfiguration } from "./AtlanticsStructs.sol";

/**                                                                                                 
          █████╗ ████████╗██╗      █████╗ ███╗   ██╗████████╗██╗ ██████╗
          ██╔══██╗╚══██╔══╝██║     ██╔══██╗████╗  ██║╚══██╔══╝██║██╔════╝
          ███████║   ██║   ██║     ███████║██╔██╗ ██║   ██║   ██║██║     
          ██╔══██║   ██║   ██║     ██╔══██║██║╚██╗██║   ██║   ██║██║     
          ██║  ██║   ██║   ███████╗██║  ██║██║ ╚████║   ██║   ██║╚██████╗
          ╚═╝  ╚═╝   ╚═╝   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═══╝   ╚═╝   ╚═╝ ╚═════╝
                                                                        
          ██████╗ ██████╗ ████████╗██╗ ██████╗ ███╗   ██╗███████╗       
          ██╔═══██╗██╔══██╗╚══██╔══╝██║██╔═══██╗████╗  ██║██╔════╝       
          ██║   ██║██████╔╝   ██║   ██║██║   ██║██╔██╗ ██║███████╗       
          ██║   ██║██╔═══╝    ██║   ██║██║   ██║██║╚██╗██║╚════██║       
          ╚██████╔╝██║        ██║   ██║╚██████╔╝██║ ╚████║███████║       
          ╚═════╝ ╚═╝        ╚═╝   ╚═╝ ╚═════╝ ╚═╝  ╚═══╝╚══════╝       
                                                               
                            Atlantic Options
              Yield bearing put options with mobile collateral                                                           
*/

interface IAtlanticPutsPool {
  function addresses() external view returns (Addresses memory);

  // Deposits collateral as a writer with a specified max strike for the next epoch
  function deposit(uint256 maxStrike, address user) external payable returns (bool);

  // Purchases an atlantic for a specified strike
  function purchase(
    uint256 strike,
    uint256 amount,
    address user
  ) external returns (uint256);

  // Unlocks collateral from an atlantic by depositing underlying. Callable by dopex managed contract integrations.
  function unlockCollateral(uint256, address to) external returns (uint256);

  // Gracefully exercises an atlantic, sends collateral to integrated protocol,
  // underlying to writer and charges an unwind fee as well as remaining funding fees
  // to the option holder/protocol
  function unwind(uint256) external returns (uint256);

  // Re-locks collateral into an atlatic option. Withdraws underlying back to user, sends collateral back
  // from dopex managed contract to option, deducts remainder of funding fees.
  // Handles exceptions where collateral may get stuck due to failures in other protocols.
  function relockCollateral(uint256) external returns (uint256 collateralCollected);

  function calculatePnl(
    uint256 price,
    uint256 strike,
    uint256 amount
  ) external returns (uint256);

  function calculatePremium(uint256, uint256) external view returns (uint256);

  function calculatePurchaseFees(uint256, uint256) external view returns (uint256);

  function settle(uint256 purchaseId, address receiver) external returns (uint256 pnl);

  function epochTickSize(uint256 epoch) external view returns (uint256);

  function calculateFundingTillExpiry(uint256 totalCollateral) external view returns (uint256);

  function eligiblePutPurchaseStrike(uint256 liquidationPrice, uint256 optionStrikeOffset) external pure returns (uint256);

  function checkpointIntervalTime() external view returns (uint256);

  function getEpochHighestMaxStrike(uint256 _epoch) external view returns (uint256 _highestMaxStrike);

  function calculateFunding(uint256 totalCollateral) external view returns (uint256 funding);

  function calculateFunding(uint256 totalCollateral, uint256 epoch) external view returns (uint256 funding);

  function calculateUnwindFees(uint256 underlyingAmount) external view returns (uint256);

  function calculateSettlementFees(
    uint256 settlementPrice,
    uint256 pnl,
    uint256 amount
  ) external view returns (uint256);

  function getUsdPrice() external view returns (uint256);

  function getEpochSettlementPrice(uint256 _epoch) external view returns (uint256 _settlementPrice);

  function currentEpoch() external view returns (uint256);

  function getOptionsPurchase(uint256 _tokenId) external view returns (OptionsPurchase memory);

  function getDepositPosition(uint256 _tokenId) external view returns (DepositPosition memory);

  function depositIdCount() external view returns (uint256);

  function purchaseIdCount() external view returns (uint256);

  function getEpochCheckpoints(uint256, uint256) external view returns (Checkpoint[] memory);

  function epochVaultStates(uint256 _epoch) external view returns (VaultState memory);

  function vaultConfiguration() external view returns (VaultConfiguration memory);

  function getEpochStrikes(uint256 _epoch) external view returns (uint256[] memory _strike_s);

  function getUnwindAmount(uint256 _optionsAmount, uint256 _optionStrike) external view returns (uint256 unwindAmount);

  function strikeMulAmount(uint256 _strike, uint256 _amount) external view returns (uint256);

  function isWithinExerciseWindow() external view returns (bool);

  function setPrivateMode(bool _mode) external;

  function getNextFundingRate() external view returns (uint256);
}

