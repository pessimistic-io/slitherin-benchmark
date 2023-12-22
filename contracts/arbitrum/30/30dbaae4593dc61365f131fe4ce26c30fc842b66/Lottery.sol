// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.0;

import {NFT, ERC721TokenReceiver, Auth, Authority} from "./NFT.sol";
import {Issuer} from "./Issuer.sol";
import {VRFV2WrapperConsumerBase} from "./VRFV2WrapperConsumerBase.sol";

contract Lottery is Auth, VRFV2WrapperConsumerBase, ERC721TokenReceiver {
    Issuer public immutable issuer;

    struct Raffle {
        NFT ticket;
        NFT prize;
        uint32 endTime;
        uint32 offset;
        uint256 requestId;
        bool drawn;
    }

    uint256 public raffleCount;

    mapping(uint256 raffleId => Raffle raffle) public raffles;
    mapping(uint256 requestId => uint256 raffleId) public raffleRequests;

    event RaffleCreated(uint256 indexed raffleId, address indexed ticket, address indexed prize, uint32 end);
    event RaffleStarted(uint256 indexed raffleId, uint256 requestId);
    event RaffleDrawn(uint256 indexed raffleId, uint256 offset);

    constructor(address _owner, Authority _authority, Issuer _issuer, address _link, address _vrfV2Wrapper)
        Auth(_owner, _authority)
        VRFV2WrapperConsumerBase(_link, _vrfV2Wrapper)
    {
        issuer = _issuer;
    }

    function startRaffleFor(NFT ticket, NFT prize, uint32 endTime) external requiresAuth returns (uint256 raffleId) {
        raffleId = raffleCount++;
        raffles[raffleId] = Raffle(ticket, prize, endTime, 0, 0, false);
        emit RaffleCreated(raffleId, address(ticket), address(prize), endTime);
    }

    function beginDraw(uint256 raffleId, uint32 gasLimit, uint16 confirmations) external requiresAuth {
        Raffle storage raffle = raffles[raffleId];
        require(raffle.requestId == 0 && !raffle.drawn, "Raffle is already drawn.");
        raffle.requestId = requestRandomness(gasLimit, confirmations, 1);
        emit RaffleStarted(raffleId, raffle.requestId);
    }

    function fulfillRandomWords(uint256 _requestId, uint256[] memory _randomWords) internal override {
        Raffle storage raffle = raffles[raffleRequests[_requestId]];
        raffle.drawn = true;
        unchecked {
            raffle.offset = uint32(_randomWords[0]);
        }
        emit RaffleDrawn(raffleRequests[_requestId], raffle.offset);
    }

    function claimPrize(uint256 raffleId, uint256 tokenId) external payable {
        Raffle memory raffle = raffles[raffleId];
        require(raffle.offset != 0, "Raffle is not drawn yet.");
        uint256 prizeId = (raffle.offset + tokenId) % raffle.ticket.totalSupply();
        _transfer(raffle.ticket, msg.sender, address(this), tokenId);
        _transfer(raffle.prize, address(this), msg.sender, prizeId);
    }

    function withdraw(NFT nft, uint256 id) external requiresAuth {
        _transfer(nft, address(this), msg.sender, id);
    }

    function _transfer(NFT nft, address from, address to, uint256 id) internal {
        uint256 fee = nft.getTransferFee(id);
        nft.safeTransferFrom{value: fee}(from, to, id);
    }
}

