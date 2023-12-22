// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import { ERC20Facet } from "./ERC20Facet.sol";
import { OwnableUpgradeable } from "./OwnableUpgradeable.sol";
import { ReentrancyGuardUpgradeable } from "./ReentrancyGuardUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";

interface IGaugeController {
    function isVaultActive(address vault) external view returns (bool);
}

contract EscrowedFactorToken is ERC20Facet, OwnableUpgradeable, ReentrancyGuardUpgradeable {
    // =============================================================
    //                          Events
    // =============================================================

    event VestingCreated(uint256 vestingId, uint256 startTime, uint256 endTime, uint256 amount, address user);
    event TokensClaimed(uint256 vestingId, uint256 amountClaimed);
    event VestingTimeChanged(uint256 _days);
    event WhitelistChanged(address _contract, bool active);

    // =============================================================
    //                          Errors
    // =============================================================

    error OnlyGaugeControllerCanMint();
    error InsufficientBalance();
    error VestingFullyClaimed();
    error NotScheduleOwner();
    error NotTransferable();

    // =============================================================
    //                          Structs
    // =============================================================

    struct VestingSchedule {
        uint256 startTime;
        uint256 endTime;
        uint256 amount;
        uint256 claimedAmount;
        address user;
    }

    // =============================================================
    //                   State Variables
    // =============================================================

    address public gaugeController;

    mapping(uint256 => VestingSchedule) public vestingSchedules;

    mapping(address => bool) public whitelist;

    uint256 public currentVestingId;

    uint256 public vestingTime;

    IERC20 public fctrToken;

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }
    
    function initialize(address _gaugeController, address _fctrTokenAddress, uint256 _vestingTime) public initializer {
        __ERC20_init('Escrowed Factor', 'esFCTR', 18);
        __Ownable_init(msg.sender);
        __ReentrancyGuard_init();

        gaugeController = _gaugeController;
        fctrToken = IERC20(_fctrTokenAddress);
        vestingTime = _vestingTime;
    }

    function mint(address to, uint256 amount) public nonReentrant {
        if (msg.sender != gaugeController) revert OnlyGaugeControllerCanMint();
        _mint(to, amount);
    }

    function createVesting(uint256 amount) public nonReentrant {
        if (balanceOf(msg.sender) < amount) revert InsufficientBalance();

        transfer(address(this), amount);

        uint256 newVestingId = currentVestingId++;

        VestingSchedule memory newSchedule = VestingSchedule(
            block.timestamp,
            block.timestamp + vestingTime,
            amount,
            0,
            msg.sender
        );

        vestingSchedules[newVestingId] = newSchedule;

        emit VestingCreated(newVestingId, newSchedule.startTime, newSchedule.endTime, amount, msg.sender);
    }

    function claimVesting(uint256 vestingId) public nonReentrant {
        VestingSchedule storage schedule = vestingSchedules[vestingId];

        if (schedule.claimedAmount >= schedule.amount) revert VestingFullyClaimed();
        if (msg.sender != schedule.user) revert NotScheduleOwner();

        uint256 claimable = calculateClaimable(
            schedule.startTime,
            schedule.endTime,
            schedule.amount,
            schedule.claimedAmount
        );

        schedule.claimedAmount += claimable;

        _burn(address(this), claimable); // Burn esFCTR

        fctrToken.transfer(msg.sender, claimable);

        emit TokensClaimed(vestingId, claimable);
    }

    function fundFctr(uint256 amount) external {
        fctrToken.transferFrom(msg.sender, address(this), amount);
    }

    function withdrawFctr(uint256 amount) external onlyOwner {
        fctrToken.transfer(owner(), amount);
    }

    function setVestingTime(uint256 _days) external onlyOwner {
        vestingTime = _days;

        emit VestingTimeChanged(_days);
    }

    function setWhitelist(address _contract, bool active) external onlyOwner {
        whitelist[_contract] = active;

        emit WhitelistChanged(_contract, active);
    }

    function calculateClaimable(
        uint256 startTime,
        uint256 endTime,
        uint256 amount,
        uint256 claimedAmount
    ) public view returns (uint256) {
        uint256 timestamp = block.timestamp;
        if (block.timestamp > endTime) timestamp = endTime;
        uint256 claimableDuration = timestamp - startTime;
        uint256 totalDuration = endTime - startTime;
        uint256 totalClaimable = (amount * claimableDuration) / totalDuration;
        return totalClaimable > claimedAmount ? totalClaimable - claimedAmount : 0;
    }

    function _beforeTokenTransfer(address from, address to, uint256 amount) internal override {
        // 1. vaults from Gauge Controller
        // 2. whitelist
        // 3. address(this)
        // 4. factor gauge controller
        if (
            IGaugeController(gaugeController).isVaultActive(from) == true ||
            whitelist[from] == true ||
            to == address(this) ||
            from == gaugeController ||
            from == address(0) ||
            to == address(0)
        ) {
            super._beforeTokenTransfer(from, to, amount);
        } else {
            revert NotTransferable();
        }
    }
}

