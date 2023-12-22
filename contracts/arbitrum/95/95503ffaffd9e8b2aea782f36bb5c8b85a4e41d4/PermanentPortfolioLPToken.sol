// SPDX-License-Identifier: MIT
// The code defines a Solidity contract called AllWeatherPortfolioLPToken that inherits from ERC20. It takes in several parameters on construction, including asset, radiantVaultAddr, and dpxVaultAddr. The contract has several functions that do the following:

// deposit: Takes in an amount and transfers tokens of asset from the user to the contract, then distributes the asset into two protocols (DPX and Radiant) based on a portfolioAllocation. The user receives an ERC20 token (AWVLP) in proportion to their deposit.
// redeem: Takes in a number of shares and an account, then redeems all DPX LP Tokens and sends them to the account. Only DPX LP tokens are redeemed. The proportion of redeemed tokens is distributed to the sender's ERC20 tokens (AWVLP).
// claimableRewards: Takes in an account, calculates the user's claimable rewards across both protocols and returns them.
// claim: Takes in an account and reward tokens, and claims all the available rewards across both protocols, sending them to the account.
// The code imports several open source libraries and uses various data structures like struct, bytes, and mapping. The SPDX-License-Identifier specifies the license for the code (MIT in this case).

pragma solidity 0.8.18;
import "./IERC20.sol";
import "./MagicArbitrumVault.sol";
import "./EquilibriaGlpVault.sol";
import "./EquilibriaGDAIVault.sol";
import "./EquilibriaRETHVault.sol";
import "./EquilibriaPendleVault.sol";
import "./RadiantArbitrumVault.sol";
import "./BasePortfolio.sol";

contract PermanentPortfolioLPToken is BasePortfolio {
  using SafeERC20 for IERC20;
  using SafeMath for uint256;

  constructor(
    address asset_,
    string memory name_,
    string memory symbol_,
    address equilibriaVaultAddr,
    address equilibriaGDAIVaultAddr,
    address equilibriaRETHVaultAddr,
    address payable magicArbitrumVaultAddr,
    address equilibriaPendleVaultAddr,
    address radiantVaultAddr
  ) BasePortfolio(asset_, name_, symbol_) {
    require(
      equilibriaVaultAddr != address(0),
      "equilibriaVaultAddr cannot be zero"
    );
    require(
      equilibriaGDAIVaultAddr != address(0),
      "equilibriaGDAIVaultAddr cannot be zero"
    );
    require(
      equilibriaRETHVaultAddr != address(0),
      "equilibriaRETHVaultAddr cannot be zero"
    );
    require(
      magicArbitrumVaultAddr != address(0),
      "magicArbitrumVaultAddr cannot be zero"
    );
    require(
      equilibriaPendleVaultAddr != address(0),
      "equilibriaPendleVaultAddr cannot be zero"
    );
    require(radiantVaultAddr != address(0), "radiantVaultAddr cannot be zero");

    vaults = [
      AbstractVault(EquilibriaGlpVault(equilibriaVaultAddr)),
      AbstractVault(EquilibriaGDAIVault(equilibriaGDAIVaultAddr)),
      AbstractVault(EquilibriaRETHVault(equilibriaRETHVaultAddr)),
      AbstractVault(EquilibriaPendleVault(equilibriaPendleVaultAddr)),
      AbstractVault(MagicArbitrumVault(magicArbitrumVaultAddr)),
      AbstractVault(RadiantArbitrumVault(radiantVaultAddr))
    ];
  }
}

