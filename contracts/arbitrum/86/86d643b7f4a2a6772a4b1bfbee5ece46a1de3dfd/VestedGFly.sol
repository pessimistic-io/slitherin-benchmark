// SPDX-License-Identifier: MIT

pragma solidity 0.8.17;

import "./ERC20.sol";
import "./Math.sol";
import "./AccessControl.sol";
import "./ReentrancyGuard.sol";
import "./EnumerableSet.sol";
import "./ABDKMath64x64.sol";
import "./IVestedGFly.sol";
import "./IGFly.sol";

//MMMMWKl.                                            .:0WMMMM//
//MMMWk,                                                .dNMMM//
//MMNd.                                                  .lXMM//
//MWd.    .','''....                         .........    .lXM//
//Wk.     ';......'''''.                ..............     .dW//
//K;     .;,         ..,'.            ..'..         ...     'O//
//d.     .;;.           .''.        ..'.            .'.      c//
//:       .','.           .''.    ..'..           ....       '//
//'         .';.            .''...'..           ....         .//
//.           ';.             .''..             ..           .//
//.            ';.                             ...           .//
//,            .,,.                           .'.            .//
//c             .;.                           '.             ;//
//k.            .;.             .             '.            .d//
//Nl.           .;.           .;;'            '.            :K//
//MK:           .;.          .,,',.           '.           'OW//
//MM0;          .,,..       .''  .,.       ...'.          'kWM//
//MMMK:.          ..'''.....'..   .'..........           ,OWMM//
//MMMMXo.             ..'...        ......             .cKMMMM//
//MMMMMWO:.                                          .,kNMMMMM//
//MMMMMMMNk:.                                      .,xXMMMMMMM//
//MMMMMMMMMNOl'.                                 .ckXMMMMMMMMM//

