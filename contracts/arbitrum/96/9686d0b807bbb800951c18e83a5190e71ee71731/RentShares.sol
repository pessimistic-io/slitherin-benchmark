// SPDX-License-Identifier: MIT
/// @author MrD 

pragma solidity >=0.8.11;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IGameCoordinator.sol";

contract RentShares is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

	// each property has a unique total of "shares"
	// each time someone stakes an active property shares are given
	// each time someone un-stakes an active property shares are removed
	// shares should be tied to the NFT ids not the spot, so that old shares can be claimed


	// keeps a total for each user per property
	// time before they expire
	// if they haven't claimed in X it burns the excess on claim


	// game contract sends MNOP to rent shares contract instead of doing the math
	// rent shares contract only accepts from game contract 


	// The burn address
    address public constant burnAddress = address(0xdead);

    // array of all property nfts that get rent
    uint256[] public nfts;
    // a fast way to check if it's a registered nft
    mapping(uint256 => bool) public nftExists;

    IERC20 public token;
    IGameCoordinator public gameCoordinator;

    mapping(address => bool) private canGive;

    mapping(uint256 => uint256) public totalRentSharePoints;
	//lock for the rent claim only 1 claim at a time
    // bool private _isWithdrawing;
    //Multiplier to add some accuracy to profitPerShare
    uint256 private constant DistributionMultiplier = 2**64;
    //profit for each share a holder holds, a share equals a decimal.
    mapping(uint256 => uint256) private profitPerShare;
    //the total reward distributed through the vault, for tracking purposes
    mapping(uint256 => uint256) public totalShareRewards;
    //the total payout through the vault, for tracking purposes
    mapping(uint256 => uint256) public totalPayouts;
    uint256 public allTotalPayouts;
    uint256 public allTotalBurns;
    uint256 public allTotalPaid;
    mapping(address => mapping(uint256 => uint256)) private rentShares;
    //Mapping of the already paid out(or missed) shares of each staker
    mapping(address => mapping(uint256 => uint256)) private alreadyPaidShares;
    //Mapping of shares that are reserved for payout
    mapping(address => mapping(uint256 => uint256)) private toBePaid;
    //Mapping of static rewards pending for an address
    mapping(address => uint256) private pendingRewards;

    constructor (
        IERC20 _tokenAddress,
        IGameCoordinator _gameCoordinator,
        uint256[] memory _nfts
    ) {
        token = _tokenAddress;
        gameCoordinator = _gameCoordinator;

        for (uint i=0; i<_nfts.length; i++) {
            addNft(_nfts[i]);
        }
        token.approve(address(gameCoordinator), type(uint256).max);
        token.approve(address(this), type(uint256).max);
    }

    modifier onlyCanGive {
      require(canGive[msg.sender], "Can't do this");
      _;
    }


    // add NFT
    function addNft(uint256 _nftId) public onlyOwner {
        if(!_isInArray(_nftId, nfts)){
            nfts.push(_nftId);
            nftExists[_nftId] = true;
        }
    }

    // bulk add NFTS
    function addNfts(uint256[] calldata _nfts) external onlyOwner {
        for (uint i=0; i<_nfts.length; i++) {
            addNft(_nfts[i]);
        }
    }

	// manage which contracts/addresses can give shares to allow other contracts to interact
    function setCanGive(address _addr, bool _canGive) public onlyOwner {
        canGive[_addr] = _canGive;
    }

    //gets shares of an address/nft
    function getRentShares(address _addr, uint256 _nftId) public view returns(uint256){
        return (rentShares[_addr][_nftId]);
    }

    //Returns the amount a player can still claim
    // @TODO if we remove the penalty remove _mod from contract
    function getAllRentOwed(address _addr, uint256 _mod) public view returns (uint256){

    	uint256 amount;
        for (uint i=0; i<nfts.length; i++) {
        	amount += getRentOwed(_addr, nfts[i]);
        }
/*
        if(_mod > 0){
       		// adjust with the no claim mod
	        amount = (amount * _mod)/100;
        }*/

        return amount;
    }

    function getRentOwed(address _addr, uint256 _nftId) public view returns (uint256){
       return  _getRentOwed(_addr, _nftId) + toBePaid[_addr][_nftId];
    }

    function canClaim(address _addr, uint256 _mod) public view returns (uint256){

        uint256 amount;
        for (uint i=0; i<nfts.length; i++) {
            amount += _getRentOwed(_addr, nfts[i]) + toBePaid[_addr][nfts[i]];
        }
/*
        if(_mod > 0){
            // adjust with the no claim mod
            amount = (amount * _mod)/100;
        }*/

        return getAllRentOwed(_addr, _mod) + pendingRewards[_addr];
    }

    event RentPaid(address indexed user, uint256 nftId, uint256 amount);
    function collectRent(uint256 _nftId, uint256 _amount) public onlyCanGive nonReentrant {
        allTotalPaid += _amount;
        _updatePorfitPerShare(_amount, _nftId);
        token.safeTransferFrom(address(msg.sender),address(this), _amount); 
        emit RentPaid(msg.sender, _nftId, _amount);
    }
    
	// claim any pending rent
    event RentClaimed(address indexed user, uint256 amount, uint256 burned);
	function claimRent(address _address, uint256 _mod) public {
		require(address(msg.sender) == address(gameCoordinator), 'Nope');
        require(gameCoordinator.getLevel(_address) > 0, "Must be level 1 or higher");
        
        // require(!_isWithdrawing,'in progress');
        

        // _isWithdrawing=true;

        // get everything to claim for this address
        uint256 amount;
        for (uint i=0; i<nfts.length; i++) {
            if(rentShares[_address][nfts[i]] > 0) {
            	uint256 amt = _getRentOwed(_address,nfts[i]);
            	if(amt > 0){
            		//Substracts the amount from the rent dividends
            		_updateClaimedRent(_address, nfts[i], amt);
            		totalPayouts[nfts[i]]+=amt;
                    amount += amt;
            	}
            }
        	
        }
        

        // adjust with the no claim mod
        // uint256  claimAmount = (amount * _mod)/100;
        // uint256  burnAmount = amount - claimAmount;

        uint256 claimAmount = amount;

        // add any static rewards
        if(pendingRewards[_address] > 0){
            claimAmount = claimAmount + pendingRewards[_address];
            pendingRewards[_address] = 0;
        }
        
        require(claimAmount!=0,"=0"); 

        allTotalPayouts+=claimAmount;
        // allTotalBurns+=burnAmount;

        token.transferFrom(address(this),_address, claimAmount);
/*
        if(burnAmount > 0){
			token.transferFrom(address(this),burnAddress, burnAmount);        	
        }*/
        emit RentClaimed(_address, claimAmount, 0);
        // _isWithdrawing=false;
//        emit OnClaimBNB(_address,amount);

    }

    function addPendingRewards(address _addr, uint256 _amount) public onlyCanGive {
      pendingRewards[_addr] = pendingRewards[_addr] + _amount;
    }


    function giveShare(address _addr, uint256 _nftId) public onlyCanGive {
        require(nftExists[_nftId], 'Not a property');
        _addShare(_addr,_nftId);
    }

    function removeShare(address _addr, uint256 _nftId) public onlyCanGive {
        require(nftExists[_nftId], 'Not a property');
        _removeShare(_addr,_nftId);
    }

    function batchGiveShares(address _addr, uint256[] calldata _nftIds) external onlyCanGive {
      
        uint256 length = _nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            // require(nftExists[_nftId], 'Not a property');
            if(nftExists[_nftIds[i]]) {
                _addShare(_addr,_nftIds[i]);
            }
        }
    }

    function batchRemoveShares(address _addr, uint256[] calldata _nftIds) external onlyCanGive {
        
        uint256 length = _nftIds.length;
        for (uint256 i = 0; i < length; ++i) {
            // require(nftExists[_nftId], 'Not a property');
            if(nftExists[_nftIds[i]]) {
                _removeShare(_addr,_nftIds[i]);
            }
        }
    }


    event ShareGiven(address indexed user, uint256 nftId);
    //adds shares to balances, adds new Tokens to the toBePaid mapping and resets staking
    function _addShare(address _addr, uint256 _nftId) private {
        // the new amount of points
        uint256 newAmount = rentShares[_addr][_nftId] + 1;

        // update the total points
        totalRentSharePoints[_nftId]+=1;

        //gets the payout before the change
        uint256 payment = _getRentOwed(_addr, _nftId);

        //resets dividends to 0 for newAmount
        alreadyPaidShares[_addr][_nftId] = profitPerShare[_nftId] * newAmount;
        //adds dividends to the toBePaid mapping
        toBePaid[_addr][_nftId]+=payment; 
        //sets newBalance
        rentShares[_addr][_nftId]=newAmount;

        emit ShareGiven(_addr, _nftId);
    }

    event ShareRemoved(address indexed user, uint256 nftId);
    //removes shares, adds Tokens to the toBePaid mapping and resets staking
    function _removeShare(address _addr, uint256 _nftId) private {
        //the amount of token after transfer
        uint256 newAmount=rentShares[_addr][_nftId] - 1;
        totalRentSharePoints[_nftId] -= 1;

        //gets the payout before the change
        uint256 payment =_getRentOwed(_addr, _nftId);
        //sets newBalance
        rentShares[_addr][_nftId]=newAmount;
        //resets dividends to 0 for newAmount
        alreadyPaidShares[_addr][_nftId] = profitPerShare[_nftId] * rentShares[_addr][_nftId];
        //adds dividends to the toBePaid mapping
        toBePaid[_addr][_nftId] += payment; 
        emit ShareRemoved(_addr, _nftId);
    }



    //gets the rent owed to an address that aren't in the toBePaid mapping 
    function _getRentOwed(address _addr, uint256 _nftId) private view returns (uint256) {
        uint256 fullPayout = profitPerShare[_nftId] * rentShares[_addr][_nftId];
        //if excluded from staking or some error return 0
        if(fullPayout<=alreadyPaidShares[_addr][_nftId]) return 0;
        return (fullPayout - alreadyPaidShares[_addr][_nftId])/DistributionMultiplier;
    }


    //adjust the profit share with the new amount
    function _updatePorfitPerShare(uint256 _amount, uint256 _nftId) private {

        totalShareRewards[_nftId] += _amount;
        if (totalRentSharePoints[_nftId] > 0) {
            //Increases profit per share based on current total shares
            profitPerShare[_nftId] += (_amount * DistributionMultiplier)/totalRentSharePoints[_nftId];
        }
    }

    //Subtracts the amount from rent to claim, fails if amount exceeds dividends
    function _updateClaimedRent(address _addr, uint256 _nftId, uint256 _amount) private {
        if(_amount==0) return;
 
        require(_amount <= getRentOwed(_addr, _nftId),"exceeds amount");
        uint256 newAmount = _getRentOwed(_addr, _nftId);

        //sets payout mapping to current amount
        alreadyPaidShares[_addr][_nftId] = profitPerShare[_nftId] * rentShares[_addr][_nftId];
        //the amount to be paid 
        toBePaid[_addr][_nftId]+=newAmount;
        toBePaid[_addr][_nftId]-=_amount;
    }

    event ContractsSet(address tokenAddress, address gameCoordinator);
    function setContracts(IERC20 _tokenAddress, IGameCoordinator _gameCoordinator) public onlyOwner {
        token = _tokenAddress;
        gameCoordinator = _gameCoordinator;
        token.approve(address(gameCoordinator), type(uint256).max);
        token.approve(address(this), type(uint256).max);

        emit ContractsSet(address(_tokenAddress), address(_gameCoordinator));
    }
    /**
     * @dev Utility function to check if a value is inside an array
     */
    function _isInArray(uint256 _value, uint256[] memory _array) internal pure returns(bool) {
        uint256 length = _array.length;
        for (uint256 i = 0; i < length; ++i) {
            if (_array[i] == _value) {
                return true;
            }
        }
        return false;
    }

}
