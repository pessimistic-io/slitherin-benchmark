// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "./ERC721Enumerable.sol";
import "./SafeMath.sol";
import "./Strings.sol";
import "./IFortunatemon.sol";
import "./INftLottery.sol";
import "./ITicketLottery.sol";

contract LotteryLens{
    using SafeMath for uint256;
    using Strings for uint256;

    function ownedTokensPage(address nft, address owner, uint pageNo, uint pageSize) public view returns (string memory,uint,uint) {
        require(ERC721Enumerable(nft).supportsInterface(type(IERC721Enumerable).interfaceId)
            && owner != address(0)
            && pageNo > 0
            && pageSize > 0,"Invalid parameter");

        uint balance = IERC721(nft).balanceOf(owner);
        if(balance == 0){
            return ("",0,0);
        }

        uint mod = balance.mod(pageSize);
        uint totalPage = (mod == 0) ? balance.div(pageSize) : balance.div(pageSize) +1;
        if(pageNo > totalPage){
            return ("",totalPage,balance);
        }

        uint startIndex = (pageNo -1).mul(pageSize);
        uint endIndex = startIndex.add(pageSize);
        endIndex = endIndex > balance ? balance : endIndex;

        string memory tokenIds = "";
        for(uint i= startIndex; i < endIndex; i++){
            uint tokenId = IERC721Enumerable(nft).tokenOfOwnerByIndex(owner,i);
            tokenIds = (bytes(tokenIds).length > 0) ? string(abi.encodePacked(tokenIds,",",tokenId.toString())):tokenId.toString();
        }

        return (tokenIds, totalPage, balance);
    }

    function ownerTokensOf(address nft, uint[] calldata tokenIds) public view returns(address[] memory){
        require(ERC721(nft).supportsInterface(type(IERC721).interfaceId)
            && nft != address(0)
            && tokenIds.length > 0,"Invalid parameter");
        uint len = tokenIds.length;
        address[] memory owners = new address[](len);

        for(uint i=0; i< len; i++){
            uint tokenId = tokenIds[i];
            address owner = ERC721(nft).ownerOf(tokenId);
            owners[i] = owner;
        }

        return owners;
    }

    function saleable(IFortunatemon nft) public view returns(uint, uint, uint){
        uint per_saleable = nft.perSaleable();
        IFortunatemon.Phase phase = nft.phase();

        uint mined = nft.phaseMined(phase);
        uint surplus_saleable = 0;
        if(phase == IFortunatemon.Phase.ONE_SALE){
            surplus_saleable = nft.firstSaleCap().sub(mined);
        }else{
            surplus_saleable = nft.cap().sub(nft.totalSupply());
        }

        return (per_saleable, mined, surplus_saleable);
    }

    function getUserLotteryResults(INftLottery nftLottery, uint _phase, address _user) public view returns(uint8[] memory){
        uint count = nftLottery.prizeCount();
        uint8[] memory cases = new uint8[](count);
        bool isLottery = nftLottery.phaseIsLottery(_phase);
        if(!isLottery){
            return cases;
        }

        bool[] memory result = nftLottery.getUserLotteryResults(_phase, _user);
        for(uint i=0; i< result.length; i++){
            if(!result[i]){
                cases[i] = 0;
            }else{
                INftLottery.LotteryList memory list = nftLottery.phaseLotteryLists(_phase,i);
                if(list.winner == address(0)){
                    cases[i] = 1;
                }else{
                    cases[i] = 2;
                }
            }
        }
        return cases;
    }

    function getPhaseLotteryPrize(ITicketLottery ticketLottery, uint phase) public view returns(uint,uint,uint,uint,uint){
        uint receivedJackpot = ticketLottery.phaseReceivedJackpot(phase);
        uint firstPrize = ticketLottery.getPhaseItemRewards(phase,ITicketLottery.Item.FIRST_PRIZE);
        uint secondPrize = ticketLottery.getPhaseItemRewards(phase,ITicketLottery.Item.SECOND_PRIZE);
        uint thirdPrize = ticketLottery.getPhaseItemRewards(phase,ITicketLottery.Item.THIRD_PRIZE);
        uint nftDividend = ticketLottery.getPhaseItemRewards(phase,ITicketLottery.Item.NFT_DIVIDEND);
        return (receivedJackpot,firstPrize,secondPrize,thirdPrize,nftDividend);
    }

    function getPhaseLuckyNos(ITicketLottery ticketLottery, uint phase, uint[] memory indexes) public view returns(uint[] memory){
        uint[] memory luckyNos = new uint[](indexes.length);
        for(uint i=0; i<indexes.length; i++){
            uint luckyNo = ticketLottery.phaseLuckyNo(phase,indexes[i]);
            luckyNos[i] = luckyNo;
        }

        return luckyNos;
    }
}
