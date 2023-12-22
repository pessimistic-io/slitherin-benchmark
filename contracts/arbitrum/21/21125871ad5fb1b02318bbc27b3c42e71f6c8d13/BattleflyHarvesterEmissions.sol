// SPDX-License-Identifier: MIT
pragma solidity ^0.8.2;

import "./IERC20Upgradeable.sol";
import "./SafeERC20Upgradeable.sol";
import "./Initializable.sol";
import "./AddressUpgradeable.sol";
import "./SafeCastUpgradeable.sol";
import "./EnumerableSetUpgradeable.sol";
import "./ReentrancyGuardUpgradeable.sol";
import "./OwnableUpgradeable.sol";

import "./IAtlasMine.sol";
import "./IBattleflyAtlasStakerV02.sol";
import "./IBattleflyTreasuryFlywheelVault.sol";
import "./IBattleflyHarvesterEmissions.sol";

contract BattleflyHarvesterEmissions is
    IBattleflyHarvesterEmissions,
    Initializable,
    OwnableUpgradeable,
    ReentrancyGuardUpgradeable
{
    using AddressUpgradeable for address;
    using SafeCastUpgradeable for uint256;
    using SafeCastUpgradeable for int256;
    using SafeERC20Upgradeable for IERC20Upgradeable;
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.UintSet;

    uint256 public constant ONE = 1e18;

    IERC20Upgradeable public MAGIC;
    IBattleflyAtlasStakerV02 public ATLAS_STAKER;
    IBattleflyTreasuryFlywheelVault public TREASURY_VAULT;

    mapping(uint64 => HarvesterEmission) public harvesterEmissionsForEpoch;
    mapping(uint256 => uint64) public lastPayoutEpoch;
    mapping(address => uint64) public lastPayoutEpochForVault;
    mapping(address => uint256) public currentVaultHarvesterStake;
    mapping(address => mapping(uint64 => uint256)) public vaultHarvesterStakeAtEpoch;

    address public VAULT1;
    address public VAULT2;
    address public CHEESE;
    address public DIGI;
    address public FRITTEN;

    function initialize(
        address _magic,
        address _atlasStaker,
        address _treasuryVault,
        address _vault1,
        address _vault2,
        address _cheese,
        address _digi,
        address _fritten
    ) external initializer {
        __Ownable_init();
        __ReentrancyGuard_init();

        require(_magic != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_atlasStaker != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_treasuryVault != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_vault1 != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_vault2 != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_cheese != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_digi != address(0), "BattflyHarvesterEmissions: invalid address");
        require(_fritten != address(0), "BattflyHarvesterEmissions: invalid address");

        MAGIC = IERC20Upgradeable(_magic);
        ATLAS_STAKER = IBattleflyAtlasStakerV02(_atlasStaker);
        TREASURY_VAULT = IBattleflyTreasuryFlywheelVault(_treasuryVault);
        VAULT1 = _vault1;
        VAULT2 = _vault2;
        CHEESE = _cheese;
        DIGI = _digi;
        FRITTEN = _fritten;
    }

    // ============================== Operations ==============================

    /**
     * @dev Topup harvester emissions
     */
    function topupHarvesterEmissions(
        uint256 _amount,
        uint256 _harvesterMagic,
        uint256 _additionalFlywheelMagic
    ) external override {
        require(_amount > 0, "BattflyHarvesterEmissions: cannot deposit 0");
        uint64 epoch = ATLAS_STAKER.currentEpoch();
        MAGIC.safeTransferFrom(msg.sender, address(this), _amount);
        harvesterEmissionsForEpoch[epoch].amount += _amount;
        harvesterEmissionsForEpoch[epoch].harvesterMagic = _harvesterMagic;
        harvesterEmissionsForEpoch[epoch].additionalFlywheelMagic = _additionalFlywheelMagic;
        vaultHarvesterStakeAtEpoch[VAULT1][epoch] = currentVaultHarvesterStake[VAULT1];
        vaultHarvesterStakeAtEpoch[VAULT2][epoch] = currentVaultHarvesterStake[VAULT2];
        vaultHarvesterStakeAtEpoch[CHEESE][epoch] = currentVaultHarvesterStake[CHEESE];
        vaultHarvesterStakeAtEpoch[DIGI][epoch] = currentVaultHarvesterStake[DIGI];
        vaultHarvesterStakeAtEpoch[FRITTEN][epoch] = currentVaultHarvesterStake[FRITTEN];
        emit topupHarvesterMagic(_amount, _harvesterMagic, _additionalFlywheelMagic, epoch);
    }

    /**
     * @dev Set MAGIC harvester amounts for participating vaults
     */
    function setVaultHarvesterStake(uint256 _amount, address _vault) external override onlyOwner {
        require(
            _vault == VAULT1 || _vault == VAULT2 || _vault == CHEESE || _vault == DIGI || _vault == FRITTEN,
            "BattflyHarvesterEmissions: vault not allowed"
        );
        currentVaultHarvesterStake[_vault] = _amount;
    }

    /**
     * @dev Get claimable emissions for flywheel deposits
     */
    function getClaimableEmission(uint256 _depositId) public view override returns (uint256 emission, uint256 fee) {
        uint64 lockAt = ATLAS_STAKER.getVaultStake(_depositId).lockAt;
        uint256 amount = ATLAS_STAKER.getVaultStake(_depositId).amount;
        uint64 retentionUnlock = ATLAS_STAKER.getVaultStake(_depositId).retentionUnlock;
        uint64 currentEpoch = ATLAS_STAKER.currentEpoch();
        uint64 startEpoch = lastPayoutEpoch[_depositId] == 0 ? lockAt : lastPayoutEpoch[_depositId] + 1;
        uint64 stopEpoch = retentionUnlock == 0
            ? currentEpoch - 1
            : (retentionUnlock >= currentEpoch ? currentEpoch - 1 : retentionUnlock - 1);
        IAtlasMine.Lock[] memory locks = ATLAS_STAKER.getAllowedLocks();
        for (uint64 i = startEpoch; i <= stopEpoch; i++) {
            uint256 totalStaked = harvesterEmissionsForEpoch[i].additionalFlywheelMagic;
            for (uint256 k = 0; k < locks.length; k++) {
                totalStaked += ATLAS_STAKER.totalStakedAtEpochForLock(locks[k], i);
            }
            uint256 reservedForHarvesterParticipants = _reservedForHarvesterParticipantsAtEpoch(i);
            if (
                totalStaked > 0 &&
                harvesterEmissionsForEpoch[i].harvesterMagic > 0 &&
                harvesterEmissionsForEpoch[i].amount > reservedForHarvesterParticipants
            ) {
                emission += ((((amount * ONE) / totalStaked) *
                    (harvesterEmissionsForEpoch[i].amount - reservedForHarvesterParticipants)) / ONE);
            }
        }
        fee =
            (emission * ATLAS_STAKER.getVault(ATLAS_STAKER.getVaultStake(_depositId).vault).fee) /
            ATLAS_STAKER.FEE_DENOMINATOR();
        emission -= fee;
    }

    /**
     * @dev Get claimable emissions for Harvester participating vaults
     */
    function getClaimableEmission(address _vault) public view override returns (uint256 emission, uint256 fee) {
        uint64 currentEpoch = ATLAS_STAKER.currentEpoch();
        uint64 startEpoch = lastPayoutEpochForVault[_vault] + 1;
        uint64 stopEpoch = currentEpoch - 1;
        for (uint64 i = startEpoch; i <= stopEpoch; i++) {
            emission += _getEmissionsForVaultAtEpoch(_vault, i);
        }
        fee = (emission * ATLAS_STAKER.getVault(_vault).fee) / ATLAS_STAKER.FEE_DENOMINATOR();
        emission -= fee;
    }

    function _getEmissionsForVaultAtEpoch(address _vault, uint64 _epoch) internal view returns (uint256) {
        uint256 stakedAmount;
        if ((_vault == VAULT1) || (_vault == VAULT2) || (_vault == CHEESE) || (_vault == DIGI) || (_vault == FRITTEN)) {
            stakedAmount = vaultHarvesterStakeAtEpoch[_vault][_epoch];
        } else {
            return 0;
        }
        if ((_vault == VAULT1) || (_vault == VAULT2) || (_vault == CHEESE)) {
            return _getEmissionForHarvesterStakeAtEpoch(_vault, _epoch);
        } else {
            uint256 magicInVault;
            for (uint256 i = 0; i < ATLAS_STAKER.depositIdsOfVault(_vault).length; i++) {
                magicInVault += ATLAS_STAKER.getVaultStake(ATLAS_STAKER.depositIdsOfVault(_vault)[i]).amount;
            }
            IAtlasMine.Lock[] memory locks = ATLAS_STAKER.getAllowedLocks();
            uint256 totalStaked;
            for (uint256 k = 0; k < locks.length; k++) {
                totalStaked += ATLAS_STAKER.totalStakedAtEpochForLock(locks[k], _epoch);
            }
            uint256 totalFlywheelOfVault = magicInVault + stakedAmount;
            uint256 totalFlywheel = harvesterEmissionsForEpoch[_epoch].additionalFlywheelMagic + totalStaked;
            uint256 reservedForHarvesterParticipants = _reservedForHarvesterParticipantsAtEpoch(_epoch);
            if (
                totalFlywheel > 0 &&
                totalFlywheel >= totalFlywheelOfVault &&
                harvesterEmissionsForEpoch[_epoch].harvesterMagic > 0 &&
                harvesterEmissionsForEpoch[_epoch].amount > reservedForHarvesterParticipants
            ) {
                uint256 harvesterShare = (((totalFlywheelOfVault * ONE) / totalFlywheel) *
                    (harvesterEmissionsForEpoch[_epoch].amount - reservedForHarvesterParticipants)) / ONE;
                return harvesterShare + _getMakeupEmissionHarvesterStakeAtEpoch(_vault, _epoch);
            }
            return 0;
        }
    }

    function _getEmissionForHarvesterStakeAtEpoch(address _vault, uint64 _epoch) internal view returns (uint256) {
        if (harvesterEmissionsForEpoch[_epoch].harvesterMagic > 0) {
            return
                (((harvesterEmissionsForEpoch[_epoch].amount * ONE) /
                    harvesterEmissionsForEpoch[_epoch].harvesterMagic) * vaultHarvesterStakeAtEpoch[_vault][_epoch]) /
                ONE;
        }
        return 0;
    }

    function _getMakeupEmissionHarvesterStakeAtEpoch(address _vault, uint64 _epoch) internal view returns (uint256) {
        uint256 emissionsRate = ATLAS_STAKER.totalPerShareAtEpochForLock(IAtlasMine.Lock.twoWeeks, _epoch) -
            ATLAS_STAKER.totalPerShareAtEpochForLock(IAtlasMine.Lock.twoWeeks, _epoch - 1);
        return (emissionsRate * vaultHarvesterStakeAtEpoch[_vault][_epoch]) / 1e28;
    }

    function _reservedForHarvesterParticipantsAtEpoch(uint64 epoch) internal view returns (uint256) {
        return
            _getEmissionForHarvesterStakeAtEpoch(VAULT1, epoch) +
            _getEmissionForHarvesterStakeAtEpoch(VAULT2, epoch) +
            _getEmissionForHarvesterStakeAtEpoch(CHEESE, epoch) +
            _getMakeupEmissionHarvesterStakeAtEpoch(DIGI, epoch) +
            _getMakeupEmissionHarvesterStakeAtEpoch(FRITTEN, epoch);
    }

    /**
     * @dev Get harvester APY for flywheel participants
     */
    function getApyAtEpochIn1000(uint64 epoch) public view override returns (uint256) {
        uint256 totalStaked = harvesterEmissionsForEpoch[epoch].additionalFlywheelMagic;
        IAtlasMine.Lock[] memory locks = ATLAS_STAKER.getAllowedLocks();
        for (uint256 k = 0; k < locks.length; k++) {
            totalStaked += ATLAS_STAKER.totalStakedAtEpochForLock(locks[k], epoch);
        }
        uint256 reservedForHarvesterParticipants = _reservedForHarvesterParticipantsAtEpoch(epoch);
        if (
            totalStaked > 0 &&
            harvesterEmissionsForEpoch[epoch].amount > reservedForHarvesterParticipants &&
            harvesterEmissionsForEpoch[epoch].harvesterMagic > 0
        ) {
            return
                ((harvesterEmissionsForEpoch[epoch].amount - reservedForHarvesterParticipants) * 365 * 100 * 1000) /
                totalStaked;
        }
        return 0;
    }

    /**
     * @dev Claim emissions for a depositId
     */
    function claim(uint256 _depositId) public override nonReentrant whenNotPaused returns (uint256) {
        address vault = ATLAS_STAKER.getVaultStake(_depositId).vault;
        require(
            msg.sender == address(ATLAS_STAKER) || msg.sender == vault,
            "BattflyHarvesterEmissions: Not the correct owner"
        );
        (uint256 emission, uint256 fee) = getClaimableEmission(_depositId);
        if (emission > 0) {
            MAGIC.safeTransfer(vault, emission);
            if (fee > 0) {
                MAGIC.approve(address(TREASURY_VAULT), fee);
                TREASURY_VAULT.topupMagic(fee);
            }
            emit ClaimHarvesterEmission(msg.sender, emission, _depositId);
        }
        lastPayoutEpoch[_depositId] = ATLAS_STAKER.currentEpoch() - 1;
        return emission;
    }

    /**
     * @dev Claim emissions for a vault
     */
    function claim(address _vault) public override nonReentrant whenNotPaused returns (uint256) {
        require(msg.sender == _vault, "BattflyHarvesterEmissions: Not the correct owner");
        (uint256 emission, uint256 fee) = getClaimableEmission(_vault);
        if (emission > 0) {
            MAGIC.safeTransfer(msg.sender, emission);
            if (fee > 0) {
                MAGIC.approve(address(TREASURY_VAULT), fee);
                TREASURY_VAULT.topupMagic(fee);
            }
            emit ClaimHarvesterEmissionFromVault(msg.sender, emission, _vault);
        }
        lastPayoutEpochForVault[_vault] = ATLAS_STAKER.currentEpoch() - 1;
        return emission;
    }


    function claimVault(address _vault) public override nonReentrant whenNotPaused returns (uint256) {
        require(msg.sender == _vault, "BattflyHarvesterEmissions: Not the correct owner");
        (uint256 emission, uint256 fee) = getClaimableEmission(_vault);
        if (emission > 0) {
            MAGIC.safeTransfer(msg.sender, emission);
            if (fee > 0) {
                MAGIC.approve(address(TREASURY_VAULT), fee);
                TREASURY_VAULT.topupMagic(fee);
            }
            emit ClaimHarvesterEmissionFromVault(msg.sender, emission, _vault);
        }
        lastPayoutEpochForVault[_vault] = ATLAS_STAKER.currentEpoch() - 1;
        return emission;
    }
    // ============================== Modifiers ==============================

    modifier whenNotPaused() {
        require(block.timestamp > ATLAS_STAKER.pausedUntil(), "BattflyHarvesterEmissions: contract paused");
        _;
    }
}

