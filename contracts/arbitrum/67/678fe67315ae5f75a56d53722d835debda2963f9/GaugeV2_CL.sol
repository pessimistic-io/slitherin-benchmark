// SPDX-License-Identifier: MIT
pragma solidity 0.8.13;


import "./SafeMath.sol";
import "./ReentrancyGuard.sol";
import "./Ownable.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

import "./IPairInfo.sol";
import "./IBribe.sol";
import "./Math.sol";

interface IFeeVault {
    function claimFees() external returns(uint256 claimed0, uint256 claimed1);
}

interface IOptionToken {
    function mint(address _to, uint256 _amount) external;
}

struct DistributionParameters {
    // ID of the reward (populated once created)
    bytes32 rewardId;
    // Address of the pool that needs to be incentivized
    address uniV3Pool;
    // Address of the reward token for the incentives
    address rewardToken;
    // Amount of `rewardToken` to distribute across all the epochs
    // Amount distributed per epoch is `amount/numEpoch`
    uint256 amount;
    // List of all UniV3 position wrappers to consider for this contract
    // (this can include addresses of Arrakis or Gamma smart contracts for instance)
    address[] positionWrappers;
    // Type (Arrakis, Gamma, ...) encoded as a `uint32` for each wrapper in the list above. Mapping between wrapper types and their
    // corresponding `uint32` value can be found in Angle Docs
    uint32[] wrapperTypes;
    // In the incentivization formula, how much of the fees should go to holders of token0
    // in base 10**4
    uint32 propToken0;
    // Proportion for holding token1 (in base 10**4)
    uint32 propToken1;
    // Proportion for providing a useful liquidity (in base 10**4) that generates fees
    uint32 propFees;
    // Timestamp at which the incentivization should start
    uint32 epochStart;
    // Amount of epochs for which incentivization should last
    uint32 numEpoch;
    // Whether out of range liquidity should still be incentivized or not
    // This should be equal to 1 if out of range liquidity should still be incentivized
    // and 0 otherwise
    uint32 isOutOfRangeIncentivized;
    // How much more addresses with a maximum boost can get with respect to addresses
    // which do not have a boost (in base 4). In the case of Curve where addresses get 2.5x more
    // this would be 25000
    uint32 boostedReward;
    // Address of the token which dictates who gets boosted rewards or not. This is optional
    // and if the horiza address is given no boost will be taken into account
    address boostingAddress;
    // Additional data passed when distributing rewards. This parameter may be used in case
    // the reward distribution script needs to look into other parameters beyond the ones above.
    bytes additionalData;
}
interface IMerklDistributionCreator {
    function createDistribution(DistributionParameters memory params) external returns(uint256);
    function rewardTokenMinAmounts(address) external view returns(uint256);
}
interface IFeeHandler {
    function collectFee(address) external;
}

