// SPDX-License-Identifier: Unlicense
pragma solidity 0.6.12;

import "./Address.sol";
import "./SafeMath.sol";
import "./SafeERC20.sol";
import "./IERC20.sol";

import "./Governable.sol";

import "./IController.sol";
import "./IStrategy.sol";
import "./IVault.sol";

import "./RewardForwarder.sol";


contract Controller is Governable {
    using SafeERC20 for IERC20;
    using Address for address;
    using SafeMath for uint256;

    // ========================= Fields =========================

    // external parties
    address public targetToken;
    address public profitSharingReceiver;
    address public rewardForwarder;
    address public universalLiquidator;
    address public dolomiteYieldFarmingRouter;

    uint256 public nextImplementationDelay;

    /// 15% of fees captured go to iFARM stakers
    uint256 public profitSharingNumerator = 700;
    uint256 public nextProfitSharingNumerator = 0;
    uint256 public nextProfitSharingNumeratorTimestamp = 0;

    /// 5% of fees captured go to strategists
    uint256 public strategistFeeNumerator = 0;
    uint256 public nextStrategistFeeNumerator = 0;
    uint256 public nextStrategistFeeNumeratorTimestamp = 0;

    /// 5% of fees captured go to the devs of the platform
    uint256 public platformFeeNumerator = 300;
    uint256 public nextPlatformFeeNumerator = 0;
    uint256 public nextPlatformFeeNumeratorTimestamp = 0;

    /// used for queuing a new delay
    uint256 public tempNextImplementationDelay = 0;
    uint256 public tempNextImplementationDelayTimestamp = 0;

    uint256 public constant MAX_TOTAL_FEE = 3000;
    uint256 public constant FEE_DENOMINATOR = 10000;

    /// @notice This mapping allows certain contracts to stake on a user's behalf
    mapping (address => bool) public addressWhitelist;
    mapping (bytes32 => bool) public codeWhitelist;

    // All eligible hardWorkers that we have
    mapping (address => bool) public hardWorkers;

    // ========================= Events =========================

    event QueueProfitSharingChange(uint profitSharingNumerator, uint validAtTimestamp);
    event ConfirmProfitSharingChange(uint profitSharingNumerator);

    event QueueStrategistFeeChange(uint strategistFeeNumerator, uint validAtTimestamp);
    event ConfirmStrategistFeeChange(uint strategistFeeNumerator);

    event QueuePlatformFeeChange(uint platformFeeNumerator, uint validAtTimestamp);
    event ConfirmPlatformFeeChange(uint platformFeeNumerator);

    event QueueNextImplementationDelay(uint implementationDelay, uint validAtTimestamp);
    event ConfirmNextImplementationDelay(uint implementationDelay);

    event AddedAddressToWhitelist(address indexed _address);
    event RemovedAddressFromWhitelist(address indexed _address);

    event AddedCodeToWhitelist(address indexed _address);
    event RemovedCodeFromWhitelist(address indexed _address);

    event SharePriceChangeLog(
        address indexed vault,
        address indexed strategy,
        uint256 oldSharePrice,
        uint256 newSharePrice,
        uint256 timestamp
    );

    // ========================= Modifiers =========================

    modifier onlyHardWorkerOrGovernance() {
        require(hardWorkers[msg.sender] || (msg.sender == governance()),
            "only hard worker can call this");
        _;
    }

    constructor(
        address _storage,
        address _targetToken,
        address _profitSharingReceiver,
        address _rewardForwarder,
        address _universalLiquidator,
        uint _nextImplementationDelay
    )
    Governable(_storage)
    public {
        require(_targetToken != address(0), "_targetToken should not be empty");
        require(_profitSharingReceiver != address(0), "_profitSharingReceiver should not be empty");
        require(_rewardForwarder != address(0), "_rewardForwarder should not be empty");
        require(_nextImplementationDelay > 0, "_nextImplementationDelay should be gt 0");

        targetToken = _targetToken;
        profitSharingReceiver = _profitSharingReceiver;
        rewardForwarder = _rewardForwarder;
        universalLiquidator = _universalLiquidator;
        nextImplementationDelay = _nextImplementationDelay;
    }

        // [Grey list]
    // An EOA can safely interact with the system no matter what.
    // If you're using Metamask, you're using an EOA.
    // Only smart contracts may be affected by this grey list.
    //
    // This contract will not be able to ban any EOA from the system
    // even if an EOA is being added to the greyList, he/she will still be able
    // to interact with the whole system as if nothing happened.
    // Only smart contracts will be affected by being added to the greyList.
    function greyList(address _addr) public view returns (bool) {
        return !addressWhitelist[_addr] && !codeWhitelist[getContractHash(_addr)];
    }

    // Only smart contracts will be affected by the whitelist.
    function addToWhitelist(address _target) public onlyGovernance {
        addressWhitelist[_target] = true;
        emit AddedAddressToWhitelist(_target);
    }

    function addMultipleToWhitelist(address[] memory _targets) public onlyGovernance {
        for (uint256 i = 0; i < _targets.length; i++) {
        addressWhitelist[_targets[i]] = true;
        }
    }

    function removeFromWhitelist(address _target) public onlyGovernance {
        addressWhitelist[_target] = false;
        emit RemovedAddressFromWhitelist(_target);
    }

    function removeMultipleFromWhitelist(address[] memory _targets) public onlyGovernance {
        for (uint256 i = 0; i < _targets.length; i++) {
        addressWhitelist[_targets[i]] = false;
        }
    }

    function getContractHash(address a) public view returns (bytes32 hash) {
        assembly {
        hash := extcodehash(a)
        }
    }

    function addCodeToWhitelist(address _target) public onlyGovernance {
        codeWhitelist[getContractHash(_target)] = true;
        emit AddedCodeToWhitelist(_target);
    }

    function removeCodeFromWhitelist(address _target) public onlyGovernance {
        codeWhitelist[getContractHash(_target)] = false;
        emit RemovedCodeFromWhitelist(_target);
    }

    function setRewardForwarder(address _rewardForwarder) public onlyGovernance {
        require(_rewardForwarder != address(0), "new reward forwarder should not be empty");
        rewardForwarder = _rewardForwarder;
    }

    function setTargetToken(address _targetToken) public onlyGovernance {
        require(_targetToken != address(0), "new target token should not be empty");
        targetToken = _targetToken;
    }

    function setProfitSharingReceiver(address _profitSharingReceiver) public onlyGovernance {
        require(_profitSharingReceiver != address(0), "new profit sharing receiver should not be empty");
        profitSharingReceiver = _profitSharingReceiver;
    }

    function setUniversalLiquidator(address _universalLiquidator) public onlyGovernance {
        require(_universalLiquidator != address(0), "new universal liquidator should not be empty");
        universalLiquidator = _universalLiquidator;
    }

    function setDolomiteYieldFarmingRouter(address _dolomiteYieldFarmingRouter) public onlyGovernance {
        require(_dolomiteYieldFarmingRouter != address(0), "new reward forwarder should not be empty");
        dolomiteYieldFarmingRouter = _dolomiteYieldFarmingRouter;
    }

    function getPricePerFullShare(address _vault) public view returns (uint256) {
        return IVault(_vault).getPricePerFullShare();
    }

    function doHardWork(address _vault) external onlyHardWorkerOrGovernance {
        uint256 oldSharePrice = IVault(_vault).getPricePerFullShare();
        IVault(_vault).doHardWork();
        emit SharePriceChangeLog(
            _vault,
            IVault(_vault).strategy(),
            oldSharePrice,
            IVault(_vault).getPricePerFullShare(),
            block.timestamp
        );
    }

    function addHardWorker(address _worker) public onlyGovernance {
        require(_worker != address(0), "_worker must be defined");
        hardWorkers[_worker] = true;
    }

    function removeHardWorker(address _worker) public onlyGovernance {
        require(_worker != address(0), "_worker must be defined");
        hardWorkers[_worker] = false;
    }

    function withdrawAll(address _vault) external {
        IVault(_vault).withdrawAll();
    }

    // transfers token in the controller contract to the governance
    function salvage(address _token, uint256 _amount) external onlyGovernance {
        IERC20(_token).safeTransfer(governance(), _amount);
    }

    function salvageStrategy(address _strategy, address _token, uint256 _amount) external onlyGovernance {
        // the strategy is responsible for maintaining the list of
        // salvageable tokens, to make sure that governance cannot come
        // in and take away the coins
        IStrategy(_strategy).salvageToken(governance(), _token, _amount);
    }

    function feeDenominator() public pure returns (uint) {
        // keep the interface for this function as a `view` for now, in case it changes in the future
        return FEE_DENOMINATOR;
    }

    function setProfitSharingNumerator(uint _profitSharingNumerator) public onlyGovernance {
        require(
            _profitSharingNumerator + strategistFeeNumerator + platformFeeNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        nextProfitSharingNumerator = _profitSharingNumerator;
        nextProfitSharingNumeratorTimestamp = block.timestamp + nextImplementationDelay;
        emit QueueProfitSharingChange(nextProfitSharingNumerator, nextProfitSharingNumeratorTimestamp);
    }

    function confirmSetProfitSharingNumerator() public onlyGovernance {
        require(
            nextProfitSharingNumerator != 0
            && nextProfitSharingNumeratorTimestamp != 0
            && block.timestamp >= nextProfitSharingNumeratorTimestamp,
            "invalid timestamp or no new profit sharing numerator confirmed"
        );
        require(
            nextProfitSharingNumerator + strategistFeeNumerator + platformFeeNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        profitSharingNumerator = nextProfitSharingNumerator;
        nextProfitSharingNumerator = 0;
        nextProfitSharingNumeratorTimestamp = 0;
        emit ConfirmProfitSharingChange(profitSharingNumerator);
    }

    function setStrategistFeeNumerator(uint _strategistFeeNumerator) public onlyGovernance {
        require(
            _strategistFeeNumerator + platformFeeNumerator + profitSharingNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        nextStrategistFeeNumerator = _strategistFeeNumerator;
        nextStrategistFeeNumeratorTimestamp = block.timestamp + nextImplementationDelay;
        emit QueueStrategistFeeChange(nextStrategistFeeNumerator, nextStrategistFeeNumeratorTimestamp);
    }

    function confirmSetStrategistFeeNumerator() public onlyGovernance {
        require(
            nextStrategistFeeNumerator != 0
            && nextStrategistFeeNumeratorTimestamp != 0
            && block.timestamp >= nextStrategistFeeNumeratorTimestamp,
            "invalid timestamp or no new strategist fee numerator confirmed"
        );
        require(
            nextStrategistFeeNumerator + platformFeeNumerator + profitSharingNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        strategistFeeNumerator = nextStrategistFeeNumerator;
        nextStrategistFeeNumerator = 0;
        nextStrategistFeeNumeratorTimestamp = 0;
        emit ConfirmStrategistFeeChange(strategistFeeNumerator);
    }

    function setPlatformFeeNumerator(uint _platformFeeNumerator) public onlyGovernance {
        require(
            _platformFeeNumerator + strategistFeeNumerator + profitSharingNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        nextPlatformFeeNumerator = _platformFeeNumerator;
        nextPlatformFeeNumeratorTimestamp = block.timestamp + nextImplementationDelay;
        emit QueuePlatformFeeChange(nextPlatformFeeNumerator, nextPlatformFeeNumeratorTimestamp);
    }

    function confirmSetPlatformFeeNumerator() public onlyGovernance {
        require(
            nextPlatformFeeNumerator != 0
            && nextPlatformFeeNumeratorTimestamp != 0
            && block.timestamp >= nextPlatformFeeNumeratorTimestamp,
            "invalid timestamp or no new platform fee numerator confirmed"
        );
        require(
            nextPlatformFeeNumerator + strategistFeeNumerator + profitSharingNumerator <= MAX_TOTAL_FEE,
            "total fee too high"
        );

        platformFeeNumerator = nextPlatformFeeNumerator;
        nextPlatformFeeNumerator = 0;
        nextPlatformFeeNumeratorTimestamp = 0;
        emit ConfirmPlatformFeeChange(platformFeeNumerator);
    }

    function setNextImplementationDelay(uint256 _nextImplementationDelay) public onlyGovernance {
        require(
            _nextImplementationDelay > 0,
            "invalid _nextImplementationDelay"
        );

        tempNextImplementationDelay = _nextImplementationDelay;
        tempNextImplementationDelayTimestamp = block.timestamp + nextImplementationDelay;
        emit QueueNextImplementationDelay(tempNextImplementationDelay, tempNextImplementationDelayTimestamp);
    }

    function confirmNextImplementationDelay() public onlyGovernance {
        require(
            tempNextImplementationDelayTimestamp != 0 && block.timestamp >= tempNextImplementationDelayTimestamp,
            "invalid timestamp or no new implementation delay confirmed"
        );
        nextImplementationDelay = tempNextImplementationDelay;
        tempNextImplementationDelay = 0;
        tempNextImplementationDelayTimestamp = 0;
        emit ConfirmNextImplementationDelay(nextImplementationDelay);
    }
}

