// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.0;

import "./ReentrancyGuard.sol";

import "./AggregatorV3Interface.sol";
import "./IFlippeningGame.sol";
import "./IFlippeningGameManagement.sol";
import "./ISwapRouter.sol";
import "./IWETH9.sol";

import "./HunchGame.sol";

import "./MultiplierLib.sol";

contract FlippeningGame is IFlippeningGame, IFlippeningGameManagement, ReentrancyGuard, HunchGame {

	struct FlippeningBetInfo {
        uint256 marketCapRatio; // Ratio is [0, MAX_PERCENTAGE], with MAX_PERCENTAGE being 1.0
        uint256 date;
        bool claimedWin;
        bool claimedReward;
    }

    uint256 public constant MAX_ALLOWED_RATIO = 9500;

    uint256 public constant FLIPPENING_GAME_ID = 1;

    uint256 public constant BETS_STATE = 0;
    uint256 public constant CLAIM_STATE = 1;

    uint256 public constant FLIPPENING_WIN_MIN_DIST_PERIOD = 1 weeks;
    uint256 public constant CLAIM_WIN_PERIOD = 1 weeks;
    uint256 public constant COLLECT_REWARD_MAX_PERIOD = 1 weeks;

    uint256 public constant MAX_POSITIONS_TO_COLLECT = 1000;

    uint256 public constant COLLECT_REWARDS_SLIPPAGE = 100;

    uint256 public constant FINDERS_FEE_PERCENTAGE = 100;
    uint256 public constant MAX_FINDERS_FEE_AMOUNT = 1 ether;

    mapping(uint256 => FlippeningBetInfo) public bets;

    uint256[] public notCollectedTicketIds;
    uint256 public nextNonCollectedTicketIdIndex;

    uint256 public state = BETS_STATE;
    uint256 public flippeningDate;
    uint256 public totalClaimedAmount;
    uint256 public totalReward;

    AggregatorV3Interface public ethMarketCapOracle;
    AggregatorV3Interface public btcMarketCapOracle;

    IWETH9 public weth;
    ISwapRouter public router;

    bool public isAlpha = true;
    bool public isCanceled = false;
    bool public hasWon = false;

    uint256[] public amountMultiplierXValues = [0.01 ether, 0.1 ether, 1 ether, 2 ether, 4 ether, 10 ether];
    uint256[] public amountMultiplierYValues = [1e4, 2e4, 2.5e4, 3e4, 3.5e4, 4e4];

    uint256[] public ratioMultiplierXValues = [0, 500, 1000, 1500, 2000, 2500, 3000, 3500, 4000, 4500, 5000, 5500, 6000, 6500, 7000, 7500, 8000, 8500, 9000, 9500];
    uint256[] public ratioMultiplierYValues = [1000e4, 300e4, 100e4, 80e4, 50e4, 25e4, 14e4, 10e4, 7e4, 5.5e4, 
    	5e4, 4.5e4, 4e4, 3.5e4, 3e4, 2.5e4, 2e4, 1.5e4, 1e4, 1000];

    uint256[] public proximityMultiplierXValues = [1 hours, 4 hours, 12 hours, 1 days, 2 days, 3 days, 4 days, 5 days, 6 days, 7 days];
    uint256[] public proximityMultiplierYValues = [25e4, 16e4, 12e4, 9e4, 6e4, 4e4, 3e4, 2e4, 1.3e4, 1e4];

    modifier notCanceled {
    	require(!isCanceled, "Game canceled");
    	_;
    }

    constructor(AggregatorV3Interface _ethMarketCapOracle, AggregatorV3Interface _btcMarketCapOracle, ITicketFundsProvider _ticketFundsProvider, ISwapRouter _router, IWETH9 _weth, address payable _treasury) 
    		HunchGame("Hunch Flippening Ticket", "HUNCH-FLIP", _ticketFundsProvider, _treasury) {
    	gameId = FLIPPENING_GAME_ID;

        ethMarketCapOracle = _ethMarketCapOracle;
        btcMarketCapOracle = _btcMarketCapOracle;
        router = _router;
        weth = _weth;
    }
	
	function buyETHTicket(uint256 _flippeningDate) external payable override nonReentrant notCanceled returns (uint256 ticketId) {
		require(msg.value >= amountMultiplierXValues[0], "Not enough ETH");
		validateBet(_flippeningDate);

		TicketFundsInfo memory ticket;
		uint256 treasuryFees;
		uint256 multiplier;

		(ticketId, ticket, treasuryFees, multiplier) = createETHTicket(msg.value);

		uint256 marketCapRatio = createBet(ticketId, _flippeningDate);

		emit BuyETHTicket(msg.sender, ticketId, _flippeningDate, marketCapRatio, msg.value, 
			treasuryFees, ticket.amount, ticket.multipliedAmount, multiplier);
	}

	function buyPositionETHTicket(uint256 _positionTokenId, uint256 _flippeningDate, uint256 _token0ETHPrice, uint256 _token1ETHPrice) external override nonReentrant notCanceled returns (uint256 ticketId) {
		validateBet(_flippeningDate);

		TicketFundsInfo memory ticket;
		uint256 treasuryFees;
		uint256 multiplier;

		(ticketId, ticket, treasuryFees, multiplier) = createETHTicketFromPosition(_positionTokenId, _token0ETHPrice, _token1ETHPrice);
		uint256 marketCapRatio = createBet(ticketId, _flippeningDate);

		emit BuyPositionETHTicket(msg.sender, ticketId, _flippeningDate, marketCapRatio, _positionTokenId, ticket.amount + treasuryFees, 
			treasuryFees, ticket.amount, ticket.multipliedAmount, multiplier);
	}

	function buyPositionTicket(uint256 _positionTokenId, uint256 _flippeningDate) external override nonReentrant notCanceled returns (uint256 ticketId) {
		validateBet(_flippeningDate);
		ticketId = createPositionTicket(_positionTokenId);
		uint256 marketCapRatio = createBet(ticketId, _flippeningDate);
		notCollectedTicketIds.push(ticketId);

		emit BuyPositionTicket(msg.sender, ticketId, _flippeningDate, marketCapRatio, _positionTokenId);
	}

	function closePositionTicket(uint256 _ticketId, uint256 _token0ETHPrice, uint256 _token1ETHPrice) external override nonReentrant notCanceled {
		updatePositionTicket(_ticketId, _token0ETHPrice, _token1ETHPrice, true);
	}

	function flip() external override nonReentrant notCanceled {
		require(state == BETS_STATE, "Already flipped");

		(, int256 ethMarketCap,,,) = ethMarketCapOracle.latestRoundData();
		(, int256 btcMarketCap,,,) = btcMarketCapOracle.latestRoundData();
		require(ethMarketCap > btcMarketCap, "No flippening");

		flippeningDate = block.timestamp;
		state = CLAIM_STATE;

		emit Flip(block.timestamp);
	}

	function claimWin(uint256 _ticketId, uint256 _token0ETHPrice, uint256 _token1ETHPrice) external override nonReentrant notCanceled {
		require(ownerOf(_ticketId) == msg.sender, "Not allowed");
		require(state == CLAIM_STATE, "Not allowed");
		require(block.timestamp - flippeningDate < CLAIM_WIN_PERIOD, "Too late");

		FlippeningBetInfo memory betInfo = bets[_ticketId];
		require(betInfo.date > 0, "No ticket");

		TicketFundsInfo memory fundsInfo = tickets[_ticketId];
		verifyTicketExists(fundsInfo);

		require(!betInfo.claimedWin, "Already claimed");

		require(betInfo.date >= flippeningDate - FLIPPENING_WIN_MIN_DIST_PERIOD && betInfo.date <= flippeningDate + FLIPPENING_WIN_MIN_DIST_PERIOD, "Losing bet");

		uint256 multipliedAmount = fundsInfo.multipliedAmount;
		if (fundsInfo.tokenId != 0) {
			(multipliedAmount,,) = updatePositionTicket(_ticketId, _token0ETHPrice, _token1ETHPrice, true);
		}

		uint256 ratioMultiplier = getRatioMultiplier(betInfo.marketCapRatio);
		multipliedAmount = multipliedAmount * ratioMultiplier / ONE_MULTIPLIER;
		uint256 distanceMultiplier = getFlippeningDistanceMultiplier(betInfo.date);
		multipliedAmount = multipliedAmount * distanceMultiplier / ONE_MULTIPLIER;

		totalClaimedAmount += multipliedAmount;
		tickets[_ticketId].multipliedAmount = multipliedAmount;
		bets[_ticketId].claimedWin = true;
		hasWon = true;

		emit ClaimWin(msg.sender, _ticketId, multipliedAmount, ratioMultiplier, distanceMultiplier);
	}

	function convertFunds(IERC20 _token, uint256 _amount, uint24 _poolFee, uint256 _tokenPrice) external override onlyOwner notCanceled returns (uint256 ethAmount) {
		verifyCollectRewardsState();

		_token.approve(address(router), _amount);
		ethAmount = router.exactInput(ISwapRouter.ExactInputParams(abi.encodePacked(address(_token), _poolFee, address(weth)), address(this), block.timestamp, 
            _amount, _amount * _tokenPrice / 10 ** ticketFundsProvider.getPricePrecisionDecimals()));
		weth.withdraw(ethAmount);

		emit ConvertFunds(_token, _amount, _poolFee, _tokenPrice, ethAmount);
	}

	function collectRewards(uint256 _maxPositionsToCollect) external override nonReentrant notCanceled returns (uint256 findersFee) {
		require(_maxPositionsToCollect > 0, "Max positions must be non-zero");
		verifyCollectRewardsState();

		uint256 notCollectedTicketIdsNum = notCollectedTicketIds.length;
		require(nextNonCollectedTicketIdIndex < notCollectedTicketIdsNum, "Collection already done");

		uint256 ethCollected = 0;
		uint256 nonCollectedTicketIdIndex = nextNonCollectedTicketIdIndex;

		uint256 nonCollectedTicketIdsIndexMax = notCollectedTicketIdsNum - nonCollectedTicketIdIndex >= _maxPositionsToCollect ? 
			nonCollectedTicketIdIndex + _maxPositionsToCollect : notCollectedTicketIdsNum;
		while (nonCollectedTicketIdIndex < nonCollectedTicketIdsIndexMax) {
			uint256 ticketId = notCollectedTicketIds[nonCollectedTicketIdIndex];
			uint256 positionId = tickets[ticketId].tokenId;

			// Make sure ticket was not closed already
			if (positionId != 0) {
				(uint256 ethAmount,) = ticketFundsProvider.getFundsWithoutPrices(positionId, ticketId, COLLECT_REWARDS_SLIPPAGE);
				ethCollected += ethAmount;

				emit CollectRewards(ticketId, positionId, ethAmount);
			}

			nonCollectedTicketIdIndex++;
		}

		nextNonCollectedTicketIdIndex = nonCollectedTicketIdIndex;

		findersFee = ethCollected * FINDERS_FEE_PERCENTAGE / MAX_PERCENTAGE;
		if (findersFee > MAX_FINDERS_FEE_AMOUNT) {
			findersFee = MAX_FINDERS_FEE_AMOUNT;
		}

		uint256 treasuryAmount = getTreasuryAmount(ethCollected - findersFee);

		(bool sentFindersFee, ) = payable(msg.sender).call{value: findersFee}("");
		require(sentFindersFee, "Failed to send finders fee");

		sendToTreasury(treasuryAmount);
	}

	function claimReward(uint256 _ticketId) external nonReentrant override {
		require(ownerOf(_ticketId) == msg.sender, "Not allowed");
		require(canClaimReward(), "Not allowed");

		FlippeningBetInfo memory betInfo = bets[_ticketId];
		require(betInfo.date > 0, "No ticket");

		TicketFundsInfo memory fundsInfo = tickets[_ticketId];
		verifyTicketExists(fundsInfo);

		require(!betInfo.claimedReward, "Already rewarded");

		uint256 reward = 0;
		if (isCanceled || !hasWon) {
			// If ticket not closed, just unstake it, no ETH reward
			if (fundsInfo.tokenId != 0) {
				ticketFundsProvider.unstakeForOwner(fundsInfo.tokenId, msg.sender, _ticketId);
			} else {
				reward = fundsInfo.amount;	
			}
		} else if (!betInfo.claimedWin) {
			// If game was not cancelled and there is a winner, then revert if win was not claimed
			revert("Nothing to claim");
		} else {
			if (totalReward == 0) {
				totalReward = address(this).balance;
			}

			reward = fundsInfo.multipliedAmount * totalReward / totalClaimedAmount;
		}

		bets[_ticketId].claimedReward = true;

		if (reward > 0) {
			(bool sentReward, ) = payable(msg.sender).call{value: reward}("");
			require(sentReward, "Failed to send reward");
		}

		emit ClaimReward(msg.sender, _ticketId, reward, fundsInfo.multipliedAmount, totalReward, totalClaimedAmount);
	}

	function setNonAlpha() external override onlyOwner notCanceled {
		isAlpha = false;

		emit SetNonAlpha();
	}

	function cancelGame() external override onlyOwner notCanceled {
		require(isAlpha, "Not allowed");
		isCanceled = true;

		emit CancelGame();
	}

	function setAmountMultiplier(uint256[] calldata _amounts, uint256[] calldata _multipliers) external override onlyOwner {
		require(isAlpha, "Not allowed");
		require(_amounts.length > 0, "Array empty");
		require(_amounts.length == _multipliers.length, "Lengths differ");
		MultiplierLib.validateOrder(_amounts, true, false);
		MultiplierLib.validateOrder(_multipliers, true, true);

		amountMultiplierXValues = _amounts;
		amountMultiplierYValues = _multipliers;

		emit SetAmountMultiplier(_amounts, _multipliers);
	}

	function setRatioMultiplier(uint256[] calldata _ratios, uint256[] calldata _multipliers) external override onlyOwner {
		require(isAlpha, "Not allowed");
		require(_ratios.length > 0, "Array empty");
		require(_ratios.length == _multipliers.length, "Lengths differ");
		MultiplierLib.validateOrder(_ratios, true, false);
		MultiplierLib.validateOrder(_multipliers, false, true);
		MultiplierLib.validateRatio(_ratios);

		ratioMultiplierXValues = _ratios;
		ratioMultiplierYValues = _multipliers;

		emit SetRatioMultiplier(_ratios, _multipliers);
	}

	function setProximityMultiplier(uint256[] calldata _timeDiffs, uint256[] calldata _multipliers) external override onlyOwner {
		require(isAlpha, "Not allowed");
		require(_timeDiffs.length > 0, "Array empty");
		require(_timeDiffs.length == _multipliers.length, "Lengths differ");
		MultiplierLib.validateOrder(_timeDiffs, true, false);
		MultiplierLib.validateProximity(_timeDiffs);
		MultiplierLib.validateOrder(_multipliers, false, true);

		proximityMultiplierXValues = _timeDiffs;
		proximityMultiplierYValues = _multipliers;

		emit SetProximityMultiplier(_timeDiffs, _multipliers);
	}

	function getMultipliedETHAmount(uint256 _ethAmount, uint256 /*_ticketId*/) public view override(HunchGame, IFlippeningGame)
		returns (uint256 multipliedETHAmount, uint256 multiplier) {
			multiplier = MultiplierLib.calculateMultiplier(_ethAmount, amountMultiplierXValues, amountMultiplierYValues);
			multipliedETHAmount = _ethAmount * multiplier / ONE_MULTIPLIER;
	}

	function getRatioMultiplier(uint256 _ratio) public view override returns (uint256 multiplier) {
		return MultiplierLib.calculateMultiplier(_ratio, ratioMultiplierXValues, ratioMultiplierYValues);
	}

	function getFlippeningDistanceMultiplier(uint256 _betDate) public view override returns (uint256) {
		uint256 _proximity = _betDate > flippeningDate ? _betDate - flippeningDate : flippeningDate - _betDate;
		return MultiplierLib.calculateMultiplier(_proximity, proximityMultiplierXValues, proximityMultiplierYValues);
	}

	function canClaimReward() public view override returns (bool) {
		return isCanceled || (state == CLAIM_STATE && block.timestamp - flippeningDate > CLAIM_WIN_PERIOD + COLLECT_REWARD_MAX_PERIOD);
	}

	function strengthOf(uint256 _ticketId) external view override returns (uint256 strength, uint256 amountMultiplier, uint256 ratioMultiplier, uint256 proximityMultiplier) {
		TicketFundsInfo memory fundsInfo = tickets[_ticketId];
		verifyTicketExists(fundsInfo);

		FlippeningBetInfo memory betInfo = bets[_ticketId];

		if (fundsInfo.tokenId != 0) {
			(uint256 totalTimeMultipliedETHFees,, ) = 
				ticketFundsProvider.getTimeMultipliedFees(fundsInfo.tokenId);
			(strength, amountMultiplier) = getMultipliedETHAmount(totalTimeMultipliedETHFees, _ticketId);
		} else {
			strength = fundsInfo.multipliedAmount;

			// Reverse treasury calculation to get original amount, and get amount multiplier
			(, amountMultiplier) = getMultipliedETHAmount(getAmountBeforeTreasury(fundsInfo.amount), _ticketId);
		}

		ratioMultiplier = getRatioMultiplier(betInfo.marketCapRatio);
		
		if (!betInfo.claimedWin) {
			strength = strength * ratioMultiplier / ONE_MULTIPLIER;
		}

		proximityMultiplier = ONE_MULTIPLIER;
		if (flippeningDate != 0) {
			proximityMultiplier = getFlippeningDistanceMultiplier(betInfo.date);
			
			if (!betInfo.claimedWin) {
				strength = strength * proximityMultiplier / ONE_MULTIPLIER;
			}
		}
	}

	function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual override {
		require(tickets[tokenId].tokenId == 0, "Cannot transfer open ticket");
		super._beforeTokenTransfer(from, to, tokenId);
    }

	function createBet(uint256 _ticketId, uint256 _flippeningDate) private returns (uint256 marketCapRatio) {
		(, int256 ethMarketCap,,,) = ethMarketCapOracle.latestRoundData();
		(, int256 btcMarketCap,,,) = btcMarketCapOracle.latestRoundData();
		marketCapRatio = uint256(ethMarketCap) * MAX_PERCENTAGE / uint256(btcMarketCap);

		require(marketCapRatio <= MAX_ALLOWED_RATIO, "Flippening too close");

		bets[_ticketId] = FlippeningBetInfo(marketCapRatio, _flippeningDate, false, false);
	}

	function validateBet(uint256 _flippeningDate) private view {
		require(state == BETS_STATE, "Bets over");
		require(_flippeningDate > block.timestamp, "Cannot bet on past");
	}

	function verifyTicketExists(TicketFundsInfo memory fundsInfo) private pure {
		require(fundsInfo.amount > 0 || fundsInfo.tokenId != 0, "No ticket");
	}

	function verifyCollectRewardsState() private view {
		require(state == CLAIM_STATE && hasWon, "Not allowed");
		require(block.timestamp - flippeningDate >= CLAIM_WIN_PERIOD, "Too early");
		require(block.timestamp - flippeningDate <= CLAIM_WIN_PERIOD + COLLECT_REWARD_MAX_PERIOD, "Too late");
	}
}

