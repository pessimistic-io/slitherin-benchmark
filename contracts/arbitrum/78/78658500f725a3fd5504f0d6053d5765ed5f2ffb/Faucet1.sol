// SPDX-License-Identifier: MIT
pragma solidity ^0.8.9;

import "./IGemChest.sol";

import "./IERC20.sol";
import "./Strings.sol";
import "./ISwapRouter.sol";
import "./IV2Contract.sol";
import { LibDiamond as ds } from "./LibDiamond.sol";
import {LibraryStorage as ls} from "./LibraryStorage.sol";
// import "hardhat/console.sol";

contract Faucet1 { 

    IGemChest gemChest;
    IV2Contract V2Contract;

    event Deposit(string uuid, uint tokenId, uint _amountforDeposit, int price, address _addr, string str);
    event Claim(string success);
    event BulkClaim(uint[]);
    event BulkFalse(uint);
    
    error errClaim(uint _id, string _str);
    
    /** 
     * @dev Modifier to ensure that the caller has a specific role before executing a function.
     * The `role` parameter is a bytes32 hash that represents the role that the caller must have.   
     */
    modifier onlyRole(bytes32 role) {
        ds._checkRole(role);
        _;
    }

    receive() external payable {}


    /**
     * @dev Initializes the LibStorage library with default values.
     * Access is restricted to users with the `ADMIN` role.
     * 
     * @param nftAddress The address of the GemChest nft contract.
     * @param weth The address of the Wrapped Ethereum.      
     */
    function initialize (address nftAddress, address signer, address quoter, address swapRouter, address weth) onlyRole(ds.ADMIN) external {   
        ls.LibStorage storage lib = ls.libStorage();
        require(!lib.initialized, "already initialized");
        lib.initialized = true;        
        gemChest = IGemChest(nftAddress); 
        lib.GemChestAddress = nftAddress;
        lib.ETH = 0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE;
        lib.SIGNER = signer;
        lib.QUOTER_ADDRESS = quoter;
        lib.UNISWAP_V3_ROUTER = swapRouter; 
        lib.WETH = weth;
        lib._lockId = 1;
        lib.routerSwapFee = 3000;
    }


    /**
     * @dev Sets the v2Contract address and activates it in the LibStorage library.
     * Access is restricted to users with the `ADMIN` role.
     * 
     * @param _v2Contract The address of the v2Contract to set.
     */
    function activateV2Contract(address _v2Contract) external onlyRole(ds.ADMIN) {
            ls.LibStorage storage lib = ls.libStorage();
            V2Contract = IV2Contract(_v2Contract); 
            lib.v2Contract = _v2Contract;
            lib.isActive = true;   
    }

    // /**
    // //  * @dev Allows users to deposit tokens into the contract, locking them for a specific period of time and 
    // //  * on the expected percentage of growth:
    // //  * @param _addr An array containing the token address, the beneficiary address, and an optional affiliate address.
    // //  * @param _amount The amount of tokens to deposit.
    // //  * @param _otherFees Additional fees associated with the deposit.
    // //  * @param _endDate The date until which the tokens will be locked.
    // //  * @param _target The target price for the token.
    // //  * @param _features An array of boolean values indicating the features of the locked tokens.
    // //  * @param _uuid A unique identifier for the deposit.
    //  */
    function deposit(
        ls.depositParams calldata params
    ) 
        public payable
    {
        ls.LibStorage storage lib = ls.libStorage();
        ls.Token storage token = lib._tokenVsIndex[params._addr[0]];
        require(token.status == ls.Status.OPEN, "invalid _token");
        require(params._endDate > block.timestamp, "invalid _endDate");
        require(params._amount >= token.minAmount, "incorect _amount");
        uint newAmount = ls._calculateFixedFee(params._addr[0], params._amount, true);
        uint totalAmount = newAmount + params._otherFees;
        require(lib.ETH == params._addr[0] ? 
        msg.value >= totalAmount : IERC20(params._addr[0]).transferFrom(msg.sender, address(this), totalAmount), "tx.failed");
        uint affiliateFee = (newAmount - params._amount) * lib.affiliateRate / 100;
        token.balance += (totalAmount - params._amount - affiliateFee);
        uint tokenId = lib._lockId++;
        int priceInUSD = ls.getLatestPrice(token.priceFeedAddress);
        lib._idVsLockedAsset[tokenId] = ls.LockedAsset({ token : params._addr[0], beneficiary : params._addr[1],
        creator : msg.sender, amount : params._amount, feeRate : lib.endFee, endDate : params._endDate, target :params._target, 
        claimedAmount : 0, priceInUSD : priceInUSD, features : params._features, status : ls.Status.OPEN });
        (!params._features[0]) ? gemChest.safeMint(address(this),tokenId) : gemChest.safeMint(params._addr[1], tokenId);
        params._addr[2] == address(0) ? () : ls.transferFromContract(params._addr[0], params._addr[2], affiliateFee);
        emit Deposit(params._uuid, tokenId, params._amount, priceInUSD, msg.sender, "Success");
    }

    /**
     * @dev Claims rewards for multiple NFTs in bulk.
     * Access is restricted to users with the `ADMIN` role.
     *
     * @param _ids An array of NFT IDs to claim rewards for.
     * @param _swapToken The address of the token to use for swapping to the desired reward.
     * @return A boolean indicating whether the claim was successful.
     */
    function bulkClaim(uint[] calldata _ids, address _swapToken) external onlyRole(ds.ADMIN) returns(bool) {
        for(uint i=0; i < _ids.length; i++){
            bool res = ls.claimable(_ids[i]);
            if (res==false) {
                emit BulkFalse(_ids[i]);
                revert errClaim(_ids[i], "bulkClaim error");
            } 
            claim(_ids[i],_swapToken);
        }
        emit BulkClaim(_ids);
        return true;
    }

    /**
     * @dev Claim function allows the owner of the asset to claim it after its vesting period ends 
     * or price of locked asset equal or grather then asset target rate.
     *
     * @param _id The ID of the locked asset.
     * @param _swapToken The address of the token to be used for swapping. 
     */
    function claim(uint256 _id, address _swapToken) public {
        uint giftreward;
        uint amountOutMinimum;
        bool swapped;
        uint swappedAmount;
        bool giftRewardReady;
        ls.LibStorage storage lib = ls.libStorage();
        ls.LockedAsset storage asset = lib._idVsLockedAsset[_id];
        ls.Token storage token = lib._tokenVsIndex[asset.token];
        require(ds.hasRole(ds.ADMIN, msg.sender) || msg.sender == asset.beneficiary, "only owner");
        bool eventIs = ls._eventIs(_id);
        require((asset.endDate <= block.timestamp || eventIs ) &&  asset.status == ls.Status.OPEN, "can't claim");
        asset.status = ls.Status.CLOSE;
        uint newAmount = ls._calculateFee(asset.amount, false, asset.feeRate);
        token.balance += (asset.amount - newAmount);         
        address receiver = (!asset.features[0]) ? address(this) : asset.beneficiary;
        if (asset.features[1] && eventIs && asset.creator != asset.beneficiary){
            giftRewardReady = true;
            giftreward = (newAmount * lib.rewardRate) / 100;            
            newAmount -= giftreward;
            if(!asset.features[2]){
                ls.transferFromContract(asset.token, asset.creator, giftreward);
            }
        }
        if (asset.features[2] && asset.token != _swapToken) {
            require(lib._tokenVsIndex[_swapToken].status == ls.Status.OPEN);
            amountOutMinimum = ls.getAmountOutMin(asset.token, _swapToken, newAmount) ;           
            if (amountOutMinimum >= ls.getAmountOraclePrice(asset.token,_swapToken,newAmount)){
                (swapped, swappedAmount) = swap(asset.token, _swapToken, newAmount,receiver);                
                require(swapped);
                if(giftRewardReady && giftreward > 0 ){
                    (swapped,) = swap(asset.token, _swapToken, giftreward, asset.creator);
                    require(swapped);
                }
            } else {
                if (asset.features[0]){
                    ls.transferFromContract(asset.token, receiver, newAmount);
                }
            }
        } else {
            if (asset.features[0]){
                ls.transferFromContract(asset.token, receiver, newAmount);
            }
        }
        asset.claimedAmount = (!asset.features[0]) ? ((asset.features[2] && swapped) ? swappedAmount : newAmount) : 0 ;
        gemChest.burn(_id);
        emit Claim("Claim is done successfully");     
    }

    /**
     * @dev swap function allows swapping of tokens using UniswapV3.
     * @param _tokenIn The input token address.
     * @param _tokenOut The output token address.
     * @param _amountIn The amount to be swapped.
     * @param _to The address to receive the swapped tokens.
     */
    function swap (address _tokenIn, address _tokenOut, uint _amountIn,address _to) internal returns (bool,uint){
        ls.LibStorage storage lib = ls.libStorage();
        address[] memory path = ls.getPath(_tokenIn,_tokenOut);        
        uint swappingAmount;
        if (_tokenIn != lib.ETH){
            require(IERC20(_tokenIn).approve(lib.UNISWAP_V3_ROUTER, _amountIn));
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: path[0],
                tokenOut: path[1],
                fee: lib.routerSwapFee,
                recipient: _to,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            swappingAmount = ISwapRouter(lib.UNISWAP_V3_ROUTER).exactInputSingle(params);
        } else {
            ISwapRouter.ExactInputSingleParams memory params = ISwapRouter.ExactInputSingleParams({
                tokenIn: lib.WETH,
                tokenOut: path[1],
                fee: lib.routerSwapFee,
                recipient: _to,
                deadline: block.timestamp,
                amountIn: _amountIn,
                amountOutMinimum: 0,
                sqrtPriceLimitX96: 0
            });
            swappingAmount =ISwapRouter(lib.UNISWAP_V3_ROUTER).exactInputSingle{value:_amountIn}(params);
        }
        return (true,swappingAmount) ;
    }

    /**
     * @dev transferBeneficiary function allows the owner of the asset to transfer the beneficiary address to a new address.
     * @param _newBeneficiary The new address of the beneficiary.
     * @param _assetId The ID of the locked asset.
     */
    function transferBeneficiary(address _newBeneficiary, uint _assetId) public {
        ls.LibStorage storage lib = ls.libStorage();
        ls.LockedAsset storage asset = lib._idVsLockedAsset[_assetId];
        require (msg.sender == asset.beneficiary || msg.sender == lib.GemChestAddress, "incorrect owner");
        if (msg.sender == asset.beneficiary) {
            gemChest.transferFrom(msg.sender, _newBeneficiary, _assetId);
        }
        asset.beneficiary = _newBeneficiary;
    }

    /**
     * @dev submitBeneficiary function allows the user to submit a new beneficiary for the asset.
     * @param _id The ID of the locked asset.
     * @param _message The message to be signed by the user.
     * @param _signature The signature of the user.
     * @param _swapToken The address of the stablecoin used to get asset claimed amount.
     * @param _newBeneficiary The address of the beneficiary of the locked asset.
     * @notice In place of SIGNER address will be hardcoded signer address
     */
    function submitBeneficiary(uint _id, string memory _message, bytes memory _signature, address _swapToken, address _newBeneficiary) public {
        ls.LibStorage storage lib = ls.libStorage();
        ls.LockedAsset storage asset = lib._idVsLockedAsset[_id];
        require(!asset.features[0], "asset isOwned");
        asset.features[0] = true;
        if (!ds.hasRole(ds.ADMIN, msg.sender)){
                _message = string (abi.encodePacked(_message, Strings.toString(_id)));
                require (ls.verify(_message, _signature, lib.SIGNER), "false signature");
        }
        if (asset.status == ls.Status.OPEN) {           
            asset.beneficiary = _newBeneficiary;
            gemChest.safeTransferFrom(address(this), _newBeneficiary, _id);
        } else {
            uint _newAmount = asset.claimedAmount;
            asset.claimedAmount = 0;
            _swapToken = asset.features[2] ? _swapToken : asset.token;
            ls.transferFromContract(_swapToken,_newBeneficiary,_newAmount);
        } 
     }

}
