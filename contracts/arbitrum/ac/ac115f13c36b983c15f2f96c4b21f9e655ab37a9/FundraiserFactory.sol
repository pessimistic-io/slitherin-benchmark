// SPDX-License-Identifier: MIT
pragma solidity ^0.8.18;

import "./Fundraiser.sol";
import "./IterableMapping.sol";
import "./IERC20.sol";
import "./IERC721.sol";
import "./Ownable.sol";

contract FundraiserFactory is Ownable {
    using IterableMapping for IterableMapping.Map;

    enum FundraiserStatus {COMING_SOON, NFT_PHASE, OPEN, CLOSED, DISTRIBUTION}

    IterableMapping.Map private activeFundraisers;
    IterableMapping.Map private endedFundraisers;

    event FundraiserCreated(address indexed fundraiser);
    event FundraiserEnded(address indexed fundraiser);

    constructor(address _owner) {
        _transferOwnership(_owner);
    }

    function createFundraiser(
        address _buyToken1,
        address _buyToken2,
        uint256 _baseAllocationPerWallet,
        uint256 _maxTotalAllocation,
        uint256 _nftTicketAllocation,
        uint256 _rate,
        uint256 _nftFundraiseStartTime,
        uint256 _openFundraiseStartTime,
        uint256 _fundraiseEndTime,
        address _nftAddress
    ) external onlyOwner() {
        Fundraiser newFundraiser = new Fundraiser(
            _buyToken1,
            _buyToken2,
            _baseAllocationPerWallet,
            _maxTotalAllocation,
            _nftTicketAllocation,
            _rate,
            _nftFundraiseStartTime,
            _openFundraiseStartTime,
            _fundraiseEndTime,
            owner(),
            address(this),
            _nftAddress
        );
        activeFundraisers.set(address(newFundraiser), activeFundraisers.size());
        emit FundraiserCreated(address(newFundraiser));
    }

    function endFundraiser(address fundraiserAddress) external {
        require(activeFundraisers.inserted[fundraiserAddress], "Fundraiser not found");
        require(msg.sender == fundraiserAddress, "Only the fundraiser contract can call this function");

        uint256 endTime = Fundraiser(fundraiserAddress).getEndTime();
        require(block.timestamp > endTime, "Fundraiser has not ended yet");

        activeFundraisers.remove(fundraiserAddress);
        endedFundraisers.set(fundraiserAddress, endedFundraisers.size());
        emit FundraiserEnded(fundraiserAddress);
    }

    function getFundraiserStatus(address fundraiserAddress) external view returns (FundraiserStatus) {
        (
        uint256 nftStartTime,
        uint256 openStartTime,
        uint256 endTime
        ) = Fundraiser(fundraiserAddress).timeConfig();
        if (block.timestamp < nftStartTime) {
            return FundraiserStatus.COMING_SOON;
        } else if (block.timestamp <= openStartTime) {
            return FundraiserStatus.NFT_PHASE;
        } else if (block.timestamp <= endTime) {
            return FundraiserStatus.OPEN;
        } else {
            return FundraiserStatus.DISTRIBUTION;
        }
    }

    function getFundraisersCount() external view returns (uint256) {
        return activeFundraisers.size();
    }

    function getEndedFundraisersCount() external view returns (uint256) {
        return endedFundraisers.size();
    }

    function getFundraiserAtIndex(uint256 index) external view returns (address) {
        require(index < activeFundraisers.size(), "Index out of bounds");
        return activeFundraisers.getKeyAtIndex(index);
    }

    function getEndedFundraiserAtIndex(uint256 index) external view returns (address) {
        require(index < endedFundraisers.size(), "Index out of bounds");
        return endedFundraisers.getKeyAtIndex(index);
    }

    function getActiveFundraisersAtIndexes(uint256[] calldata indexes) external view returns (address[] memory) {
        require(indexes.length > 0, "Indexes array must not be empty");

        address[] memory activeFundraisersAddresses = new address[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            require(indexes[i] < activeFundraisers.size(), "Index out of bounds");
            activeFundraisersAddresses[i] = activeFundraisers.getKeyAtIndex(indexes[i]);
        }

        return activeFundraisersAddresses;
    }

    function getEndedFundraisersAtIndexes(uint256[] calldata indexes) external view returns (address[] memory) {
        require(indexes.length > 0, "Indexes array must not be empty");

        address[] memory endedFundraisersAddresses = new address[](indexes.length);

        for (uint256 i = 0; i < indexes.length; i++) {
            require(indexes[i] < endedFundraisers.size(), "Index out of bounds");
            endedFundraisersAddresses[i] = endedFundraisers.getKeyAtIndex(indexes[i]);
        }

        return endedFundraisersAddresses;
    }
}

