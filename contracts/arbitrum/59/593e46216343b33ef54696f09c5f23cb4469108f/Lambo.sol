// SPDX-License-Identifier: MIT
pragma solidity ^0.8.1;

import "./MechaPunkx.sol";
import "./Ownable.sol";
import "./ERC20.sol";
import "./ERC20Burnable.sol";

/*
************************
******** LAMBO *********
************************

LAMBO (by LamboCorp) is an ERC20 yielded daily to each MechaPunkx NFT.
LAMBO optimizes passive yield by auto-controlling inflation.

If more LAMBO is being burned, the yield increases.
If less LAMBO is being burned, the yield decreases.

Increasing yield allows passive earning that increases as the utility increases (token / network use), and accomodates for growth.
Decreasing yield prevents continual inflation when low expenditure.
*/
contract Lambo is ERC20, ERC20Burnable, Ownable {

	uint256 public startTime = block.timestamp;

	// Manager can modify LAMBO token settings
	address private manager = address(this); 
	// Dao receives percentage of burned LAMBO
	address public dao = 0x9615f693C05258594ac9b0d85251ae4719395D77;
	uint256 public daoPercentage = 30;
	
	MechaPunkx private MechaPunkxNFT;

	// Maps MechaPunkx tokenId to amount of LAMBO claimed
	mapping(uint256 => uint256) private claimed;

	// Records the date when the emission rate is changed (~ monthly)
	uint256[] public emissionRateChanges = [startTime];
	// Records the rate of LAMBO yield for that interval (starting at 10 LAMBO / day)
	uint256[] public emissionRates = [10];
	uint256 public emissionRateMin = 2;
	uint256 public emissionRateMax = 50;

	// LAMBO yield rate calculated based on the burn rate
	// (Time-Weighted) Average Daily Burn Rates, calculated monthly, for most recent 6 months
	bool public useBurnRate = true;
	bool public includeDaoBurn = false;
	uint256[6] public burnRates = [0, 0, 0, 0, 0, 0];
	uint256[6] public burnRateWeights = [100, 70, 50, 30, 20, 10]; 
	uint256 public burnRateWeightSum = 280;
	uint256 public burnRateIndex = 0; // Index of next write
	uint256 public burnIntervalStart = block.timestamp;
	uint256 public burnDuringInterval = 0;
	uint256 public createdDuringInterval = 0;

	// Limit the percent variation in yield rate between consecutive months
	uint256 public burnModifierMin = 50; // At most, the rate can decrease 50% in one month
	uint256 public burnModifierMax = 150; // At most, the rate can increase 50% in one month

	constructor(address mAddress) ERC20("LAMBO", "LAMBO") { 
		MechaPunkxNFT = MechaPunkx(mAddress);
	}

	modifier onlyLamboCorp() {
		require(msg.sender == owner() || msg.sender == manager, "Not allowed");
		_;
	}

	function setManager(address _manager) external onlyOwner {
		manager = _manager;
	}

	// Set the address where the DAO will receive a percentage of spent LAMBO
	function setDAO(address _dao) external onlyOwner {
		dao = _dao;   
	}

	// A percentage of all resources burned goes to the DAO, LAMBO being one resource
	function setDAOPercentage(uint256 perc) external onlyLamboCorp {
		require(perc <= 100, "Must be less than 100");
		daoPercentage = perc;
	}

	function setUseBurnRate(bool status) external onlyOwner {
		useBurnRate = status;
	}

	function setIncludeDaoBurn(bool status) external onlyOwner {
		includeDaoBurn = status;
	}

	// Update the LAMBO yield rate based on the burn rate
	// Calculate Avg. Daily Burn Rate of LAMBO (runs once per month, triggers on LAMBO burn)
	function updateBurnRate() private {

		uint256 current = block.timestamp;
		
		// If 1 or more months has passed since last update
		if (current > (burnIntervalStart + 30 days)) {

			uint256 duration = (current - burnIntervalStart) / 1 days;
			uint256 burnRateAverage = burnDuringInterval / duration;

			// Record avg. burn rate for the interval
			burnRates[burnRateIndex] = burnRateAverage;

			// Update the LAMBO yield based on the burn rate
			if (useBurnRate) {

				// Get time-weighted avg. burn rate for past 6 months
				uint256 burnAvg = 0;
				uint256 counter = 0;

				// Iterate burn rates each month in order (most recent is at burnRateIndex)
				for (uint256 i = burnRateIndex; i > 0; i--) {
					burnAvg += burnRates[i] * burnRateWeights[counter];
					counter += 1;
				}
				// Handle the 0 case outside of loop because decrementing "i" causes underflow
				burnAvg += burnRates[0] * burnRateWeights[counter];
				counter += 1;
				
				for (uint256 i = 5; i > burnRateIndex; i--) {
					burnAvg += burnRates[i] * burnRateWeights[counter];
					counter += 1;
				}
				
				burnAvg = burnAvg / burnRateWeightSum;
				uint256 burnDuringIntervalTWA = burnAvg * duration;
				uint256 mod = 100; // how much to increase / decrease yield rate (100 is no change)
			
				// If no claims, no burn, do nothing
				if (createdDuringInterval == 0 && burnDuringIntervalTWA == 0) {
					mod = 100;
				}
				else if (createdDuringInterval == 0) {
					// If no one claims during the month (handling div by zero)
					mod = burnDuringIntervalTWA * 100;
				}
				else {
					// If more burned than yielded, increase yield
					if (burnDuringIntervalTWA > createdDuringInterval) {
						uint256 excessBurn = burnDuringIntervalTWA - createdDuringInterval;
						mod = ((createdDuringInterval + excessBurn) * 100) / createdDuringInterval;
					}
					else if (burnDuringIntervalTWA < createdDuringInterval) {
						// If more yielded than burned, decrease yield
						uint256 excessYield = createdDuringInterval - burnDuringIntervalTWA;
						mod = ((createdDuringInterval - excessYield) * 100) / createdDuringInterval;
					}
				}

				// Limit how much the yield rate can change between consecutive months
				if (mod < burnModifierMin) mod = burnModifierMin;
				else if (mod > burnModifierMax) mod = burnModifierMax;

				uint256 currentRate = currentEmissionRate();
				uint256 newRate = (currentRate * mod) / 100;
				if (newRate < emissionRateMin) newRate = emissionRateMin;
				else if (newRate > emissionRateMax) newRate = emissionRateMax;
 
				if (newRate != currentRate) {
					emissionRateChanges.push(current);
					emissionRates.push(newRate);
				}
			}
			
			// Reset interval start and counters
			burnIntervalStart = current;
			createdDuringInterval = 0;
			burnDuringInterval = 0;
			if (burnRateIndex > 4) burnRateIndex = 0;
			else burnRateIndex += 1;
		}
	}

	function burn(uint256 quantity) public override {
		require(quantity > 0, "Must be non-zero quantity");
		uint256 toDao = (quantity * daoPercentage) / 100;
		if (quantity == 2 || quantity == 3) toDao = 1;
		uint256 remainder = quantity - toDao;
		if (includeDaoBurn) burnDuringInterval += quantity;
		else burnDuringInterval += remainder;
		updateBurnRate();
		if (toDao > 0) transferFrom(msg.sender, dao, toDao * (10**18));
		super._burn(msg.sender, remainder * (10**18));
	}

	function burnFrom(address addr, uint256 quantity) public override {
		require(quantity > 0, "Must be non-zero quantity");
		uint256 toDao = (quantity * daoPercentage) / 100;
		if (quantity == 2 || quantity == 3) toDao = 1;
		uint256 remainder = quantity - toDao;
		if (includeDaoBurn) burnDuringInterval += quantity;
		else burnDuringInterval += remainder;
		updateBurnRate();
		if (toDao > 0) transferFrom(addr, dao, toDao * (10**18));
		super.burnFrom(addr, remainder * (10**18));
	}
	
	function amountCanClaim(uint256 tokenId) public view returns (uint256) {

		require(MechaPunkxNFT.exists(tokenId), "MechaPunkx with that ID does not exist");
		uint256 yieldStartTime = MechaPunkxNFT.lamboYieldStartTime(tokenId);
		require(yieldStartTime > 0, "Must convert MechaPunkx to yield LAMBO before claiming"); 

		// Sum the amount earned for each interval
		uint256 current = block.timestamp;
		uint256 canClaim = 0;
		uint256 n = emissionRateChanges.length;

		for (uint256 i = 0; i < n; i++) {
			uint256 rate = emissionRates[i];
			uint256 rateChangeStart = emissionRateChanges[i];
			uint256 rateChangeEnd;
			if (i == n - 1) rateChangeEnd = current;
			else rateChangeEnd = emissionRateChanges[i+1];
			
			// Only count intervals after the NFT started yielding
			if (yieldStartTime < rateChangeEnd) { 
				uint256 start = rateChangeStart;
				if (yieldStartTime > start) start = yieldStartTime;
				uint256 duration = (rateChangeEnd - start) / 1 days;
				canClaim += duration * rate;
			}
		}
		
		// Subtract the amount previously claimed (canClaim is always > claimed)
		canClaim -= claimed[tokenId];

		return canClaim;
	}

	// Claim LAMBO allocated to a MechaPunkx NFT
	function claim(uint256 tokenId) external {
		require(MechaPunkxNFT.ownerOf(tokenId) == msg.sender, "You do not own that MechaPunkx token ID");
		uint256 canClaim = amountCanClaim(tokenId);

		if (canClaim > 0) {
			createdDuringInterval += canClaim;
			claimed[tokenId] += canClaim;
			_mint(msg.sender, canClaim * (10**18));
		}
	}

	// Gas optimized version for holders of multiple NFT's
	function claimAll() external {

		address owner = msg.sender;
		uint256 tokenCount = MechaPunkxNFT.balanceOf(owner);
		uint256 current = block.timestamp;
		uint256 n = emissionRateChanges.length;
		uint256 nLambos;
		uint256 sum;

		uint256[] memory tokens = new uint256[](tokenCount);
		uint256[] memory yieldStarts = new uint256[](tokenCount);

		for(uint256 i = 0; i < tokenCount; i++){
			uint256 t = MechaPunkxNFT.tokenOfOwnerByIndex(owner, i);
			uint256 ys = MechaPunkxNFT.lamboYieldStartTime(t);
			if (ys > 0) {
				tokens[nLambos] = t;
				yieldStarts[nLambos] = ys;
				nLambos += 1;
			}
		}
		
		uint256[] memory canClaim = new uint256[](nLambos);

		for (uint256 i = 0; i < n; i++) {
			
			uint256 rate = emissionRates[i];
			uint256 rateChangeStart = emissionRateChanges[i];
			uint256 rateChangeEnd;
			if (i == n - 1) rateChangeEnd = current;
			else rateChangeEnd = emissionRateChanges[i+1];

			for(uint256 j = 0; j < nLambos; j++){
				// Only count intervals after the NFT started yielding
				uint256 ys = yieldStarts[j];
				if (ys < rateChangeEnd) { 
					uint256 start = rateChangeStart;
					if (ys > start) start = ys;
					canClaim[j] += ((rateChangeEnd - start) / 1 days) * rate;
				}

				// If sum is complete for the NFT
				if (i == n - 1) {
					uint256 tokenId = tokens[j];
					canClaim[j] -= claimed[tokenId];
					uint256 c = canClaim[j];
					if (c > 0) {
						claimed[tokenId] += c;
						sum += c;
					}
				}
			}
		}

		if (sum > 0) {
			createdDuringInterval += sum;		
			_mint(owner, sum * (10**18));
		}
	}
	
	// Returns number of LAMBO yielded per day by a MechaPunkx NFT
	function currentEmissionRate() public view returns (uint256) {
		return emissionRates[emissionRates.length-1];
	}

	function setEmissionRateMinMax(uint256 minRate, uint256 maxRate) external onlyOwner {
		require(minRate <= maxRate, "Min should be <= max");
		// When emissionRateMin is 1, burnModifierMax has to be >= 200 to move rate from 1 to 2, otherwise rounded down
		require(minRate >= 2, "Min cannot be under 2");
		emissionRateMin = minRate;
		emissionRateMax = maxRate;
	}

	function setBurnModifierMinMax(uint256 minRate, uint256 maxRate) external onlyLamboCorp {
		require(minRate <= maxRate, "Min should be <= max");
		burnModifierMin = minRate;
		burnModifierMax = maxRate;
	}

	function updateBurnRateWeights(uint256 w0, uint256 w1, uint256 w2, uint256 w3, uint256 w4, uint256 w5) external onlyOwner {
		burnRateWeights[0] = w0;
		burnRateWeights[1] = w1;
		burnRateWeights[2] = w2;
		burnRateWeights[3] = w3;
		burnRateWeights[4] = w4;
		burnRateWeights[5] = w5;
		burnRateWeightSum = w0 + w1 + w2 + w3 + w4 + w5;
	}

	function emissionRatesLength() external view returns (uint256) {
		return emissionRates.length;
	}

	function emissionRateChangesLength() external view returns (uint256) {
		return emissionRateChanges.length;
	}

	function getClaimedAmount(uint256 tokenId) external view returns (uint256) {
		return claimed[tokenId];
	}
}

