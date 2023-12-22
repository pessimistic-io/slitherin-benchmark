// SPDX-License-Identifier: UNLICENSED

pragma solidity ^0.8.13;

import {IDarkAgeCoin} from "./IDarkAgeCoin.sol";
import {DarkAgeCoin} from "./DarkAgeCoin.sol";
import {OwnableUpgradeable} from "./OwnableUpgradeable.sol";
import {UUPSUpgradeable} from "./UUPSUpgradeable.sol";
import {Initializable} from "./Initializable.sol";
import {PausableUpgradeable} from "./PausableUpgradeable.sol";
import {FixedPoint} from "./FixedPoint.sol";
import {SafeERC20} from "./SafeERC20.sol";
import {IDarkAgeRealm} from "./IDarkAgeRealm.sol";

/**
 * @title DarkAgeRealm
 * @notice In a land where peasants battle for power and riches, no one is safe from plunder.
 * As a peasant in this treacherous land, you can burn rivals' fortunes through Conflagration Plunder, seek refuge in
 * the Sanctuary of Protection, and revel in the Bountiful Harvest bestowed upon you.
 *
 * Embrace the chaos, strategize to protect your wealth, and watch as alliances and rivalries unfold. The fate of your fortune lies within your grasp.
 */

contract DarkAgeRealm is IDarkAgeRealm, Initializable, UUPSUpgradeable, PausableUpgradeable, OwnableUpgradeable {
    using FixedPoint for uint256;
    using SafeERC20 for IDarkAgeCoin;

    IDarkAgeCoin public DAC;
    uint256 public refugePeriod;
    uint256 public dungeonPeriod;
    uint256 public plunderFee; // bps
    uint256 public sanctuaryTitheIn; // bps
    uint256 public sanctuaryTitheOut; // bps
    uint256 public totalClaimableTreasure;

    mapping(address => uint256) public lastTimeConflagrated;
    mapping(address => uint256) public lastTimePlundering;
    mapping(address => uint256) public protectedWealth;
    mapping(address => bool) public sanctifiedAddresses;
    mapping(address => uint256) public lastClaimedTreasure;

    enum CallType {Sanctuary}

    modifier sanctifiedAddress(address _peasant) {
        require(!sanctifiedAddresses[_peasant], "Address is protected from conflagration");

        _;
    }

    event ConflagrationPlunder(address indexed attacker, address indexed victim, uint256 amount);
    event SanctuaryProtection(address indexed peasent, uint256 amount);
    event DepartSanctuary(address indexed peasent, uint256 amount);
    event ClaimTreasure(address indexed peasent, uint256 amount);
    event SanctifyAddress(address indexed peasent);
    event DesanctifyAddress(address indexed peasent);
    event UpdateRefugePeriod(uint256 newPeriod);
    event UpdateDungeonPeriod(uint256 newPeriod);
    event UpdatePlunderFee(uint256 newFee);
    event UpdateSanctuaryTitheIn(uint256 newTithe);
    event UpdateSanctuaryTitheOut(uint256 newTithe);

    constructor() {
        _disableInitializers();
    }

    function initialize(
        address _token,
        uint32 _plunderFee,
        uint32 _titheIn,
        uint32 _titheOut,
        uint256 _refugePeriod,
        uint256 _dungeonPeriod
    ) public initializer {
        __Ownable_init();
        __Pausable_init();
        __UUPSUpgradeable_init();
        DAC = IDarkAgeCoin(_token);
        plunderFee = _plunderFee;
        sanctuaryTitheIn = _titheIn;
        sanctuaryTitheOut = _titheOut;
        refugePeriod = _refugePeriod;
        dungeonPeriod = _dungeonPeriod;
    }

    /**
     * @notice Engage in a daring act of Conflagration Plunder against an unsuspecting victim!
     * @dev Burns the specified amount of tokens from the victim, mints the same amount to the contract, and takes a plunder fee from the attacker.
     * @param _peasant The address of the victim to conflagrate.
     * @param _amount The amount of tokens to burn from the victim.
     * Ah, the sweet scent of treachery! With stealthy cunning, you seek to conflagrate a rival's purse,
     * setting their hard-earned wealth ablaze in a dazzling act of plunder.
     * But beware, crafty peasant! Each act of plunder comes at a cost. In exchange for this dastardly deed,
     * you too shall pay a small tribute from your own hoard.
     * Conflagration Plunder knows no honor - only the relentless pursuit of riches.
     */

    function conflagrateVictim(address _peasant, uint256 _amount) external sanctifiedAddress(_peasant) whenNotPaused {
        require(_peasant != address(0), "Invalid address");
        if (lastTimeConflagrated[_peasant] != 0) {
            require(
                lastTimeConflagrated[_peasant] + refugePeriod < block.timestamp,
                "Rest period not passed to conflagrate victim again"
            );
        }

        if (lastTimePlundering[msg.sender] != 0) {
            require(
                lastTimePlundering[msg.sender] + dungeonPeriod < block.timestamp,
                "You have been thrown in the dungeons for a time period"
            );
        }

        require(_amount <= DAC.balanceOf(msg.sender), "Insufficient wealth to conflagrate that amount");

        require(_amount <= DAC.balanceOf(_peasant), "Insufficient wealth to conflagrate in victim's purse");

        totalClaimableTreasure += _amount;
        lastTimeConflagrated[_peasant] = block.timestamp;
        lastTimePlundering[msg.sender] = block.timestamp;

        DAC.burn(_peasant, _amount);
        DAC.forge(address(this), _amount);
        DAC.burn(msg.sender, _calculatePlunderFee(_amount));

        emit ConflagrationPlunder(msg.sender, _peasant, _amount);
    }

    /**
     * @notice Venture into the hallowed grounds of the Sanctuary, seeking protection for your hard-earned wealth.
     * @dev Adds the specified amount to the peasent's protected wealth with a tithe to enter.
     * @param _peasant The address of the user entering the Sanctuary.
     * @param _amount The amount of tokens the user wishes to protect within the Sanctuary.
     * O weary traveler, burdened by the weight of your wealth and the treachery of your peers, seek solace
     * within the hallowed halls of the Sanctuary. Here, your precious fortune shall be safeguarded from
     * the ravages of Conflagration Plunder. Yet beware, for the Sanctuary demands its due: a tithe
     * collected over time, in exchange for the protection it provides.
     */

    function enterSanctuary(address _peasant, uint256 _amount) internal {
        uint256 totalTithe = (_amount * sanctuaryTitheIn) / 10000;
        uint256 enterAmount = _amount - totalTithe;
        protectedWealth[_peasant] += enterAmount;
        DAC.burn(address(this), totalTithe);

        emit SanctuaryProtection(_peasant, enterAmount);
    }

    /**
     * @notice Courageously step out of the sanctuary and rejoin the fray!
     * @dev Calculates the tithe for departing the sanctuary and then returns the remaining protected wealth minus the tithe to the user's balance. Burns the tithe amount.
     * @param _amount The amount of tokens the user wants to withdraw from the sanctuary.
     * Beware, brave villager! As you leave the sanctuary's protective embrace,
     * you must pay the tithe that has accumulated during your respite.
     * With your newly lightened purse, step back into the realm and prepare for the next Conflagration Plunder!
     */

    function departSanctuary(uint256 _amount) external {
        require(protectedWealth[msg.sender] >= _amount, "Insufficient protected wealth");

        uint256 totalTithe = (_amount * sanctuaryTitheOut) / 10000;
        uint256 actualWithdrawAmount = _amount - totalTithe;
        protectedWealth[msg.sender] -= _amount;
        // burn the tithe amount
        DAC.burn(address(this), totalTithe);

        DAC.safeTransfer(msg.sender, actualWithdrawAmount);

        emit DepartSanctuary(msg.sender, actualWithdrawAmount);
    }

    /**
     * @notice Gather your share of the realm's bountiful treasure, amassed from the ashes of plundered wealth.
     * @dev Calculate and transfer the claimable treasure reward for the user based on their token balance and total supply.
     * As fortune favors the bold, the realm bestows upon its inhabitants a chance to claim their share of the
     * amassed treasure, built from the remnants of their adversaries' conflagrated wealth. Hark, ye seeker
     * of riches, for your due reward awaits, proportional to the heft of your purse and the realm's total fortune.
     */

    function claimTreasure() external {
        uint256 userWealth = DAC.balanceOf(msg.sender);
        require(userWealth > 0, "No wealth to claim treasure");
        uint256 lastTotalClaim = lastClaimedTreasure[msg.sender];
        require(totalClaimableTreasure > lastTotalClaim, "No new treasure to claim");
        uint256 claimableTreasure = totalClaimableTreasure - lastTotalClaim;

        uint256 userWealthFP = userWealth.divd(1e18);
        uint256 claimableTreasureFP = claimableTreasure.divd(1e18);
        uint256 totalSupplyFP = DAC.totalSupply().divd(1e18);

        uint256 rewardFP = userWealthFP.muld(claimableTreasureFP).divd(totalSupplyFP);

        uint256 reward = rewardFP.muld(1e18);

        lastClaimedTreasure[msg.sender] = totalClaimableTreasure;

        DAC.safeTransfer(msg.sender, reward);

        emit ClaimTreasure(msg.sender, reward);
    }

    /**
     * @notice Gaze upon your claimable fortune, held within the realm's treasury.
     * @dev Calculate the user's claimable treasure reward based on their token balance and total supply.
     * @param _peasant The address of the user to calculate the claimable treasure for.
     * @return The claimable treasure amount for the specified user.
     * Peer into the depths of the realm's treasure vault and bear witness to the wealth that awaits you.
     * This function shall reveal the bounties you may claim, based upon your purse's weight and the
     * fortunes amassed by the realm. Fear not, for it shall not take from the treasury; only provide
     * insight into the riches that can be yours, should you choose to claim your share.
     */

    function getClaimableTreasure(address _peasant) external view returns (uint256) {
        uint256 userWealth = DAC.balanceOf(_peasant);

        if (userWealth == 0) {
            return 0;
        }

        uint256 lastTotalClaim = lastClaimedTreasure[_peasant];

        if (totalClaimableTreasure <= lastTotalClaim) {
            return 0;
        }

        uint256 claimableTreasure = totalClaimableTreasure - lastTotalClaim;

        uint256 userWealthFP = userWealth.divd(1e18);
        uint256 claimableTreasureFP = claimableTreasure.divd(1e18);
        uint256 totalSupplyFP = DAC.totalSupply().divd(1e18);

        uint256 claimableResultFP = userWealthFP.muld(claimableTreasureFP).divd(totalSupplyFP);

        uint256 claimableResult = claimableResultFP.muld(1e18);

        return claimableResult;
    }

    /**
     * @notice Set the plunder fee required to initiate a Conflagration Plunder.
     * @param _plunderFee The new plunder fee in basis points.
     */
    function setPlunderFee(uint256 _plunderFee) external onlyOwner {
        require(_plunderFee <= 10000, "Plunder fee must be less than 10000");
        plunderFee = _plunderFee;
        emit UpdatePlunderFee(_plunderFee);
    }

    /**
     * @notice Set the tithe rate going in for tokens stashed in the Sanctuary of Protection.
     * @param _sanctuaryTithe The new sanctuary tithe rate in basis points.
     */
    function setSanctuaryTitheIn(uint256 _sanctuaryTithe) external onlyOwner {
        require(_sanctuaryTithe <= 10000, "Sanctuary tithe must be less than 10000");
        sanctuaryTitheIn = _sanctuaryTithe;
        emit UpdateSanctuaryTitheIn(_sanctuaryTithe);
    }

    /**
     * @notice Set the tithe rate to leave for tokens stashed in the Sanctuary of Protection.
     * @param _sanctuaryTithe The new sanctuary tithe rate in basis points.
     */
    function setSanctuaryTitheOut(uint256 _sanctuaryTithe) external onlyOwner {
        require(_sanctuaryTithe <= 10000, "Sanctuary tithe must be less than 10000");
        sanctuaryTitheOut = _sanctuaryTithe;
        emit UpdateSanctuaryTitheOut(_sanctuaryTithe);
    }

    /**
     * @notice Set the refuge period, the cooldown time after a user is conflagrated.
     * @param _refugePeriod The new refuge period in seconds.
     */
    function setRefugePeriod(uint256 _refugePeriod) external onlyOwner {
        require(_refugePeriod > 0, "Refuge period must be greater than 0");
        refugePeriod = _refugePeriod;
        emit UpdateRefugePeriod(_refugePeriod);
    }

    /**
     * @notice Set the dungeon period, the cooldown time after a user plunders another.
     * @param _dungeonPeriod The new dungeon period in seconds.
     */
    function setDungeonPeriod(uint256 _dungeonPeriod) external onlyOwner {
        require(_dungeonPeriod > 0, "Dungeon period must be greater than 0");
        dungeonPeriod = _dungeonPeriod;
        emit UpdateDungeonPeriod(_dungeonPeriod);
    }

    function onTokenTransfer(address sender, uint256 value, bytes calldata _data) external {
        require(msg.sender == address(DAC), "Sender must be this address");

        uint8 callType = abi.decode(_data, (uint8));

        if (callType == uint8(CallType.Sanctuary)) {
            enterSanctuary(sender, value);
        } else {
            revert("Invalid call type");
        }
    }

    /**
     * @notice Grant a peasant divine protection from the fires of Conflagration Plunder.
     * @dev Mark an address as sanctified, preventing it from being a victim of Conflagration Plunder.
     * @param _peasant The address of the peasant to sanctify.
     * By the power vested in you, the ruler of this realm, you may bestow upon a peasant
     * the gift of invulnerability. With this sacred act, the chosen one shall be spared
     * from the wrathful flames that engulf others in the Conflagration Plunder.
     */

    function sanctifyAddress(address _peasant) external onlyOwner {
        require(_peasant != address(0), "Invalid address");
        sanctifiedAddresses[_peasant] = true;

        emit SanctifyAddress(_peasant);
    }

    /**
     * @notice Revoke a peasant's divine protection, subjecting them to the fires of Conflagration Plunder.
     * @dev Mark an address as no longer sanctified, allowing it to be a victim of Conflagration Plunder.
     * @param _peasant The address of the peasant to desanctify.
     * As ruler, you hold the power to grant and rescind protection at your whim. With this act,
     * you strip away the divine shield that once guarded a peasant from the ravages of the Conflagration
     * Plunder. No longer shall they be spared, and they must face the same trials as their fellow villagers.
     */

    function desanctifyAddress(address _peasant) external onlyOwner {
        require(_peasant != address(0), "Invalid address");
        sanctifiedAddresses[_peasant] = false;

        emit DesanctifyAddress(_peasant);
    }

    /**
     * @notice Inquire the realm's state of slumber or activity.
     * @dev Check if the contract is paused or active.
     * @return boolean value indicating if the contract is paused (true) or active (false).
     * Approach the great pendulum of the realm and ascertain its state of motion or stillness. This function
     * unveils the contract's current status, allowing you to determine whether the operations within the realm
     * have come to a temporary halt or are in full swing. Glimpse into the workings of the realm, but know
     * that the pendulum's sway shall not be altered by your inquiry.
     */
    function isPaused() external view returns (bool) {
        return paused();
    }

    function _calculatePlunderFee(uint256 _amount) internal view returns (uint256) {
        return (_amount * plunderFee) / 10000;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    receive() external payable {}
}