contract GaugeV2_CL is ReentrancyGuard, Ownable {

    using SafeERC20 for IERC20;

    bool public emergency;


    IERC20 public immutable horiza;
    IERC20 public immutable TOKEN;
    IERC20 public oHoriza;

    address public VE;
    address public DISTRIBUTION;
    address public gaugeRewarder;
    address public internal_bribe;
    address public external_bribe;
    address public feeVault;
    address public feeHandler;

    DistributionParameters public gaugeParams;
    IMerklDistributionCreator public merkl;


    event RewardAdded(uint256 reward);
    event ClaimFees(address indexed from, uint256 claimed0, uint256 claimed1);
    event EmergencyActivated(address indexed gauge, uint256 timestamp);
    event EmergencyDeactivated(address indexed gauge, uint256 timestamp);

    modifier onlyDistribution() {
        require(msg.sender == DISTRIBUTION, "Caller is not RewardsDistribution contract");
        _;
    }

    modifier isNotEmergency() {
        require(emergency == false);
        _;
    }

    constructor(address _rewardToken,address _ve,address _token,address _distribution, address _internal_bribe, address _external_bribe, address _feeVault) {

        horiza = IERC20(_rewardToken);     // main reward
        VE = _ve;                               // vested
        TOKEN = IERC20(_token);                 // underlying (LP)
        DISTRIBUTION = _distribution;           // distro address (voter)
        internal_bribe = _internal_bribe;       // lp fees goes here
        external_bribe = _external_bribe;       // bribe fees goes here
        feeVault = _feeVault;                   // fee vault concentrated liqudity position
        emergency = false;                      // emergency flag

	    merkl = IMerklDistributionCreator(0x8BB4C975Ff3c250e0ceEA271728547f3802B36Fd); // merkl address
        gaugeParams.uniV3Pool = _token;              // address of the pool
        gaugeParams.rewardToken = _rewardToken;      // reward token to distribute with Merkl
        gaugeParams.propToken0 = 3000;               // Proportion of the rewards going for token 0 LPs
        gaugeParams.propToken1 = 3000;               // Proportion of the rewards going for token 1 LPs
        gaugeParams.propFees = 4000;                 // Proportion of the rewards going for LPs that would have earned fees
        gaugeParams.numEpoch = 168;                  // Streaming rewards for a week = DURATION / 3600
        gaugeParams.boostedReward = 25000;
        gaugeParams.boostingAddress = _ve;

    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    ONLY OWNER
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */

    ///@notice set distribution address (should be GaugeProxyL2)
    function setDistribution(address _distribution) external onlyOwner {
        require(_distribution != address(0), "horiza addr");
        require(_distribution != DISTRIBUTION, "same addr");
        DISTRIBUTION = _distribution;
    }

    ///@notice set gauge rewarder address
    function setGaugeRewarder(address _gaugeRewarder) external onlyOwner {
        require(_gaugeRewarder != gaugeRewarder, "same addr");
        gaugeRewarder = _gaugeRewarder;
    }

    ///@notice set feeVault address
    function setFeeVault(address _feeVault) external onlyOwner {
        require(_feeVault != address(0), "horiza addr");
        require(_feeVault != feeVault, "same addr");
        feeVault = _feeVault;
    }

    ///@notice set new internal bribe contract (where to send fees)
    function setInternalBribe(address _int) external onlyOwner {
        require(_int >= address(0), "horiza");
        internal_bribe = _int;
    }

    function activateEmergencyMode() external onlyOwner {
        require(emergency == false, "emergency");
        emergency = true;
        emit EmergencyActivated(address(this), block.timestamp);
    }

    function stopEmergencyMode() external onlyOwner {
        require(emergency == true,"emergency");
        emergency = false;
        emit EmergencyDeactivated(address(this), block.timestamp);
    }

    function setMerklParams(DistributionParameters memory params) external onlyOwner {
        require(params.rewardToken == address(oHoriza) && params.uniV3Pool == address(TOKEN), "invalid params");
        gaugeParams = params;
    }

    function setMerkl(address _merkl) external onlyOwner {
        merkl = IMerklDistributionCreator(_merkl); // merkl address
    }

    function setoHoriza(address _oHoriza) external onlyOwner {
        oHoriza = IERC20(_oHoriza);
        horiza.approve(_oHoriza, type(uint256).max);
        gaugeParams.rewardToken = _oHoriza;
    }

    function setFeeHandler(address _feeHandler) external onlyOwner {
        feeHandler = _feeHandler;
    }

    /* -----------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
                                    DISTRIBUTION
    --------------------------------------------------------------------------------
    --------------------------------------------------------------------------------
    ----------------------------------------------------------------------------- */


    /// @dev Receive rewards from distribution

    function notifyRewardAmount(address token, uint256 reward) external nonReentrant isNotEmergency onlyDistribution {
        require(token == address(horiza));
        horiza.safeTransferFrom(DISTRIBUTION, address(this), reward);
        DistributionParameters memory params = gaugeParams;
        params.amount = horiza.balanceOf(address(this));
        params.epochStart = uint32(block.timestamp);

        //get oHoriza from HORIZA
        IOptionToken(address(oHoriza)).mint(address(this), params.amount);
        uint256 _minAmount = merkl.rewardTokenMinAmounts(params.rewardToken);

        if(params.amount / params.numEpoch > _minAmount) {
            oHoriza.approve(address(merkl), params.amount);
            merkl.createDistribution(params);
        }

        emit RewardAdded(reward);
    }


    function claimFees() external nonReentrant returns (uint256 claimed0, uint256 claimed1) {
        return _claimFees();
    }

     function _claimFees() internal returns (uint256 claimed0, uint256 claimed1) {

        address _token = address(TOKEN);
        IFeeHandler(feeHandler).collectFee(_token);
        (claimed0, claimed1) = IFeeVault(feeVault).claimFees();

        if (claimed0 > 0 || claimed1 > 0) {

            uint256 _fees0 = claimed0;
            uint256 _fees1 = claimed1;

            (address _token0) = IPairInfo(_token).token0();
            (address _token1) = IPairInfo(_token).token1();
            if (_fees0  > 0) {
                IERC20(_token0).approve(internal_bribe, 0);
                IERC20(_token0).approve(internal_bribe, _fees0);
                IBribe(internal_bribe).notifyRewardAmount(_token0, _fees0);
            } 

            if (_fees1  > 0) {
                IERC20(_token1).approve(internal_bribe, 0);
                IERC20(_token1).approve(internal_bribe, _fees1);
                IBribe(internal_bribe).notifyRewardAmount(_token1, _fees1);
            } 
            emit ClaimFees(msg.sender, claimed0, claimed1);
        }
    }

}

