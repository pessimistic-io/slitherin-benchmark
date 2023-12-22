// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IERC20.sol";
import "./AggregatorV3Interface.sol";
import "./IQuoter.sol";
import "./Strings.sol";
// import "hardhat/console.sol";


// Define the LibraryStorage library.
library LibraryStorage {

    // The LIB_STORAGE_POSITION constant represents the storage slot of the library.
    bytes32 constant LIB_STORAGE_POSITION = keccak256("diamond.standard.lib.storage");

    // The Status enum represents the possible status values for a Token or LockedAsset.
    enum Status {x, CLOSE, OPEN}

    // The Deposit event is emitted when a deposit is made.
    event Deposit( uint indexed num, address ETH, string str);
    
    // The Claim event is emitted when a claim is made.
    event Claim(string success);


    /**
     * @dev This struct represents a token, which includes its address, price feed address,
     * minimum amount to lock, collected fee balance, decimal, and status.
     */
    struct Token {
        address tokenAddress;
        address priceFeedAddress;
        uint minAmount;
        uint balance;
        uint8 decimal;
        Status status;
    }


    struct depositParams {
        address[] _addr ;
        uint _amount;
        uint _otherFees; 
        uint _endDate;
        uint _target;
        bool[] _features;
        string _uuid;
    }

    /** The LockedAsset struct represents a locked asset.
     * @dev This struct represents a locked asset, which includes the token being locked,
     * the beneficiary who will receive the asset after the lockup period, the creator of the lock, 
     * the amount being locked, the claimed amount, the end date of the lockup period, the fee rate 
     * (expressed as a percentage), the price of the asset in USD at the time of creation, 
     * the target rate (expressed as a percentage) the asset, an array of boolean is gift and 
     * is owned features, and the status of the lock.
     */
    struct LockedAsset {
        address token;
        address beneficiary;
        address creator;
        uint amount;
        uint claimedAmount;
        uint endDate;
        uint8 feeRate;
        int priceInUSD;
        uint target;
        bool[] features;
        Status status;
    }

    // The LibStorage struct represents the storage for the LibraryStorage library.
    struct LibStorage {
        address UNISWAP_V3_ROUTER;
        address QUOTER_ADDRESS;
        address ETH;
        address WETH;
        address SIGNER;
        address GemChestAddress;
        uint8 startFee;
        uint8 endFee;
        uint8 affiliateRate;
        uint8 slippage;
        uint8 rewardRate;
        uint24  routerSwapFee;
        uint _lockId;
        Token Token;
        Status status;
        mapping(address => Token) _tokenVsIndex;
        mapping(uint256 => LockedAsset) _idVsLockedAsset;
        uint[][] fixedFees;
        address v2Contract;
        bool isActive;
        bool initialized;
    }

    // The libStorage function returns the storage for the LibraryStorage library.
    function libStorage() internal pure returns (LibStorage storage lib) {
        bytes32 position = LIB_STORAGE_POSITION;
        assembly {
            lib.slot := position
        }
    }
    
    // The getToken function returns information about a token.
    function getToken(address _tokenAddress) internal view returns(
        address tokenAddress, 
        uint256 minAmount, 
        uint balance, 
        address priceFeedAddress,
        uint8 decimal,
        Status status
    )
    {
        LibStorage storage lib = libStorage();
        Token memory token = lib._tokenVsIndex[_tokenAddress];
        return (token.tokenAddress, token.minAmount, token.balance, token.priceFeedAddress, token.decimal, token.status);
    }

    // The getLockedAsset function returns information about a locked asset
    function getLockedAsset(uint256 assetId) internal view returns(
        address token,
        address beneficiary,
        address creator,
        uint256 amount,
        uint8 feeRate,
        uint256 endDate,
        uint256 claimedAmount,
        int priceInUSD,
        uint target,
        bool[] memory features,
        Status status
    )
    {
        LibStorage storage lib = libStorage();
        LockedAsset memory asset = lib._idVsLockedAsset[assetId];
        token = asset.token;
        beneficiary = asset.beneficiary;
        creator = asset.creator;
        amount = asset.amount;
        feeRate = asset.feeRate;
        endDate = asset.endDate;
        claimedAmount = asset.claimedAmount;
        priceInUSD = asset.priceInUSD;
        target = asset.target;
        features = asset.features;
        status = asset.status;
        return(
            token,                          
            beneficiary,
            creator,
            amount,
            feeRate,
            endDate,
            claimedAmount,
            priceInUSD,
            target,
            features,
            status       
        );
    }

    /** 
     * @dev This function calculates a fee based on a given amount, a percentage, and a boolean to indicate whether to add or subtract the fee.
     */
    function _calculateFee(uint amount, bool plus, uint procent) internal pure returns(uint256 calculatedAmount) { 
        // Calculate the fee based on the given percentage.
        uint reminder = amount * procent / 100;
        // If the percentage is 0, the calculated amount is just the original amount.
        calculatedAmount = procent == 0 ? amount : (plus) ? amount + reminder : amount - reminder;
    }

    /**
     * @dev This function calculates a fixed fee based on the current price of the token.
     */
    function _calculateFixedFee(address _token, uint amount, bool plus) internal view returns(uint256 calculatedAmount) { 
        LibStorage storage lib = libStorage();
        Token memory token = lib._tokenVsIndex[_token];        
        uint fixedAmount = (uint(getLatestPrice(token.priceFeedAddress)) * amount) / (10**token.decimal);        

        uint fee = lib.fixedFees[lib.fixedFees.length-1][1];
        for(uint i; i < lib.fixedFees.length; i++) {
            if (fixedAmount <= lib.fixedFees[i][0]){
                fee = lib.fixedFees[i][1];
                break;
            }
        }
        calculatedAmount = _calculateFee(amount, plus, fee);
    }

    /**
     *@dev Gets the latest price for a given price feed address.
     *@param _priceFeedAddress The address of the price feed.
     *@return The latest price.
     */
    function getLatestPrice(address _priceFeedAddress) internal view returns (int) {   
        AggregatorV3Interface priceFeed;
        priceFeed = AggregatorV3Interface(_priceFeedAddress);
        ( /*uint80 roundID*/,
        int price,
        /*uint startedAt*/,
        /*uint timeStamp*/,
        /*uint80 answeredInRound*/
        ) = priceFeed.latestRoundData();

        return price;
    }

    /**
     * @dev Helper function to get the path of token pairs for later actions.
     * @param _tokenIn The address of the token to swap from.
     * @param _tokenOut The address of the token to swap to.
     * @return path of tokens.
     */
    function getPath(address _tokenIn, address _tokenOut) internal view returns(address[] memory path){
        LibStorage storage lib = libStorage();
        path = new address[](2);
        if (_tokenIn == lib.ETH){
            path[0] = lib.WETH;
            path[1] = _tokenOut;
        } else if (_tokenOut == lib.ETH) {
            path[0] = _tokenIn;
            path[1] = lib.WETH;
        } else {
            path[0] = _tokenIn;
            path[1] = _tokenOut;
        }
    }

    // The getMessageHash function takes a message string and returns its keccak256 hash.
    function getMessageHash(string memory _message) internal pure returns (bytes32){
        return keccak256(abi.encodePacked(_message));
    }

    // The getEthSignedMessageHash function takes a message hash and returns its hash as an Ethereum signed message.
    function getEthSignedMessageHash(bytes32 _messageHash) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked("\x19Ethereum Signed Message:\n32", _messageHash));
    }

    // The verify function takes a message, signature, and signer address and returns a boolean indicating whether the signature is valid for the given message and signer.
    function verify(string memory message, bytes memory signature, address signer) internal pure returns (bool) {
        bytes32 messageHash = getMessageHash(message);
        bytes32 ethSignedMessageHash = getEthSignedMessageHash(messageHash);

        return recoverSigner(ethSignedMessageHash, signature) == signer;
    }

    // The recoverSigner function takes an Ethereum signed message hash and a signature and returns the address that signed the message.
    function recoverSigner(bytes32 _ethSignedMessageHash, bytes memory _signature) internal pure returns (address){
        (bytes32 r, bytes32 s, uint8 v) = splitSignature(_signature);
        return ecrecover(_ethSignedMessageHash, v, r, s);
    }

    // The recoverSigner function takes an Ethereum signed message hash and a signature and returns the address that signed the message.
    function splitSignature(bytes memory sig) internal pure returns (bytes32 r,bytes32 s,uint8 v){
        require(sig.length == 65, "invalid signature length");
        assembly { 
            r := mload(add(sig, 32))
            s := mload(add(sig, 64))
            v := byte(0, mload(add(sig, 96)))
        }
    }

    /** 
     * @dev This function calculates the estimated minimum amount of `_tokenOut` tokens that can be received for a given `_amountIn` of `_tokenIn` tokens
     */
    function getAmountOutMin(address _tokenIn, address _tokenOut, uint256 _amountIn) internal returns(uint256 amountOut) {
        address[] memory path = getPath(_tokenIn, _tokenOut);
        try IQuoter(libStorage().QUOTER_ADDRESS).quoteExactInputSingle(path[0],path[1], libStorage().routerSwapFee ,_amountIn,0)
        returns (uint _amountOut) {
            return _amountOut;
        } catch {
            amountOut=0;
        }
    }


    /**
     * @dev This helper function checks if a locked asset with the given `id` can be claimed
     */
    function claimable(uint256 id) internal view returns(bool success){
        LockedAsset memory asset = libStorage()._idVsLockedAsset[id];
        // Check if the claim period has ended or if the asset has already been claimed, and if the status of the asset is open
        success = (asset.endDate <= block.timestamp || _eventIs(id)) &&  asset.status == Status.OPEN ? true : false;
    }

    /**
     * @dev This function Check if the given asset current price greater or equal to the target price  
     * @param id locked asset id
     */
    function _eventIs(uint id) internal view returns(bool success) { 
        LockedAsset memory asset = libStorage()._idVsLockedAsset[id];
        if (asset.status == Status.CLOSE || asset.status == Status.x){
            return false;
        }
        else {
            ( /*address tokenAddress*/,
                /*uint256 minAmount*/,
                /*uint balance*/,
                address _priceFeedAddress,
                /* uint8 decimal*/,
                /*Status status*/
            ) = getToken(asset.token);
            // Get the latest price of the token from the price feed using the oracle contract
            int oraclePrice = getLatestPrice(_priceFeedAddress);
            // Check if the current price of the token is greater than or equal to the target price of the asset amount
            success = oraclePrice * 5 >= (asset.priceInUSD * int(asset.target)) / 100 ? true : false;
        } 
    }

    /**
     * 
     * @dev Internal function to transfer funds from the contract to a given receiver.
     * @param _token The address of the token to transfer.
     * @param _receiver The address to receive the funds.
     * @param _value The amount of funds to transfer.
     */
    function transferFromContract (address _token, address _receiver, uint _value) internal {
        (bool sent,) = (_token == libStorage().ETH) ?  payable(_receiver).call{value: _value} ("") : (IERC20(_token).transfer(_receiver,_value), bytes(""));
        require(sent, "tx failed");
    } 

    function getAmountOraclePrice (address _token, address _swapToken, uint newAmount) internal view returns(uint amountOraclePrice) {
        LibStorage storage lib = libStorage();
        Token memory token = lib._tokenVsIndex[_token];
        uint8 oraclePriceLenght = uint8(bytes(Strings.toString( uint(getLatestPrice(token.priceFeedAddress)))).length);
        oraclePriceLenght = (oraclePriceLenght >= 8 ) ? 8 : (17 - oraclePriceLenght);
        amountOraclePrice = ((( uint(getLatestPrice(token.priceFeedAddress)) * newAmount ) / 10** token.decimal )  
        * 10**lib._tokenVsIndex[_swapToken].decimal) / 10 ** oraclePriceLenght;
        amountOraclePrice -= (amountOraclePrice * lib.slippage) / 100;
    } 
}



/** 
                                                         \                           /      
                                                          \                         /      
                                                           \                       /       
                                                            ]                     [    ,'| 
                                                            ]                     [   /  | 
                                                            ]___               ___[ ,'   | 
                                                            ]  ]\             /[  [ |:   | 
                                                            ]  ] \           / [  [ |:   | 
                                                            ]  ]  ]         [  [  [ |:   | 
                                                            ]  ]  ]__     __[  [  [ |:   | 
                                                            ]  ]  ] ]\ _ /[ [  [  [ |:   | 
                                                            ]  ]  ] ] (#) [ [  [  [ :====' 
                                                            ]  ]  ]_].nHn.[_[  [  [        
                                                            ]  ]  ]  HHHHH. [  [  [        
                                                            ]  ] /   `HH("N  \ [  [        
                                                            ]__]/     HHH  "  \[__[        
                                                            ]         NNN         [        
                                                            ]         N "         [          
                                                            ]         N H         [        
                                                           /          N            \        
                                                          /     how far you can     \       
                                                         /        go mr.Green ?      \          
                                                    
*/
