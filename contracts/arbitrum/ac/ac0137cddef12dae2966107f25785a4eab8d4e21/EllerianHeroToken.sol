pragma solidity ^0.8.0;
//SPDX-License-Identifier: MIT

import "./IEllerianHero.sol";
import "./IERC20.sol";
import "./Ownable.sol";

/** 
 * Tales of Elleria
*/
contract EllerianHeroToken is Ownable {

    bool private globalMintOpened = false;
    uint256 private transactionLimit = 10;

    uint256[][] private tokenMintPrice = [[150000000000000000000,30000000000000000000]];
    address[][] private tokenMintPair;

    IEllerianHero private minterAbi;

    //address private mintBurnAddress;
    address private feesAddress;

    function GetVariantMintCost(uint256 _variant) public view returns (uint256[] memory) {
        return tokenMintPrice[_variant];
    }

     function GetMintingPair(uint256 _variant) public view returns (address[] memory) {
        return tokenMintPair[_variant];
    }
    
    /*
    * Allows the owner to block or allow minting.
    */
    function SetGlobalMint(bool _allow) external onlyOwner {
        globalMintOpened = _allow;
    }

    function SetTransactionLimit(uint256 _limit) external onlyOwner {
        transactionLimit = _limit;
    }

    /*  
    * Adjusts the prices and tokens used for payment.
    */
    function SetMintingPrices(uint256[][] memory _mintPricesInWEI, address[][] memory _mintPairAddresses) external onlyOwner{
        tokenMintPrice = _mintPricesInWEI;
        tokenMintPair = _mintPairAddresses;
        globalMintOpened = false;
    }

    /*
    * Link with other contracts necessary for this to function.
    */
    function SetAddresses(address _minterAddress, address _feesAddress/*, address _mintBurnAddress*/) external onlyOwner {
        minterAbi = IEllerianHero(_minterAddress);

        feesAddress = _feesAddress;
        //mintBurnAddress = _mintBurnAddress;
    }

    function AttemptMint(uint256 _variant, uint256 _amount) external {
        require(_amount <= transactionLimit, "LIMIT");
        require (globalMintOpened, "ERR16");
        require (tx.origin == msg.sender, "9");

        // 10 + 1
        if (_amount == 10) _amount = 11;

        // Collect payments from both tokens.
        IERC20(tokenMintPair[_variant][0]).transferFrom(msg.sender, feesAddress, tokenMintPrice[_variant][0]);
        IERC20(tokenMintPair[_variant][1]).transferFrom(msg.sender, feesAddress, tokenMintPrice[_variant][1]);

        // Tell the main contract to let us mint.
        minterAbi.mintUsingToken(msg.sender, _amount, _variant);
    }
}
