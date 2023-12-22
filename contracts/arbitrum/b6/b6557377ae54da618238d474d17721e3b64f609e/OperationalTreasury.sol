// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.20;

import "./IERC20.sol";
import "./ReentrancyGuard.sol";
import "./SafeERC20.sol";
import "./IOperationalTreasury.sol";
import "./ICoverPool.sol";

/**
 * @title Operational Treasury for managing options on HEGSC tokens
 * @dev This contract allows users to list HEGSC token in purpose of selling future rewards,
 * and for users to speculate and buy option and claim epoch rewards.
 */
contract OperationalTreasury is IOperationalTreasury, ReentrancyGuard {
    using SafeERC20 for IERC20;
    IERC20 public USDC;
    ICoverPool public HEGIC;
    Protocol public protocolState = Protocol.Active;

    uint256 constant EPOCH_DURATION = 30 days;
    uint256 public extendedClaimTime = 0;
    uint256 public claimTime = 2 days;
    uint256 public nextTERId = 1;
    address public owner;

    mapping(uint256 => uint256[]) private epochTERs;
    mapping(address => uint256) public hegicOwnerToTERId;
    mapping(uint256 => terData) public terIdToData;
    mapping(uint256 => address) public terIdToBuyer;

    constructor(address _usdc, address _hegic) {
        USDC = IERC20(_usdc);
        HEGIC = ICoverPool(_hegic);
        owner = msg.sender;
    }

     /**
     * @notice Deposit HEGSC token and list future epoch rewards for sale
     * @dev After transfering the new TER ID (tokenised epoch rewards) is made.
     * @param hegicTokenId The ID of the HEGSC token to deposit
     * @param price The price at which to list the rewards for sale
     */
    function depositAndList(uint256 hegicTokenId, uint256 price) external {
        require(protocolState == Protocol.Active, "Protocol is paused");
        require(
            HEGIC.ownerOf(hegicTokenId) == msg.sender,
            "Not the owner of the HEGIC token"
        );
        require(price > 0, "Price must be greater than zero");
        require(
            HEGIC.availableToClaim(hegicTokenId) == 0,
            "Claim rewards first"
        );
        HEGIC.transferFrom(msg.sender, address(this), hegicTokenId);

        uint256 terId = nextTERId++;

        terData memory newTer = terData({
            tokenID: hegicTokenId,
            holder: msg.sender,
            hegicBalance: getHegicBalance(hegicTokenId),
            listForEpoch: getCurrentEpoch(),
            expiryAt: computeCurrentEpochEndTime(),
            price: price,
            state: State.Listed
        });

        hegicOwnerToTERId[msg.sender] = terId;
        terIdToData[terId] = newTer;
        epochTERs[newTer.listForEpoch].push(terId);

        emit Listed(terId, price, newTer.hegicBalance);
    }

     /**
     * @notice Buy a listed TER (Tokenized Epoch Rewards)
     * @dev Marks TER status as Active and gives buyer the right to claim rewards for the current Epoch after it ends.
     * USDC funds are sent to the TER seller.
     * @param terId The ID of the TER token to buy
     */
    function buyTER(uint256 terId) external nonReentrant {
        terData storage listing = terIdToData[terId];
        require(listing.state == State.Listed, "Not listed for sale");
        require(getCurrentEpoch() == listing.listForEpoch, "Epoch has changed");

        uint256 price = listing.price;
        listing.state = State.Active;
        terIdToBuyer[terId] = msg.sender;
        require(
            USDC.transferFrom(msg.sender, listing.holder, price),
            "Payment failed"
        );
        emit Purchased(terId, msg.sender, price);
    }

    /**
     * @notice Claim rewards for a TER after its epoch has ended. Claiming time is 48h after the epoch ends.
     * @dev Claims HEGIC rewards and transfers them to the TER token buyer, and closes the TER state.
     * @param terId The ID of the TER token for which to claim rewards
     */
    function claim(uint256 terId) external nonReentrant {
        terData storage listing = terIdToData[terId];

        require(terIdToBuyer[terId] == msg.sender, "Not the TER buyer");

        require(
            block.timestamp >= listing.expiryAt &&
                block.timestamp <=
                listing.expiryAt + claimTime + extendedClaimTime,
            "Either epoch hasn't ended yet or claiming period has ended"
        );
        require(listing.state == State.Active, "Cannot claim for this TER");

        listing.state = State.Closed;
        uint256 amount = HEGIC.claim(listing.tokenID);

        if (amount > 0) {
            USDC.transfer(msg.sender, amount);
        }

        emit Claimed(terId, amount, msg.sender);
    }

    /**
     * @notice Close an epoch and release all HEGSC tokens to their owners. Can be called by anyone after 48h of the epoch end.
     * @dev Releases HEGSC tokens back to the original holders after the epoch ends, changing the state of the TER tokens to Released.
     * @param epochNum The epoch number to close
     */
    function closeEpoch(uint256 epochNum) external {
        require(
            getCurrentEpoch() > epochNum,
            "Cannot close the current or a future epoch"
        );
        require(
            block.timestamp > computeClaimTime(epochNum) + extendedClaimTime,
            "Too early to close epoch"
        );

        for (uint i = 0; i < epochTERs[epochNum].length; i++) {
            uint256 terId = epochTERs[epochNum][i];

            _releaseHegic(terId);
        }

        delete epochTERs[epochNum];

        emit EpochClosed(epochNum);
    }

    function _releaseHegic(uint256 terId) internal {
        terData storage listing = terIdToData[terId];
        listing.state = State.Released;
        HEGIC.transferFrom(address(this), listing.holder, listing.tokenID);

        emit Released(listing.tokenID, listing.holder);
    }

    /**
     * @notice Change the price of a listed TER token
     * @dev Updates the listing price of a TER token, if it's not sold. Can only be called by the TER token owner.
     * @param TERid The ID of the TER token to update
     * @param newPrice The new price for the TER token
     */
    function changePrice(uint256 TERid, uint256 newPrice) external {
        terData storage listing = terIdToData[TERid];
        require(
            listing.holder == msg.sender,
            "Only the TER owner can change the price"
        );
        require(
            listing.state == State.Listed,
            "TER is not currently listed for sale"
        );
        require(newPrice > 0, "New price must be greater than zero");

        listing.price = newPrice;
    }

     /**
     * @notice Delist a TER token and retrieve the underlying HEGSC token.
     * @dev Removes a TER token from listing and returns the HEGSC token to it's owner. 
     * @param terId The ID of the TER token to delist
     */
    function delistAndRetrieve(uint256 terId) external {
        terData storage listing = terIdToData[terId];

        require(
            listing.holder == msg.sender,
            "Only the TER minter can delist and retrieve"
        );

        require(
            listing.state == State.Listed,
            "TER has been bought or released"
        );

        // Remove terId from the epochTERs mapping
        uint256[] storage terList = epochTERs[listing.listForEpoch];
        for (uint256 i = 0; i < terList.length; i++) {
            if (terList[i] == terId) {
                terList[i] = terList[terList.length - 1];
                terList.pop();
                break;
            }
        }
        _releaseHegic(terId);
    }

    function checkEpochPnL(uint256 epochID) public view returns (bool) {
        require(epochID < getCurrentEpoch(), "Cannot check current epoch");

        (,,,uint256 profitTokenOut,,) = HEGIC.epoch(epochID);

        return profitTokenOut > 0;
    }

    /**
     * @notice Claim rewards on behalf of a TER token buyer
     * @dev Can be called by the owner to claim rewards for a TER token buyer and transfer to them. It's the same as claim()
     * and it's a helper function if people forget to claim themselves.
     * @param terId The ID of the TER token for which to claim rewards
     */
    function claimRewardsOnBehalf(uint256 terId) external onlyOwner {
        terData storage listing = terIdToData[terId];
        require(
            block.timestamp >= listing.expiryAt &&
                block.timestamp <=
                listing.expiryAt + claimTime + extendedClaimTime,
            "Either epoch hasn't ended yet or claiming period has ended"
        );
        require(listing.state == State.Active, "TER is not active");
        address buyer = terIdToBuyer[terId];
        require(buyer != address(0), "No buyer for this TER");

        listing.state = State.Closed;
        uint256 amount = HEGIC.claim(listing.tokenID);

        if (amount > 0) {
            require(USDC.transfer(buyer, amount), "Transfer failed");
        }

        emit RewardsClaimedOnBehalf(terId, buyer, amount);
    }

    /**
     * @notice Extend the claim time for all TER tokens
     * @dev Can be called by the owner to extend the claim period for rewards,
     * in case of an issue in distribution of Epoch Rewards by Hegic.
     * @param daysToExtend The number of days to extend the claim period by
     */
    function extendClaimTime(uint256 daysToExtend) external onlyOwner {
        require(daysToExtend > 0, "Days to extend must be greater than zero");
        extendedClaimTime += daysToExtend * 1 days;
        emit ClaimTimeExtended(extendedClaimTime);
    }

    function computeCurrentEpochEndTime() public view returns (uint256) {
        (uint256 start, , , , , ) = HEGIC.epoch(getCurrentEpoch());
        return start + EPOCH_DURATION;
    }

    function computeClaimTime(uint256 epochNum) public view returns (uint256) {
        (uint256 start, , , , , ) = HEGIC.epoch(epochNum);
        return start + EPOCH_DURATION + claimTime;
    }

    function getCurrentEpoch() public view returns (uint256) {
        return HEGIC.currentEpoch();
    }

    // function getCurrentEpochTest() public view returns (uint256) {
    //     return HEGIC.currentEpoch() + 1;
    // }

    function getHegicBalance(uint256 tokenID) internal view returns (uint256) {
        return HEGIC.coverTokenBalance(tokenID);
    }

    function getTERsForEpoch(
        uint256 epoch
    ) external view returns (uint256[] memory) {
        return epochTERs[epoch];
    }

    function setProtocolState(Protocol _state) external onlyOwner {
        protocolState = _state;
    }

    modifier onlyOwner() {
        require(msg.sender == owner, "Only the owner can call this");
        _;
    }

    function transferOwnership(address newOwner) external onlyOwner {
        require(newOwner != address(0), "New owner cannot be the zero address");
        owner = newOwner;
    }
}

