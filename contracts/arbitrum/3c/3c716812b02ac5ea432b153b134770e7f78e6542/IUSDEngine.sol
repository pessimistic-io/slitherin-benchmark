// SPDX-License-Identifier: MIT
pragma solidity ^0.8.15;

/**

********\                                                
\__**  __|                                               
   ** | ******\   ******\   ******\  **\   **\  ******\  
   ** |**  __**\ **  __**\ **  __**\ ** |  ** |**  __**\ 
   ** |** /  ** |** |  \__|** /  ** |** |  ** |******** |
   ** |** |  ** |** |      ** |  ** |** |  ** |**   ____|
   ** |\******  |** |      \******* |\******  |\*******\ 
   \__| \______/ \__|       \____** | \______/  \_______|
                                 ** |                    
                                 ** |                    
                                 \__|                    

 */

interface IUSDEngine {
    ///////////////////
    // Errors
    ///////////////////
    error USDEngine__TokenAddressesAndPriceFeedAddressesAmountsDontMatch();
    error USDEngine__NeedsMoreThanZero();
    error USDEngine__TokenNotAllowed(address token);
    error USDEngine__TransferFailed();
    error USDEngine__BreaksHealthFactor(uint256 healthFactorValue);
    error USDEngine__MintFailed();
    error USDEngine__HealthFactorOk();
    error USDEngine__HealthFactorNotImproved();
    error USDEngine__NotLatestPrice();
    error OracleLib__StalePrice();

    ///////////////////
    // Events
    ///////////////////
    event CollateralDeposited(address indexed user, address indexed token, uint256 indexed amount);
    event CollateralRedeemed(address indexed redeemedFrom, uint256 indexed amountCollateral, address from, address to); // if from != to, then it was liquidated
}

