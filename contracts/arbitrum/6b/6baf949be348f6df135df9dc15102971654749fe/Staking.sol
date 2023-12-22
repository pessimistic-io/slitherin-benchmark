// SPDX-License-Identifier: AGPL-3.0
pragma solidity ^0.7.5;

import "./SafeMath.sol";
import "./SafeERC20.sol";

import "./IERC20.sol";
import "./IsPana.sol";
import "./IKarsha.sol";
import "./IDistributor.sol";

import "./PanaAccessControlled.sol";

contract PanaStaking is PanaAccessControlled {
    /* ========== DEPENDENCIES ========== */

    using SafeMath for uint256;
    using SafeERC20 for IERC20;
    using SafeERC20 for IsPana;
    using SafeERC20 for IKarsha;

    /* ========== EVENTS ========== */

    event DistributorSet(address distributor);
    event WarmupSet(uint256 warmup);
    event StakingMigrated(uint256 amount);

    /* ========== DATA STRUCTURES ========== */

    struct Epoch {
        uint256 length; // in seconds
        uint256 number; // since inception
        uint256 end; // timestamp
        uint256 distribute; // amount
    }

    /* ========== STATE VARIABLES ========== */

    IERC20 public immutable PANA;
    IsPana public immutable sPANA;
    IKarsha public immutable KARSHA;

    Epoch public epoch;
    bool private firstEpochSet;

    IDistributor public distributor;

    bool private _allowedExternalStaking;
    mapping(address => bool) public approvedDepositor;

    address public stakingMigrator;

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address _pana,
        address _sPana,
        address _karsha,
        address _authority
    ) PanaAccessControlled(IPanaAuthority(_authority)) {
        require(_pana != address(0), "Zero address: PANA");
        PANA = IERC20(_pana);
        require(_sPana != address(0), "Zero address: sPANA");
        sPANA = IsPana(_sPana);
        require(_karsha != address(0), "Zero address: KARSHA");
        KARSHA = IKarsha(_karsha);

        firstEpochSet = false;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice stake Pana
     * @param _to address
     * @param _amount uint
     * @return uint
     */
    function stake(
        address _to,
        uint256 _amount
    ) external returns (uint256) {
        // check if external staking is not allowed, only bond depositor should be able to stake it.
        if (!_allowedExternalStaking) {
            require(approvedDepositor[msg.sender], "External Staking is not allowed - Only approved depositor allowed");
        }
        
        rebase();
        PANA.safeTransferFrom(msg.sender, address(this), _amount);
        
        return _send(_to, _amount);
    }

    /**
     * @notice redeem Pana/sPana for Karsha/Pana
     * @param _to address
     * @param _amount uint
     * @param _trigger bool
     * @return amount_ uint
     */
    function unstake(
        address _to,
        uint256 _amount,
        bool _trigger
    ) external returns (uint256 amount_) {
        amount_ = _amount;
        uint256 bounty;
        if (_trigger) {
            bounty = rebase();
        }

        KARSHA.burn(msg.sender, _amount); // amount was given in Karsha terms
        amount_ = KARSHA.balanceFrom(amount_).add(bounty); // convert amount to Pana terms & add bounty
    
        require(amount_ <= PANA.balanceOf(address(this)), "Insufficient Pana balance in contract");
        PANA.safeTransfer(_to, amount_);
    }

    /**
     * @notice trigger rebase if epoch over
     * @return uint256
     */
    function rebase() public returns (uint256) {
        require(firstEpochSet == true, "Epoch not Initialized");
        uint256 bounty;
        if (epoch.end <= block.timestamp) {
            sPANA.rebase(epoch.distribute, epoch.number);

            epoch.end = epoch.end.add(epoch.length);
            epoch.number++;

            if (address(distributor) != address(0)) {
                distributor.distribute();
                bounty = distributor.retrieveBounty(); // Will mint Pana for this contract if there exists a bounty
            }
            uint256 balance = PANA.balanceOf(address(this));
            uint256 staked = sPANA.circulatingSupply();
            if (balance <= staked.add(bounty)) {
                epoch.distribute = 0;
            } else {
                epoch.distribute = balance.sub(staked).sub(bounty);
            }
        }
        return bounty;
    }

    // Set Depositor Contract
    function addApprovedDepositor(address _depositor) external onlyGovernor {
        require(_depositor != address(0), "Zero address: _depositor");
        approvedDepositor[_depositor] = true;
    }

    // Remove Depositor Contract
    function removeApprovedDepositor(address _depositor) external onlyGovernor {
        require(_depositor != address(0), "Removal: Invalid Depositor");
        require(approvedDepositor[_depositor], "Already set to false");
        approvedDepositor[_depositor] = false;
    }
    
    // Allow External Staking directly using PANA
    function allowExternalStaking(bool allow) external onlyGovernor {
        _allowedExternalStaking = allow;
    }


    /**
     * @notice allow approved address to withdraw Pana
     */
    function migrate() external {
        require(stakingMigrator == msg.sender, "Not Approved");
        uint256 _amount = PANA.balanceOf(address(this));
        PANA.safeTransfer(msg.sender, _amount);
        emit StakingMigrated(_amount);
    }

    /**
     * @notice set Staking Contract migrator
     * @param _migrator address
     */
    function setStakingMigrator(address _migrator) external onlyGovernor {
        require(_migrator != address(0), "Zero address: Staking Migrator");
        stakingMigrator = _migrator;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    /**
     * @notice send staker their amount as Karsha
     * @param _to address
     * @param _amount uint
     */
    function _send(
        address _to,
        uint256 _amount
    ) internal returns (uint256) {
        KARSHA.mint(_to, KARSHA.balanceTo(_amount)); // send as Karsha (convert units from Pana)
        return KARSHA.balanceTo(_amount);
    }

    /* ========== VIEW FUNCTIONS ========== */

    /**
     * @notice returns the sPana index, which tracks rebase growth
     * @return uint
     */
    function index() public view returns (uint256) {
        return sPANA.index();
    }
    
    /**
     * @notice seconds until the next epoch begins
     */
    function secondsToNextEpoch() external view returns (uint256) {
        return epoch.end.sub(block.timestamp);
    }

    /**
     * @notice staked Karsha in terms of Pana
     */
    function stakingSupply() external view returns (uint256) {
        return KARSHA.balanceFrom(IERC20(address(KARSHA)).totalSupply());
    }

    /* ========== MANAGERIAL FUNCTIONS ========== */

    /**
     * @notice sets the contract address for LP staking
     * @param _distributor address
     */
    function setDistributor(address _distributor) external onlyGovernor {
        distributor = IDistributor(_distributor);
        emit DistributorSet(_distributor);
    }

    /**
     * @notice initialize first rebase parameters
     * @param _epochLength uint
     * @param _firstEpochNumber uint
     * @param _firstEpochTime uint
     */
    function setFirstEpoch(
        uint256 _epochLength,
        uint256 _firstEpochNumber,
        uint256 _firstEpochTime
    ) external onlyGovernor {
        require(firstEpochSet == false, "Cannot Initialize epoch multiple times");
        epoch = Epoch({length: _epochLength, number: _firstEpochNumber, end: _firstEpochTime, distribute: 0});
        firstEpochSet = true;
    }

}

