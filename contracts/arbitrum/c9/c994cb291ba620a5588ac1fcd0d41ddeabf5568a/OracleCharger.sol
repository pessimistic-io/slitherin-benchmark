// SPDX-License-Identifier: MIT
// Metaline Contracts (OracleCharger.sol)

pragma solidity ^0.8.0;

import "./ERC20.sol";

import "./TransferHelper.sol";

interface TokenPriceOracle {
    // returns 8 decimal usd price, token usd value = token count * retvalue / 100000000;
    function getERC20TokenUSDPrice(address tokenAddr) external returns(uint256);
}

library OracleCharger {

    struct ChargeTokenSet {
        uint8 decimals;
        address tokenAddr;
        uint256 maximumUSDPrice;
        uint256 minimumUSDPrice;
    }

    struct OracleChargerStruct {
        uint locked;
        address tokenPriceOracleAddr;
        address receiveIncomeAddr;
        mapping(string=>ChargeTokenSet) chargeTokens;
    }
    
    modifier lock(OracleChargerStruct storage charger) {
        require(charger.locked == 0, 'OracleCharger: LOCKED');
        charger.locked = 1;
        _;
        charger.locked = 0;
    }

    function setTPOracleAddr(OracleChargerStruct storage charger, address tpOracleAddr) internal {
        charger.tokenPriceOracleAddr = tpOracleAddr;
    }

    function setReceiveIncomeAddr(OracleChargerStruct storage charger, address incomeAddr) internal {
        charger.receiveIncomeAddr = incomeAddr;
    }

    function addChargeToken(
        OracleChargerStruct storage charger, 
        string memory tokenName, 
        address tokenAddr, 
        uint256 maximumUSDPrice, 
        uint256 minimumUSDPrice
        ) internal 
    {
        uint8 decimals = 18;
        if(tokenAddr != address(0)){
            decimals = ERC20(tokenAddr).decimals();
        }

        charger.chargeTokens[tokenName] = ChargeTokenSet({
            decimals:decimals,
            tokenAddr:tokenAddr,
            maximumUSDPrice:maximumUSDPrice,
            minimumUSDPrice:minimumUSDPrice
        });
    }

    function removeChargeToken(OracleChargerStruct storage charger, string memory tokenName) internal {
        delete charger.chargeTokens[tokenName];
    }

    function charge(OracleChargerStruct storage charger, string memory tokenName, uint256 usdValue) internal lock(charger) {
        require(charger.receiveIncomeAddr != address(0), "income addr not set");

        ChargeTokenSet storage tokenSet = charger.chargeTokens[tokenName];
        require(tokenSet.decimals > 0, "token not set");

        // get eth usd price
        uint256 tokenUSDPrice = TokenPriceOracle(charger.tokenPriceOracleAddr).getERC20TokenUSDPrice(tokenSet.tokenAddr);
        if(tokenSet.minimumUSDPrice > 0 && tokenUSDPrice < tokenSet.minimumUSDPrice) {
            tokenUSDPrice = tokenSet.minimumUSDPrice;
        }
        if(tokenSet.maximumUSDPrice > 0 && tokenUSDPrice > tokenSet.maximumUSDPrice) {
            tokenUSDPrice = tokenSet.maximumUSDPrice;
        }
        uint256 tokenCost = usdValue * 10**tokenSet.decimals / tokenUSDPrice;

        if(tokenSet.tokenAddr == address(0)){
            // charge eth
            require(msg.value >= tokenCost, "insufficient eth");
            (bool sent, ) = charger.receiveIncomeAddr.call{value: tokenCost}("");
            require(sent, "Trans fee err");
            if(msg.value > tokenCost){
                // send back
                (sent, ) = msg.sender.call{value: (msg.value - tokenCost)}("");
                require(sent, "Trans fee err");
            }
        }
        else {
            // charge erc20

            require(IERC20(tokenSet.tokenAddr).balanceOf(msg.sender) >= tokenCost, "insufficient token");

            TransferHelper.safeTransferFrom(tokenSet.tokenAddr, msg.sender, charger.receiveIncomeAddr, tokenCost);
        }
    }
    
}


