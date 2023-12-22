// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./IERC721.sol";
import "./Strings.sol";
import "./SafeMath.sol";
import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./Pausable.sol";
import "./console.sol";

contract Arbkeys_Lottery is Ownable, ReentrancyGuard, Pausable {
    using Strings for uint256;
    using SafeMath for uint256;

    uint40 private _lotteryEndTime = 1_684_195_200; // Date.UTC(2023, 5, 16, 0, 0, 0) / 1000 | 2023.5.16 UTC
    uint64 private _cost = 0.0005 ether;
    uint[] private participants;
    uint[] private lotteryTokenIds;
    uint[] private lotteryTokenAmounts;
    uint private _amount;
    uint private _lotteryId = 0;
    address private winnerAddress;
    address[] public claimWinners;
    address[] public lotteryWinners;
    address[] public lotteryNftWinners;
    address[] public lotteryEthWinners;

    bool public _lotteryEnded;

    mapping(address => uint[]) private _tokenIdToWinner;
    mapping(address => uint[]) private _tokenAmountToWinner;
    mapping(address => uint[]) private _unitTokenIdToWinner;
    mapping(address => uint[]) private _unitTokenAmountToWinner;

    IERC721 public _nftContract;

    event Received(address from, uint256 amount);

    constructor(address nftContract_) payable {
        _nftContract = IERC721(nftContract_);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function enterLottery(uint40 _tokenId, uint40 _level) external nonReentrant payable {
        require(block.timestamp < _lotteryEndTime, "Lottery is not started");
        require(msg.value == _cost, "NftStake: payment is not enough");
        for (uint i = 0; i < _level; i++) {
            participants.push(_tokenId);
        }
    }

    function stakeAll(uint[] memory _tokenId, uint[] memory _level) external nonReentrant payable {
        require(block.timestamp < _lotteryEndTime, "Lottery is not started");
        require(msg.value == _cost * _tokenId.length, "NftStake: payment is not enough");
        for (uint i = 0; i < _tokenId.length; i++) {
            for (uint j = 0; j < _level[i]; j++) {
                participants.push(_tokenId[i]);
            }
        }
    }

    function getOwnerAddress(uint256 tokenId) internal view returns (address) {
        // Verify that the token exists
        require(_nftContract.ownerOf(tokenId) != address(0), "Invalid token ID");
        // Return the owner address
        return _nftContract.ownerOf(tokenId);
    }

    function pickWinners() internal {
        for (uint i = 0; i < 5; i++) {
            uint index = uint(keccak256(abi.encodePacked(block.difficulty, block.timestamp, participants.length))) % participants.length;
            winnerAddress = getOwnerAddress(participants[index]);
            lotteryWinners.push(winnerAddress);
            claimWinners.push(winnerAddress);
        }
    }

    function startLottery(uint40 lotteryEndTime_, uint[] memory _tokenIds, uint[] memory _tokenAmounts) external onlyOwner{
        require(lotteryEndTime_ > block.timestamp, "Time is not correct");
        _lotteryEnded = false;
        _lotteryId++;
        setLotteryEndTime(lotteryEndTime_);
        
        for (uint i = 0; i < lotteryNftWinners.length; i++) {
            delete _unitTokenIdToWinner[lotteryNftWinners[i]];
        }
        for (uint j = 0; j < lotteryEthWinners.length; j++) {
            delete _unitTokenAmountToWinner[lotteryEthWinners[j]];
        }
        delete lotteryTokenIds;
        delete lotteryWinners;
        delete lotteryNftWinners;
        delete lotteryEthWinners;
        delete participants;
        delete lotteryTokenAmounts;
        for(uint i = 0; i< _tokenIds.length; i ++) {
            lotteryTokenIds.push(_tokenIds[i]);
            IERC721 nftContract = IERC721(_nftContract);
            nftContract.transferFrom(msg.sender, address(this), _tokenIds[i]);
        }
        for(uint j = 0; j < _tokenAmounts.length; j++) {
            lotteryTokenAmounts.push(_tokenAmounts[j]);
        }
    }

    function endLottery() external onlyOwner{
        require(_lotteryEnded == false, "Lottery already ended");
        require(block.timestamp >= _lotteryEndTime, "Lottery end time not reached");
        _lotteryEnded = true;
        pickWinners();
        for(uint i = 0; i < 3; i++){
            lotteryNftWinners.push(lotteryWinners[i]);
        }
        for(uint j = 3; j < 5; j++){
            lotteryEthWinners.push(lotteryWinners[j]);
        }
        for(uint k = 0; k < 3; k++) {
            _tokenIdToWinner[lotteryNftWinners[k]].push(lotteryTokenIds[k]);
            _unitTokenIdToWinner[lotteryNftWinners[k]].push(lotteryTokenIds[k]);
        }
        for(uint l = 0; l < 2; l++) {
            _tokenAmountToWinner[lotteryEthWinners[l]].push(lotteryTokenAmounts[l]);
            _unitTokenAmountToWinner[lotteryEthWinners[l]].push(lotteryTokenAmounts[l]);
        }
    }

    function isInArray(address _addressToCheck) internal view returns (bool) {
        for (uint i = 0; i < claimWinners.length; i++) {
            if (claimWinners[i] == _addressToCheck) {
                return true;
            }
        }
        return false;
    }

    function claimPrize() external payable nonReentrant {
        require(isInArray(msg.sender), "Only the winner can claim the prize.");
        _amount = 0;
        if(_tokenIdToWinner[msg.sender].length != 0) {
            for(uint i = 0; i < _tokenIdToWinner[msg.sender].length; i ++) {
                IERC721 nftContract = IERC721(_nftContract);
                nftContract.transferFrom(address(this), msg.sender, _tokenIdToWinner[msg.sender][i]);
            }
            delete _tokenIdToWinner[msg.sender];
        }
        if(_tokenAmountToWinner[msg.sender].length != 0) {
            for(uint j = 0; j < _tokenAmountToWinner[msg.sender].length; j ++) {
                _amount = SafeMath.add(_amount, _tokenAmountToWinner[msg.sender][j]);
            }
            payable(msg.sender).transfer(_amount);
            delete _tokenAmountToWinner[msg.sender];
        }
        for(uint k = 0; k < claimWinners.length; k++) {
            if(claimWinners[k] == msg.sender) {
                for (uint l = k; l < claimWinners.length - 1; l++) {
                    claimWinners[l] = claimWinners[l + 1];
                }
                claimWinners.pop();
                break;
            }
        }
    }
    
    function claimEth(uint amount_) external payable nonReentrant {
        require(isInArray(msg.sender), "Only the winner can claim the prize.");
        for(uint i = 0; i < _tokenAmountToWinner[msg.sender].length; i ++) {
            if(_tokenAmountToWinner[msg.sender][i] == amount_){
                payable(msg.sender).transfer(_amount);
                for(uint j = i; j < _tokenAmountToWinner[msg.sender].length - 1; j++) {
                    _tokenAmountToWinner[msg.sender][j] = _tokenAmountToWinner[msg.sender][j+1];
                }
                _tokenAmountToWinner[msg.sender].pop();
                break;
            }
        }
    }

    function claimNFT(uint _tokenId) external payable nonReentrant {
        require(isInArray(msg.sender), "Only the winner can claim the prize.");
        for(uint i = 0; i < _tokenIdToWinner[msg.sender].length; i ++) {
            if(_tokenIdToWinner[msg.sender][i] == _tokenId){
                IERC721 nftContract = IERC721(_nftContract);
                nftContract.transferFrom(address(this), msg.sender, _tokenIdToWinner[msg.sender][i]);
                for(uint j = i; j < _tokenIdToWinner[msg.sender].length - 1; j++) {
                    _tokenIdToWinner[msg.sender][j] = _tokenIdToWinner[msg.sender][j+1];
                }
                _tokenIdToWinner[msg.sender].pop();
                break;
            }
        }
    }

    function prizeOwner() external view returns(uint, address[] memory) {
        return (_lotteryId, lotteryWinners);
    }

    function prize() external view returns(bool) {
        bool prizeStatus = false;
        for(uint i = 0; i < claimWinners.length; i++) {
            if(claimWinners[i] == msg.sender) {
                return prizeStatus = true;
            }
        }
        return prizeStatus;
    }

    function lotteryEndTime() external view returns (uint40) {
        return _lotteryEndTime;
    }

    function setLotteryEndTime(uint40 lotteryEndTime_) internal {
        _lotteryEndTime = lotteryEndTime_;
    }

    function setNftContract(address nftContract_) external onlyOwner {
        _nftContract = IERC721(nftContract_);
    }

    function cost() external view returns (uint64) {
        return _cost;
    }

    function setCost(uint64 cost_) external onlyOwner {
        _cost = cost_;
    }

    function pause() external onlyOwner {
        _pause();
    }
    
    function unpause() external onlyOwner {
        _unpause();
    }

    function withdraw() external onlyOwner {
        require(payable(_msgSender()).send(address(this).balance));
        IERC721 nftContract = IERC721(_nftContract);
        for(uint i = 0; i < lotteryTokenIds.length; i++) {
            nftContract.transferFrom(address(this), msg.sender, lotteryTokenIds[i]);
        }
    }
}
