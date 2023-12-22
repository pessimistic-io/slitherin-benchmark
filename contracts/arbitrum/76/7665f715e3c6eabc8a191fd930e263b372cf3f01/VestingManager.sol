pragma solidity ^0.8.0;
//SPDX-License-Identifier: Apache-2.0
//Modified from: https://github.com/abdelhamidbakhta/token-vesting-contracts/blob/main/contracts/VestingManager.sol
import "./Ownable.sol";
import "./IERC20.sol";
import "./SafeERC20.sol";
import "./ReentrancyGuard.sol";

contract VestingManager is Ownable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    struct VestingSchedule{
        bool initialized;
        address owner;
        address recipient;
        address erc20Token;
        uint256 startTime;
        uint256 totalVestingDuration;
        uint256 unlockInterval;
        uint256 totalAmount;
        uint256 amountReleased;
        bool revocable;
        bool revoked;
    }

    bytes32[] private vestingSchedulesIds;
    mapping(bytes32 => VestingSchedule) private vestingSchedules;
    mapping (address => bytes32) private addressToVestingSchedules;

    mapping(address => bool) private isWalletApproved;
    mapping(address => uint256) private vestingSchedulesLockedAmounts;

    mapping(address => bytes32[]) private creatorVestingIds;
    mapping(address => bytes32[]) private recipientVestingIds;
    mapping(address => bytes32[]) private tokenVestingIds;

    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(vestingSchedules[vestingScheduleId].initialized == true);
        require(vestingSchedules[vestingScheduleId].revoked == false);
        _;
    }

    function getVestingIdsForCreator(address _creator) external view returns(bytes32[] memory){
        return creatorVestingIds[_creator];
    }

    function getVestingIdsForRecipient(address _recipient) external view returns(bytes32[] memory){
        return recipientVestingIds[_recipient];
    }

    function getVestingIdsByToken(address _token) external view returns(bytes32[] memory){
        return tokenVestingIds[_token];
    }

    function getVestingSchedulesCount() external view returns(uint256){
        return vestingSchedulesIds.length;
    }    

    function getVestingIdAtIndex(uint256 _index) external view returns(bytes32){
        require(_index < vestingSchedulesIds.length, "VestingManager: index out of bounds");
        return vestingSchedulesIds[_index];
    }

    function getVestingSchedule(bytes32 _vestingScheduleId) external view returns(VestingSchedule memory){
        return vestingSchedules[_vestingScheduleId];
    }

    function getLockedTokenAmount(address _token) external view returns(uint256) {
        return vestingSchedulesLockedAmounts[_token];
    }

    function setWalletApproval(address _address, bool _isApproved) external onlyOwner {
        isWalletApproved[_address] = _isApproved;
    }

    /**
    * @notice Creates a vesting schedule.
    * @param _recipient The address to receive tokens when released.
    * @param _token The ERC20 token.
    * @param _startTime Start time of the vest in UNIX timestamp.
    * @param _totalVestingDuration Total length of the vest in seconds.
    * @param _unlockInterval The ERC20 token.
    * @param _amountTotal Total amount of tokens to be released.
    * @param _revocable Can this vesting schedule be revoked by the owner?
    */
    function createVestingSchedule(
        address _recipient,
        address _token,
        uint256 _startTime,
        uint256 _totalVestingDuration,
        uint256 _unlockInterval,
        uint256 _amountTotal,
        bool _revocable
    ) public {
        require(_totalVestingDuration > 0, "VestingManager: totalVestingDuration must be > 0");
        require(_amountTotal > 0, "VestingManager: amount must be > 0");
        require(_unlockInterval >= 1, "VestingManager: unlockInterval must be >= 1");
        require(isWalletApproved[tx.origin], "VestingManager: wallet is not approved");

        bytes32 vestingScheduleId = computeNextVestingScheduleIdForHolder(_recipient);
        vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            tx.origin,
            _recipient,
            _token,
            _startTime,
            _totalVestingDuration,
            _unlockInterval,
            _amountTotal,
            0,
            _revocable,
            false
        );

        vestingSchedulesLockedAmounts[_token] = vestingSchedulesLockedAmounts[_token] + _amountTotal;
        vestingSchedulesIds.push(vestingScheduleId);

        creatorVestingIds[tx.origin].push(vestingScheduleId);
        recipientVestingIds[_recipient].push(vestingScheduleId);
        tokenVestingIds[_token].push(vestingScheduleId);

        deposit(_amountTotal, _token);
        emit VestingScheduleCreated(tx.origin, _recipient, _token, _startTime, _totalVestingDuration, _unlockInterval, _amountTotal, _revocable, vestingScheduleId);
    }

    function revoke(bytes32 vestingScheduleId) public onlyIfVestingScheduleNotRevoked (vestingScheduleId){
        VestingSchedule storage vestingSchedule = vestingSchedules[vestingScheduleId];
        require(tx.origin == vestingSchedule.owner, "VestingManager: you did not create this vest" );
        require(vestingSchedule.revocable == true, "VestingManager: vesting is not revocable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if(vestedAmount > 0) {
            release(vestingScheduleId, vestedAmount);
        }

        uint256 unreleased = vestingSchedule.totalAmount - vestingSchedule.amountReleased;
        vestingSchedulesLockedAmounts[vestingSchedule.erc20Token] = vestingSchedulesLockedAmounts[vestingSchedule.erc20Token] - unreleased;

        IERC20(vestingSchedule.erc20Token).safeTransfer(vestingSchedule.owner, unreleased);

        vestingSchedule.revoked = true;
        emit Revoked(vestingScheduleId);
    }

    /**
    * @notice Release vested amount of tokens.
    * @param _vestingScheduleId the vesting schedule identifier
    * @param _amount the amount to release
    */
    function release(
        bytes32 _vestingScheduleId,
        uint256 _amount
    ) public nonReentrant onlyIfVestingScheduleNotRevoked(_vestingScheduleId){
        VestingSchedule storage vestingSchedule = vestingSchedules[_vestingScheduleId];
        bool isRecipient = msg.sender == vestingSchedule.recipient;
        bool isOwner = msg.sender == vestingSchedule.owner;
        require(
            isRecipient || isOwner,
            "VestingManager: only recipient and owner can release vested tokens"
        );

        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        require(vestedAmount >= _amount, "VestingManager: cannot release tokens, not enough vested tokens");

        vestingSchedule.amountReleased = vestingSchedule.amountReleased + _amount;
        vestingSchedulesLockedAmounts[vestingSchedule.erc20Token] = vestingSchedulesLockedAmounts[vestingSchedule.erc20Token] - _amount;

        IERC20(vestingSchedule.erc20Token).safeTransfer(vestingSchedule.recipient, _amount);

        emit Released(msg.sender, _vestingScheduleId, _amount, vestingSchedule.erc20Token);
    }

    function computeReleasableAmount(bytes32 _vestingScheduleId) public onlyIfVestingScheduleNotRevoked (_vestingScheduleId) view
    returns(uint256) {
        VestingSchedule storage vestingSchedule = vestingSchedules[_vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    function deposit(uint256 _amountInWEI, address _token) internal {
        IERC20(_token).transferFrom(msg.sender, address(this), _amountInWEI);
        emit ERC20Deposit(msg.sender, _amountInWEI, _token);
    }

    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns(uint256){
        uint256 currentTime = block.timestamp;
        if ((currentTime < vestingSchedule.startTime) || vestingSchedule.revoked == true) {
            return 0;
        } else if (currentTime >= vestingSchedule.startTime + vestingSchedule.totalVestingDuration) {
            return vestingSchedule.totalAmount - vestingSchedule.amountReleased;
        } else {
            uint256 timeFromStart = currentTime - vestingSchedule.startTime;
            uint unlockInterval = vestingSchedule.unlockInterval;
            uint256 passedIntervals = timeFromStart / unlockInterval;
            uint256 vestedSeconds = passedIntervals * unlockInterval;
            uint256 vestedAmount = vestingSchedule.totalAmount * vestedSeconds / vestingSchedule.totalVestingDuration;
            vestedAmount = vestedAmount - vestingSchedule.amountReleased;
            return vestedAmount;
        }
    }

    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index)
    internal
    pure
    returns(bytes32){
        return keccak256(abi.encodePacked(holder, index));
    }

    function computeNextVestingScheduleIdForHolder(address holder)
    internal
    view
    returns(bytes32){
        return computeVestingScheduleIdForAddressAndIndex(holder, recipientVestingIds[holder].length);
    }

    event ERC20Deposit(address indexed sender, uint256 value, address token);
    event VestingScheduleCreated(
        address owner,
        address recipient,
        address erc20Token,
        uint256 startTime,
        uint256 totalVestingDuration,
        uint256 unlockInterval,
        uint256 amountTotal,
        bool revocable,
        bytes32 vestingScheduleId);
    event Released(address recipient, bytes32 vestingScheduleId, uint256 value, address token);
    event Revoked(bytes32 vestingSchedulesId);
}
