// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.17;

import { TournamentToken } from "./TournamentToken.sol";
import { ITournamentToken } from "./ITournamentToken.sol";
import { TournamentConsumer } from "./TournamentConsumer.sol";
import { IERC20 } from "./IERC20.sol";
import { ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { Clones } from "./Clones.sol";
import { IUniswapV2FactoryCustomFee } from "./IUniswapV2FactoryCustomFee.sol";
import { IUniswapV2PairCustomFee } from "./IUniswapV2PairCustomFee.sol";
import { IUniswapV2Router02CustomFee } from "./IUniswapV2Router02CustomFee.sol";
import { Math } from "./Math.sol";

import "./console.sol";

/**
 * @dev
 * Token IDs
 * - Each tokenId is stored in a mapping (uint8 => address)
 * 
 * Bracket storage
 * - Tournament bracket is a uint8[16]
 * - Each byte contains a uint8 representing tokenId
 * - 0xff represents unresolved game state uint8(-1)
 * - Winner of each round is stored in the next empty slot
 * 
 * MatchId: (tokenId, tokenId) -> winnerId
 * 
 * Round      0               1               2
 * 		 0: (0,1) -> A   4: (A,B) -> E   6: (E,F) -> Winner
 * 		 1: (2,3) -> B   5: (C,D) -> F
 * 		 2: (4,5) -> C
 * 		 3: (6,7) -> D
 * 
 * Bracket (each slot uint8)
 *  
 *  0 \
 *     8 
 *  1 /  \
 *        12
 *  2 \  /  \
 *     9     \
 *  3 /       \
 *            14 (winner)
 *  4 \       /
 *     10    /
 *  5 /  \  /
 *        13
 *  6 \  /
 *     11
 *  7 /
 * 
 * Lifecycle
 * startTournament() -> startRound() -> endRound() -> endTournament()
 * 
 * Redemption
 * - Winning token can be burned for usdc at end of each tournament
 * - tournaments[id].reward = tournament_usdc_amount / winning_token_supply
 * - redeem() fuction used to transfer + burn winning tokens for reward_usdc/token
 * - Pending rewards tracked in contract, burning tokens limits reward to token supply
 * 
 **/
contract TournamentManager is TournamentConsumer {
	using SafeERC20 for IERC20;
	using SafeERC20 for ERC20;
	using SafeERC20 for ITournamentToken;

	address public manager;
	address public tokenImplementation;

	IUniswapV2FactoryCustomFee public factory;
	IUniswapV2Router02CustomFee public router;
	address public usdcAddress;
	IERC20 public usdc;
	uint256 constant USDC_PRECISION = 1e6;
	uint256 constant PRECISION = 1e18;
	uint256 constant BASIS_PRECISION = 10000;

	// initial balance of each token = 10,000
	uint256 constant public STARTING_BALANCE = 10000000000000000000000;
	string[8] NAMES = ["Sifu", "Bitlord", "Cobie", "CZ", "Dani", "Vitalik", "Justin", "SBF"];
	string[8] SYMBOLS = ["SIFU", "BTLD", "COBI", "CZ", "DANI", "VTLK", "JSTN", "SBF"];
	uint8[16] INITIAL_BRACKET = [0, 1, 2, 3, 4, 5, 6, 7, 255, 255, 255, 255, 255, 255, 255, 255];

	// data for current tournament in progress
	uint8 public round;
	bool public isTournamentActive;
	bool public isRoundActive;
	bool public isTradingPaused;
	bool public initialized;

	// rewards & fees in USDC
	uint256 public pendingRewards;
	uint256 public pendingFees;

	// tournaments
	uint256 public id; // tournament ID
	mapping(uint256 => Tournament) public tournaments;

	// Previous k value for a token pair. Used to calculate fees.
	mapping(address => uint256) public kLast;

	// Original Liquidity added per pool
	uint256 public startingLiquidity;

	struct Tournament {
		address[8] tokens;	// array of tournament tokens
		uint8[16] bracket;	// tournament bracket
		uint256 reward;		// reward per winning token
	}

	constructor(
		uint64 _subscriptionId,
		address coordinatorAddress
	) TournamentConsumer(_subscriptionId, coordinatorAddress) {}

	event ManagementTransferred(address newManager);
	event TokenImplementationChanged(address newImplementation);
	event TournamentStarted(uint256 indexed tournamentId, uint256 tournamentUsdc);
	event RoundStarted(uint256 indexed tournamentId, uint8 round);
	event TradingPauseStatusSet(bool status);
	event RoundEnded(uint256 indexed tournamentId, uint8 round, uint8[16] bracket);
	event MatchResolved(uint256 indexed tournamentId, uint8 tokenA, uint8 tokenB, uint8 winningId, uint256 totalUsdc);
	event TournamentResolved(uint256 indexed tournamentId, address indexed winningToken, uint256 reward);
	event Redeem(uint256 tournamentId, uint256 amount, address indexed sender);
	event FeeCollected(uint256 amount);
	event EmergencyPauseTrading(bool status);
	event Log(string log);

	function initialize(IUniswapV2Router02CustomFee _router, address _usdcAddress, address _tokenImplementation) external {
		require(!initialized, "already initialized");
		initialized = true;
		manager = msg.sender;
		router = _router;
		tokenImplementation = _tokenImplementation;
		factory = IUniswapV2FactoryCustomFee(router.factory());
		usdcAddress = _usdcAddress;
		usdc = IERC20(_usdcAddress);
		usdc.approve(address(router), type(uint).max);
	}

	modifier onlyManager() {
		require(msg.sender == manager, "onlyManger: sender is not manager");
		_;
	}

	// @dev Transfer Management
	function transferManagement(address newManager) external onlyOwner {
		manager = newManager;
		emit ManagementTransferred(newManager);
	}

	// @dev Set Tournament token implementation
	function setTokenImplementation(address _tokenImplementation) external onlyOwner {
		require(_tokenImplementation != address(0), "Cannot be zero address");
		tokenImplementation = _tokenImplementation;
		emit TokenImplementationChanged(_tokenImplementation);
	}

	// @dev set router and factory
	function setRouter(address _router) external onlyOwner {
		require(_router != address(0), "Cannot be zero address");
		router = IUniswapV2Router02CustomFee(_router);
		factory = IUniswapV2FactoryCustomFee(router.factory());
	}

	// @dev collect fee
	function collectFee() external onlyOwner {
		uint256 pending = pendingFees;
		pendingFees = 0; // check-effects-interactions
		usdc.safeTransfer(owner(), pending);
		emit FeeCollected(pending);
	}

	// withdraw tournament liquidity to owner
	function withdrawLiquidity(uint256 amount) external onlyOwner {
		require(getLiquidityBalance() > 0, "no liquidity");
		usdc.safeTransfer(owner(), getLiquidityBalance());
	}

	// withdraw arbitrary ERC20 to owner. cannot use for USDC
	function withdrawERC20(IERC20 token) external onlyOwner {
		require(address(token) != usdcAddress, "can only withdraw USDC with withdrawLiquidity()");
		token.transfer(owner(), token.balanceOf(address(this)));
	}

	// @dev withdraw all usdc liquidity in emergency
	function emergencyWithdraw() external onlyOwner {
		if (isTradingPaused) {
			setTokenPauseStatus(false);
		}
		IUniswapV2PairCustomFee pair;
		address tokenAddress;
		for (uint8 i = 0; i < 8; i ++) {
			tokenAddress = tournaments[id].tokens[i];
			pair = IUniswapV2PairCustomFee(factory.getPair(tokenAddress, usdcAddress));
			// try/catch in case insufficient liquidity
			try router.removeLiquidity(
				tokenAddress, usdcAddress, pair.balanceOf(address(this)), 0, 0, address(this), block.timestamp
			) returns (uint amountA, uint amountB) {
            	// do nothing
        	} catch {
            	emit Log("external call failed");
        	}
		}
		usdc.safeTransfer(owner(), usdc.balanceOf(address(this)));
	}

	// @dev set token pause status in emergency
	function emergencySetTradingPauseStatus(bool status) external onlyOwner {
		setTokenPauseStatus(status);
		emit EmergencyPauseTrading(status);
	}

	// @dev seed liquidity, create pools, mint tokens
	// @dev whitelist manager & factory to transfer between each other during pauses
	function startTournament() external onlyManager {
		require(!isTournamentActive, "startTournament: Tournament already active");
		uint256 tournamentUsdc = getLiquidityBalance();
		require(tournamentUsdc >= 8 * USDC_PRECISION, "require at least 8 reward token");
		isTournamentActive = true;
		tournaments[id].bracket = INITIAL_BRACKET;
		round = 0;
		deployTokens();
		addUniswapLiquidity();
		startRound();
		emit TournamentStarted(id, tournamentUsdc);
	}

	// @dev start next round
	// set round active, start random interval, unpause tokens if round > 0
	function startRound() internal {
		require(isTournamentActive, "startRound: Tournament is not active.");
		require(!isRoundActive, "startRound: A round is currently active.");

		isRoundActive = true;
		start();
		if (round > 0) {
			setTokenPauseStatus(false);
		}
		emit RoundStarted(id, round);
	}

	// @dev Pause or unpause
	function setTokenPauseStatus(bool status) internal {
		for (uint8 i = 0; i < 8; i++) {
			ITournamentToken(tournaments[id].tokens[i]).setPauseStatus(status);
		}
		isTradingPaused = status;
		emit TradingPauseStatusSet(status);
	}

	// @def Triggered by Tournament Coordinator
	// End round and stop VRF.
	function stop() internal override {
		super.stop();
		endRound();
	}

	// @dev End current round and start next round
	// Update matches, increment round, set round inactive, pause trading
	function endRound() internal {
		require(isTournamentActive, "endRound: Tournament is not active.");
		require(isRoundActive, "endRound: Round is not active.");

		updateMatches();
		emit RoundEnded(id, round, tournaments[id].bracket);
		round++;
		isRoundActive = false;
		if (round == 3) {
			endTournament();
		}
		else {
			setTokenPauseStatus(true);
			startRound();
		}
	}

	/// @dev seed liquidity, create pools, mint tokens
	function endTournament() internal {
		require(isTournamentActive, "endTournament: Tournament is not active");
		require(round == 3, "endTournament: Tournament cannot be ended");
		resolveTournament();
		id++;
		isTournamentActive = false;
	}

	// @dev logic to resolve matches based on round
	function updateMatches() internal {
		if (round == 0) {
			tournaments[id].bracket[8]  = resolveMatch(0, 1);
			tournaments[id].bracket[9]  = resolveMatch(2, 3);
			tournaments[id].bracket[10] = resolveMatch(4, 5);
			tournaments[id].bracket[11] = resolveMatch(6, 7);
		}
		else if (round == 1) {
			tournaments[id].bracket[12] = resolveMatch(
				tournaments[id].bracket[8],
				tournaments[id].bracket[9]
			);
			tournaments[id].bracket[13] = resolveMatch(
				tournaments[id].bracket[10],
				tournaments[id].bracket[11]
			);
		}
		else if (round == 2) {
			tournaments[id].bracket[14] = resolveMatch(
				tournaments[id].bracket[12], 
				tournaments[id].bracket[13]
			);
		}
	}

	// @dev Resolve a single match between two tokenIds
	// 1. Calculate winning/losing tokens based on highest uniswap price
	// 2. Calculate fees (change in k)
	// 3. Remove fee liquidity and swap tokens for USDC
	// 4. Remove losing token liquidity
	// 5. Swap USDC from losing pair for winning tokens
	// 6. Burn remaining tokens and return winning ID
	function resolveMatch(uint8 tokenA, uint8 tokenB) internal returns (uint8 winningId) {
		// cache variables to save gas costs
		ITournamentToken winningToken;
		ITournamentToken losingToken;
		IUniswapV2PairCustomFee winningPair;
		IUniswapV2PairCustomFee losingPair;
		uint256 winningLpFee;
		uint256 losingLpFee;

		// scope to avoid stack too deep
		// calculate winning pair
		{
			IUniswapV2PairCustomFee tokenAPair;
			IUniswapV2PairCustomFee tokenBPair;
			uint256 tokenAPrice;
			uint256 tokenBPrice;

			(tokenAPrice, tokenAPair) = getSpotPriceAndPair(tournaments[id].tokens[tokenA]);
			(tokenBPrice, tokenBPair) = getSpotPriceAndPair(tournaments[id].tokens[tokenB]);

			if (tokenAPrice >= tokenBPrice) {
				winningToken = ITournamentToken(tournaments[id].tokens[tokenA]);
				losingToken = ITournamentToken(tournaments[id].tokens[tokenB]);
				winningId = tokenA;
				winningPair = tokenAPair;
				losingPair = tokenBPair;
			} else {
				winningToken = ITournamentToken(tournaments[id].tokens[tokenB]);
				losingToken = ITournamentToken(tournaments[id].tokens[tokenA]);
				winningId = tokenB;
				winningPair = tokenBPair;
				losingPair = tokenAPair;
			}
		}

		// calculate LP fee as % growth in k
		{
			uint256 losingFee = calculateFee(losingPair);
			losingLpFee = (losingFee * losingPair.balanceOf(address(this))) / 1e18;
			uint256 winningFee = calculateFee(winningPair);
			winningLpFee = (winningFee * winningPair.balanceOf(address(this))) / 1e18;
		}

		// cache usdc balance before fees
		uint256 usdcBalanceBefore = usdc.balanceOf(address(this));

		// remove fee liquidity and swap for USDC
		address[] memory path = new address[](2);
		path[1] = address(usdc);

		// remove & sell losing liquidity tokens
		if (losingLpFee > 0) {
			router.removeLiquidity(
				address(losingToken), address(usdc), losingLpFee, 0, 0, address(this), block.timestamp
			);
			path[0] = address(losingToken);
			router.swapExactTokensForTokens(
				losingToken.balanceOf(address(this)), 0, path, address(this), block.timestamp
			);
		}

		// remove & sell winning liquidity tokens
		if (winningLpFee > 0) {
			router.removeLiquidity(
				address(winningToken), address(usdc), winningLpFee, 0, 0, address(this), block.timestamp
			);
			path[0] = address(winningToken);
			router.swapExactTokensForTokens(
				winningToken.balanceOf(address(this)), 0, path, address(this), block.timestamp
			);
		}

		// update k for winning pair
		kLast[address(winningPair)] = getKValue(winningPair);

		// save pending fees
		pendingFees += usdc.balanceOf(address(this)) - usdcBalanceBefore;
		usdcBalanceBefore = usdc.balanceOf(address(this));

		// remove remaining losing liquidity
		router.removeLiquidity(
			address(losingToken),
			address(usdc),
			losingPair.balanceOf(address(this)), // liquidity
			0, 					// amountAMin
			0, 					// amountBMin
			address(this), 		// to, 
			block.timestamp 	// deadline
		);

		// swap USDC for winning token
    	path[0] = address(usdc);
    	path[1] = address(winningToken);

    	// subtract starting liquidity from swap amount
    	uint256 swapAmount = usdc.balanceOf(address(this)) - usdcBalanceBefore;
    	swapAmount = swapAmount < startingLiquidity ? 0 : swapAmount - startingLiquidity;

    	// swap remaining usdc for winning token
    	if (swapAmount > 0) {
    		router.swapExactTokensForTokens(
				swapAmount, 	// amountIn
				0, 													// amountOutMin
				path,  												// path
				address(this), 										// to
				block.timestamp										// deadline
			);
    	}

		// burn remaining tokens and emit event
		losingToken.burn(losingToken.balanceOf(address(this)));
		winningToken.burn(winningToken.balanceOf(address(this)));
		emit MatchResolved(id, tokenA, tokenB, winningId, usdc.balanceOf(address(winningPair)));

		return winningId;
	}

	// Get percentage growth in k with 18 decimals of precision
	// growth_percentage = 1 - sqrt(k1) / sqrt(k2)
	function calculateFee(IUniswapV2PairCustomFee pair) internal view returns (uint256) {
		uint256 k1 = kLast[address(pair)];
		uint256 k2 = getKValue(pair);
		if (k2 == 0) { return 1e18; }
		return 1e18 - (Math.sqrt(k1) * 1e18) / Math.sqrt(k2);
	}

	// @dev Get k value from uniswap pair by multiplying rewards
	function getKValue(IUniswapV2PairCustomFee pair) internal view returns (uint256) {
		(uint112 reserve0, uint112 reserve1, ) = pair.getReserves();
		return uint256(reserve0) * uint256(reserve1);
	}

	// @dev Remove liquidity for winning token and calculate reward
	function resolveTournament() internal {
		ITournamentToken winningToken = ITournamentToken(getWinningToken(id));
		IERC20 pair = IERC20(factory.getPair(address(winningToken), address(usdc)));
		uint256 usdcBefore = usdc.balanceOf(address(this));

		router.removeLiquidity(
			address(winningToken),			// tokenA
			address(usdc),					// tokenB
			pair.balanceOf(address(this)), 	// liquidity 
			0, 								// amountAMin
			0, 								// amountBMin
			address(this), 					// to,
			block.timestamp 				// deadline
		);

		// burn tokens owned by this contract
		winningToken.burn(winningToken.balanceOf(address(this)));

		// calculate reward based on remaining usdc and total supply
		uint256 totalReward = usdc.balanceOf(address(this)) - usdcBefore;
    	totalReward = totalReward < startingLiquidity ? 0 : totalReward - startingLiquidity;

		uint256 reward = (totalReward * PRECISION) / winningToken.totalSupply();
		tournaments[id].reward = reward;
		pendingRewards += totalReward;

		emit TournamentResolved(id, address(winningToken), totalReward);
	}

	// @dev Redeem `amount` tokens
	// Only winning token for valid tournament can be redeemed
	function redeem(uint256 tournamentId, uint256 amount) external {
		ITournamentToken winningToken = ITournamentToken(getWinningToken(tournamentId));
		// require(winningToken.balanceOf(msg.sender) <= amount, "TournamentManger: insufficient redemption amount");
		uint256 usdcReward = (tournaments[tournamentId].reward * amount) / PRECISION;
		pendingRewards -= usdcReward;
		winningToken.safeTransferFrom(msg.sender, address(this), amount);
		winningToken.burn(amount);
		usdc.safeTransfer(msg.sender, usdcReward);
		emit Redeem(tournamentId, amount, msg.sender);
	}

	// @dev calculate reward amount
	function calculateReward(uint256 supply, uint256 totalReward) public view returns (uint256) {
		uint256 reward =
		(
			(totalReward * PRECISION) / supply
		);
        return reward;
    }

    // @dev Deploy tokens behind minimal proxy and set whitelist status
    // Use block hash to generate random ordering of token names
	function deployTokens() internal {
		uint8[8] memory numbers;

        for (uint8 i = 0; i < 8; i++) {
            numbers[i] = i;
        }

        bytes32 blockHash = blockhash(block.number - 1);
        uint256 randomNumber;

        for (uint8 i = 0; i < 8; i++) {
            randomNumber = uint256(blockHash) % (i + 1);
            (numbers[i], numbers[randomNumber]) = (numbers[randomNumber], numbers[i]);
            blockHash = keccak256(abi.encodePacked(blockHash));
        }

		address token;
		for (uint8 i = 0; i < 8; i++) {
			token = Clones.clone(tokenImplementation);
			ITournamentToken(token).initialize(STARTING_BALANCE, NAMES[numbers[i]], SYMBOLS[numbers[i]]);
			tournaments[id].tokens[i] = token;
			ITournamentToken(token).setWhitelistStatus(address(this), address(factory), true);
			ITournamentToken(token).setWhitelistStatus(address(factory), address(this), true);
		}
	}

	// @dev Add uniswap liquidity for game tokens
	function addUniswapLiquidity() internal {
		uint256 tournamentUsdc = getLiquidityBalance();
		uint256 liquidity = tournamentUsdc / 8;
		startingLiquidity = liquidity;

		// loop through tokens and add liquidity
		IERC20 token;
		for (uint8 i = 0; i < 8; i++) {
			// cache token and create pair
			token = IERC20(tournaments[id].tokens[i]);
			token.approve(address(router), type(uint).max);

			// (uint amountA, uint amountB, uint liquidity) = 
			router.addLiquidity(
				address(usdc),						// tokenA
				address(token),						// tokenB
				liquidity, 							// amountADesired
				token.balanceOf(address(this)),		// amountBDesired
				1, 									// uint amountAMin
				1,									// uint amountBMin
				address(this), 						// address to
				block.timestamp 					// uint deadline
			);
			address pairAddress = factory.getPair(address(token), address(usdc));
			IERC20(pairAddress).approve(address(router), type(uint).max);
			kLast[pairAddress] = getKValue(IUniswapV2PairCustomFee(pairAddress));
		}
	}

	/// @dev View function to get tournament token price in USDC for amount
    function getAmountsOut(address token, uint256 amount) public view returns (uint256) {
    	address[] memory path = new address[](2);
    	path[0] = token;
    	path[1] = address(usdc);
    	return router.getAmountsOutWithFee(amount, path)[1];
    }

    // @dev View function to get spot price and pair of token in USDC using reserves
    function getSpotPriceAndPair(address token) public view returns (uint256 spotPrice, IUniswapV2PairCustomFee) {
    	IUniswapV2PairCustomFee pair = IUniswapV2PairCustomFee(factory.getPair(token, usdcAddress));
    	(uint256 reserves0, uint256 reserves1, ) = pair.getReserves();
    	if (pair.token0() == usdcAddress) {
    		spotPrice = (reserves0 * PRECISION) / reserves1;
    	}
    	else {
    		spotPrice = (reserves1 * PRECISION) / reserves0;
    	}
    	return (spotPrice, pair);
    }

    // @dev View function to get spot price of token in USDC using reserves
    function getSpotPrice(address token) public view returns (uint256 spotPrice) {
    	IUniswapV2PairCustomFee pair = IUniswapV2PairCustomFee(factory.getPair(token, usdcAddress));
    	(uint256 reserves0, uint256 reserves1, ) = pair.getReserves();
    	if (pair.token0() == usdcAddress) {
    		return (reserves0 * PRECISION) / reserves1;
    	}
    	else {
    		return (reserves1 * PRECISION) / reserves0;
    	}
    }

    // @dev View function to get token by ID
    function getTokenById(uint256 tournamentId, uint8 tokenId) public view returns (address) {
    	require(tokenId < 8, "getTokenById: id out of bounds");
    	return tournaments[tournamentId].tokens[tokenId];
    }

    // @dev Get winning token for a tournament ID
    // 14th slot in bracket is winner
    function getWinningToken(uint256 tournamentId) public view returns (address) {
    	require(tournamentId <= id, "no tournament with this id");
    	require(tournaments[tournamentId].bracket[14] != 255, "getWinningToken: no winner for this tournament");
    	return tournaments[tournamentId].tokens[tournaments[tournamentId].bracket[14]];
    }

    function getBracket(uint256 tournamentId) public view returns (uint8[16] memory) {
    	return tournaments[tournamentId].bracket;
    }

    function getTokens(uint256 tournamentId) public view returns (address[8] memory) {
    	return tournaments[tournamentId].tokens;
    }

    function getReward(uint256 tournamentId) public view returns (uint256) {
    	return tournaments[tournamentId].reward;
    }

    // get balance of usdc minus pending fees and pending rewards
    function getLiquidityBalance() public view returns (uint256) {
    	return usdc.balanceOf(address(this)) - pendingRewards - pendingFees;
    }
}
