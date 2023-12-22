// contracts/PNFTToken.sol
// SPDX-License-Identifier: Apache-2.0
pragma solidity 0.7.6;
pragma abicoder v2;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./Math.sol";
import "./SafeMath.sol";
import "./ERC20Upgradeable.sol";
import "./ERC20BurnableUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./PausableUpgradeable.sol";
import "./Initializable.sol";
import "./PNFTTokenStorage.sol";

/**
 * @title PNFTToken
 */
contract PNFTToken is
    Initializable,
    ERC20Upgradeable,
    ERC20BurnableUpgradeable,
    PausableUpgradeable,
    OwnableUpgradeable,
    ReentrancyGuard,
    PNFTTokenStorageV1
{
    using SafeMath for uint256;

    event Released(uint256 amount);
    event Revoked();

    /**
     * @dev Reverts if no vesting schedule matches the passed identifier.
     */
    modifier onlyIfVestingScheduleExists(bytes32 vestingScheduleId) {
        require(_vestingSchedules[vestingScheduleId].initialized == true);
        _;
    }

    /**
     * @dev Reverts if the vesting schedule does not exist or has been revoked.
     */
    modifier onlyIfVestingScheduleNotRevoked(bytes32 vestingScheduleId) {
        require(_vestingSchedules[vestingScheduleId].initialized == true);
        require(_vestingSchedules[vestingScheduleId].revoked == false);
        _;
    }

    //

    function initialize(string memory name, string memory symbol) public initializer {
        __ERC20_init(name, symbol);
        __ERC20Burnable_init();
        __Pausable_init();
        __Ownable_init();
    }

    function pause() public onlyOwner {
        _pause();
    }

    function unpause() public onlyOwner {
        _unpause();
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override whenNotPaused {
        super._beforeTokenTransfer(from, to, amount);
    }

    receive() external payable {}

    fallback() external payable {}

    /**
     * @dev Returns the number of vesting schedules associated to a beneficiary.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCountByBeneficiary(address _beneficiary) external view returns (uint256) {
        return _holdersVestingCount[_beneficiary];
    }

    /**
     * @dev Returns the vesting schedule id at the given index.
     * @return the vesting id
     */
    function getVestingIdAtIndex(uint256 index) external view returns (bytes32) {
        require(index < getVestingSchedulesCount(), "PNFTToken: index out of bounds");
        return _vestingSchedulesIds[index];
    }

    /**
     * @notice Returns the vesting schedule information for a given holder and index.
     * @return the vesting schedule structure information
     */
    function getVestingScheduleByAddressAndIndex(
        address holder,
        uint256 index
    ) external view returns (VestingSchedule memory) {
        return getVestingSchedule(computeVestingScheduleIdForAddressAndIndex(holder, index));
    }

    /**
     * @notice Returns the total amount of vesting schedules.
     * @return the total amount of vesting schedules
     */
    function getVestingSchedulesTotalAmount() external view returns (uint256) {
        return _vestingSchedulesTotalAmount;
    }

    function createVestingScheduleBatch(VestingScheduleParams[] calldata params) public onlyOwner {
        for (uint256 i = 0; i < params.length; i++) {
            createVestingSchedule(params[i]);
        }
    }

    /**
     * @notice Creates a new vesting schedule for a beneficiary.
     */
    function createVestingSchedule(VestingScheduleParams calldata params) public onlyOwner {
        require(params.duration > 0, "PNFTToken: duration must be > 0");
        require(params.amount > 0, "PNFTToken: amount must be > 0");
        require(params.slicePeriodSeconds >= 1, "PNFTToken: slicePeriodSeconds must be >= 1");
        bytes32 vestingScheduleId = this.computeNextVestingScheduleIdForHolder(params.beneficiary);
        uint256 cliff = params.start.add(params.cliff);
        _vestingSchedules[vestingScheduleId] = VestingSchedule(
            true,
            params.beneficiary,
            cliff,
            params.start,
            params.duration,
            params.slicePeriodSeconds,
            params.revocable,
            params.amount,
            0,
            false
        );
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount.add(params.amount);
        _vestingSchedulesIds.push(vestingScheduleId);
        uint256 currentVestingCount = _holdersVestingCount[params.beneficiary];
        _holdersVestingCount[params.beneficiary] = currentVestingCount.add(1);
        if (params.unvestingAmount > 0) {
            address payable beneficiaryPayable = payable(params.beneficiary);
            _mint(beneficiaryPayable, params.unvestingAmount);
        }
    }

    /**
     * @notice Revokes the vesting schedule for given identifier.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function revoke(bytes32 vestingScheduleId) public onlyOwner onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = _vestingSchedules[vestingScheduleId];
        require(vestingSchedule.revocable == true, "PNFTToken: vesting is not revocable");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        if (vestedAmount > 0) {
            release(vestingScheduleId);
        }
        uint256 unreleased = vestingSchedule.amountTotal.sub(vestingSchedule.released);
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount.sub(unreleased);
        vestingSchedule.revoked = true;
    }

    /**
     * @notice Release vested amount of tokens.
     * @param vestingScheduleId the vesting schedule identifier
     */
    function release(bytes32 vestingScheduleId) public nonReentrant onlyIfVestingScheduleNotRevoked(vestingScheduleId) {
        VestingSchedule storage vestingSchedule = _vestingSchedules[vestingScheduleId];
        bool isBeneficiary = msg.sender == vestingSchedule.beneficiary;
        bool isOwner = msg.sender == owner();
        require(isBeneficiary || isOwner, "PNFTToken: only beneficiary and owner can release vested tokens");
        uint256 vestedAmount = _computeReleasableAmount(vestingSchedule);
        vestingSchedule.released = vestingSchedule.released.add(vestedAmount);
        address payable beneficiaryPayable = payable(vestingSchedule.beneficiary);
        _vestingSchedulesTotalAmount = _vestingSchedulesTotalAmount.sub(vestedAmount);
        _mint(beneficiaryPayable, vestedAmount);
    }

    /**
     * @dev Returns the number of vesting schedules managed by this contract.
     * @return the number of vesting schedules
     */
    function getVestingSchedulesCount() public view returns (uint256) {
        return _vestingSchedulesIds.length;
    }

    /**
     * @notice Computes the vested amount of tokens for the given vesting schedule identifier.
     * @return the vested amount
     */
    function computeReleasableAmount(
        bytes32 vestingScheduleId
    ) public view onlyIfVestingScheduleNotRevoked(vestingScheduleId) returns (uint256) {
        VestingSchedule storage vestingSchedule = _vestingSchedules[vestingScheduleId];
        return _computeReleasableAmount(vestingSchedule);
    }

    /**
     * @notice Returns the vesting schedule information for a given identifier.
     * @return the vesting schedule structure information
     */
    function getVestingSchedule(bytes32 vestingScheduleId) public view returns (VestingSchedule memory) {
        return _vestingSchedules[vestingScheduleId];
    }

    /**
     * @dev Computes the next vesting schedule identifier for a given holder address.
     */
    function computeNextVestingScheduleIdForHolder(address holder) public view returns (bytes32) {
        return computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder]);
    }

    /**
     * @dev Returns the last vesting schedule for a given holder address.
     */
    function getLastVestingScheduleForHolder(address holder) public view returns (VestingSchedule memory) {
        return _vestingSchedules[computeVestingScheduleIdForAddressAndIndex(holder, _holdersVestingCount[holder] - 1)];
    }

    /**
     * @dev Computes the vesting schedule identifier for an address and an index.
     */
    function computeVestingScheduleIdForAddressAndIndex(address holder, uint256 index) public pure returns (bytes32) {
        return keccak256(abi.encodePacked(holder, index));
    }

    /**
     * @dev Computes the releasable amount of tokens for a vesting schedule.
     * @return the amount of releasable tokens
     */
    function _computeReleasableAmount(VestingSchedule memory vestingSchedule) internal view returns (uint256) {
        uint256 currentTime = getCurrentTime();
        if ((currentTime < vestingSchedule.cliff) || vestingSchedule.revoked == true) {
            return 0;
        } else if (currentTime >= vestingSchedule.start.add(vestingSchedule.duration)) {
            return vestingSchedule.amountTotal.sub(vestingSchedule.released);
        } else {
            uint256 timeFromStart = currentTime.sub(vestingSchedule.start);
            uint secondsPerSlice = vestingSchedule.slicePeriodSeconds;
            uint256 vestedSlicePeriods = timeFromStart.div(secondsPerSlice);
            uint256 vestedSeconds = vestedSlicePeriods.mul(secondsPerSlice);
            uint256 vestedAmount = vestingSchedule.amountTotal.mul(vestedSeconds).div(vestingSchedule.duration);
            vestedAmount = vestedAmount.sub(vestingSchedule.released);
            return vestedAmount;
        }
    }

    function getCurrentTime() internal view virtual returns (uint256) {
        return block.timestamp;
    }
}