contract VestedGFly is AccessControl, ERC20, ReentrancyGuard, IVestedGFly {
    using ABDKMath64x64 for uint256;
    using EnumerableSet for EnumerableSet.UintSet;

    /// @dev The identifier of the role which maintains other roles.
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN");
    /// @dev The identifier of the role which allows accounts to manage vestings.
    bytes32 public constant VESTING_MANAGER_ROLE = keccak256("VESTING_MANAGER");

    int128 public COEFFICIENT_A;
    int128 public COEFFICIENT_B;
    uint256 private SECONDS_IN_MONTH;

    mapping(uint256 => uint128) public claimedByVestingId;
    mapping(uint256 => VestingPosition) public vestingPosition;
    mapping(address => EnumerableSet.UintSet) private vestingIdsByAddress;

    IGFly public gFly;

    uint256 public override unminted;
    uint256 public currentVestingId;

    constructor(address gFly_, address dao) ERC20("vgFLY", "VGFLY") {
        require(gFly_ != address(0), "VestedGFly:INVALID_ADDRESS");
        require(dao != address(0), "VestedGFly:INVALID_ADDRESS");

        _setupRole(ADMIN_ROLE, dao);
        _setupRole(ADMIN_ROLE, msg.sender); // This will be surrendered after deployment
        _setRoleAdmin(ADMIN_ROLE, ADMIN_ROLE);
        _setRoleAdmin(VESTING_MANAGER_ROLE, ADMIN_ROLE);

        gFly = IGFly(gFly_);
        COEFFICIENT_A = 510445346680717146; //  0.0276712976903175 in signed 64.64-bit fixed point number.
        COEFFICIENT_B = 934732469242685894; //  0.0506719486922830 in signed 64.64-bit fixed point number.
        SECONDS_IN_MONTH = 2628000;
    }

    modifier onlyAdmin() {
        require(hasRole(ADMIN_ROLE, msg.sender), "VestedGFly:ACCESS_DENIED");
        _;
    }

    modifier onlyVestingManager() {
        require(hasRole(VESTING_MANAGER_ROLE, msg.sender), "VestedGFly:ACCESS_DENIED");
        _;
    }

    /**
     * @dev Add a new vesting position for an account given the amount, burnable percentage and the initial unlockable amount
     */
    function addVestingPosition(
        address owner,
        uint256 amount,
        bool burnable,
        uint256 initialUnlockable,
        uint256 employmentTimestamp
    ) external override onlyAdmin {
        require(amount > 0, "VestedGFly:CANNOT_VEST_0");
        require(initialUnlockable <= amount, "VestedGFly:CANNOT_UNLOCK_MORE_THAN_TOTAL");
        require(
            unminted + totalSupply() + gFly.totalSupply() + amount <= gFly.MAX_SUPPLY(),
            "VestedGFly:SUPPLY_OVERFLOW"
        );
        if (burnable) {
            require(employmentTimestamp <= block.timestamp, "VestedGFly:CANNOT_SET_A_FUTURE_EMPLOYMENT_DATE");
        } else {
            employmentTimestamp = 0;
        }
        unminted += amount;
        currentVestingId++;
        vestingPosition[currentVestingId] = VestingPosition(
            burnable,
            false,
            owner,
            block.timestamp,
            block.timestamp,
            employmentTimestamp,
            amount,
            amount,
            initialUnlockable,
            0,
            0,
            0
        );
        vestingIdsByAddress[owner].add(currentVestingId);
        emit VestingPositionAdded(owner, currentVestingId, amount, burnable, initialUnlockable, block.timestamp);
    }

    /**
     * @dev Function to mint VestedGFly for vested positions
     */
    function mint() external override nonReentrant {
        for (uint256 i = 0; i < vestingIdsByAddress[msg.sender].values().length; i++) {
            uint256 vestingId = vestingIdsByAddress[msg.sender].at(i);
            if (!vestingPosition[vestingId].minted) {
                unminted -= vestingPosition[vestingId].initialAllocation;
                vestingPosition[vestingId].minted = true;
                _mint(msg.sender, vestingPosition[vestingId].initialAllocation);
                emit Minted(msg.sender, vestingId, vestingPosition[vestingId].initialAllocation);
            }
        }
    }

    /**
     * @dev Function to burn VestedGFly from vested positions
     */
    function burn(uint256 vestingId, uint256 amount) external override onlyAdmin {
        require(vestingPosition[vestingId].burnable, "VestedGFly:POSITION_NOT_BURNABLE");
        require(
            vestingPosition[vestingId].employeeBurnt + amount <= maxBurnable(vestingId),
            "VestedGFly:EMPLOYEE_BURN_AMOUNT_EXCEEDED"
        );
        _claimGFly(vestingId);
        _burnPosition(vestingId, amount);
        vestingPosition[vestingId].employeeBurnt += amount;
        emit Burned(vestingPosition[vestingId].owner, vestingId, amount);
    }

    /**
     * @dev Function to burn all VestedGFly from vested positions
     */
    function burnAll(uint256 vestingId) external override onlyAdmin {
        require(vestingPosition[vestingId].burnable, "VestedGFly:POSITION_NOT_BURNABLE");
        _claimGFly(vestingId);
        uint256 toBeVested = vestingPosition[vestingId].initialAllocation -
        vestingPosition[vestingId].burnt -
        claimedByVestingId[vestingId];
        uint256 burnable = Math.min(toBeVested,maxBurnable(vestingId));
        _burnPosition(vestingId, burnable);
        vestingPosition[vestingId].employeeBurnt += burnable;
        emit Burned(vestingPosition[vestingId].owner, vestingId, burnable);
    }

    /**
     * @dev Function to transfer a vested position for a specified amount to a new owner.
     * This function is created to facilitate the setup of an OTC market for vested positions.
     * The new vesting position will follow the emissions schedule of the old position.
     * The remaining to be vested tokens of the original vesting position will be: toBeVestedBeforeTransfer - amount
     */
    function transferVestingPosition(
        uint256 vestingId,
        uint256 amount,
        address newOwner
    ) external override onlyVestingManager {
        require(amount > 0, "VestedGFly:CANNOT_TRANSFER_0");
        _claimGFly(vestingId);
        uint256 previouslyBurnt = vestingPosition[vestingId].burnt;
        uint256 previouslyRemaining = vestingPosition[vestingId].remainingAllocation;
        uint256 toBeVested = vestingPosition[vestingId].initialAllocation -
            previouslyBurnt -
            claimedByVestingId[vestingId];
        require(toBeVested >= amount, "VestedGFly:INSUFFICIENT_VESTING_AMOUNT");
        _burnPosition(vestingId, amount);
        currentVestingId++;
        vestingPosition[currentVestingId] = VestingPosition(
            false,
            true,
            newOwner,
            vestingPosition[vestingId].startTime,
            block.timestamp,
            0,
            ((previouslyRemaining) * amount) / toBeVested,
            amount,
            0,
            0,
            0,
            0
        );
        vestingIdsByAddress[newOwner].add(currentVestingId);
        _mint(newOwner, amount);
        emit VestingPositionTransfered(vestingPosition[vestingId].owner, vestingId, newOwner, currentVestingId, amount);
    }

    /**
     * @dev Function to claim all GFly (burn VestedGFly following vesting schedule and mint GFly 1 to 1)
     */
    function claimAllGFly() external override nonReentrant {
        for (uint256 i = 0; i < vestingIdsByAddress[msg.sender].values().length; i++) {
            uint256 vestingId = vestingIdsByAddress[msg.sender].at(i);
            if (vestingPosition[vestingId].minted) {
                _claimGFly(vestingId);
            }
        }
    }

    /**
     * @dev Function to claim GFly for a specific vestingId (burn VestedGFly following vesting schedule and mint GFly 1 to 1)
     */
    function claimGFly(uint256 vestingId) external override nonReentrant {
        require(vestingPosition[vestingId].owner == msg.sender, "VestedGFly:NOT_OWNER_OF_VESTING");
        _claimGFly(vestingId);
    }

    /**
     * @dev Get the total amount of vested tokens of an account.
     */
    function totalVestedOf(address account) external view override returns (uint256 total) {
        for (uint256 i = 0; i < vestingIdsByAddress[account].values().length; i++) {
            uint256 vestingId = vestingIdsByAddress[account].at(i);
            (uint256 vested, , ) = _vestingSnapshot(vestingId, block.timestamp);
            total += vested;
        }
    }

    /**
     * @dev Get the amount of vested tokens of vesting object.
     */
    function vestedOf(uint256 vestingId) external view override returns (uint256) {
        (uint256 vested, , ) = _vestingSnapshot(vestingId, block.timestamp);
        return vested;
    }

    /**
     * @dev Get the total amount of claimable GFly of an account.
     */
    function totalClaimableOf(address account) external view override returns (uint256 total) {
        for (uint256 i = 0; i < vestingIdsByAddress[account].values().length; i++) {
            uint256 vestingId = vestingIdsByAddress[account].at(i);
            (uint256 vested, uint256 claimed, uint256 balance) = _vestingSnapshot(vestingId, block.timestamp);
            uint256 claimable = vested >= claimed ? vested - claimed : 0;
            total += Math.min(claimable, balance);
        }
    }

    /**
     * @dev Get the amount of claimable GFly of a vesting object.
     */
    function claimableOf(uint256 vestingId) public view override returns (uint256) {
        (uint256 vested, uint256 claimed, uint256 balance) = _vestingSnapshot(vestingId, block.timestamp);
        uint256 claimable = vested >= claimed ? vested - claimed : 0;
        return Math.min(claimable, balance);
    }

    /**
     * @dev Get the total claimed amount of VestedGFly of an account.
     */
    function totalClaimedOf(address account) external view override returns (uint256 total) {
        for (uint256 i = 0; i < vestingIdsByAddress[account].values().length; i++) {
            uint256 vestingId = vestingIdsByAddress[account].at(i);
            (, uint256 claimed, ) = _vestingSnapshot(vestingId, block.timestamp);
            total += claimed;
        }
    }

    /**
     * @dev Get the claimed amount of VestedGFly of a vesting object
     */
    function claimedOf(uint256 vestingId) external view override returns (uint256) {
        (, uint256 claimed, ) = _vestingSnapshot(vestingId, block.timestamp);
        return claimed;
    }

    /**
     * @dev Get the total balance of vestedGFly of an account.
     */
    function totalBalance(address account) external view override returns (uint256 total) {
        total = balanceOf(account);
    }

    /**
     * @dev Get the VestedGFly balance of a vesting object.
     */
    function balanceOfVesting(uint256 vestingId) external view override returns (uint256) {
        (, , uint256 balance) = _vestingSnapshot(vestingId, block.timestamp);
        return balance;
    }

    /**
     * @dev Get the amount of claimable GFly of a vesting object at a certain point in time.
     */
    function claimableOfAtTimestamp(uint256 vestingId, uint256 timestamp) external view override returns (uint256) {
        (uint256 vested, uint256 claimed, uint256 balance) = _vestingSnapshot(
            vestingId,
            Math.max(block.timestamp, timestamp)
        );
        uint256 claimable = vested >= claimed ? vested - claimed : 0;
        return Math.min(claimable, balance);
    }

    /**
     * @dev Get the vestingIds of an address
     */
    function getVestingIdsOfAddress(address account) external view override returns (uint256[] memory) {
        return vestingIdsByAddress[account].values();
    }

    /**
     * @dev Get maximum burnable amount of a vesting object.
     * This is based on the time difference since when an employee started working and the current time on a 36 months timeline.
     */
    function maxBurnable(uint256 vestingId) public view override returns (uint256 burnable) {
        burnable = 0;
        if (vestingPosition[vestingId].burnable) {
            uint256 elapsedTime = Math.min(
                block.timestamp - vestingPosition[vestingId].employmentTimestamp,
                SECONDS_IN_MONTH * 36
            );
            burnable =
                vestingPosition[vestingId].initialAllocation -
                ((elapsedTime * vestingPosition[vestingId].initialAllocation) / (SECONDS_IN_MONTH * 36));
        }
    }

    function _burnPosition(uint256 vestingId, uint256 amount) internal {
        if (vestingPosition[vestingId].initialAllocation > 0 && amount > 0) {
            uint256 vestedAtLastBurn = claimedByVestingId[vestingId];
            vestingPosition[vestingId].vestedAtLastBurn = vestedAtLastBurn;
            vestingPosition[vestingId].lastBurnTime = block.timestamp;
            uint256 toBeVested = vestingPosition[vestingId].initialAllocation -
                vestingPosition[vestingId].burnt -
                vestedAtLastBurn;
            require(amount <= toBeVested, "VestedGFly:NOT_ENOUGH_AVAILABLE_FOR_BURN");
            vestingPosition[vestingId].burnt += amount;
            vestingPosition[vestingId].remainingAllocation =
                (vestingPosition[vestingId].remainingAllocation * (toBeVested - amount)) /
                toBeVested;
            _burn(vestingPosition[vestingId].owner, amount);
        }
    }

    function _claimGFly(uint256 vestingId) internal {
        require(vestingPosition[vestingId].initialAllocation > 0, "VestedGFly:UNEXISTING_VESTING_POSITION");
        require(vestingPosition[vestingId].minted, "VestedGFly:CANNOT_CLAIM_UNMINTED_POSITION");
        address owner = vestingPosition[vestingId].owner;
        uint256 claimable = _claim(vestingId);
        if (claimable > 0) {
            gFly.mint(owner, claimable);
        }
    }

    function _claim(uint256 vestingId) private returns (uint128 claimable) {
        claimable = uint128(claimableOf(vestingId));
        if (claimable > 0) {
            claimedByVestingId[vestingId] += claimable;
            _burn(vestingPosition[vestingId].owner, claimable);
            emit GFlyClaimed(vestingPosition[vestingId].owner, vestingId, claimable);
        }
    }

    function _partlyBurned(uint256 vestingId) internal view returns (bool) {
        return vestingPosition[vestingId].lastBurnTime > vestingPosition[vestingId].startTime;
    }

    function _getVestingStartAndEnd(uint256 vestingId, uint256 currentTime)
        internal
        view
        returns (
            uint256 startMonth,
            uint256 currentMonth,
            uint256 secondsInStartMonth,
            uint256 secondsInCurrentMonth
        )
    {
        startMonth = 1;

        if (_partlyBurned(vestingId)) {
            startMonth +=
                (vestingPosition[vestingId].lastBurnTime - vestingPosition[vestingId].startTime) /
                SECONDS_IN_MONTH;
        }
        uint256 passedSeconds = currentTime - vestingPosition[vestingId].startTime;
        currentMonth = passedSeconds / SECONDS_IN_MONTH;
        secondsInCurrentMonth = passedSeconds - (currentMonth * SECONDS_IN_MONTH);

        passedSeconds = vestingPosition[vestingId].lastBurnTime - vestingPosition[vestingId].startTime;
        uint256 lastBurnMonth = passedSeconds / SECONDS_IN_MONTH;
        secondsInStartMonth = SECONDS_IN_MONTH - (passedSeconds - (lastBurnMonth * SECONDS_IN_MONTH));
        if (currentMonth == lastBurnMonth) {
            secondsInStartMonth -= (SECONDS_IN_MONTH - secondsInCurrentMonth);
        }
        currentMonth += 1;
    }

    function _vestingSnapshot(uint256 vestingId, uint256 timestamp)
        internal
        view
        returns (
            uint256,
            uint256,
            uint256
        )
    {
        uint128 claimed = claimedByVestingId[vestingId];
        uint256 balance = vestingPosition[vestingId].minted
            ? (vestingPosition[vestingId].initialAllocation - vestingPosition[vestingId].burnt - claimed)
            : 0;
        return (_totalVestedOf(vestingId, vestingPosition[vestingId].remainingAllocation, timestamp), claimed, balance);
    }

    /**
     * @dev Internal function to calculate the total amount of vested tokens at a certain moment in time.
     * This follows the following equation: y = a*P*e^(b*x), where:
     * a = coefficient a (0.0276712976903175)
     * b = coefficient b (0.0506719486922830)
     * P = percentage of tokens allocated on a total of 8.5 million.
     * e = eulers number
     * x = month since start
     */
    function _totalVestedOf(
        uint256 vestingId,
        uint256 remainingAllocation,
        uint256 currentTime
    ) internal view returns (uint256 total) {
        if (currentTime < vestingPosition[vestingId].startTime) {
            return 0;
        }
        (
            uint256 startMonth,
            uint256 currentMonth,
            uint256 secondsInStartMonth,
            uint256 secondsInCurrentMonth
        ) = _getVestingStartAndEnd(vestingId, currentTime);

        int128 percentageAllocation = ABDKMath64x64.divu(remainingAllocation, 85e5 * 1 ether);
        if (_partlyBurned(vestingId)) {
            total += vestingPosition[vestingId].vestedAtLastBurn;
        } else {
            total += vestingPosition[vestingId].initialUnlockable;
        }

        for (uint256 month = startMonth; month <= Math.min(currentMonth, 36); month++) {
            uint256 secondsInMonth = SECONDS_IN_MONTH;
            if (month == startMonth && _partlyBurned(vestingId)) {
                secondsInMonth = secondsInStartMonth;
            } else if (month == currentMonth) {
                secondsInMonth = secondsInCurrentMonth;
            }
            total +=
                secondsInMonth *
                ABDKMath64x64.mulu(
                    ABDKMath64x64.mul(
                        COEFFICIENT_A,
                        ABDKMath64x64.mul(
                            percentageAllocation,
                            ABDKMath64x64.exp(ABDKMath64x64.mul(COEFFICIENT_B, ABDKMath64x64.fromUInt(month)))
                        )
                    ),
                    1e18
                );
        }
        total = Math.min(total, vestingPosition[vestingId].initialAllocation - vestingPosition[vestingId].burnt);
    }

    function _beforeTokenTransfer(
        address from,
        address to,
        uint256
    ) internal virtual override {
        //Allow only mint and burn
        require(from == address(0) || to == address(0), "VestedGFly:TRANSFER_DENIED");
    }
}

