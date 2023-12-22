// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;
pragma abicoder v2;

import { IERC20, ERC20 } from "./ERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { Initializable } from "./Initializable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { PausableUpgradeable } from "./PausableUpgradeable.sol";
import "./IERC20Metadata.sol";

import "./ILaunchpadVesting.sol";

contract Launchpad is
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable,
    PausableUpgradeable
{
    using SafeERC20 for IERC20;

    struct UserInfo {
        uint256 priorityQuota; // user's priority access quota for project token without any mulitplier
        uint256 lowFDVPurchased; // project token priority purchae
        uint256 highFDVPurchased; // project token public purchase
        uint256 lowFDVClaimed; // project token priority claimed
        uint256 highFDVClaimed; // project token public claimed
    }

    struct PhaseInfo {
        uint32 endTime;
        uint256 saleCap; // accumulated project token sale cap at current phase
        uint256 allocatedAmount; // project token allocated
        uint256 tokenPerSaleToken; // project token per sale token in DENOMINATOR
        uint256 priorityMultiplier; // > 0 for priority sale, = 0 for public sale in DENOMINATOR
        bool isLofFDV;
    }

    uint256 public constant DENOMINATOR = 1e18;
    uint256 public LOW_FDV_VESTING_PART; // Some % part of claimed amount during priority phase will be vested
    uint256 public HIGH_FDV_VESTING_PART; // Some % part of claimed amount during public phase will be vested

    address public projectToken; // Project token contract
    address public saleToken; // token used to purchase IDO
    ILaunchpadVesting public vestingContract;

    uint32 public startTime; // sale start time
    uint256 public max_launch_tokens_to_distribute; // max PROJECT_TOKEN amount to distribute during the sale
    uint256 public min_sale_token_amount; // max PROJECT_TOKEN amount to distribute during the sale

    mapping(address => UserInfo) public userInfo; // users claim & priority cap data
    mapping(bytes32 => uint256) public userPurchased; // Mapping user + phase => purchased. The index is hashed based on the user address and phase number
    PhaseInfo[] public phaseInfos;

    uint256 public maxRaiseAmount; // max amount of Sale Token to raise
    uint256 public totalRaised; // total amount of Sale Token raised
    uint256 public totalAllocated; // total amount of Project Tokens allocated

    address public treasury; // Address of treasury multisig, it will receive raised amount

    bool public canClaimTokens;
    bool public unsoldTokensWithdrew;

    /* ============ Constructor ============ */
    constructor() {
        _disableInitializers();
    }

    /****************** EVENTS ******************/
    event AllocationPurchased(address indexed purchaser, uint256 amount, uint256 phaseNumber);
    event Claim(address indexed user, uint256 priorityPhaseClaimable, uint256 publicPhaseClaimable);
    event PriorityAccessUpdated();
    event TransferredToTreasury(address token, uint256 amount);
    event EmergencyWithdraw(address token, uint256 amount);
    event ClaimingPhaseStarted();
    event UnsoldTokensWithdrawn(address indexed withdrawer, uint256 amount);
    event PhaseUpdated(
        uint256 indexed phaseIndex,
        uint32 endTime,
        uint256 saleCap,
        uint256 tokenPerSaleToken,
        uint256 priorityMultiplier,
        bool isLofFDV
    );

    event PhaseAdded(
        uint256 indexed phaseIndex,
        uint32 endTime,
        uint256 saleCap,
        uint256 tokenPerSaleToken,
        uint256 priorityMultiplier,
        bool isLofFDV
    );

    /****************** ERRORS ******************/

    error InvalidPhase();
    error InvalidTime();
    error AlreadyStarted();
    error PhaseAlreadyEnded();
    error InvalidPerSaleAmount();
    error NoAvailablePhase();
    error InvalidAmount();
    error InvalidSaleCap();
    error InvalidFDVPart();
    error InvalidLength();
    error ZeroAddress();
    error SaleNotStarted();
    error SaleNotCompleted();
    error SaleCompleted();
    error NotEnoughToken();
    error RaisedMaxAmount();
    error AlreadyWithdrawn();
    error ClaimingPhaseNotStartedYet();
    error ClaimingPhaseAlreadyStarted();
    error ExceedsUserPriorityCap();
    error TokenDecimalExceedsLimit();
    error StartTimeNotInitialized();
    error ZeroAllocation();

    /* ============ Initializer ============ */

    function __Launchpad_init() public initializer {
        __Ownable_init();
        __ReentrancyGuard_init();
        __Pausable_init();
    }

    /****************** MODIFIERS ******************/

    /// @dev Check whether the sale is currently active
    /// Will be marked as inactive if PROJECT_TOKEN has not been deposited into the contract
    modifier isSaleActive() {
        if (!hasStarted()) revert SaleNotStarted();
        if (hasEnded()) revert SaleCompleted();
        _;
    }

    /// @dev Check whether users can claim their purchased PROJECT_TOKEN or not
    modifier isClaimable() {
        if (!hasEnded()) revert SaleNotCompleted();
        if (!canClaimTokens) revert ClaimingPhaseNotStartedYet();
        _;
    }

    /****************** PUBLIC VIEWS ******************/

    /// @dev Returns whether the sale has already started
    function hasStarted() public view returns (bool) {
        return _currentBlockTimestamp() >= startTime;
    }

    /// @dev Returns whether the sale has already ended
    function hasEnded() public view returns (bool) {
        uint256 length = phaseInfos.length;
        if (length == 0) return true;

        return phaseInfos[length - 1].endTime <= _currentBlockTimestamp();
    }

    function getUserPurchased(address _user, uint256 _phaseNumber) public view returns (uint256) {
        bytes32 identifier = _getUserPurchasedIdentifier(_user, _phaseNumber);
        return userPurchased[identifier];
    }

    function getUserAllocQuota(
        address _user,
        uint256 _phaseNumber
    ) external view returns (uint256 userLeftQuota) {
        if (_phaseNumber < 1 || _phaseNumber > phaseInfos.length) {
            return 0;
        }
        PhaseInfo memory phaseInfo = phaseInfos[_phaseNumber - 1];
        if (phaseInfo.saleCap <= totalAllocated)
            return 0;

        uint256 currentPhaseRemainTokens = phaseInfo.saleCap - totalAllocated;
        if (phaseInfo.priorityMultiplier == 0) {
            userLeftQuota = currentPhaseRemainTokens;
        } else {
            UserInfo memory userData = userInfo[_user];
            uint256 currentUserRemainTokens = ((userData.priorityQuota * phaseInfo.priorityMultiplier)/ DENOMINATOR ) 
                - getUserPurchased(_user, _phaseNumber);

            userLeftQuota = (currentPhaseRemainTokens < currentUserRemainTokens)
                ? currentPhaseRemainTokens
                : currentUserRemainTokens;
        }
    }

    /// @dev Returns current running Phase number.
    function getCurrentPhaseInfo()
        public
        view
        returns (uint256 phaseNumber, PhaseInfo memory phaseInfo)
    {
        uint256 currentBlockTimestamp = _currentBlockTimestamp();
        uint256 length = phaseInfos.length;

        if(length == 0){
            revert NoAvailablePhase();
        }

        if (currentBlockTimestamp < startTime) {
            return (0, phaseInfo);
        } // not started

        for (uint256 i = 0; i < length; i++) {
            phaseInfo = phaseInfos[i];
            if (currentBlockTimestamp < phaseInfo.endTime) return (i + 1, phaseInfo);
        }

        revert PhaseAlreadyEnded();
    }

    /// @dev Get user token amount to claim
    function getExpectedClaimAmount(
        address account
    ) public view returns (uint256 lowFDVPurchased, uint256 highFDVPurchased) {
        if (totalAllocated == 0) return (0, 0);

        UserInfo memory user = userInfo[account];

        lowFDVPurchased = user.lowFDVPurchased - user.lowFDVClaimed;
        highFDVPurchased = user.highFDVPurchased - user.highFDVClaimed;
    }

    /****************** EXTERNAL FUNCTIONS  ******************/

    /// @dev Purchase an PROJECT_TOKEN allocation for the sale for a value of "amount" saleToken
    function buy(uint256 amount) external whenNotPaused isSaleActive nonReentrant {
        if(amount < min_sale_token_amount){
            revert InvalidAmount();
        }
        (uint256 phaseNumber, PhaseInfo memory phaseInfo) = getCurrentPhaseInfo();

        _checkValidCapAndUpdate(amount, phaseNumber);
        _checkValidAndBuy(msg.sender, amount, phaseNumber, phaseInfo);

        IERC20(saleToken).safeTransferFrom(msg.sender, address(this), amount);

        emit AllocationPurchased(msg.sender, amount, phaseNumber);
    }

    /// @dev Claim purchased PROJECT_TOKEN during the sale
    function claim() external whenNotPaused isClaimable nonReentrant {
        (uint256 lowFDVPurchased, uint256 highFDVPurchased) = getExpectedClaimAmount(msg.sender);

        if (lowFDVPurchased == 0 && highFDVPurchased == 0) revert InvalidAmount();

        UserInfo storage user = userInfo[msg.sender];
        if (lowFDVPurchased != 0) {
            user.lowFDVClaimed += lowFDVPurchased;
            _processClaims(true, lowFDVPurchased, msg.sender);
        }

        if (highFDVPurchased != 0) {
            user.highFDVClaimed += highFDVPurchased;
            _processClaims(false, highFDVPurchased, msg.sender);
        }

        emit Claim(msg.sender, lowFDVPurchased, highFDVPurchased);
    }

    /********************** ADMIN FUNCTIONS  **********************/

    /// @dev Assign priority access status and cap for users
    function setUsersPriorityAccess(
        address[] calldata users,
        uint256[] calldata userQuota
    ) public onlyOwner {
        if (users.length != userQuota.length) revert InvalidLength();
        for (uint256 i = 0; i < users.length; ++i) {
            UserInfo storage user = userInfo[users[i]];
            user.priorityQuota = userQuota[i];
        }

        emit PriorityAccessUpdated();
    }

    /// @dev Withdraw unsold PROJECT_TOKEN if max_launch_tokens_to_distribute has not been reached
    /// Must only be called by the owner
    function withdrawUnsoldTokens() external onlyOwner {
        if (!hasEnded()) revert SaleNotCompleted();
        if (unsoldTokensWithdrew) revert AlreadyWithdrawn();

        unsoldTokensWithdrew = true;
        uint256 amountOfUnsoldTokens = (max_launch_tokens_to_distribute - totalAllocated);

        IERC20(projectToken).safeTransfer(owner(), amountOfUnsoldTokens);
        emit UnsoldTokensWithdrawn(owner(), amountOfUnsoldTokens);
    }

    /// @dev Start Tokens Claiming Phase
    function startClaimingPhase() external onlyOwner {
        if (!hasEnded()) revert SaleNotCompleted();
        if (canClaimTokens) revert ClaimingPhaseAlreadyStarted();

        canClaimTokens = true;

        vestingContract.setVestingStartTime(_currentBlockTimestamp());
        emit ClaimingPhaseStarted();
    }

    function addPhase(
        uint32 endTime,
        uint256 saleCap,
        uint256 tokenPerSaleToken,
        uint256 priorityMultiplier,
        bool isLowFDV
    ) external onlyOwner {
        if (startTime == 0) revert StartTimeNotInitialized();
        if (startTime <= _currentBlockTimestamp()) revert AlreadyStarted();
        if (endTime <= startTime) revert InvalidTime();
        if (tokenPerSaleToken <= 0) revert InvalidPerSaleAmount();
        if (saleCap > max_launch_tokens_to_distribute) revert InvalidSaleCap();
        if (phaseInfos.length > 0 && endTime <= phaseInfos[phaseInfos.length-1].endTime) revert InvalidTime();
        if (phaseInfos.length > 0 && saleCap < phaseInfos[phaseInfos.length-1].saleCap) revert InvalidSaleCap();
        
        PhaseInfo memory newPhase = PhaseInfo({
            endTime: endTime,
            saleCap: saleCap,
            allocatedAmount: 0,
            tokenPerSaleToken: tokenPerSaleToken,
            priorityMultiplier: priorityMultiplier,
            isLofFDV: isLowFDV
        });

        phaseInfos.push(newPhase);

        uint256 index = phaseInfos.length - 1;
        emit PhaseAdded(index, endTime, saleCap, tokenPerSaleToken, priorityMultiplier, isLowFDV);
    }

    function setPhase(
        uint256 index,
        uint32 endTime,
        uint256 saleCap,
        uint256 tokenPerSaleToken,
        uint256 priorityMultiplier,
        bool isLowFDV
    ) external onlyOwner {
        if (startTime != 0 && startTime <= _currentBlockTimestamp()) revert AlreadyStarted();
        if (index >= phaseInfos.length) revert InvalidPhase();
        if (endTime <= startTime) revert InvalidTime();
        if (endTime <= _currentBlockTimestamp()) revert InvalidTime();
        if (tokenPerSaleToken <= 0) revert InvalidPerSaleAmount();
        if (saleCap > max_launch_tokens_to_distribute) revert InvalidSaleCap();

        PhaseInfo storage phase = phaseInfos[index];

        if (index > 0 && endTime <= phaseInfos[index-1].endTime) revert InvalidTime();
        if (index < phaseInfos.length-1 && endTime >= phaseInfos[index+1].endTime) revert InvalidTime();
        if (index > 0 && saleCap <= phaseInfos[index-1].saleCap) revert InvalidSaleCap();
        if (index < phaseInfos.length-1 && saleCap >= phaseInfos[index+1].saleCap) revert InvalidSaleCap();

        phase.endTime = endTime;
        phase.saleCap = saleCap;
        phase.tokenPerSaleToken = tokenPerSaleToken;
        phase.priorityMultiplier = priorityMultiplier;
        phase.isLofFDV = isLowFDV;

        emit PhaseUpdated(index, endTime, saleCap, tokenPerSaleToken, priorityMultiplier, isLowFDV);
    }

    function configLaunchpad(
        address _projectToken,
        address _saleToken,
        address _vestingContract,
        address _treasury,
        uint32 _startTime,
        uint256 _maxToDistribute,
        uint256 _maxToRaise,
        uint256 _lowFDVVestingPart,
        uint256 _highFDVVestingPart,
        uint256 _minSaleTokenAmount
    ) public onlyOwner {
        if (startTime != 0 && startTime <= _currentBlockTimestamp()) revert AlreadyStarted();
        if (_treasury == address(0)) revert ZeroAddress();
        if (_maxToDistribute == 0) revert InvalidAmount();
        if (_maxToRaise == 0) revert InvalidAmount();
        if (_startTime <= _currentBlockTimestamp()) revert InvalidTime();
        if (_projectToken == address(0)) revert ZeroAddress();
        if (_saleToken == address(0)) revert ZeroAddress();
        if (_vestingContract == address(0)) revert ZeroAddress();
        if (_lowFDVVestingPart >= DENOMINATOR) revert InvalidFDVPart();
        if (_highFDVVestingPart >= DENOMINATOR) revert InvalidFDVPart();

        uint8 projectTokenTokenDecimals = IERC20Metadata(_projectToken).decimals();
        uint8 saleTokenDecimals = IERC20Metadata(_saleToken).decimals();

        if (saleTokenDecimals > projectTokenTokenDecimals) revert TokenDecimalExceedsLimit();

        projectToken = _projectToken;
        saleToken = _saleToken;
        vestingContract = ILaunchpadVesting(_vestingContract);
        startTime = _startTime;
        treasury = _treasury;
        maxRaiseAmount = _maxToRaise;
        LOW_FDV_VESTING_PART = _lowFDVVestingPart;
        HIGH_FDV_VESTING_PART = _highFDVVestingPart;
        min_sale_token_amount = _minSaleTokenAmount;
        max_launch_tokens_to_distribute = _maxToDistribute;
    }

    function setProjectToken(address _projectToken) external onlyOwner() {
        projectToken = _projectToken;
    }

    function transferFundsToTreasury(uint256 amount) external onlyOwner {
        if(IERC20(saleToken).balanceOf(address(this)) < amount) revert InvalidAmount();
        IERC20(saleToken).safeTransfer(treasury, amount);

        emit TransferredToTreasury(saleToken, amount);
    }

    function setVestingPart(uint256 _lowFDVVesting, uint256 _highFDVVesting) external onlyOwner() {
        LOW_FDV_VESTING_PART = _lowFDVVesting;
        HIGH_FDV_VESTING_PART = _highFDVVesting;
    }

    /****************** /!\ EMERGENCY ONLY ******************/

    /// @dev Emergency Withdraw for Failsafe
    function emergencyWithdrawFunds(address token, uint256 amount) external whenPaused onlyOwner {
        IERC20(token).safeTransfer(owner(), amount);

        emit EmergencyWithdraw(token, amount);
    }

    function pause() external onlyOwner {
        _pause();
    }

    function unpause() external onlyOwner {
        _unpause();
    }

    /* ============ Internal Functions ============ */

    function _getUserPurchasedIdentifier(
        address _user,
        uint256 _phaseNumber
    ) internal pure returns (bytes32) {
        return keccak256(abi.encodePacked(_user, _phaseNumber));
    }

    function _checkValidAndBuy(
        address _buyer,
        uint256 _saleTokenAmount,
        uint256 _phaseNumber,
        PhaseInfo memory phaseInfo
    ) internal {
        UserInfo storage user = userInfo[_buyer];
        uint256 _toAllocated = _tokenAllocBySale(_saleTokenAmount, phaseInfo);
        bytes32 identifier = _getUserPurchasedIdentifier(_buyer, _phaseNumber);

        userPurchased[identifier] += _toAllocated;

        // only for priority access pass check
        if (phaseInfo.priorityMultiplier > 0) {
            uint256 _userCap = (user.priorityQuota * phaseInfo.priorityMultiplier) / DENOMINATOR;

            if (userPurchased[identifier] > _userCap) revert ExceedsUserPriorityCap();
        }

        if (phaseInfo.isLofFDV) user.lowFDVPurchased += _toAllocated;
        else user.highFDVPurchased += _toAllocated;
    }

    function _checkValidCapAndUpdate(uint256 _saleTokenAmount, uint256 _phaseNumber) internal {
        PhaseInfo storage phaseInfo = phaseInfos[_phaseNumber - 1];

        totalRaised += _saleTokenAmount;

        if (totalRaised > maxRaiseAmount) revert RaisedMaxAmount();

        uint256 amountOfTokensToBeAllocated = _tokenAllocBySale(_saleTokenAmount, phaseInfo);
        if (amountOfTokensToBeAllocated == 0) revert ZeroAllocation();

        totalAllocated += amountOfTokensToBeAllocated;
        phaseInfo.allocatedAmount += amountOfTokensToBeAllocated;

        if (
            totalAllocated > max_launch_tokens_to_distribute ||
            totalAllocated > phaseInfo.saleCap
        ) revert NotEnoughToken();
    }

    function _tokenAllocBySale(
        uint256 _saleTokenAmount,
        PhaseInfo memory phaseInfo
    ) internal view returns (uint256) {
        uint256 numerator = _saleTokenAmount *
            phaseInfo.tokenPerSaleToken *
            10 ** IERC20Metadata(projectToken).decimals();
        uint256 denominator = DENOMINATOR * 10 ** IERC20Metadata(saleToken).decimals();

        return numerator / denominator;
    }

    /// @dev Process user's claims for low/high FDV sale
    function _processClaims(bool isLowFDV, uint256 claimAmountForPhase, address to) internal {
        uint256 vestingAmount;
        if (isLowFDV) {
            vestingAmount = (claimAmountForPhase * LOW_FDV_VESTING_PART) / DENOMINATOR;
        } else {
            vestingAmount = (claimAmountForPhase * HIGH_FDV_VESTING_PART) / DENOMINATOR;
        }

        if (claimAmountForPhase - vestingAmount > 0)
            IERC20(projectToken).safeTransfer(to, claimAmountForPhase - vestingAmount);

        if (vestingAmount != 0) {
            IERC20(projectToken).safeIncreaseAllowance(address(vestingContract), vestingAmount);
            vestingContract.vestTokens(isLowFDV, vestingAmount, to);
        }
    }

    /// @dev Utility function to get the current block timestamp
    function _currentBlockTimestamp() internal view returns (uint256) {
        return block.timestamp;
    }
}

