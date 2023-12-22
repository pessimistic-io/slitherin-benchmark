// SPDX-License-Identifier: BUSL-1.1
pragma solidity 0.8.12;

import "./Initializable.sol";
import "./UUPSUpgradeable.sol";
import "./OwnableUpgradeable.sol";
import "./ArraysUpgradeable.sol";
import { IERC20 } from "./IERC20.sol";
import { SafeERC20 } from "./SafeERC20.sol";

import { IKeeperRegistry } from "./IKeeperRegistry.sol";

/**
 * @dev owned by governance contract
 */
contract KeeperRegistry is
    Initializable,
    OwnableUpgradeable,
    UUPSUpgradeable,
    IKeeperRegistry
{
    using SafeERC20 for IERC20;
    uint256 public maxNumKeepers; // Max # of keepers to allow at a time
    uint256 public currentNumKeepers; // Current # of keepers.

    // Bond token
    IERC20 public bondCoin; // ERC20 token used to provide bonds. Meant to be Steer token.
    uint256 public bondAmount; // Amount of bondCoin required to become a keeper
    uint256 public freeCoin; // Amount of bondCoin no longer affiliated with any keeper (due to slashing etc.)

    /**
     * Slash safety period--if a keeper leaves, this is the amount of time (in seconds) they must 
        wait before they can withdraw their bond.
     */
    uint256 public transferDelay;

    mapping(uint256 => address) public keeperLicenses; // This mapping is pretty much just used to track which licenses are free.
    mapping(address => WorkerDetails) public registry; // Registry of keeper info for keepers and former keepers.

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() initializer() {}

    function initialize(
        address coinAddress,
        uint256 keeperTransferDelay,
        uint256 maxKeepers,
        uint256 bondSize
    ) public initializer {
        __UUPSUpgradeable_init();
        __Ownable_init();
        bondCoin = IERC20(coinAddress);
        transferDelay = keeperTransferDelay;
        maxNumKeepers = maxKeepers;
        require(bondSize > 0, "SIZE");
        bondAmount = bondSize;
    }

    function _authorizeUpgrade(address) internal override onlyOwner {}

    /**
     * @dev setup utility function for owner to add initial keepers. Addresses must each be unique and not hold any bondToken.
     * @param joiners array of addresses to become keepers.
     * note that this function will pull bondToken from the owner equal to bondAmount * numJoiners.
     * note that this function assumes that the keeper registry currently has no keepers. It will revert if this assumption fails.
     */
    function joiningForOwner(address[] calldata joiners) public onlyOwner {
        uint256 noOfJoiners = joiners.length;
        require(noOfJoiners != 0, "JOINERS");
        // Cache last license index
        uint256 lastKeeperLicense = noOfJoiners + 1;

        // Cache bond amount
        uint256 _bondAmount = bondAmount;

        bondCoin.safeTransferFrom(
            msg.sender,
            address(this),
            _bondAmount * noOfJoiners
        );

        // Ensure not too many keepers are being added.
        require(noOfJoiners <= maxNumKeepers, "MAX_KEEPERS");

        // Add each keeper to the registry
        for (uint256 i = 1; i != lastKeeperLicense; ++i) {
            // Make sure license is not already claimed by another keeper
            require(keeperLicenses[i] == address(0), "Address not new.");

            // Register keeper to license
            keeperLicenses[i] = joiners[i - 1];

            // Register license (and other info) to keeper
            registry[joiners[i - 1]] = WorkerDetails({
                bondHeld: _bondAmount,
                licenseNumber: i,
                leaveTimestamp: 0
            });
        }

        currentNumKeepers += noOfJoiners;
    }

    /**
     * @param amount Amount of bondCoin to be deposited.
     * @dev this function has three uses:
        1. If the caller is a keeper, they can increase their bondHeld by amount. This helps to avoid slashing.
        2. If the caller is not a keeper or former keeper, they can attempt to claim a keeper license and become a keeper.
        3. If the caller is a former keeper, they can attempt to cancel their leave request, claim a keeper license, and become a keeper.
        In all 3 cases registry[msg.sender].bondHeld is increased by amount. In the latter 2, msg.sender's bondHeld after the transaction must be >= bondAmount.
     */
    function join(uint256 licenseNumber, uint256 amount) public {
        // Transfer in bond.
        if (amount > 0) {
            bondCoin.safeTransferFrom(msg.sender, address(this), amount);
        }

        // Look up msg.sender in the mapping
        WorkerDetails memory _workerDetails = registry[msg.sender];

        if (_workerDetails.licenseNumber > 0) {
            // If they have a license, they're a keeper, and amount will go towards their bondHeld
            // If maxNumKeepers was decreased, they may not be a keeper, but this won't cause anything to break.
            registry[msg.sender].bondHeld = _workerDetails.bondHeld + amount;
        } else {
            /*
                Two scenarios here:
                1. If their bondAmount is zero and their leaveTimestamp is zero, they are not yet a keeper, so this is a new address attempting to become a keeper.
                2. If they are queued to leave but have not yet left, they are not a keeper, so this will cancel their leave request (by zeroing out leaveTimestamp) 
                and attempt to make them a keeper.
                Either way the solution is the same -- if their new bondAmount is enough, they become a keeper with no leave date. Otherwise, this function reverts.
            */

            // Make sure requested license is valid and available
            require(
                keeperLicenses[licenseNumber] == address(0),
                "License not available."
            );
            require(licenseNumber > 0, "LICENSE_NUMBER");
            require(licenseNumber <= maxNumKeepers, "LICENSE_NUMBER");

            // Join must be sufficient to become a keeper
            uint256 newBondAmount = _workerDetails.bondHeld + amount;
            require(newBondAmount >= bondAmount, "Insufficient bond amount.");

            ++currentNumKeepers;

            // Register license/bond amount with keeper
            registry[msg.sender] = WorkerDetails({
                bondHeld: newBondAmount,
                licenseNumber: licenseNumber,
                leaveTimestamp: 0
            });

            // Register keeper with license
            keeperLicenses[licenseNumber] = msg.sender;

            emit PermissionChanged(msg.sender, permissionType.FULL);
        }
    }

    /**
     * @dev Allows keepers to queue to leave the registry. Their elevated permissions are immediately revoked, and their funds can be retrieved once the transferDelay has passed.
     * note that this function can only be called by keepers (or, in rare cases, former keepers whose licenses were revoked by a decrease in maxNumKeepers)
     * emits a permissionChanged event if the call succeeds.
     */
    function queueToLeave() public {
        WorkerDetails memory _workerDetails = registry[msg.sender];
        require(
            _workerDetails.licenseNumber > 0,
            "msg.sender is already not a keeper."
        );

        // Remove permissions immediately. Keeper can remove funds once the transferDelay has passed. This ensures that keeper can be slashed if they misbehaved just before leaving.
        registry[msg.sender] = WorkerDetails({
            bondHeld: _workerDetails.bondHeld,
            licenseNumber: 0,
            leaveTimestamp: block.timestamp + transferDelay
        });
        delete keeperLicenses[_workerDetails.licenseNumber];

        // Decrease numKeepers count
        --currentNumKeepers;

        emit PermissionChanged(msg.sender, permissionType.NONE);
    }

    /**
     * @dev addresses call this after they have queued to leave and waited the requisite amount of time.
     */
    function leave() external {
        WorkerDetails memory info = registry[msg.sender];

        // Validate leave request
        require(info.leaveTimestamp > 0, "Not queued to leave.");
        require(
            info.leaveTimestamp < block.timestamp,
            "Transfer delay not passed."
        );

        // Send former keeper their previously staked tokens
        bondCoin.safeTransfer(msg.sender, info.bondHeld);

        // Reset the former keeper's data
        delete registry[msg.sender];
    }

    /**
     * @dev returns true if the given address has the power to vote, reverts otherwise. This function is built to be called by the orchestrator.
     * @param targetAddress address to check
     * @return licenseNumber true if the given address has the power to vote, reverts otherwise.
     */
    function checkLicense(
        address targetAddress
    ) public view returns (uint256 licenseNumber) {
        licenseNumber = registry[targetAddress].licenseNumber;
        require(licenseNumber > 0, "NOT_A_KEEPER");
    }

    /**
     * @dev slashes a keeper, removing their permissions and forfeiting their bond.
     * @param targetKeeper keeper to denounce
     * @param amount amount of bondCoin to slash
     * note that the keeper will only lose their license if, post-slash, their bond held is less than bondAmount.
     */
    function denounce(
        address targetKeeper,
        uint256 amount
    ) external onlyOwner {
        WorkerDetails memory _workerDetails = registry[targetKeeper];

        // Remove bondCoin from keeper who is being denounced, add to freeCoin (to be withdrawn by owner)
        uint256 currentBondHeld = _workerDetails.bondHeld;

        // If slash amount is greater than keeper's held bond, just slash 100% of their bond
        if (currentBondHeld < amount) {
            amount = currentBondHeld;
        }

        // Slash keeper's bond by amount
        uint256 newBond = currentBondHeld - amount;
        // Add keeper's slashed bond tokens to freeCoin
        freeCoin += amount;

        // Remove user as keeper if they are below threshold, and are a keeper
        if (newBond < bondAmount && _workerDetails.licenseNumber > 0) {
            keeperLicenses[_workerDetails.licenseNumber] = address(0);
            registry[targetKeeper].licenseNumber = 0;
            --currentNumKeepers;
            registry[targetKeeper].bondHeld = 0;
            //User is not a keeper anymore so user's remaining bond amount after substracting the slashed amount is given back
            bondCoin.safeTransfer(targetKeeper, newBond);
            //User can again try to become a keeper by calling join and bonding again.
        } else {
            registry[targetKeeper].bondHeld = newBond;
        }
        emit PermissionChanged(targetKeeper, permissionType.SLASHED);
    }

    /**
     * @dev withdraws slashed tokens from the vault and sends them to targetAddress.
     * @param amount amount of bondCoin to withdraw
     * @param targetAddress address receiving the tokens
     */
    function withdrawFreeCoin(
        uint256 amount,
        address targetAddress
    ) external onlyOwner {
        freeCoin -= amount;
        bondCoin.safeTransfer(targetAddress, amount);
    }

    /**
     * @dev change bondAmount to a new value.
     * @dev Does not change existing keeper permissions. If the bondAmount is being increased, existing keepers will not be slashed or removed. 
            note, they will still be able to vote until they are slashed.
     * @param amount new bondAmount.
     */
    function changeBondAmount(uint256 amount) external onlyOwner {
        bondAmount = amount;
    }

    /**
     * @dev change numKeepers to a new value. If numKeepers is being reduced, this will not remove any keepers, nor will it change orchestrator requirements.
        However, it will render keeper licenses > maxNumKeepers invalid and their votes will stop counting.
     */
    function changeMaxKeepers(uint16 newNumKeepers) external onlyOwner {
        maxNumKeepers = newNumKeepers;
    }
}

