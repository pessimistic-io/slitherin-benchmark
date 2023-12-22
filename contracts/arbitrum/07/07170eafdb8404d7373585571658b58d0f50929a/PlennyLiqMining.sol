// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;
pragma experimental ABIEncoderV2;

import "./SafeERC20Upgradeable.sol";
import "./SafeMathUpgradeable.sol";
import "./AddressUpgradeable.sol";
import "./IUniswapV2Pair.sol";
import "./PlennyLiqMiningStorage.sol";
import "./PlennyBasePausableV2.sol";
import "./ExtendedMathLib.sol";
import "./IWETH.sol";

/// @title  PlennyLiqMining
/// @notice Staking for liquidity mining integrated with the DEX, allows users to stake LP-token and earn periodic rewards.
contract PlennyLiqMining is PlennyBasePausableV2, PlennyLiqMiningStorage {

    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address payable;
    using ExtendedMathLib for uint256;

    /// An event emitted when logging function calls
    event LogCall(bytes4  indexed sig, address indexed caller, bytes data) anonymous;

    /// @notice Initializes the contract instead of the constructor. Called once during contract deployment.
    /// @param  _registry plenny contract registry
    function initialize(address _registry) external initializer {
        // 5%
        liquidityMiningFee = 500;

        liqMiningReward = 1;
        // 0.01%

        // 0.5%
        fishingFee = 50;

        // 1 day = 6500 blocks
        nextDistributionSeconds = 6500;

        // 10 years in blocks
        maxPeriodWeek = 23725000;
        // 1 week in blocks
        averageBlockCountPerWeek = 45500;

        PlennyBasePausableV2.__plennyBasePausableInit(_registry);
    }

    /// @notice Locks LP token in this contract for the given period.
    /// @param  amount lp amount to lock
    /// @param  period period, in weeks
    function lockLP(uint256 amount, uint256 period) external whenNotPaused nonReentrant {
        _logs_();
        require(amount > 0, "ERR_EMPTY");
        require(period <= maxPeriodWeek, "ERR_MAX_PERIOD");

        uint256 weight = calculateWeight(period);
        uint256 endDate = _blockNumber().add(averageBlockCountPerWeek.mul(period));
        lockedBalance.push(LockedBalance(msg.sender, amount, _blockNumber(), endDate, weight, false));
        uint256 index = lockedBalance.length - 1;
        lockedIndexesPerAddress[msg.sender].push(index);

        totalUserLocked[msg.sender] = totalUserLocked[msg.sender].add(amount);
        totalUserWeight[msg.sender] = totalUserWeight[msg.sender].add(amount.mul(weight).div(WEIGHT_MULTIPLIER));
        if (userLockedPeriod[msg.sender] == 0) {
            userLockedPeriod[msg.sender] = _blockNumber().add(nextDistributionSeconds);
            userLastCollectedPeriod[msg.sender] = _blockNumber();
        }

        totalValueLocked = totalValueLocked.add(amount);
        totalWeightLocked = totalWeightLocked.add(amount.mul(weight).div(WEIGHT_MULTIPLIER));

        require(contractRegistry.lpContract().transferFrom(msg.sender, address(this), amount), "Failed");
    }

    /// @notice Relocks the LP tokens once the locking period has expired.
    /// @param  index id of the previously locked record
    /// @param  period the new locking period, in weeks
    function relockLP(uint256 index, uint256 period) external whenNotPaused nonReentrant {
        _logs_();
        uint256 i = lockedIndexesPerAddress[msg.sender][index];
        require(index < lockedBalance.length, "ERR_NOT_FOUND");
        require(period > 0, "ERR_INVALID_PERIOD");
        require(period <= maxPeriodWeek, "ERR_MAX_PERIOD");
        LockedBalance storage balance = lockedBalance[i];
        require(balance.owner == msg.sender, "ERR_NO_PERMISSION");
        require(balance.endDate < _blockNumber(), "ERR_LOCKED");

        uint256 oldWeight = balance.amount.mul(balance.weight).div(WEIGHT_MULTIPLIER);
        totalUserWeight[msg.sender] = totalUserWeight[msg.sender].sub(oldWeight);
        totalWeightLocked = totalWeightLocked.sub(oldWeight);

        uint256 weight = calculateWeight(period);
        balance.endDate = _blockNumber().add(averageBlockCountPerWeek.mul(period));
        balance.weight = weight;

        uint256 newWeight = balance.amount.mul(balance.weight).div(WEIGHT_MULTIPLIER);
        totalUserWeight[msg.sender] = totalUserWeight[msg.sender].add(newWeight);
        totalWeightLocked = totalWeightLocked.add(newWeight);
    }

    /// @notice Withdraws the LP tokens, once the locking period has expired.
    /// @param  index id of the locking record
    function withdrawLP(uint256 index) external whenNotPaused nonReentrant {
        _logs_();
        uint256 i = lockedIndexesPerAddress[msg.sender][index];
        require(index < lockedBalance.length, "ERR_NOT_FOUND");

        LockedBalance storage balance = lockedBalance[i];
        require(balance.owner == msg.sender, "ERR_NO_PERMISSION");
        require(balance.endDate < _blockNumber(), "ERR_LOCKED");

        if (lockedIndexesPerAddress[msg.sender].length == 1) {
            userLockedPeriod[msg.sender] = 0;
        }

        uint256 fee = balance.amount.mul(fishingFee).div(100).div(100);
        uint256 weight = balance.amount.mul(balance.weight).div(WEIGHT_MULTIPLIER);

        if (_blockNumber() > (userLastCollectedPeriod[msg.sender]).add(nextDistributionSeconds)) {
            totalUserEarned[msg.sender] = totalUserEarned[msg.sender].add(
                calculateReward(weight).mul(_blockNumber().sub(userLastCollectedPeriod[msg.sender])).div(nextDistributionSeconds));
            totalWeightCollected = totalWeightCollected.add(weight);
            totalWeightLocked = totalWeightLocked.sub(weight);
        } else {
            totalWeightLocked = totalWeightLocked.sub(weight);
        }

        totalUserLocked[msg.sender] = totalUserLocked[msg.sender].sub(balance.amount);
        totalUserWeight[msg.sender] = totalUserWeight[msg.sender].sub(weight);
        totalValueLocked = totalValueLocked.sub(balance.amount);

        balance.deleted = true;
        removeElementFromArray(index, lockedIndexesPerAddress[msg.sender]);

        IUniswapV2Pair lpToken = contractRegistry.lpContract();
        require(lpToken.transfer(msg.sender, balance.amount - fee), "Failed");
        require(lpToken.transfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), fee), "Failed");
    }

    /// @notice Collects plenny reward for the locked LP tokens
    function collectReward() external whenNotPaused nonReentrant {
        if (totalUserEarned[msg.sender] == 0) {
            require(userLockedPeriod[msg.sender] < _blockNumber(), "ERR_LOCKED_PERIOD");
        }

        uint256 reward = calculateReward(totalUserWeight[msg.sender]).mul((_blockNumber().sub(userLastCollectedPeriod[msg.sender]))
        .div(nextDistributionSeconds)).add(totalUserEarned[msg.sender]);

        uint256 fee = reward.mul(liquidityMiningFee).div(10000);

        bool reset = true;
        uint256 [] memory userRecords = lockedIndexesPerAddress[msg.sender];
        for (uint256 i = 0; i < userRecords.length; i++) {
            LockedBalance storage balance = lockedBalance[userRecords[i]];
            reset = false;
            if (balance.weight > WEIGHT_MULTIPLIER && balance.endDate < _blockNumber()) {
                uint256 diff = balance.amount.mul(balance.weight).div(WEIGHT_MULTIPLIER).sub(balance.amount);
                totalUserWeight[msg.sender] = totalUserWeight[msg.sender].sub(diff);
                totalWeightLocked = totalWeightLocked.sub(diff);
                balance.weight = uint256(1).mul(WEIGHT_MULTIPLIER);
            }
        }

        if (reset) {
            userLockedPeriod[msg.sender] = 0;
        } else {
            userLockedPeriod[msg.sender] = _blockNumber().add(nextDistributionSeconds);
        }
        userLastCollectedPeriod[msg.sender] = _blockNumber();
        totalUserEarned[msg.sender] = 0;
        totalWeightCollected = 0;

        IPlennyReward plennyReward = contractRegistry.rewardContract();
        require(plennyReward.transfer(msg.sender, reward - fee), "Failed");
        require(plennyReward.transfer(contractRegistry.requireAndGetAddress("PlennyRePLENishment"), fee), "Failed");
    }

    /// @notice Changes the liquidity Mining Fee. Managed by the contract owner.
    /// @param  newLiquidityMiningFee mining fee. Multiplied by 10000
    function setLiquidityMiningFee(uint256 newLiquidityMiningFee) external onlyOwner {
        require(newLiquidityMiningFee < 10001, "ERR_WRONG_STATE");
        liquidityMiningFee = newLiquidityMiningFee;
    }

    /// @notice Changes the fishing Fee. Managed by the contract owner
    /// @param  newFishingFee fishing(exit) fee. Multiplied by 10000
    function setFishingFee(uint256 newFishingFee) external onlyOwner {
        require(newFishingFee < 10001, "ERR_WRONG_STATE");
        fishingFee = newFishingFee;
    }

    /// @notice Changes the next Distribution in seconds. Managed by the contract owner
    /// @param  value number of blocks.
    function setNextDistributionSeconds(uint256 value) external onlyOwner {
        nextDistributionSeconds = value;
    }

    /// @notice Changes the max Period in week. Managed by the contract owner
    /// @param  value max locking period, in blocks
    function setMaxPeriodWeek(uint256 value) external onlyOwner {
        maxPeriodWeek = value;
    }

    /// @notice Changes average block counts per week. Managed by the contract owner
    /// @param count blocks per week
    function setAverageBlockCountPerWeek(uint256 count) external onlyOwner {
        averageBlockCountPerWeek = count;
    }

    /// @notice Percentage reward for liquidity mining. Managed by the contract owner.
    /// @param  value multiplied by 100
    function setLiqMiningReward(uint256 value) external onlyOwner {
        liqMiningReward = value;
    }

    /// @notice Number of total locked records.
    /// @return uint256 number of records
    function lockedBalanceCount() external view returns (uint256) {
        return lockedBalance.length;
    }

    /// @notice Shows potential reward for the given user.
    /// @return uint256 token amount
    function getPotentialRewardLiqMining() external view returns (uint256) {
        return calculateReward(totalUserWeight[msg.sender]);
    }

    /// @notice Gets number of locked records per address.
    /// @param  addr address to check
    /// @return uint256 number
    function getBalanceIndexesPerAddressCount(address addr) external view returns (uint256){
        return lockedIndexesPerAddress[addr].length;
    }

    /// @notice Gets locked records per address.
    /// @param  addr address to check
    /// @return uint256[] arrays of indexes
    function getBalanceIndexesPerAddress(address addr) external view returns (uint256[] memory){
        return lockedIndexesPerAddress[addr];
    }

    /// @notice Gets the LP token rate.
    /// @return rate
    function getUniswapRate() external view returns (uint256 rate){

        IUniswapV2Pair lpContract = contractRegistry.lpContract();

        address token0 = lpContract.token0();
        if (token0 == contractRegistry.requireAndGetAddress("WETH")) {
            (uint256 tokenEth, uint256 tokenPl2,) = lpContract.getReserves();
            return tokenPl2 > 0 ? uint256(1).mul((10 ** uint256(18))).mul(tokenEth).div(tokenPl2) : 0;
        } else {
            (uint256 pl2, uint256 eth,) = lpContract.getReserves();
            return pl2 > 0 ? uint256(1).mul((10 ** uint256(18))).mul(eth).div(pl2) : 0;
        }
    }

    /// @notice Calculates the reward of the user based on the user's participation (weight) in the LP locking.
    /// @param  weight participation in the LP mining
    /// @return uint256 plenny reward amount
    function calculateReward(uint256 weight) public view returns (uint256) {
        if (totalWeightLocked > 0) {
            return contractRegistry.plennyTokenContract().balanceOf(
                contractRegistry.requireAndGetAddress("PlennyReward")).mul(liqMiningReward)
                .mul(weight).div(totalWeightLocked.add(totalWeightCollected)).div(10000);
        } else {
            return 0;
        }
    }

    /// @notice Calculates the user's weight based on its locking period.
    /// @param  period locking period, in weeks
    /// @return uint256 weight
    function calculateWeight(uint256 period) internal pure returns (uint256) {

        uint256 periodInWei = period.mul(10 ** uint256(18));
        uint256 weightInWei = uint256(1).add((uint256(2).mul(periodInWei.sqrt())).div(10));

        uint256 numerator = (weightInWei.sub(1)).mul(WEIGHT_MULTIPLIER);
        uint256 denominator = (10 ** uint256(18)).sqrt();
        return numerator.div(denominator).add(WEIGHT_MULTIPLIER);
    }

    /// @notice String equality.
    /// @param  a first string
    /// @param  b second string
    /// @return bool true/false
    function stringsEqual(string memory a, string memory b) internal pure returns (bool) {
        return (keccak256(abi.encodePacked(a)) == keccak256(abi.encodePacked(b)));
    }

    /// @notice Emits log event of the function calls.
    function _logs_() internal {
        emit LogCall(msg.sig, msg.sender, msg.data);
    }

    /// @notice Removes index element from the given array.
    /// @param  index index to remove from the array
    /// @param  array the array itself
    function removeElementFromArray(uint256 index, uint256[] storage array) private {
        if (index == array.length - 1) {
            array.pop();
        } else {
            array[index] = array[array.length - 1];
            array.pop();
        }
    }
}

