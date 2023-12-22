// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;
import "./SafeMath.sol";

/**
 * @dev Vesting library.

 * This library is used for token distribution based on vesting params.
 * Also here are some structs used across Forcefi smart contracts.
 */
library Vesting {
    using SafeMath for uint256;

    /**
    * @notice Fundraising data struct.

    * @param1 - fundraising label to identify the contract
    * @param2  - when vesting will start
    * @param3  - how much time tokens will be locked
    * @param4  - how much vesting will last
    * @param5  - how often vesting will be released. (If set to 0, it will be linear)
    * @param6  - how much tokens will be releasable right after cliff period ends
    * @param7  - total tokens amount that can be raised
    * @param8  - minimal amount of tokens that's needed to successfully finish campaign
    * @param9  - investment token : locked token ratio multiplied by 100. Higher rate means more investment tokens are needed to get locked token.
    * @param10  - sale start date timestamp
    * @param11  - sale end date timestamp
    * @param12  - if bool is set true, only whitelisted addresses can participate
    * @param13  - minimal amount of tokens that can be bought in these campaign for single invest event
    */
    struct FundraisingData {
        string _label;
        uint _vestingStart;
        uint _cliffPeriod;
        uint _vestingPeriod;
        uint _releasePeriod;
        uint _tgePercent;
        uint _totalCampaignLimit;
        uint _campaignSoftCap;
        uint _rate;
        uint _startDate;
        uint _endDate;
        bool _isPrivate;
        uint _campaignMinTicketLimit;
    }

    /**
    * @notice Vesting plan data struct.

    * @param1 - vesting label to identify the contract
    * @param2  - when sale will start
    * @param3  - how much time tokens will be locked
    * @param4  - how much vesting will last
    * @param5  - how often vesting will be released. (If set to 0, it will be linear)
    * @param6  - how much tokens will be releasable right after cliff period ends
    * @param7  - total tokens amount that can be allocated for this vesting plan
    * @param8  - how much tokens are already allocated for this vesting plan
    * @param9  - whether the plan is initialized, prevent of duplicate vesting plans
    */
    struct VestingPlan {
        string label;
        uint saleStart;
        uint cliffPeriod;
        uint vestingPeriod;
        uint releasePeriod;
        uint tgePercent;
        uint totalTokenAmount;
        uint tokenAllocated;
        bool initialized;
    }

    /**
    * @notice Individual Vesting data struct.

    * @param1 - tokens allocated for this owner vesting
    * @param2  - tokens released
    * @param3  - whether the plan is initialized, prevent of duplicate vesting plans
    * @param4  - initialization timestamp to calculate the right amount of tokens that can be released based on vesting plan
    */
    struct IndividualVesting {
        uint tokenAmount;
        uint tokensReleased;
        bool initialized;
        uint initializedTimestamp;
    }

    /**
    * @notice Token data struct.

    * @param1 - ERC20 token name
    * @param2  - ERC20 token ticker
    * @param3  - ERC20 factory address that created the token
    * @param4  - initial mint amount
    * @param5  - param is used for equity fundraising
    */
    struct TokenData{
        string _tokenName;
        string _tokenTicker;
        address _erc20TokenFactoryAddress;
        uint _mintAmount;
        bool isNewToken;
    }

    function computeReleasableAmount(uint start, uint duration, uint period, uint lockUpPeriod, uint tgeAmount, uint invested, uint released) internal view returns(uint256){
        uint256 currentTime = block.timestamp;
        if (currentTime >= start.add(duration)) {
            return invested.sub(released);
        } else {
            uint256 tgeCalculatedAmount = invested * tgeAmount / 100;
            uint256 timeFromStart = currentTime.sub(start).sub(lockUpPeriod);
            uint256 vestedPeriods = timeFromStart.div(period);
            uint256 vestedSeconds = vestedPeriods.mul(period);
            uint256 vestedAmount = (invested - tgeCalculatedAmount).mul(vestedSeconds).div(duration);

            uint256 tgeVestedAmount = vestedAmount.add(tgeCalculatedAmount);
            tgeVestedAmount = tgeVestedAmount.sub(released);

            return tgeVestedAmount;
        }
    }

    function toWei(uint _amount) internal pure returns(uint){
        return _amount * 10**18;
    }
}

