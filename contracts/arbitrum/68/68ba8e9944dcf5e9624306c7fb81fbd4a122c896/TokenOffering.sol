//SPDX-License-Identifier: MIT

pragma solidity 0.8.18;

import "./Ownable2Step.sol";
import "./IERC20.sol";

enum Phase {
    Closed,
    Presale,
    Public
}

/// @title Stumble Upon Rumble - Token Offering Contract
/// @notice This contract is designed to manage the sale of the stumble upon rumble erc20 token.
/// @notice Each purchaser will be allocated 1 share for each wei USDC committed.
/// @notice Presale purchasers will be allocated an additional % bonus on top of all presale shares purchased, and have the opportunity to earn a large ticket boost.
/// @notice The contract defines a maximum threshold, which is the maximum intended fundraise.
/// @notice Token distribution will be determined by the number of shares sold. Total Tokens / Total Shares.

contract TokenOffering is Ownable2Step {
    struct UserShares {
        uint64 presaleShares;
        uint64 publicShares;
        uint64 usdcDeposited;
    }

    uint64 immutable maximumThreshold;
    uint64 immutable walletLimit;
    uint64 immutable presaleBoost;
    uint64 immutable largeTicketBoost;
    uint64 immutable largeTicketThreshold;

    uint64 private presaleShares;
    uint64 private publicShares;

    Phase public phase;

    IERC20 public usdc;

    mapping(address purchaser => UserShares) private shareTracking;
    mapping(address purchaser => bool allowed) public allowList;
    address[] public purchasers;

    /// @notice Event emitted when a purchase occurs
    /// @param purchaser The address of the purchaser
    /// @param USDCvalue The amount of USDC used for the purchase
    /// @param shares The amount of shares purchased
    event Purchase(address indexed purchaser, uint64 USDCvalue, uint64 shares);

    /// @notice Event emitted when the contract phase changes
    /// @param phase The new phase of the contract
    event PhaseChanged(Phase indexed phase);

    constructor(
        address _usdc,
        uint64 _maximumThreshold,
        uint64 _walletLimit,
        uint64 _presaleBoost,
        uint64 _largeTicketBoost,
        uint64 _largeTicketThreshold
    ) {
        require(_presaleBoost >= 100000, "Presale boost must be greater than 1000.");
        require(_largeTicketBoost >= 100000, "Large ticket boost must be greater than 1000.");
        require(_largeTicketThreshold > 0, "Large ticket threshold must be greater than 0.");
        require(_walletLimit < _maximumThreshold, "Wallet limit must be less than maximum threshold.");
        require(_usdc != address(0), "USDC cannot be zero address.");
        maximumThreshold = _maximumThreshold;
        walletLimit = _walletLimit;
        presaleBoost = _presaleBoost;
        largeTicketBoost = _largeTicketBoost;
        largeTicketThreshold = _largeTicketThreshold;
        usdc = IERC20(_usdc);
    }

    /// @dev Allows a user to purchase tokens during the public phase
    /// @param amount The amount of USDC the user wants to commit
    function purchasePublic(uint64 amount) external {
        require(phase == Phase.Public, "Public phase must be active.");
        require(usdc.balanceOf(address(this)) + amount <= maximumThreshold, "Fundraise has reached maximum threshold.");
        usdc.transferFrom(msg.sender, address(this), amount);
        publicShares += amount;
        shareTracking[msg.sender].publicShares += amount;
        shareTracking[msg.sender].usdcDeposited += amount;
        purchasers.push(msg.sender);
        emit Purchase(msg.sender, amount, amount);
    }

    /// @dev Allows a user to purchase tokens during the presale phase
    /// @param amount The amount of USDC the user wants to commit
    function purchasePresale(uint64 amount) external {
        require(phase == Phase.Presale, "Presale must be active.");
        require(allowList[msg.sender], "User must be on allowlist.");
        require(usdc.balanceOf(address(this)) + amount <= maximumThreshold, "Fundraise has reached maximum threshold.");
        uint64 currentUserDeposit = shareTracking[msg.sender].usdcDeposited;
        require(shareTracking[msg.sender].usdcDeposited + amount <= walletLimit, "User has reached wallet limit.");

        usdc.transferFrom(msg.sender, address(this), amount);

        uint64 totalSharesToAdd = amount;

        if (currentUserDeposit + amount >= largeTicketThreshold) {
            totalSharesToAdd = (totalSharesToAdd * largeTicketBoost) / 100000;
            if (currentUserDeposit < largeTicketThreshold) {
                totalSharesToAdd += _addBoostForPriorShares();
            }
        }

        presaleShares += totalSharesToAdd;
        shareTracking[msg.sender].presaleShares += totalSharesToAdd;
        shareTracking[msg.sender].usdcDeposited += amount;
        purchasers.push(msg.sender);

        emit Purchase(msg.sender, amount, totalSharesToAdd);
    }

    /// @dev Allows the contract owner to cycle through the contract phases
    function cyclePhase() external onlyOwner {
        if (phase == Phase.Closed) {
            phase = Phase.Presale;
        } else if (phase == Phase.Presale) {
            phase = Phase.Public;
        } else if (phase == Phase.Public) {
            phase = Phase.Closed;
        }
        emit PhaseChanged(phase);
    }

    /// @notice Returns the total number of shares
    /// @return The total number of shares
    function getTotalShares() external view returns (uint64) {
        return ((presaleShares * presaleBoost) / 100000) + publicShares;
    }

    /// @notice Returns the number of shares owned by a user
    /// @param _address The address of the user
    /// @return The number of shares owned by the user
    function getUserShares(address _address) external view returns (uint64) {
        if (allowList[_address]) {
            uint64 presaleSharesUser = (shareTracking[_address].presaleShares * presaleBoost) / 100000;
            return presaleSharesUser + shareTracking[_address].publicShares;
        } else {
            return shareTracking[_address].publicShares;
        }
    }

    /// @notice Returns a list of all purchaser addresses
    /// @return An array containing all purchaser addresses
    function getAllPurchasers() external view returns (address[] memory) {
        return purchasers;
    }

    /// @dev Allows the contract owner to withdraw funds from the contract
    function withdrawFunds() external onlyOwner {
        require(phase == Phase.Closed, "Fundraise must be closed.");
        usdc.transfer(msg.sender, usdc.balanceOf(address(this)));
    }

    /// @dev Allows the contract owner to add users to the allowlist
    /// @param _addresses An array of addresses to be added to the allowlist
    function setAllowlist(address[] calldata _addresses) external onlyOwner {
        uint256 length = _addresses.length;
        for (uint256 i = 0; i < length; i++) {
            allowList[_addresses[i]] = true;
        }
    }

    function _addBoostForPriorShares() internal view returns (uint64) {
        uint64 priorShares = shareTracking[msg.sender].presaleShares;
        uint64 boostToAdd = ((priorShares * largeTicketBoost) / 100000) - priorShares;
        return boostToAdd;
    }
}

