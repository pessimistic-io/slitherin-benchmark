// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./AavePool.sol";
import "./GmxPool.sol";
import "./AddressesArbitrum.sol";

import { CompositionToken, PullOptions} from "./Structs.sol";

library Allocate {
  using SafeERC20Upgradeable for IERC20Upgradeable;

  /// @notice pull all assets from yield pool based on debt assets
  function pullFromYieldingPool(address yieldingPoolAddress, address lendingPoolAddress) internal {
    address[2] memory debtTokenAddresses = [
      Addresses.WBTC_DEBT_VARIABLE_ADDRESS,
      Addresses.WETH_DEBT_VARIABLE_ADDRESS
    ];

    // Withdraw Debt Tokens from GLP 
    for (uint8 index; index < debtTokenAddresses.length; index++) {
      address assetAddress = debtTokenAddresses[index];
      // Checks if the asset to be swapped is a debt token and swap for a non-debt token
      if (assetAddress == Addresses.WBTC_DEBT_VARIABLE_ADDRESS) {
        assetAddress = Addresses.WBTC_ADDRESS;
      } else if (assetAddress == Addresses.WETH_DEBT_VARIABLE_ADDRESS) {
        assetAddress = Addresses.WETH_ADDRESS;
      }

      IYieldingPool(yieldingPoolAddress)
        .pullAndTransfer(
          assetAddress,
          IERC20Upgradeable(debtTokenAddresses[index]).balanceOf(lendingPoolAddress),
          abi.encode(PullOptions(0)),
          lendingPoolAddress
        );
    }

    //  Withdraw any remaining GLP as USDC
    IYieldingPool(yieldingPoolAddress)
      .pullAndTransfer(
        Addresses.USDC_ADDRESS,
        type(uint256).max,
        abi.encode(PullOptions(0)),
        lendingPoolAddress
      );
  }

  /// @notice sends all available USDC to the lending pool
  function supplyToLendingPool(address lendingPoolAddress) internal {
    uint256 usdcAmount = IERC20Upgradeable(Addresses.USDC_ADDRESS).balanceOf(address(this)) * 6666 / 10000;
    if(usdcAmount > 0) {
      IERC20Upgradeable(Addresses.USDC_ADDRESS).safeIncreaseAllowance(lendingPoolAddress, usdcAmount);
      IERC20Upgradeable(Addresses.USDC_ADDRESS).transfer(lendingPoolAddress, usdcAmount);
    }

    // Supply USDC to Aave
    ILendingPool(lendingPoolAddress).supply(
      Addresses.USDC_ADDRESS,
      usdcAmount
    );
  }

  /// @notice borrows the token based on the composition of GLP
  /// @param transfer if true, it will transfers the borrowed tokens from lending pool to the yield pool
  function borrowFromLendingPool(
    address lendingPoolAddress,
    address yieldingPoolAddress,
    uint256 borrowRate,
    CompositionToken[] memory compositions,
    bool transfer
  ) internal {
    uint256 totalWeight = 0;
    //  Calculates the borrowable amount of tokens in USDC based on our risk appetite (borrow rate)
    uint256 borrowableAmountInUsdc = IERC20Upgradeable(Addresses.AUSDC_ADDRESS)
                                      .balanceOf(address(lendingPoolAddress))
                                      * borrowRate
                                      / 100000
                                      * 6666
                                      / 10000;
    
    // Get total weight
    for (uint index = 0; index < compositions.length; index++) {
      totalWeight += compositions[index].weight;
    }

    // Borrow based on weights
    for (uint index = 0; index < compositions.length; index++) {
      // Amount in token's value that we can borrow for this allocation token
      uint256 borrowableTokenAmount = borrowableAmountInUsdc
                                        * compositions[index].weight
                                        / totalWeight
                                        * (
                                          10 ** (compositions[index].tokenDecimals - 6)
                                        ) 
                                        / (
                                          compositions[index]
                                            .maxPrice
                                            / (10 ** 30)
                                        );

      if (transfer == true) {
        //  Borrow tokens. Variable interest rate have a setting of integer: 2
        //  Transfers the token to the yield pool
        ILendingPool(lendingPoolAddress)
          .borrowAndTransfer(
            compositions[index].tokenAddress,
            borrowableTokenAmount,
            2,
            yieldingPoolAddress
          );
      } else {
        ILendingPool(lendingPoolAddress)
          .borrow(
            compositions[index].tokenAddress,
            borrowableTokenAmount,
            2
          );
      }
    }
  }
}
