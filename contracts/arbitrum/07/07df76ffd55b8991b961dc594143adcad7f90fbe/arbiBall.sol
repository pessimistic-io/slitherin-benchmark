// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.18;
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {VRFCoordinatorV2Interface} from "./VRFCoordinatorV2Interface.sol";
import {VRFConsumerBaseV2} from "./VRFConsumerBaseV2.sol";

interface arbiBallTreasuryInterface {
	function depositFromRaffle(uint32 _raffleId) external payable;
	function withdrawFromRaffle(address payable _user, uint32 _raffleId, uint256 _amount) external;
	function getFundsAccumulatedInRaffle(uint32 _raffleId) external view returns(uint256);
}


contract arbiBall is OwnableUpgradeable , VRFConsumerBaseV2 {

	event NewRaffle(uint256 raffleId);
	event PurchasedTicket(address player, uint256 raffleId, uint256 ticketsPurchased);
	event WinningTicket(uint256 raffleId, Ticket ticket);
	event JackpotClaimed(uint256 raffleId, address player, uint256 amount);
	VRFCoordinatorV2Interface COORDINATOR;
	
	struct Ticket {
		uint8 a;
		uint8 b;
		uint8 c;
		uint8 d;
		uint8 e;
	}
	
	uint32 public raffleId;
	uint8 private turns;
	uint256 public entryFee;
	uint256 public ownerAccumulated;
	
	address public treasuryVault;
	address private vrfCoordinator;
	bytes32 private keyHash;
	uint16 public jackpotCut;
	uint16 private requestConfirmations;
	uint32 private callbackGasLimit;
	uint32 private numWords;
	uint64 private s_subscriptionId;
	uint256 private s__raffleId;
	
	
	mapping (bytes32 => Ticket[]) public players;
	mapping (uint256 => address[]) public raffleEntries;
	mapping (uint256 => Ticket) public winningValues;
	mapping (bytes32 => bool) public hasEntered;
	mapping (bytes32 => bool) public hasClaimed;
	mapping (uint32 => bool) public hasJackpotBeenClaimed;
	mapping (uint32 => uint32) public raffleStartTime;
	mapping (uint32 => bool) public isRaffleOver;
	mapping (address => bool) public isController;
	mapping (uint256 => uint32) private raffleEndReq;
	mapping (uint32 => uint32) public raffleEndTime;

	modifier onlyController {
		require(isController[msg.sender], "Caller is not a controller");
		_;
	}
	
	function initialize(address _vrfCoordinatorAddress, uint64 subscriptionId) public initializer {
		__Ownable_init();
		__VRFConsumerBaseV2_init(_vrfCoordinatorAddress);
		COORDINATOR = VRFCoordinatorV2Interface(_vrfCoordinatorAddress);
		
		//chainLink Setup
		s_subscriptionId = subscriptionId;
		vrfCoordinator = _vrfCoordinatorAddress;
		keyHash = 0x08ba8f62ff6c40a58877a106147661db43bc58dabfb814793847a839aa03367f;
		callbackGasLimit = 250000;
		requestConfirmations = 3;
		jackpotCut = 75;
	}
	
	function buyTicket(uint32 _raffleId, uint256 numberOfTickets, Ticket[] memory ticket) external payable {
		require(msg.value == entryFee * numberOfTickets, "Incorrect numberOfTickets of ETH sent");
		require(raffleEndTime[_raffleId] > block.timestamp, "Raffle has ended");
		require(raffleStartTime[_raffleId] < block.timestamp, "Raffle has not started yet");
		unchecked {
		for (uint256 i = 0; i < numberOfTickets; i++) {
			players[keccak256(abi.encodePacked(_raffleId, msg.sender))].push(ticket[i]);
		}
		if (hasEntered[keccak256(abi.encodePacked(_raffleId, msg.sender))] == false) {
			raffleEntries[_raffleId].push(msg.sender);
			hasEntered[keccak256(abi.encodePacked(_raffleId,msg.sender))] = true;
		}
	}
		arbiBallTreasuryInterface(treasuryVault).depositFromRaffle{value: msg.value}(_raffleId);
		
		emit PurchasedTicket(msg.sender, _raffleId, numberOfTickets);
	}
	
	function redeemPrize(uint32 _raffleId) external {
		require(!hasClaimed[keccak256(abi.encodePacked(_raffleId,msg.sender))], "Error: Already Prize Claimed");
		require(isRaffleOver[_raffleId], "Raffle is not over yet");
		uint256 ticketsBought = players[keccak256(abi.encodePacked(_raffleId,msg.sender))].length;
		uint256 prize = 0;
		for (uint256 i =0; i < ticketsBought; i++) {
			if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].c == winningValues[_raffleId].c &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].d == winningValues[_raffleId].d &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].e == winningValues[_raffleId].e
			) {
				if (!hasJackpotBeenClaimed[_raffleId]) {
					uint256 jackpotAmount = arbiBallTreasuryInterface(treasuryVault).getFundsAccumulatedInRaffle(_raffleId) * jackpotCut / 100;
					prize += jackpotAmount;
					hasJackpotBeenClaimed[_raffleId] = true;
					emit JackpotClaimed(_raffleId, msg.sender, jackpotAmount);
				}
			}
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].c == winningValues[_raffleId].c &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].d == winningValues[_raffleId].d
			) {
				prize += 0.24891 ether;
			}
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].c == winningValues[_raffleId].c &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].e == winningValues[_raffleId].e
			) {
				prize += 0.0497864 ether;
			}
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].c == winningValues[_raffleId].c
			) {
				prize += 0.00497863 ether;
			}
			
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].e == winningValues[_raffleId].e
			) {
				prize += 0.00248931 ether;
			}
			
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].b == winningValues[_raffleId].b
			) {
				prize += 0.0001 ether;
			}
			
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].a == winningValues[_raffleId].a &&
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].e == winningValues[_raffleId].e
			) {
				prize += 0.0001 ether;
			}
			
			else if (
				players[keccak256(abi.encodePacked(_raffleId,msg.sender))][i].e == winningValues[_raffleId].e
			) {
				prize += 0.0001 ether;
			}
		}
		hasClaimed[keccak256(abi.encodePacked(_raffleId,msg.sender))] = true;
		arbiBallTreasuryInterface(treasuryVault).withdrawFromRaffle(payable(msg.sender),_raffleId,prize);
	}
	
	
	// Owner Functions
	function startRaffle(uint32 endTime) external onlyController {
		startNewRaffle(endTime);
	}
	
	function setEntryFee(uint256 fee) external onlyController {
		entryFee = fee;
	}
	
	function endRaffle(uint32[] calldata _raffleIds) public onlyController {
		for (uint256 i = 0; i < _raffleIds.length; i++) {
			require(raffleEndTime[_raffleIds[i]] < uint32(block.timestamp), "Raffle has not ended yet");
			s__raffleId = COORDINATOR.requestRandomWords(
				keyHash,
				s_subscriptionId,
				requestConfirmations,
				callbackGasLimit * 1,
				1
			);
			raffleEndReq[s__raffleId] = _raffleIds[i];
		}
	}
	
	function setController(address _controller) external onlyOwner {
		isController[_controller] = true;
	}
	
	function setTreasuryVault(address _treasuryVault) external onlyOwner {
		treasuryVault = _treasuryVault;
	}
	
	function setJackpotCut(uint16 _jackpotCut) external onlyOwner {
		jackpotCut = _jackpotCut;
	}
	
	function setWinningNumbers(uint32 _raffleId, Ticket memory winningNumbers) external onlyController {
		winningValues[_raffleId] = winningNumbers;
		isRaffleOver[_raffleId] = true;
		emit WinningTicket(_raffleId, winningValues[_raffleId]);
	}
	
	function prefillRaffle(uint32 _raffleId) external payable onlyController {
		arbiBallTreasuryInterface(treasuryVault).depositFromRaffle{value: msg.value}(_raffleId);
	}
	
	// Getter Functions
	
	function getTickets( uint32 _raffleId, address player ) public view returns(Ticket[] memory) {
		uint256 length =  players[keccak256(abi.encodePacked(_raffleId, player))].length;
		Ticket[] memory tickets = new Ticket[](length);
		for(uint256 i = 0; i < length; i++) {
			tickets[i] = players[keccak256(abi.encodePacked(_raffleId, player))][i];
		}
		return tickets;
	}
	
	function getRaffleEntries(uint256 raffle) public view returns(address[] memory) {
		return raffleEntries[raffle];
	}
	
	function getTotalRaffleEntries(uint256 raffle) public view returns(uint256) {
		return raffleEntries[raffle].length;
	}
	
	function getRaffleEntriesByIndex(uint256 raffle, uint256 index) public view returns(address) {
		return raffleEntries[raffle][index];
	}
	
	function getRafflesToFinalise(uint32 from, uint32 to) public view returns(uint32[] memory) {
		uint32[] memory raffleIds = new uint32[](raffleId);
		uint256 count;
		for(uint32 i = from; i < to; i++) {
			if(raffleEndTime[i] < uint32(block.timestamp) && !isRaffleOver[i] && i != 0) {
				raffleIds[count] = i;
				count++;
			}
		}
		return raffleIds;
	}
	
	// internal functions
	// Contract Internal Functions
	function fulfillRandomWords(
		uint256 _requestId,
		uint256[] memory randomWords
	) internal override {
		inHouseRandomizer(randomWords[0], raffleEndReq[_requestId]);
	}
	
	function inHouseRandomizer(uint256 randomNumber, uint32 _raffleId) internal {
		uint8[5] memory winningNumbers;
		winningNumbers[0] = uint8(uint256(keccak256(abi.encode(randomNumber,block.timestamp, _raffleId))) % 41);
		if (winningNumbers[0] == 0) {
			turns++;
			if (turns > 10){
				endRaffleRandomisation(randomNumber, _raffleId);
			}
			inHouseRandomizer(randomNumber+turns, _raffleId);
		}
		winningNumbers[1] = uint8(uint256(keccak256(abi.encode(randomNumber, winningNumbers[0],block.timestamp, _raffleId))) % 41);
		if (
			winningNumbers[1] == winningNumbers[0] ||
			winningNumbers[1] == 0
		) {
			turns++;
			if (turns > 10){
				endRaffleRandomisation(randomNumber, _raffleId);
			}
			inHouseRandomizer(randomNumber+turns, _raffleId);
		}
		winningNumbers[2] = uint8(
			uint256(
				keccak256(
					abi.encode(
						randomNumber,
						winningNumbers[1],
						winningNumbers[0],
						block.timestamp,
						_raffleId
					)
				)
			)
			% 41
		);
		if (
			winningNumbers[2] == winningNumbers[1] ||
			winningNumbers[2] == winningNumbers[0] ||
			winningNumbers[2] == 0
		) {
			turns++;
			if (turns > 10){
				endRaffleRandomisation(randomNumber, _raffleId);
			}
			inHouseRandomizer(randomNumber+turns, _raffleId);
		}
		winningNumbers[3] = uint8(
			uint256(
				keccak256(
					abi.encode(
						randomNumber,
						winningNumbers[2],
						winningNumbers[1],
						winningNumbers[0],
						block.timestamp,
						_raffleId
					)
				)
			) % 41
		);
		if (
			winningNumbers[3] == winningNumbers[2] ||
			winningNumbers[3] == winningNumbers[1] ||
			winningNumbers[3] == winningNumbers[0] ||
			winningNumbers[3] == 0
		) {
			turns++;
			if (turns > 10){
				endRaffleRandomisation(randomNumber, _raffleId);
			}
			inHouseRandomizer(randomNumber+turns, _raffleId);
		}
		winningNumbers[4] = uint8(
			uint256(
				keccak256(
					abi.encode(
						randomNumber,
						winningNumbers[3],
						winningNumbers[2],
						winningNumbers[1],
						winningNumbers[0],
						block.timestamp,
						_raffleId
					)
				)
			) % 10
		);
		winningValues[_raffleId] =  Ticket(
			winningNumbers[0],
			winningNumbers[1],
			winningNumbers[2],
			winningNumbers[3],
			winningNumbers[4]
		);
		
		isRaffleOver[_raffleId] = true;
		turns = 0;
		emit WinningTicket(_raffleId, winningValues[_raffleId]);
	}
	
	function startNewRaffle(uint32 endTime) internal {
		++raffleId;
		raffleStartTime[raffleId] = uint32(block.timestamp);
		raffleEndTime[raffleId] = uint32(endTime);
		emit NewRaffle(raffleId);
	}

	function endRaffleRandomisation(uint256 randomNumber, uint256 raffleId) internal {
		turns = 0;
		uint8[5] memory winningNumbers;
		uint8 winningNumber = uint8(uint256(keccak256(abi.encode(randomNumber,block.timestamp, raffleId)))) % 11;
		winningNumbers[0] = winningNumber == 0 ? 1 : winningNumber;
		winningNumbers[1] = winningNumber + 10;
		winningNumbers[2] = winningNumber + 20;
		winningNumbers[3] = winningNumber + 30;
		winningNumber = uint8(uint256(keccak256(abi.encode(randomNumber, winningNumbers[0], raffleId)))) % 11;
		winningNumbers[4] = winningNumber == 0 ? 1 : winningNumber;
	}
}

