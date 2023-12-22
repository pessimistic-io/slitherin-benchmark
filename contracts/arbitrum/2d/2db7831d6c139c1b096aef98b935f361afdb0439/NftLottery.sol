// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./Ownable.sol";
import "./ReentrancyGuard.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./ERC721Holder.sol";
import "./AssetTransfer.sol";

contract NftLottery is Ownable,ReentrancyGuard,ERC721Holder{
    enum PrizeType {
        ETH,
        ERC20,
        ERC721
    }

    struct Prize {
        address asset;
        uint amount;
        uint tokenId;
        PrizeType prizeType;
    }

    struct LotteryList {
        uint luckyTokenId;
        address winner;
        Prize prize;
    }

    uint private immutable _prizeCount;
    address private _lotteryNft;

    mapping(uint => uint) private _phaseLotteryTime;
    mapping(uint => Prize[]) private _phasePrizes;
    mapping(uint => LotteryList[]) private _phaseLotteryLists;

    event ResetLotteryNft(address indexed operator, address oldLotteryNft, address newLotteryNft);
    event PaymentReceived(address indexed sender,uint amount);
    event ClaimPrize(address indexed winner, uint phase, uint rank, uint luckyTokenId);
    event WithdrawAsset(address indexed operator, address indexed asset, address indexed receiver, uint amount);

    constructor(address lotteryNft, uint prizeCount) {
        require(lotteryNft != address(0) ,"nft is the zero address");
        _lotteryNft = lotteryNft;
        _prizeCount = prizeCount;
    }

    function resetLotteryNft(address lotteryNft) external onlyOwner{
        address oldLotteryNft = _lotteryNft;
        _lotteryNft = lotteryNft;

        emit ResetLotteryNft(msg.sender, oldLotteryNft, lotteryNft);
    }

    function prizeCount() public view returns(uint){
        return _prizeCount;
    }

    function lotteryNft() public view returns(address){
        return _lotteryNft;
    }

    function phaseIsLottery(uint phase) public view returns(bool){
        return _phaseLotteryTime[phase] >0;
    }

    function phaseIsExpire(uint phase) public view returns(bool){
        if(!phaseIsLottery(phase)){
            return false;
        }

        return _phaseLotteryTime[phase]+ 24*60*60 < block.timestamp;
    }

    function phasePrizes(uint phase, uint index) public view returns(Prize memory){
        return _phasePrizes[phase][index];
    }

    function phaseLotteryLists(uint phase, uint index) public view returns(LotteryList memory){
        return _phaseLotteryLists[phase][index];
    }

    function setPhasePrizes(uint _phase, Prize[] calldata _prizes) external onlyOwner{
        require(!phaseIsLottery(_phase),"Prize has been drawn");
        require(_prizes.length == prizeCount(),"The number of prizes does not match");

        delete _phasePrizes[_phase];
        Prize[] storage prizes = _phasePrizes[_phase];

        for(uint i=0;i<_prizes.length;i++){
            Prize memory _prize = _prizes[i];
            prizes.push(_prize);
        }
    }

    function lottery(uint _phase, uint[] calldata _luckyTokenIds) external onlyOwner{
        Prize[] memory prizes = _phasePrizes[_phase];
        require(prizes.length == prizeCount(),"The draw hasn't started yet");
        require(_luckyTokenIds.length == prizeCount(),"The number of tokenIds does not match");
        require(!phaseIsLottery(_phase),"Prize has been drawn");

        LotteryList[] storage lotteryLists = _phaseLotteryLists[_phase];
        for(uint i= 0; i< _luckyTokenIds.length; i++){
            uint _luckyTokenId = _luckyTokenIds[i];
            Prize memory prize = prizes[i];

            LotteryList memory lotteryList = LotteryList({
                luckyTokenId: _luckyTokenId,
                winner: address(0),
                prize: prize
            });

            lotteryLists.push(lotteryList);
        }
        _phaseLotteryTime[_phase] = block.timestamp;
    }

    function claimPrize(uint _phase) external nonReentrant{
        address winner = msg.sender;
        require(isUserLottery(_phase, winner),"Losing lottery");
        require(!phaseIsExpire(_phase),"The claim has expired");

        LotteryList[] storage lotteryLists = _phaseLotteryLists[_phase];
        for(uint i=0; i< lotteryLists.length; i++){
            LotteryList storage lotteryList = lotteryLists[i];
            //已领取过
            if(lotteryList.winner != address(0)){
                continue;
            }

            uint256 tokenId = lotteryList.luckyTokenId;
            //该中奖的tokenId的所有者不是领奖人
            if(IERC721(_lotteryNft).ownerOf(tokenId) != winner){
                continue;
            }

            lotteryList.winner = winner;

            Prize memory prize = lotteryList.prize;
            if(PrizeType.ETH == prize.prizeType || PrizeType.ERC20 == prize.prizeType){
                AssetTransfer.reward(address(this), winner, prize.asset, prize.amount);
            }else if(PrizeType.ERC721 == prize.prizeType){
                IERC721(prize.asset).safeTransferFrom(address(this), winner, prize.tokenId);
            }else{
                revert("NftLottery: Unknown prize type");
            }

            emit ClaimPrize(winner, _phase, (i+1), tokenId);
        }
    }

    function isUserLottery(uint _phase, address _user) public view returns(bool){
        bool[] memory _prizeLResults = getUserLotteryResults(_phase, _user);
        for(uint i=0; i<_prizeLResults.length;i++){
            if(_prizeLResults[i]){
                return true;
            }
        }
        return false;
    }

    function getUserLotteryResults(uint _phase, address _user) public view returns(bool[] memory){
        bool[] memory _lotteryResults = new bool[](prizeCount());
        if(!phaseIsLottery(_phase)){
            return _lotteryResults;
        }

        LotteryList[] memory lotteryLists = _phaseLotteryLists[_phase];
        for(uint i=0; i< lotteryLists.length; i++){
            LotteryList memory lotteryList = lotteryLists[i];
            if(isClaimPrize(_phase, i)){
                if(lotteryList.winner == _user){
                    _lotteryResults[i] = true;
                }
            }else{
                if(IERC721(_lotteryNft).ownerOf(lotteryList.luckyTokenId) == _user){
                    _lotteryResults[i] = true;
                }
            }
        }

        return _lotteryResults;
    }

    function isClaimPrize(uint _phase, uint _index) public view returns(bool){
        if(!phaseIsLottery(_phase)){
            return false;
        }

        LotteryList memory lotteryList = phaseLotteryLists(_phase,_index);
        return lotteryList.winner != address(0);
    }

    function withdraw(address _asset, address _to, uint256 _amount) public onlyOwner{
        require(_to != address(0),"WithdrawAsset: _to the zero address");
        uint256 amount = _asset == address(0) ? address(this).balance : IERC20(_asset).balanceOf(address(this));
        require(_amount >0 && _amount <= amount);
        AssetTransfer.reward(address(this), _to, _asset, _amount);

        emit WithdrawAsset(msg.sender, _to, _asset, _amount);
    }

    receive() external payable virtual {
        emit PaymentReceived(_msgSender(), msg.value);
    }
}

