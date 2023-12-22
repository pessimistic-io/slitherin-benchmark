// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import {LibraryStorage as ls} from "./LibraryStorage.sol";
import {LibDiamond as ds} from "./LibDiamond.sol";
import "./IFaucet1.sol";
import "./IV2Contract.sol";
import "./IGemChest.sol";
import "./IERC20.sol";
// import "hardhat/console.sol";


contract Faucet2 {
    
    IGemChest public gemChest;
    IV2Contract public iv2Contract;

    uint public getAmountOutMinState;

    event Deposit(string uuid, uint tokenId, uint _amountforDeposit,int price, string str);
    event Log(bool message);

    /** @dev Modifier to ensure that the caller has a specific role before executing a function.
     * The `role` parameter is a bytes32 hash that represents the role that the caller must have.   
     */
    modifier onlyRole(bytes32 role) {
        ds._checkRole(role);
        _;
    }

    /**
     * @dev Modifier to ensure that the contract is active
     */
    modifier isActive {
        require(ls.libStorage().isActive == true, "v2 isn't actived");
        _;
    }

    /**
     * @dev Returns information about a token.
     * @param _tokenAddress The address of the token to get information for.
     * @return The token's address, minimum amount, balance ,pricefeed address, number of decimals, and status.
     */
    function getToken(address _tokenAddress) external view returns(address, uint256, uint, address , uint, ls.Status){        
        return ls.getToken(_tokenAddress);
    }   

    /**
     * @dev Returns information about a locked asset.
     * @param assetid The ID of the locked asset to get information for.
     * @return The asset's locked tolen address, owner, beneficiary, creator, amount, fee rate, end date, claimed token amount ,lock price nn USD, target rate, features and status.
     */
    function getLockedAsset(uint256 assetid) external view returns (address, address, address ,uint256, uint256, uint256,uint256,int,uint, bool[] memory, ls.Status){
        return ls.getLockedAsset(assetid);    
    }

    /** 
     * @dev Adds a new token to the contract with the specified parameters.
     * Only the ADMIN role can call this function.
     * The token's status is set to OPEN by default.
     *
     * @param _address Address of the token contract to be added
     * @param _minAmount The minimum amount of the token that can be deposited
     * @param _priceFeedAddress Price feed address of token pair
     * @param _decimal The number of decimal places used by the token. 
     */
    function addToken(address _address, uint256 _minAmount, address _priceFeedAddress, uint8 _decimal) external onlyRole(ds.ADMIN) {
        ls.LibStorage storage lib = ls.libStorage();
        lib._tokenVsIndex[_address] = ls.Token({tokenAddress : _address, minAmount : _minAmount,
        priceFeedAddress : _priceFeedAddress, balance : 0, decimal : _decimal, status : ls.Status.OPEN});
    }

    function addTokenn(address[] memory _address, address[] memory _priceFeedAddress , uint256[] memory _minAmount, uint8[] memory _decimal) external onlyRole(ds.ADMIN) {
        ls.LibStorage storage lib = ls.libStorage();
        for(uint i=0; i < _address.length; i++){
            lib._tokenVsIndex[_address[i]] = ls.Token({tokenAddress : _address[i], minAmount : _minAmount[i],
            priceFeedAddress : _priceFeedAddress[i], balance : 0, decimal : _decimal[i], status : ls.Status.OPEN});
        }
    }

    /** @dev Adds a new token to the contract with the specified parameters.
     * Only the ADMIN role can call this function.
     * The token's status is set to OPEN by default.
     *
     * @param _token The address of the token contract to be added.
     * @param _priceFeedAddress Price feed address of token pair.
     * @param _minAmount The minimum amount of the token that can be deposited.
     * @param _isActive the boolean for token status
     * @param _decimal The number of decimal places used by the token.
     */
    function setToken(address _token, address _priceFeedAddress, uint _minAmount, bool _isActive, uint8 _decimal) external onlyRole(ds.ADMIN) {  
        ls.LibStorage storage lib = ls.libStorage();  
        ls.Token storage token = lib._tokenVsIndex[_token];
        token.priceFeedAddress = _priceFeedAddress;
        token.minAmount = _minAmount;
        token.decimal = _decimal; 
        token.status = _isActive  ? ls.Status.OPEN : ls.Status.CLOSE;
    }

    /**
     * @dev Sets the fee parameters for the contract.
     * Only the ADMIN role can call this function.
     * 
     * @param _startFee The starting fee for the contract.
     * @param _endFee The ending fee for the contract.
     * @param _affiliateRate The affiliate rate for the contract.
     * @param _arr array representing the fixed fees for the contract.
     */
    function setFee(uint8 _startFee, uint8 _endFee, uint8 _affiliateRate, uint8 _slippage, uint8 _rewardRate, uint[][] memory _arr) external onlyRole(ds.ADMIN) {
        ls.LibStorage storage lib = ls.libStorage();  
        lib.startFee = _startFee;
        lib.endFee = _endFee;
        lib.slippage = _slippage;
        lib.affiliateRate = _affiliateRate;
        lib.fixedFees = _arr;
        lib.rewardRate = _rewardRate;
    }
    
    /**
     * @dev This function swaps the balance of collected fees and transfer, but only if the caller has the ADMIN role.
     * @param _tokenIn The address of the token to swap from.
     */
    // */address _tokenOut*/
    //  * @param _tokenOut The address of the token to swap to.
    function swapTokenBalance(address _tokenIn) public onlyRole(ds.ADMIN) {
        ls.LibStorage storage lib = ls.libStorage();  
        ls.Token storage token = lib._tokenVsIndex[_tokenIn];
        uint swapingAmount = token.balance;
        token.balance = 0;
        // if (_tokenIn == _tokenOut) {
        ls.transferFromContract(_tokenIn, msg.sender, swapingAmount);
        // } else {
            // require(IFaucet1(payable(address(this))).swap( _tokenIn, _tokenOut, swapingAmount,  msg.sender)); 
        // }
    }

    /**
     * @dev This function checks if an array of assets can be claimed.
     * @param _arr The array of asset IDs to check.
     * @return ids An array of asset IDs, checked A boolean array representing whether each asset is claimable or not.
     */
    function checkClaim(uint[] calldata _arr) public view returns(uint[] memory ids, bool[] memory checked){
        ids = new uint[](_arr.length);
        checked = new bool[](_arr.length);
        for (uint i=0; i < _arr.length; i++){
            ids[i] = _arr[i];
            checked[i] = ls.claimable(_arr[i]);
        }
    }

    /**
     * @dev Migrates an asset to V2.
     * Only assets with an `OPEN` status, is not gift and is owned features can be migrated.
     * Only the beneficiary can call this function.
     * 
     * @param assetId The ID of the asset to be migrated.
     * 
     * The function sets the status of the asset to `CLOSE`, calls the `Migrate` function of the V2 contract to create a new asset,
     * burns the old asset, and transfers the asset amount to the V2 contract. If the asset token is ETH, the transfer is made via a call
     * with the ETH value in the transaction. Otherwise, the transfer is made using the `transfer` function of the token.
     */
    function migrateAsset(uint assetId) public isActive {
        ls.LibStorage storage lib = ls.libStorage();
        ls.LockedAsset storage asset = lib._idVsLockedAsset[assetId];        
        require(asset.status == ls.Status.OPEN && asset.features[0] && !asset.features[1] );
        require(msg.sender == asset.beneficiary);
        asset.status = ls.Status.CLOSE;
        iv2Contract.Migrate(
        asset.token, asset.beneficiary, asset.creator, asset.amount, asset.endDate,
        asset.feeRate, asset.priceInUSD, asset.target, asset.features);
        gemChest.burn(assetId);
        (bool sent,) = ls.libStorage().ETH == asset.token ?  lib.v2Contract.call{value: asset.amount} (""):
        (IERC20(asset.token).transfer(lib.v2Contract, asset.amount), bytes(""));
        require(sent);
    }

    // @notice this functions just used for tests. 
    function executeGetAmountOutMin(address _tokenIn, address _tokenOut, uint256 _amountIn) public {
        getAmountOutMinState = ls.getAmountOutMin(_tokenIn,_tokenOut, _amountIn);
    }   

    function getAmountOutMin() public view returns(uint){
        return getAmountOutMinState;
    }
    
}   

